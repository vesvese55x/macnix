#!/usr/bin/env python3
"""MacNix Auto-Install — VNC-based automated macOS installation engine.

Connects to a QEMU VM running macOS Recovery and drives the entire
installation flow without user interaction:

  1. Launch QEMU with Recovery media attached
  2. Wait for Recovery to boot
  3. Open Terminal via Utilities menu
  4. Erase disk with diskutil
  5. Navigate to Install macOS
  6. Monitor disk growth until installation finishes
  7. Take a qcow2 snapshot and shut down
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import signal
import socket
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOG_DIR = Path("/var/log/macnix")
LOG_FILE = LOG_DIR / "auto-install.log"

logger = logging.getLogger("macnix-auto-install")


def _setup_logging(verbose: bool = False) -> None:
    """Configure dual console + file logging."""
    level = logging.DEBUG if verbose else logging.INFO
    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)-7s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

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
        logger.warning("Cannot write to %s — file logging disabled", LOG_FILE)

    logger.setLevel(logging.DEBUG)


# ---------------------------------------------------------------------------
# QMP Client
# ---------------------------------------------------------------------------
class QMPClient:
    """Minimal QMP (QEMU Machine Protocol) client over TCP."""

    def __init__(self, host: str, port: int, timeout: float = 10.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self._sock: Optional[socket.socket] = None

    # -- connection ---------------------------------------------------------

    def connect(self) -> None:
        """Open TCP connection and perform QMP capabilities negotiation."""
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.settimeout(self.timeout)
        self._sock.connect((self.host, self.port))
        # Read greeting
        greeting = self._recv_json()
        logger.debug("QMP greeting: %s", greeting)
        # Negotiate capabilities
        self._send_json({"execute": "qmp_capabilities"})
        resp = self._recv_json()
        if "return" not in resp:
            raise RuntimeError(f"QMP capabilities negotiation failed: {resp}")
        logger.info("QMP connected to %s:%d", self.host, self.port)

    def close(self) -> None:
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None

    # -- commands -----------------------------------------------------------

    def execute(self, command: str, arguments: Optional[dict] = None) -> dict:
        """Execute a QMP command and return the response."""
        msg: dict = {"execute": command}
        if arguments:
            msg["arguments"] = arguments
        self._send_json(msg)
        # Read responses, skipping asynchronous events
        while True:
            resp = self._recv_json()
            if "return" in resp or "error" in resp:
                return resp
            # Otherwise it's an event — log and continue
            logger.debug("QMP event: %s", resp)

    def quit(self) -> dict:
        return self.execute("quit")

    def send_key(self, key: str, hold_ms: int = 100) -> dict:
        """Send a single QMP key event."""
        return self.execute(
            "send-key",
            {"keys": [{"type": "qcode", "data": key}], "hold-time": hold_ms},
        )

    def send_key_combo(self, keys: list[str], hold_ms: int = 100) -> dict:
        """Send a key combination (e.g. ['meta_l', 'space'])."""
        key_objs = [{"type": "qcode", "data": k} for k in keys]
        return self.execute("send-key", {"keys": key_objs, "hold-time": hold_ms})

    def savevm(self, name: str) -> dict:
        """Create an internal VM snapshot via human-monitor-command."""
        return self.execute(
            "human-monitor-command",
            {"command-line": f"savevm {name}"},
        )

    # -- transport ----------------------------------------------------------

    def _send_json(self, obj: dict) -> None:
        data = json.dumps(obj).encode("utf-8") + b"\n"
        assert self._sock is not None
        self._sock.sendall(data)

    def _recv_json(self) -> dict:
        assert self._sock is not None
        buf = b""
        while True:
            chunk = self._sock.recv(4096)
            if not chunk:
                raise ConnectionError("QMP connection closed unexpectedly")
            buf += chunk
            try:
                return json.loads(buf.decode("utf-8"))
            except json.JSONDecodeError:
                continue  # Incomplete frame, keep reading


# ---------------------------------------------------------------------------
# VNC Automation Wrapper
# ---------------------------------------------------------------------------
class VNCAutomation:
    """Thin wrapper around vncdotool for keyboard/mouse/screenshot ops."""

    def __init__(self, host: str = "localhost", port: int = 5900):
        self.host = host
        self.display = port - 5900  # vncdotool uses display number
        self._client = None

    def connect(self) -> None:
        try:
            from vncdotool import api as vnc_api
        except ImportError:
            raise RuntimeError(
                "vncdotool is required: pip install vncdotool"
            )
        self._client = vnc_api.connect(
            f"{self.host}::{self.host}:{self.port}",
            password=None,
        )
        logger.info("VNC connected to %s display :%d", self.host, self.display)

    @property
    def port(self) -> int:
        return self.display + 5900

    def close(self) -> None:
        if self._client:
            try:
                self._client.disconnect()
            except Exception:
                pass
            self._client = None

    def type_text(self, text: str, interval: float = 0.05) -> None:
        """Type a string character-by-character."""
        if self._client is None:
            raise RuntimeError("VNC not connected")
        for char in text:
            self._client.keyPress(char)
            time.sleep(interval)

    def press_key(self, key: str) -> None:
        if self._client is None:
            raise RuntimeError("VNC not connected")
        self._client.keyPress(key)

    def key_combo(self, *keys: str) -> None:
        """Press a key combination (e.g., 'ctrl', 'alt', 'del')."""
        if self._client is None:
            raise RuntimeError("VNC not connected")
        for k in keys[:-1]:
            self._client.keyDown(k)
        self._client.keyPress(keys[-1])
        for k in reversed(keys[:-1]):
            self._client.keyUp(k)

    def capture_screenshot(self, filepath: str) -> str:
        """Take a screenshot and save as PNG. Returns filepath."""
        if self._client is None:
            raise RuntimeError("VNC not connected")
        self._client.captureScreen(filepath)
        logger.debug("Screenshot saved: %s", filepath)
        return filepath

    def click(self, x: int, y: int, button: int = 1) -> None:
        if self._client is None:
            raise RuntimeError("VNC not connected")
        self._client.mouseMove(x, y)
        time.sleep(0.1)
        self._client.mousePress(button)

    def mouse_move(self, x: int, y: int) -> None:
        if self._client is None:
            raise RuntimeError("VNC not connected")
        self._client.mouseMove(x, y)


# ---------------------------------------------------------------------------
# Disk Monitor
# ---------------------------------------------------------------------------
class DiskGrowthMonitor:
    """Monitors qcow2 file size growth to detect installation completion."""

    def __init__(
        self,
        disk_path: Path,
        poll_interval: float = 30.0,
        stable_threshold: float = 600.0,  # 10 minutes
        min_size_gb: float = 15.0,
    ):
        self.disk_path = disk_path
        self.poll_interval = poll_interval
        self.stable_threshold = stable_threshold
        self.min_size_bytes = int(min_size_gb * 1024**3)
        self._last_size: int = 0
        self._last_growth_time: float = 0.0

    def get_size(self) -> int:
        """Return current file size in bytes."""
        try:
            return self.disk_path.stat().st_size
        except FileNotFoundError:
            return 0

    def get_size_gb(self) -> float:
        return self.get_size() / (1024**3)

    def reset(self) -> None:
        self._last_size = self.get_size()
        self._last_growth_time = time.time()

    def check(self) -> bool:
        """Check disk growth. Returns True if installation appears complete.

        Completion criteria:
          - Disk size > min_size_bytes
          - No growth detected for stable_threshold seconds
        """
        current_size = self.get_size()
        now = time.time()

        if current_size != self._last_size:
            delta_mb = (current_size - self._last_size) / (1024**2)
            logger.info(
                "Disk growth: +%.1f MB (total: %.2f GB)",
                delta_mb,
                current_size / (1024**3),
            )
            self._last_size = current_size
            self._last_growth_time = now
            return False

        stable_duration = now - self._last_growth_time
        if current_size >= self.min_size_bytes and stable_duration >= self.stable_threshold:
            logger.info(
                "Installation appears complete: %.2f GB, stable for %.0fs",
                current_size / (1024**3),
                stable_duration,
            )
            return True

        logger.debug(
            "Disk stable for %.0fs / %.0fs (%.2f GB / %.2f GB min)",
            stable_duration,
            self.stable_threshold,
            current_size / (1024**3),
            self.min_size_bytes / (1024**3),
        )
        return False


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
@dataclass
class InstallConfig:
    """All parameters for an automated macOS installation run."""

    vnc_port: int = 5900
    qmp_host: str = "localhost"
    qmp_port: int = 5902
    disk_path: Path = Path("/var/lib/macnix/disks/macOS.qcow2")
    recovery_path: Path = Path("/var/lib/macnix/disks/BaseSystem.img")
    timeout: int = 7200  # 2 hours
    dry_run: bool = False
    verbose: bool = False

    # Tuning
    boot_wait: float = 120.0   # seconds to wait for Recovery boot
    format_wait: float = 30.0  # seconds to wait after diskutil
    poll_interval: float = 30.0
    stable_threshold: float = 600.0  # 10 min no growth = done
    min_disk_gb: float = 15.0

    # Paths to QEMU support files (defaults for installed system)
    firmware_dir: Path = Path("/var/lib/macnix/firmware")
    opencore_img: Path = Path("/var/lib/macnix/disks/OpenCore.qcow2")
    ovmf_code: Path = Path("/var/lib/macnix/firmware/OVMF_CODE.fd")
    ovmf_vars: Path = Path("/var/lib/macnix/firmware/OVMF_VARS.fd")

    # Snapshot
    snapshot_name: str = "clean-install"

    # Screenshot directory for debugging
    screenshot_dir: Path = Path("/var/log/macnix/screenshots")


# ---------------------------------------------------------------------------
# QEMU Launcher
# ---------------------------------------------------------------------------
class QEMULauncher:
    """Launches and manages a QEMU process for macOS installation."""

    def __init__(self, config: InstallConfig):
        self.config = config
        self._process: Optional[subprocess.Popen] = None

    def build_command(self) -> list[str]:
        """Build the QEMU command line."""
        cfg = self.config
        vnc_display = cfg.vnc_port - 5900

        return [
            "qemu-system-x86_64",
            "-enable-kvm",
            "-machine", "q35,accel=kvm,kernel_irqchip=on",
            "-cpu", "host,kvm=on,vendor=GenuineIntel,+invtsc",
            "-smp", "4,cores=4,threads=1",
            "-m", "8G",
            "-device", 'isa-applesmc,osk=ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc',
            "-smbios", "type=2,manufacturer=Apple Inc.,product=iMacPro1,1",
            "-vnc", f":{vnc_display}",
            "-qmp", f"tcp:{cfg.qmp_host}:{cfg.qmp_port},server,nowait",
            "-drive", f"if=pflash,format=raw,readonly=on,file={cfg.ovmf_code}",
            "-drive", f"if=pflash,format=raw,file={cfg.ovmf_vars}",
            "-device", "ide-hd,bus=sata.2,drive=OpenCore",
            "-drive", f"id=OpenCore,if=none,format=qcow2,file={cfg.opencore_img}",
            "-device", "virtio-blk-pci,drive=MacHDD",
            "-drive", f"id=MacHDD,if=none,format=qcow2,file={cfg.disk_path}",
            "-device", "ide-hd,bus=sata.3,drive=InstallMedia",
            "-drive", f"id=InstallMedia,if=none,format=raw,file={cfg.recovery_path}",
            "-device", "virtio-net-pci,netdev=net0",
            "-netdev", "user,id=net0",
            "-device", "virtio-vga",
            "-display", "none",
        ]

    def launch(self) -> subprocess.Popen:
        """Start the QEMU process."""
        cmd = self.build_command()
        logger.info("Launching QEMU: %s", " ".join(cmd[:5]) + " ...")
        logger.debug("Full command: %s", " \\\n  ".join(cmd))
        self._process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=os.setsid,  # New process group for clean shutdown
        )
        logger.info("QEMU started with PID %d", self._process.pid)
        return self._process

    def terminate(self) -> None:
        """Terminate the QEMU process if still running."""
        if self._process and self._process.poll() is None:
            logger.info("Terminating QEMU (PID %d)", self._process.pid)
            try:
                os.killpg(os.getpgid(self._process.pid), signal.SIGTERM)
                self._process.wait(timeout=15)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                logger.warning("QEMU did not exit gracefully, sending SIGKILL")
                try:
                    os.killpg(os.getpgid(self._process.pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass

    @property
    def is_running(self) -> bool:
        return self._process is not None and self._process.poll() is None


# ---------------------------------------------------------------------------
# Installation Orchestrator
# ---------------------------------------------------------------------------
class MacOSInstaller:
    """Drives the full automated macOS installation sequence."""

    def __init__(self, config: InstallConfig):
        self.config = config
        self.launcher = QEMULauncher(config)
        self.qmp: Optional[QMPClient] = None
        self.vnc: Optional[VNCAutomation] = None
        self.disk_monitor = DiskGrowthMonitor(
            config.disk_path,
            poll_interval=config.poll_interval,
            stable_threshold=config.stable_threshold,
            min_size_gb=config.min_disk_gb,
        )
        self._start_time: float = 0.0

    # -- public API ---------------------------------------------------------

    def run(self) -> bool:
        """Execute the full installation. Returns True on success."""
        if self.config.dry_run:
            return self._dry_run()

        self._start_time = time.time()

        try:
            self._validate_inputs()
            self._launch_qemu()
            self._connect_qmp()
            self._wait_for_boot()
            self._connect_vnc()
            self._open_terminal()
            self._erase_disk()
            self._start_installation()
            self._monitor_installation()
            self._take_snapshot()
            self._shutdown()
            logger.info("✓ macOS installation completed successfully!")
            return True

        except KeyboardInterrupt:
            logger.warning("Installation interrupted by user")
            return False
        except Exception as exc:
            logger.error("Installation failed: %s", exc, exc_info=True)
            return False
        finally:
            self._cleanup()

    # -- dry run ------------------------------------------------------------

    def _dry_run(self) -> bool:
        """Print what would happen without executing anything."""
        cfg = self.config
        cmd = self.launcher.build_command()

        print("=" * 60)
        print("  MacNix Auto-Install — DRY RUN")
        print("=" * 60)
        print()
        print(f"  Disk image:    {cfg.disk_path}")
        print(f"  Recovery:      {cfg.recovery_path}")
        print(f"  VNC port:      {cfg.vnc_port}")
        print(f"  QMP port:      {cfg.qmp_port}")
        print(f"  Timeout:       {cfg.timeout}s ({cfg.timeout // 60} min)")
        print(f"  Min disk size: {cfg.min_disk_gb} GB")
        print(f"  Stable time:   {cfg.stable_threshold}s")
        print(f"  Snapshot name: {cfg.snapshot_name}")
        print()
        print("  QEMU command:")
        print(f"    {' '.join(cmd[:3])} \\")
        for arg in cmd[3:]:
            print(f"      {arg} \\")
        print()
        print("  Automation steps:")
        print("    1. Launch QEMU with Recovery media")
        print(f"    2. Wait {cfg.boot_wait}s for Recovery to boot")
        print("    3. Connect VNC and open Terminal (Utilities → Terminal)")
        print('    4. Run: diskutil eraseDisk APFS "Macintosh HD" disk0')
        print(f"    5. Wait {cfg.format_wait}s for format")
        print("    6. Navigate to Install macOS")
        print("    7. Monitor disk growth (poll every {cfg.poll_interval}s)")
        print(f"    8. Completion: no growth for {cfg.stable_threshold}s AND > {cfg.min_disk_gb} GB")
        print(f"    9. Take snapshot: '{cfg.snapshot_name}'")
        print("   10. Shutdown via QMP quit")
        print()
        print("  [DRY RUN] No actions performed.")
        return True

    # -- validation ---------------------------------------------------------

    def _validate_inputs(self) -> None:
        """Verify all required files exist before starting."""
        cfg = self.config
        missing = []
        for label, path in [
            ("Recovery image", cfg.recovery_path),
            ("OpenCore image", cfg.opencore_img),
            ("OVMF_CODE", cfg.ovmf_code),
            ("OVMF_VARS", cfg.ovmf_vars),
        ]:
            if not path.exists():
                missing.append(f"  {label}: {path}")

        if not cfg.disk_path.exists():
            logger.info("Disk image not found, creating: %s", cfg.disk_path)
            cfg.disk_path.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(
                [
                    "qemu-img", "create", "-f", "qcow2",
                    str(cfg.disk_path), "80G",
                ],
                check=True,
                capture_output=True,
            )
            logger.info("Created 80G qcow2 disk image")

        if missing:
            raise FileNotFoundError(
                "Required files not found:\n" + "\n".join(missing)
            )

    # -- QEMU lifecycle -----------------------------------------------------

    def _launch_qemu(self) -> None:
        logger.info("=" * 50)
        logger.info("Starting QEMU for macOS Recovery")
        logger.info("=" * 50)
        self.launcher.launch()
        # Give QEMU a moment to initialize
        time.sleep(3)
        if not self.launcher.is_running:
            raise RuntimeError("QEMU exited immediately — check configuration")

    def _connect_qmp(self) -> None:
        """Connect to QMP with retries."""
        cfg = self.config
        self.qmp = QMPClient(cfg.qmp_host, cfg.qmp_port)
        max_attempts = 10
        for attempt in range(1, max_attempts + 1):
            try:
                self.qmp.connect()
                return
            except (ConnectionRefusedError, OSError) as exc:
                if attempt == max_attempts:
                    raise RuntimeError(
                        f"Failed to connect to QMP after {max_attempts} attempts"
                    ) from exc
                logger.debug(
                    "QMP connection attempt %d/%d failed: %s",
                    attempt, max_attempts, exc,
                )
                time.sleep(2)

    # -- boot wait ----------------------------------------------------------

    def _wait_for_boot(self) -> None:
        """Wait for macOS Recovery to boot."""
        logger.info(
            "Waiting %.0fs for macOS Recovery to boot...",
            self.config.boot_wait,
        )
        self._sleep_with_timeout(self.config.boot_wait, "Recovery boot wait")
        logger.info("Boot wait complete — attempting VNC connection")

    def _connect_vnc(self) -> None:
        """Connect to VNC with retries."""
        cfg = self.config
        self.vnc = VNCAutomation("localhost", cfg.vnc_port)
        max_attempts = 5
        for attempt in range(1, max_attempts + 1):
            try:
                self.vnc.connect()
                return
            except Exception as exc:
                if attempt == max_attempts:
                    raise RuntimeError(
                        f"Failed to connect to VNC after {max_attempts} attempts"
                    ) from exc
                logger.debug(
                    "VNC connection attempt %d/%d failed: %s",
                    attempt, max_attempts, exc,
                )
                time.sleep(5)

    # -- Terminal navigation ------------------------------------------------

    def _open_terminal(self) -> None:
        """Open Terminal in macOS Recovery via menu bar: Utilities → Terminal."""
        assert self.vnc is not None
        logger.info("Opening Terminal via Utilities menu...")

        # Take a diagnostic screenshot
        self._screenshot("pre-terminal")

        # Click on the "Utilities" menu in the menu bar.
        # In macOS Recovery, the menu bar is at the top.  Standard menu layout:
        #   Apple | macOS Recovery | Edit | Utilities | Window | Help
        # Utilities is roughly at x=300, y=12 (top menu bar).
        self.vnc.click(300, 12)
        time.sleep(1.5)

        # Click "Terminal" in the dropdown menu.
        # Terminal is typically the last item, roughly y=80-120 depending on
        # resolution.  We try a reasonable coordinate.
        self.vnc.click(300, 120)
        time.sleep(3.0)

        self._screenshot("post-terminal-open")
        logger.info("Terminal should now be open")

    # -- disk formatting ----------------------------------------------------

    def _erase_disk(self) -> None:
        """Erase the target disk using diskutil in Terminal."""
        assert self.vnc is not None
        logger.info("Erasing disk with diskutil...")

        cmd = 'diskutil eraseDisk APFS "Macintosh HD" disk0'
        self.vnc.type_text(cmd, interval=0.04)
        time.sleep(0.5)
        self.vnc.press_key("return")

        logger.info("Waiting %.0fs for disk format...", self.config.format_wait)
        self._sleep_with_timeout(self.config.format_wait, "disk format")
        self._screenshot("post-diskutil")
        logger.info("Disk format command sent")

    # -- installation start -------------------------------------------------

    def _start_installation(self) -> None:
        """Navigate back from Terminal and start the macOS installer.

        After erasing disk in Terminal, we close Terminal and select
        'Install macOS' from the Recovery utilities window.
        """
        assert self.vnc is not None
        logger.info("Starting macOS installation...")

        # Close Terminal: Cmd+Q
        self.vnc.key_combo("super_l", "q")
        time.sleep(2.0)

        self._screenshot("post-terminal-close")

        # The Recovery main window should now show the utility picker.
        # "Install macOS" is typically the second option.  We try clicking
        # roughly at its expected position and then clicking Continue.
        # Recovery window is typically centered ~1024x768.

        # Click on "Install macOS" (or "Reinstall macOS") icon.
        # This is usually in the second row, roughly at (512, 350).
        self.vnc.click(512, 350)
        time.sleep(2.0)
        self._screenshot("selected-install")

        # Click "Continue" button (bottom-right of the picker window)
        self.vnc.click(700, 500)
        time.sleep(2.0)

        # May see license agreement — click "Agree"
        self.vnc.click(700, 500)
        time.sleep(1.0)
        # Confirmation dialog — click "Agree" again
        self.vnc.click(550, 400)
        time.sleep(2.0)

        # Select disk "Macintosh HD" — it should be the only disk.
        # Click it and then click "Install"
        self.vnc.click(512, 350)
        time.sleep(1.0)
        self.vnc.click(700, 500)
        time.sleep(3.0)

        self._screenshot("install-started")
        logger.info("macOS installer should now be running")

        # Initialize the disk monitor after install starts
        self.disk_monitor.reset()

    # -- installation monitoring --------------------------------------------

    def _monitor_installation(self) -> None:
        """Poll disk growth until installation completes or timeout."""
        logger.info("Monitoring installation progress...")
        logger.info(
            "Completion criteria: disk > %.1f GB and no growth for %ds",
            self.config.min_disk_gb,
            int(self.config.stable_threshold),
        )

        poll_count = 0
        while not self._is_timed_out():
            time.sleep(self.config.poll_interval)
            poll_count += 1

            if self.disk_monitor.check():
                logger.info("Installation completed after %d polls", poll_count)
                return

            if not self.launcher.is_running:
                raise RuntimeError(
                    "QEMU process exited unexpectedly during installation"
                )

            # Periodic screenshot for debugging (every 5 minutes)
            if poll_count % 10 == 0:
                elapsed = time.time() - self._start_time
                logger.info(
                    "Install in progress: %.1f GB, elapsed %.0f min",
                    self.disk_monitor.get_size_gb(),
                    elapsed / 60,
                )
                self._screenshot(f"progress-{poll_count}")

        raise TimeoutError(
            f"Installation did not complete within {self.config.timeout}s"
        )

    # -- snapshot and shutdown -----------------------------------------------

    def _take_snapshot(self) -> None:
        """Take a qcow2 snapshot of the completed installation."""
        assert self.qmp is not None
        name = self.config.snapshot_name
        logger.info("Taking qcow2 snapshot: '%s'", name)
        resp = self.qmp.savevm(name)
        logger.debug("Snapshot response: %s", resp)
        logger.info("✓ Snapshot '%s' created", name)

    def _shutdown(self) -> None:
        """Shut down the VM gracefully via QMP."""
        assert self.qmp is not None
        logger.info("Shutting down VM via QMP quit...")
        try:
            self.qmp.quit()
        except (ConnectionError, BrokenPipeError):
            # Expected — QEMU closes the socket on quit
            pass
        time.sleep(2)
        logger.info("VM shutdown complete")

    # -- helpers ------------------------------------------------------------

    def _screenshot(self, label: str) -> None:
        """Take a diagnostic screenshot if VNC is connected."""
        if self.vnc is None:
            return
        try:
            self.config.screenshot_dir.mkdir(parents=True, exist_ok=True)
            ts = time.strftime("%Y%m%d-%H%M%S")
            path = self.config.screenshot_dir / f"{label}-{ts}.png"
            self.vnc.capture_screenshot(str(path))
        except Exception as exc:
            logger.debug("Screenshot failed (%s): %s", label, exc)

    def _sleep_with_timeout(self, duration: float, description: str) -> None:
        """Sleep for up to `duration` seconds, respecting global timeout."""
        deadline = min(
            time.time() + duration,
            self._start_time + self.config.timeout,
        )
        remaining = deadline - time.time()
        if remaining <= 0:
            raise TimeoutError(f"Timeout reached during: {description}")
        logger.debug("Sleeping %.0fs (%s)", min(duration, remaining), description)
        time.sleep(min(duration, remaining))

    def _is_timed_out(self) -> bool:
        elapsed = time.time() - self._start_time
        if elapsed >= self.config.timeout:
            return True
        return False

    def _cleanup(self) -> None:
        """Clean up all resources."""
        if self.vnc:
            self.vnc.close()
        if self.qmp:
            self.qmp.close()
        if self.launcher.is_running:
            self.launcher.terminate()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="macnix-auto-install",
        description="Automated macOS installation engine for MacNix",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
examples:
  %(prog)s --vnc-port 5900 --qmp-port 5902 \\
           --disk macOS.qcow2 --recovery BaseSystem.img

  %(prog)s --dry-run   # Preview what would happen
""",
    )

    parser.add_argument(
        "--vnc-port", type=int, default=5900,
        help="VNC port (default: 5900)",
    )
    parser.add_argument(
        "--qmp-port", type=int, default=5902,
        help="QMP TCP port (default: 5902)",
    )
    parser.add_argument(
        "--qmp-host", default="localhost",
        help="QMP host (default: localhost)",
    )
    parser.add_argument(
        "--disk", type=Path,
        default=Path("/var/lib/macnix/disks/macOS.qcow2"),
        help="Path to macOS qcow2 disk image",
    )
    parser.add_argument(
        "--recovery", type=Path,
        default=Path("/var/lib/macnix/disks/BaseSystem.img"),
        help="Path to BaseSystem.img recovery media",
    )
    parser.add_argument(
        "--opencore", type=Path,
        default=Path("/var/lib/macnix/disks/OpenCore.qcow2"),
        help="Path to OpenCore qcow2 image",
    )
    parser.add_argument(
        "--ovmf-code", type=Path,
        default=Path("/var/lib/macnix/firmware/OVMF_CODE.fd"),
        help="Path to OVMF_CODE.fd",
    )
    parser.add_argument(
        "--ovmf-vars", type=Path,
        default=Path("/var/lib/macnix/firmware/OVMF_VARS.fd"),
        help="Path to OVMF_VARS.fd",
    )
    parser.add_argument(
        "--timeout", type=int, default=7200,
        help="Maximum time in seconds (default: 7200 / 2 hours)",
    )
    parser.add_argument(
        "--snapshot-name", default="clean-install",
        help="Name for the qcow2 snapshot (default: clean-install)",
    )
    parser.add_argument(
        "--boot-wait", type=float, default=120.0,
        help="Seconds to wait for Recovery boot (default: 120)",
    )
    parser.add_argument(
        "--min-disk-gb", type=float, default=15.0,
        help="Minimum disk size in GB to consider install complete (default: 15)",
    )
    parser.add_argument(
        "--stable-threshold", type=float, default=600.0,
        help="Seconds of no disk growth before declaring completion (default: 600)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print what would happen without executing anything",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Enable debug logging",
    )

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    _setup_logging(args.verbose)

    config = InstallConfig(
        vnc_port=args.vnc_port,
        qmp_host=args.qmp_host,
        qmp_port=args.qmp_port,
        disk_path=args.disk,
        recovery_path=args.recovery,
        opencore_img=args.opencore,
        ovmf_code=args.ovmf_code,
        ovmf_vars=args.ovmf_vars,
        timeout=args.timeout,
        dry_run=args.dry_run,
        verbose=args.verbose,
        boot_wait=args.boot_wait,
        min_disk_gb=args.min_disk_gb,
        stable_threshold=args.stable_threshold,
        snapshot_name=args.snapshot_name,
    )

    installer = MacOSInstaller(config)
    success = installer.run()
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
