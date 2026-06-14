#!/usr/bin/env python3
"""MacNix Fingerprint Bridge — Biometric unlock for macOS VMs.

Provides Parallels-style fingerprint authentication for macOS VMs running
under QEMU/KVM.  The daemon watches VNC screenshots for the login screen,
prompts for fingerprint verification via fprintd, retrieves the stored
macOS password from the system keyring (secret-tool), and injects it
into the VM via QMP send-key.

Subcommands:
    setup   — Store macOS password and enroll fingerprint
    daemon  — Run the monitoring daemon
    test    — Verify fingerprint → credential injection pipeline
    status  — Show fingerprint sensor status
    reset   — Remove stored credentials
"""

from __future__ import annotations

import argparse
import getpass
import json
import logging
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SERVICE_NAME = "macnix-vm"
KEYRING_USER = "macOS"
LOG_DIR = Path("/var/log/macnix")
LOG_FILE = LOG_DIR / "fingerprint-bridge.log"
PID_FILE = Path("/run/macnix-fingerprint-bridge.pid")

# Default VM connection parameters
DEFAULT_QMP_HOST = "localhost"
DEFAULT_QMP_PORT = 5902
DEFAULT_VNC_HOST = "localhost"
DEFAULT_VNC_PORT = 5900

# Polling and retry parameters
POLL_INTERVAL = 2.0        # seconds between login-screen checks
FINGERPRINT_TIMEOUT = 30   # seconds to wait for fingerprint
MAX_FP_FAILURES = 3        # fallback to password after N failures
KEY_INJECT_DELAY = 0.05    # seconds between QMP key presses

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logger = logging.getLogger("macnix-fingerprint")


def _setup_logging(verbose: bool = False, daemon: bool = False) -> None:
    """Configure logging for interactive or daemon mode."""
    level = logging.DEBUG if verbose else logging.INFO
    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)-7s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    if not daemon:
        console = logging.StreamHandler(sys.stderr)
        console.setLevel(level)
        console.setFormatter(fmt)
        logger.addHandler(console)

    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        fh = logging.FileHandler(LOG_FILE)
        fh.setLevel(logging.DEBUG)
        fh.setFormatter(fmt)
        logger.addHandler(fh)
    except PermissionError:
        if not daemon:
            print(f"Warning: cannot write to {LOG_FILE}", file=sys.stderr)

    logger.setLevel(logging.DEBUG)


# ---------------------------------------------------------------------------
# QMP Client (lightweight)
# ---------------------------------------------------------------------------
class QMPClient:
    """Minimal QMP client for key injection."""

    def __init__(self, host: str = DEFAULT_QMP_HOST, port: int = DEFAULT_QMP_PORT):
        self.host = host
        self.port = port
        self._sock: Optional[socket.socket] = None

    def connect(self) -> None:
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.settimeout(10.0)
        self._sock.connect((self.host, self.port))
        self._recv_json()  # greeting
        self._send_json({"execute": "qmp_capabilities"})
        resp = self._recv_json()
        if "return" not in resp:
            raise RuntimeError(f"QMP negotiation failed: {resp}")
        logger.debug("QMP connected to %s:%d", self.host, self.port)

    def close(self) -> None:
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None

    def send_key(self, key: str, hold_ms: int = 100) -> None:
        """Send a single key press via QMP."""
        self._execute(
            "send-key",
            {"keys": [{"type": "qcode", "data": key}], "hold-time": hold_ms},
        )

    def send_key_combo(self, keys: list[str], hold_ms: int = 100) -> None:
        key_objs = [{"type": "qcode", "data": k} for k in keys]
        self._execute("send-key", {"keys": key_objs, "hold-time": hold_ms})

    def _execute(self, command: str, arguments: Optional[dict] = None) -> dict:
        msg: dict = {"execute": command}
        if arguments:
            msg["arguments"] = arguments
        self._send_json(msg)
        while True:
            resp = self._recv_json()
            if "return" in resp or "error" in resp:
                return resp

    def _send_json(self, obj: dict) -> None:
        assert self._sock is not None
        self._sock.sendall(json.dumps(obj).encode("utf-8") + b"\n")

    def _recv_json(self) -> dict:
        assert self._sock is not None
        buf = b""
        while True:
            chunk = self._sock.recv(4096)
            if not chunk:
                raise ConnectionError("QMP connection closed")
            buf += chunk
            try:
                return json.loads(buf.decode("utf-8"))
            except json.JSONDecodeError:
                continue


# ---------------------------------------------------------------------------
# Character → QMP qcode mapping
# ---------------------------------------------------------------------------
# Maps printable ASCII to QMP qcode key names.
_CHAR_TO_QCODE: dict[str, tuple[str, bool]] = {}  # char → (qcode, needs_shift)


def _build_charmap() -> None:
    """Build the character → qcode lookup table."""
    global _CHAR_TO_QCODE

    lower = "abcdefghijklmnopqrstuvwxyz"
    for ch in lower:
        _CHAR_TO_QCODE[ch] = (ch, False)
        _CHAR_TO_QCODE[ch.upper()] = (ch, True)

    digits = "0123456789"
    for d in digits:
        _CHAR_TO_QCODE[d] = (d, False)

    # Shifted digit symbols
    shift_digits = {
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
        "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
    }
    for sym, digit in shift_digits.items():
        _CHAR_TO_QCODE[sym] = (digit, True)

    # Special characters
    specials = {
        " ": ("spc", False),
        "\n": ("ret", False),
        "\t": ("tab", False),
        "-": ("minus", False),
        "=": ("equal", False),
        "[": ("bracket_left", False),
        "]": ("bracket_right", False),
        "\\": ("backslash", False),
        ";": ("semicolon", False),
        "'": ("apostrophe", False),
        ",": ("comma", False),
        ".": ("dot", False),
        "/": ("slash", False),
        "`": ("grave_accent", False),
        "_": ("minus", True),
        "+": ("equal", True),
        "{": ("bracket_left", True),
        "}": ("bracket_right", True),
        "|": ("backslash", True),
        ":": ("semicolon", True),
        '"': ("apostrophe", True),
        "<": ("comma", True),
        ">": ("dot", True),
        "?": ("slash", True),
        "~": ("grave_accent", True),
    }
    _CHAR_TO_QCODE.update(specials)


_build_charmap()


# ---------------------------------------------------------------------------
# Credential Store (secret-tool)
# ---------------------------------------------------------------------------
class CredentialStore:
    """Interface to GNOME Keyring via secret-tool CLI."""

    @staticmethod
    def store_password(password: str) -> bool:
        """Store the macOS VM password in the keyring."""
        try:
            proc = subprocess.run(
                [
                    "secret-tool", "store",
                    "--label", "MacNix VM Password",
                    "service", SERVICE_NAME,
                    "user", KEYRING_USER,
                ],
                input=password.encode("utf-8"),
                capture_output=True,
                timeout=30,
            )
            return proc.returncode == 0
        except FileNotFoundError:
            logger.error("secret-tool not found — install libsecret-tools")
            return False
        except subprocess.TimeoutExpired:
            logger.error("secret-tool timed out")
            return False

    @staticmethod
    def retrieve_password() -> Optional[str]:
        """Retrieve the stored macOS VM password."""
        try:
            proc = subprocess.run(
                [
                    "secret-tool", "lookup",
                    "service", SERVICE_NAME,
                    "user", KEYRING_USER,
                ],
                capture_output=True,
                timeout=10,
            )
            if proc.returncode == 0 and proc.stdout:
                return proc.stdout.decode("utf-8").strip()
            return None
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return None

    @staticmethod
    def clear_password() -> bool:
        """Remove the stored password from the keyring."""
        try:
            proc = subprocess.run(
                [
                    "secret-tool", "clear",
                    "service", SERVICE_NAME,
                    "user", KEYRING_USER,
                ],
                capture_output=True,
                timeout=10,
            )
            return proc.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return False


# ---------------------------------------------------------------------------
# Fingerprint Interface (fprintd)
# ---------------------------------------------------------------------------
class FingerprintSensor:
    """Interface to fprintd for fingerprint enrollment and verification."""

    @staticmethod
    def is_available() -> bool:
        """Check if a fingerprint sensor is detected and fprintd is usable."""
        try:
            proc = subprocess.run(
                ["fprintd-list", os.getenv("USER", "root")],
                capture_output=True,
                timeout=10,
            )
            return proc.returncode == 0
        except FileNotFoundError:
            return False
        except subprocess.TimeoutExpired:
            return False

    @staticmethod
    def list_enrolled() -> str:
        """Return enrolled fingerprint info as a string."""
        try:
            proc = subprocess.run(
                ["fprintd-list", os.getenv("USER", "root")],
                capture_output=True,
                text=True,
                timeout=10,
            )
            return proc.stdout if proc.returncode == 0 else proc.stderr
        except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
            return f"Error: {exc}"

    @staticmethod
    def enroll() -> bool:
        """Interactively enroll a fingerprint.  Runs in foreground."""
        try:
            proc = subprocess.run(
                ["fprintd-enroll"],
                timeout=120,
            )
            return proc.returncode == 0
        except FileNotFoundError:
            print("Error: fprintd-enroll not found — install fprintd")
            return False
        except subprocess.TimeoutExpired:
            print("Error: fingerprint enrollment timed out")
            return False

    @staticmethod
    def verify(timeout: int = FINGERPRINT_TIMEOUT) -> bool:
        """Attempt fingerprint verification.  Returns True on match."""
        try:
            proc = subprocess.run(
                ["fprintd-verify"],
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            if proc.returncode == 0 and "verify-match" in proc.stdout.lower():
                return True
            logger.debug("fprintd-verify output: %s", proc.stdout)
            return False
        except FileNotFoundError:
            logger.error("fprintd-verify not found")
            return False
        except subprocess.TimeoutExpired:
            logger.warning("Fingerprint verification timed out")
            return False


# ---------------------------------------------------------------------------
# Login Screen Detector (VNC screenshot pixel analysis)
# ---------------------------------------------------------------------------
class LoginScreenDetector:
    """Detects the macOS login screen by analyzing VNC screenshots.

    The macOS login screen has a characteristic dark blurred gradient
    background.  We sample pixels at known coordinates and check if
    they fall within expected luminance ranges.
    """

    # Sample points on a 1024×768 display where the login screen
    # background should be a dark gradient (y ~= 100..200, various x)
    SAMPLE_POINTS = [
        (100, 150),   # left side, upper area
        (512, 150),   # center, upper area
        (900, 150),   # right side, upper area
        (512, 700),   # center, lower area
    ]

    # Login screen background is typically very dark (luminance < 60)
    MAX_LUMINANCE = 60
    MIN_DARK_PIXELS = 3  # at least 3 of 4 sample points must be dark

    def __init__(self, vnc_host: str = "localhost", vnc_port: int = DEFAULT_VNC_PORT):
        self.vnc_host = vnc_host
        self.vnc_port = vnc_port

    def capture_and_check(self) -> bool:
        """Capture a VNC screenshot and check if it looks like a login screen.

        Uses vncdotool CLI to capture a screenshot, then analyzes pixel
        colors with PIL/Pillow.
        """
        tmpdir = tempfile.gettempdir()
        screenshot_path = os.path.join(tmpdir, "macnix-login-check.png")

        try:
            display = self.vnc_port - 5900
            subprocess.run(
                [
                    "vncdo",
                    "--server", f"{self.vnc_host}::{self.vnc_host}:{self.vnc_port}",
                    "capture", screenshot_path,
                ],
                capture_output=True,
                timeout=15,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.debug("VNC capture failed: %s", exc)
            return False

        return self._analyze_screenshot(screenshot_path)

    def _analyze_screenshot(self, path: str) -> bool:
        """Analyze pixel colors at sample points to detect login screen."""
        try:
            from PIL import Image
        except ImportError:
            logger.warning("Pillow not installed — login detection degraded")
            return self._fallback_detection(path)

        try:
            img = Image.open(path).convert("RGB")
        except Exception as exc:
            logger.debug("Cannot open screenshot: %s", exc)
            return False

        dark_count = 0
        for x, y in self.SAMPLE_POINTS:
            if x >= img.width or y >= img.height:
                continue
            r, g, b = img.getpixel((x, y))
            luminance = 0.299 * r + 0.587 * g + 0.114 * b
            logger.debug(
                "Pixel (%d,%d): RGB(%d,%d,%d) lum=%.1f",
                x, y, r, g, b, luminance,
            )
            if luminance < self.MAX_LUMINANCE:
                dark_count += 1

        is_login = dark_count >= self.MIN_DARK_PIXELS
        logger.debug(
            "Login screen detection: %d/%d dark pixels → %s",
            dark_count, len(self.SAMPLE_POINTS),
            "LOGIN" if is_login else "not login",
        )
        return is_login

    @staticmethod
    def _fallback_detection(path: str) -> bool:
        """Fallback: check file size heuristic (login screen is mostly dark)."""
        try:
            size = os.path.getsize(path)
            # Dark images compress well; login screen PNG is typically < 50 KB
            return size < 50_000
        except OSError:
            return False


# ---------------------------------------------------------------------------
# Key Injector
# ---------------------------------------------------------------------------
class KeyInjector:
    """Injects a password string into the VM via QMP send-key."""

    def __init__(self, qmp: QMPClient):
        self.qmp = qmp

    def inject_password(self, password: str) -> bool:
        """Type the password into the VM and press Enter."""
        logger.info("Injecting password (%d chars)...", len(password))

        for i, char in enumerate(password):
            entry = _CHAR_TO_QCODE.get(char)
            if entry is None:
                logger.warning(
                    "Unmappable character at position %d (0x%02x), skipping",
                    i, ord(char),
                )
                continue

            qcode, needs_shift = entry
            if needs_shift:
                self.qmp.send_key_combo(["shift", qcode])
            else:
                self.qmp.send_key(qcode)
            time.sleep(KEY_INJECT_DELAY)

        # Press Enter
        time.sleep(0.2)
        self.qmp.send_key("ret")
        logger.info("Password injection complete")
        return True


# ---------------------------------------------------------------------------
# Daemon
# ---------------------------------------------------------------------------
@dataclass
class DaemonConfig:
    """Configuration for the fingerprint bridge daemon."""

    qmp_host: str = DEFAULT_QMP_HOST
    qmp_port: int = DEFAULT_QMP_PORT
    vnc_host: str = DEFAULT_VNC_HOST
    vnc_port: int = DEFAULT_VNC_PORT
    poll_interval: float = POLL_INTERVAL
    max_failures: int = MAX_FP_FAILURES
    verbose: bool = False


class FingerprintBridgeDaemon:
    """Main daemon loop: detect login screen → fingerprint → inject."""

    def __init__(self, config: DaemonConfig):
        self.config = config
        self._running = False
        self._qmp: Optional[QMPClient] = None
        self._detector = LoginScreenDetector(config.vnc_host, config.vnc_port)
        self._sensor = FingerprintSensor()
        self._creds = CredentialStore()
        self._fp_failures = 0

    def run(self) -> int:
        """Start the daemon loop. Returns exit code."""
        self._running = True
        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)

        self._write_pidfile()

        logger.info("MacNix Fingerprint Bridge daemon starting")
        logger.info(
            "QMP=%s:%d  VNC=%s:%d  poll=%.1fs",
            self.config.qmp_host, self.config.qmp_port,
            self.config.vnc_host, self.config.vnc_port,
            self.config.poll_interval,
        )

        # Validate prerequisites
        if not self._sensor.is_available():
            logger.error("No fingerprint sensor available — exiting")
            return 1

        password = self._creds.retrieve_password()
        if not password:
            logger.error(
                "No stored macOS password — run 'macnix-fingerprint setup' first"
            )
            return 1

        try:
            self._main_loop(password)
        except Exception as exc:
            logger.error("Daemon crashed: %s", exc, exc_info=True)
            return 1
        finally:
            self._cleanup()

        logger.info("Daemon stopped gracefully")
        return 0

    def _main_loop(self, password: str) -> None:
        """Core polling loop."""
        while self._running:
            time.sleep(self.config.poll_interval)

            if not self._detector.capture_and_check():
                # Not on login screen — reset failure counter
                self._fp_failures = 0
                continue

            logger.info("Login screen detected — requesting fingerprint")
            self._attempt_unlock(password)

    def _attempt_unlock(self, password: str) -> None:
        """Attempt fingerprint verification and credential injection."""
        if self._fp_failures >= self.config.max_failures:
            logger.warning(
                "Max fingerprint failures (%d) reached — prompting for password",
                self.config.max_failures,
            )
            self._fallback_password_prompt()
            self._fp_failures = 0
            return

        logger.info("Place your finger on the sensor...")
        if self._sensor.verify():
            logger.info("✓ Fingerprint verified — unlocking VM")
            self._inject_password(password)
            self._fp_failures = 0
            # Wait for the desktop to load before polling again
            time.sleep(10.0)
        else:
            self._fp_failures += 1
            logger.warning(
                "Fingerprint verification failed (%d/%d)",
                self._fp_failures, self.config.max_failures,
            )

    def _inject_password(self, password: str) -> None:
        """Connect to QMP and inject the password."""
        qmp = QMPClient(self.config.qmp_host, self.config.qmp_port)
        try:
            qmp.connect()
            injector = KeyInjector(qmp)
            injector.inject_password(password)
        except Exception as exc:
            logger.error("Password injection failed: %s", exc)
        finally:
            qmp.close()

    def _fallback_password_prompt(self) -> None:
        """Fallback: prompt user to type password manually.

        In daemon mode this sends a desktop notification instead of
        blocking on stdin.
        """
        logger.info("Sending desktop notification for manual password entry")
        try:
            subprocess.run(
                [
                    "notify-send",
                    "--urgency=critical",
                    "MacNix Fingerprint Bridge",
                    "Fingerprint failed 3 times. Please type your macOS password manually.",
                ],
                capture_output=True,
                timeout=5,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired):
            logger.debug("notify-send not available")

    def _handle_signal(self, signum: int, _frame) -> None:
        sig_name = signal.Signals(signum).name
        logger.info("Received %s — shutting down", sig_name)
        self._running = False

    def _write_pidfile(self) -> None:
        try:
            PID_FILE.parent.mkdir(parents=True, exist_ok=True)
            PID_FILE.write_text(str(os.getpid()))
        except PermissionError:
            logger.debug("Cannot write PID file %s", PID_FILE)

    def _cleanup(self) -> None:
        try:
            PID_FILE.unlink(missing_ok=True)
        except PermissionError:
            pass
        if self._qmp:
            self._qmp.close()


# ---------------------------------------------------------------------------
# CLI Subcommands
# ---------------------------------------------------------------------------
def cmd_setup(args: argparse.Namespace) -> int:
    """Interactive setup: store password and enroll fingerprint."""
    print("=" * 50)
    print("  MacNix Fingerprint Bridge — Setup")
    print("=" * 50)
    print()

    # Step 1: Store macOS password
    print("[1/2] Store macOS VM password")
    print("This password will be used to auto-unlock your macOS VM.")
    print()
    password = getpass.getpass("Enter macOS password: ")
    confirm = getpass.getpass("Confirm macOS password: ")

    if password != confirm:
        print("Error: passwords do not match")
        return 1

    if not password:
        print("Error: password cannot be empty")
        return 1

    creds = CredentialStore()
    if creds.store_password(password):
        print("✓ Password stored in system keyring")
    else:
        print("✗ Failed to store password")
        return 1

    print()

    # Step 2: Enroll fingerprint
    print("[2/2] Enroll fingerprint")
    sensor = FingerprintSensor()
    if not sensor.is_available():
        print("Warning: no fingerprint sensor detected")
        print("You can enroll later with: macnix-fingerprint setup")
        return 0

    print("Follow the prompts to scan your finger...")
    print()
    if sensor.enroll():
        print("✓ Fingerprint enrolled successfully")
    else:
        print("✗ Fingerprint enrollment failed")
        print("You can retry with: fprintd-enroll")
        return 1

    print()
    print("Setup complete! Start the daemon with:")
    print("  sudo systemctl start macnix-fingerprint-bridge")
    return 0


def cmd_daemon(args: argparse.Namespace) -> int:
    """Run the fingerprint bridge daemon."""
    _setup_logging(args.verbose, daemon=True)
    config = DaemonConfig(
        qmp_host=args.qmp_host,
        qmp_port=args.qmp_port,
        vnc_host=args.vnc_host,
        vnc_port=args.vnc_port,
        verbose=args.verbose,
    )
    daemon = FingerprintBridgeDaemon(config)
    return daemon.run()


def cmd_test(args: argparse.Namespace) -> int:
    """Test the full fingerprint → injection pipeline."""
    print("MacNix Fingerprint Bridge — Test")
    print()

    # Check sensor
    sensor = FingerprintSensor()
    if not sensor.is_available():
        print("✗ No fingerprint sensor detected")
        return 1
    print("✓ Fingerprint sensor available")

    # Check credentials
    creds = CredentialStore()
    password = creds.retrieve_password()
    if not password:
        print("✗ No stored password — run 'setup' first")
        return 1
    print(f"✓ Password retrieved ({len(password)} chars)")

    # Test fingerprint
    print()
    print("Place your finger on the sensor...")
    if not sensor.verify():
        print("✗ Fingerprint verification failed")
        return 1
    print("✓ Fingerprint verified")

    # Test QMP connection
    print()
    print(f"Testing QMP connection to {args.qmp_host}:{args.qmp_port}...")
    qmp = QMPClient(args.qmp_host, args.qmp_port)
    try:
        qmp.connect()
        print("✓ QMP connected")
    except Exception as exc:
        print(f"✗ QMP connection failed: {exc}")
        print("  (Is the VM running?)")
        return 1
    finally:
        qmp.close()

    print()
    print("All tests passed! The fingerprint bridge is ready.")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    """Show fingerprint sensor and daemon status."""
    print("MacNix Fingerprint Bridge — Status")
    print()

    # Sensor
    sensor = FingerprintSensor()
    available = sensor.is_available()
    print(f"Fingerprint sensor: {'✓ available' if available else '✗ not detected'}")
    if available:
        print()
        print("Enrolled fingerprints:")
        print(sensor.list_enrolled())

    # Credentials
    creds = CredentialStore()
    password = creds.retrieve_password()
    print(f"Stored password:    {'✓ present' if password else '✗ not set'}")

    # Daemon
    pid = None
    if PID_FILE.exists():
        try:
            pid = int(PID_FILE.read_text().strip())
            # Check if process is actually running
            os.kill(pid, 0)
        except (ValueError, ProcessLookupError, PermissionError):
            pid = None

    print(f"Daemon:             {'✓ running (PID ' + str(pid) + ')' if pid else '✗ not running'}")

    # QMP connectivity
    qmp = QMPClient(args.qmp_host, args.qmp_port)
    try:
        qmp.connect()
        print(f"VM QMP:             ✓ connected ({args.qmp_host}:{args.qmp_port})")
    except Exception:
        print(f"VM QMP:             ✗ not reachable ({args.qmp_host}:{args.qmp_port})")
    finally:
        qmp.close()

    return 0


def cmd_reset(args: argparse.Namespace) -> int:
    """Remove stored credentials."""
    print("MacNix Fingerprint Bridge — Reset")
    print()

    creds = CredentialStore()
    if creds.clear_password():
        print("✓ Stored password removed from keyring")
    else:
        print("✗ Failed to remove password (may not exist)")

    print()
    print("Note: to remove enrolled fingerprints, run:")
    print(f"  fprintd-delete {os.getenv('USER', 'root')}")
    return 0


# ---------------------------------------------------------------------------
# Argument Parser
# ---------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="macnix-fingerprint-bridge",
        description="Biometric unlock for MacNix macOS VMs",
    )

    # Global options
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Enable debug logging",
    )
    parser.add_argument(
        "--qmp-host", default=DEFAULT_QMP_HOST,
        help=f"QMP host (default: {DEFAULT_QMP_HOST})",
    )
    parser.add_argument(
        "--qmp-port", type=int, default=DEFAULT_QMP_PORT,
        help=f"QMP port (default: {DEFAULT_QMP_PORT})",
    )
    parser.add_argument(
        "--vnc-host", default=DEFAULT_VNC_HOST,
        help=f"VNC host (default: {DEFAULT_VNC_HOST})",
    )
    parser.add_argument(
        "--vnc-port", type=int, default=DEFAULT_VNC_PORT,
        help=f"VNC port (default: {DEFAULT_VNC_PORT})",
    )

    sub = parser.add_subparsers(dest="command", help="Available commands")

    # setup
    sub.add_parser(
        "setup",
        help="Store macOS password and enroll fingerprint",
    )

    # daemon
    sub.add_parser(
        "daemon",
        help="Run the fingerprint monitoring daemon",
    )

    # test
    sub.add_parser(
        "test",
        help="Test the fingerprint → credential injection pipeline",
    )

    # status
    sub.add_parser(
        "status",
        help="Show sensor and daemon status",
    )

    # reset
    sub.add_parser(
        "reset",
        help="Remove stored credentials",
    )

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    if args.command != "daemon":
        _setup_logging(args.verbose)

    dispatch = {
        "setup": cmd_setup,
        "daemon": cmd_daemon,
        "test": cmd_test,
        "status": cmd_status,
        "reset": cmd_reset,
    }

    handler = dispatch.get(args.command)
    if handler is None:
        parser.print_help()
        return 1

    return handler(args)


if __name__ == "__main__":
    sys.exit(main())
