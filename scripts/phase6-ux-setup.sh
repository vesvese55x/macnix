#!/usr/bin/env bash
# MacNix Phase 6 — UX Layer (Display, Audio, Input, Boot Sequence)
# Configures display output, evdev input, and boot sequence
# Looking Glass removed (incompatible with macOS guests)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/common.sh"

require_root
log_header "MacNix Phase 6 — UX Layer"

PROFILE="${MACNIX_GPU_PROFILE}"
BRANCH=$(python3 -c "import json; print(json.load(open('${PROFILE}'))['branch'])" 2>/dev/null || echo "D")

# ────────────────────────────────────────────────────────────
# 6.1  Display Configuration
# ────────────────────────────────────────────────────────────
log_step "6.1  Configuring display output"

case "$BRANCH" in
    A|B)
        # Multi-GPU passthrough: macOS uses the passed-through GPU directly
        log_info "Branch ${BRANCH}: Direct GPU output"
        log_info "  macOS will display on the monitor connected to the passed-through GPU"
        log_info "  No relay software needed — native display performance"
        ;;
    E)
        # Single-GPU: start/revert hooks switch GPU between host and guest
        log_info "Branch E: Single-GPU passthrough"
        log_info "  Display manager will stop before VM starts"
        log_info "  GPU unbinds from host → binds to VM"
        log_info "  macOS appears on your monitor (native GPU output)"

        # Ensure hooks are executable
        HOOKS_DIR="/opt/macnix/scripts/single-gpu-hooks"
        if [[ -d "$HOOKS_DIR" ]]; then
            chmod +x "${HOOKS_DIR}/start.sh" "${HOOKS_DIR}/revert.sh" 2>/dev/null || true
        fi
        ;;
    C)
        # Intel GVT-g: SPICE client in fullscreen
        log_info "Branch C: Intel GVT-g with SPICE display"
        log_info "  macOS will appear via SPICE fullscreen viewer"

        # Enable SPICE viewer service
        if [[ -f /etc/systemd/system/macnix-spice-viewer.service ]]; then
            systemctl enable macnix-spice-viewer.service 2>/dev/null || true
            log_success "SPICE viewer service enabled"
        else
            # Create it inline if not already installed
            cat > /etc/systemd/system/macnix-spice-viewer.service <<EOF
[Unit]
Description=MacNix SPICE Display
After=macnix-vm.service
Requires=macnix-vm.service

[Service]
Type=simple
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/remote-viewer --full-screen spice://localhost:5930
User=macnix
Environment=DISPLAY=:0
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical.target
EOF
            systemctl enable macnix-spice-viewer.service 2>/dev/null || true
            log_success "SPICE viewer service created and enabled"
        fi
        ;;
    D)
        # Software rendering: SPICE client
        log_info "Branch D: Software rendering with SPICE display"
        log_warn "Performance will be limited (15-30% native)"
        log_info "  Consider adding a macOS-compatible AMD GPU for full performance"

        # Same SPICE service as Branch C
        if [[ -f /etc/systemd/system/macnix-spice-viewer.service ]]; then
            systemctl enable macnix-spice-viewer.service 2>/dev/null || true
        else
            cat > /etc/systemd/system/macnix-spice-viewer.service <<EOF
[Unit]
Description=MacNix SPICE Display
After=macnix-vm.service
Requires=macnix-vm.service

[Service]
Type=simple
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/remote-viewer --full-screen spice://localhost:5930
User=macnix
Environment=DISPLAY=:0
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical.target
EOF
            systemctl enable macnix-spice-viewer.service 2>/dev/null || true
        fi
        log_success "SPICE viewer service enabled"
        ;;
esac

# ────────────────────────────────────────────────────────────
# 6.2  Input Configuration (Evdev)
# ────────────────────────────────────────────────────────────
log_step "6.2  Configuring input passthrough"

if [[ "$BRANCH" =~ ^[ABE]$ ]]; then
    log_info "Evdev input passthrough configured"
    log_info "  Toggle host/guest: Press BOTH Ctrl keys simultaneously"
    log_info "  Fallback: USB tablet always available via VNC/SPICE"

    # Ensure evdev config is populated with detected devices
    if [[ -f /etc/macnix/evdev.conf ]]; then
        source /etc/macnix/evdev.conf
        if [[ -z "${KBD_EVDEV:-}" ]]; then
            # Try to detect now
            KBD_EVDEV=$(find /dev/input/by-id/ -name '*kbd*' -o -name '*keyboard*' 2>/dev/null | head -1 || true)
            MOUSE_EVDEV=$(find /dev/input/by-id/ -name '*mouse*' 2>/dev/null | head -1 || true)
            cat > /etc/macnix/evdev.conf <<EOF
KBD_EVDEV="${KBD_EVDEV}"
MOUSE_EVDEV="${MOUSE_EVDEV}"
CAPTURE_KEY=KEY_RIGHTCTRL
EOF
            log_info "Updated evdev paths: kbd=${KBD_EVDEV}, mouse=${MOUSE_EVDEV}"
        fi
    fi
else
    log_info "Branch ${BRANCH}: Using USB tablet + SPICE mouse (no evdev needed)"
fi

# ────────────────────────────────────────────────────────────
# 6.3  Audio
# ────────────────────────────────────────────────────────────
log_step "6.3  Verifying audio setup"
if command -v pipewire &>/dev/null; then
    log_success "PipeWire available — audio will work via QEMU intel-hda"
elif command -v pulseaudio &>/dev/null; then
    log_success "PulseAudio available — audio will work via QEMU intel-hda"
else
    log_warn "No audio daemon found — install pipewire or pulseaudio for sound"
fi

# ────────────────────────────────────────────────────────────
# 6.4  Boot Sequence (seamless, invisible Linux)
# ────────────────────────────────────────────────────────────
log_step "6.4  Configuring seamless boot sequence"

# GRUB: zero timeout, hidden, quiet
if [[ -f /etc/default/grub ]]; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub 2>/dev/null || true
    if ! grep -q "GRUB_TIMEOUT_STYLE" /etc/default/grub; then
        echo 'GRUB_TIMEOUT_STYLE=hidden' >> /etc/default/grub
    fi
    update_grub_config 2>/dev/null || true
fi

# Plymouth: Apple boot theme (already installed by gpu-config module)
if [[ -d /usr/share/plymouth/themes/macnix ]]; then
    plymouth-set-default-theme -R macnix 2>/dev/null || true
    log_success "Plymouth Apple boot theme active"
fi

# TTY autologin (so the VM auto-starts without login screen)
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF

# ────────────────────────────────────────────────────────────
# 6.5  QMP Socket for Fingerprint Bridge
# ────────────────────────────────────────────────────────────
log_step "6.5  Configuring QMP socket for automation"
log_info "QMP: tcp:localhost:5902 (for fingerprint bridge + auto-install)"
log_info "VNC: localhost:5900 (for automation, localhost only)"

# ────────────────────────────────────────────────────────────
# 6.6  Recovery Access
# ────────────────────────────────────────────────────────────
log_step "6.6  Configuring recovery access"
log_info "  TTY access: Ctrl+Alt+F2 for Linux console"
log_info "  Evdev toggle: Both Ctrl keys to release input from VM"
log_info "  Debug: type 'macnix-debug' in TTY for diagnostics"

# Install debug script if it exists
if [[ -f "${SCRIPT_DIR}/macnix-debug.sh" ]]; then
    cp "${SCRIPT_DIR}/macnix-debug.sh" /usr/local/bin/macnix-debug
    chmod +x /usr/local/bin/macnix-debug
fi

# Create macnix system user for services
if ! id macnix &>/dev/null; then
    useradd -r -s /bin/false -G kvm,video,input macnix 2>/dev/null || true
fi

log_header "Phase 6 Complete"
log_info "Display: ${BRANCH} configuration applied"
log_info "Input: evdev passthrough (Ctrl+Ctrl toggle)"
log_info "Audio: PipeWire/PulseAudio via intel-hda"
log_info "Boot: Plymouth Apple logo → auto-login → VM auto-start"
log_info "Recovery: Ctrl+Alt+F2 for Linux TTY"
