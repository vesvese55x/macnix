#!/usr/bin/env bash
# MacNix Phase 6 — UX Layer (Looking Glass, Audio, Input, Boot Sequence)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/common.sh"

require_root
log_header "MacNix Phase 6 — UX Layer"

PROFILE="${MACNIX_GPU_PROFILE}"
BRANCH=$(python3 -c "import json; print(json.load(open('${PROFILE}'))['branch'])" 2>/dev/null || echo "D")

# ────────────────────────────────────────────────────────────
# 6.1  Looking Glass (KVMFR) — only for passthrough branches
# ────────────────────────────────────────────────────────────
if [[ "$BRANCH" =~ ^[ABE]$ ]]; then
    log_step "6.1  Installing Looking Glass"
    
    LG_VERSION="B7-rc1"
    LG_DIR="/opt/macnix/looking-glass"
    mkdir -p "$LG_DIR"
    
    # Check if already built
    if [[ -x "${LG_DIR}/looking-glass-client" ]]; then
        log_info "Looking Glass already installed"
    else
        # Install build deps
        apt-get install -y \
            cmake gcc g++ pkg-config \
            libsdl2-dev libsdl2-ttf-dev \
            libspice-protocol-dev \
            libfontconfig-dev libx11-dev \
            nettle-dev libgnutls28-dev \
            libxi-dev libxss-dev libxcursor-dev \
            libxinerama-dev libxpresent-dev \
            libwayland-dev wayland-protocols \
            libpipewire-0.3-dev libsamplerate0-dev \
            binutils-dev 2>/dev/null || log_warn "Some LG deps may be missing"
        
        # Clone and build
        if [[ ! -d "${LG_DIR}/src" ]]; then
            git clone --depth 1 --branch "${LG_VERSION}" \
                https://github.com/gnif/LookingGlass.git "${LG_DIR}/src" 2>/dev/null || \
            git clone --depth 1 https://github.com/gnif/LookingGlass.git "${LG_DIR}/src"
        fi
        
        cd "${LG_DIR}/src/client"
        mkdir -p build && cd build
        cmake -DENABLE_WAYLAND=ON -DENABLE_X11=ON -DENABLE_PIPEWIRE=ON ..
        make -j$(nproc)
        cp looking-glass-client "${LG_DIR}/"
        log_success "Looking Glass built"
    fi
    
    # 6.2 IVSHMEM shared memory device
    log_step "6.2  Configuring IVSHMEM shared memory"
    
    # Determine SHMEM size based on resolution target
    SHMEM_SIZE="64"  # MB, enough for 1080p; use 256 for 4K
    
    # Create shared memory file
    SHM_PATH="/dev/shm/looking-glass"
    touch "$SHM_PATH"
    chmod 660 "$SHM_PATH"
    chown root:kvm "$SHM_PATH"
    
    # Add IVSHMEM to QEMU override
    GPU_OVERRIDE="/etc/macnix/qemu-gpu-override.conf"
    if ! grep -q "ivshmem" "$GPU_OVERRIDE" 2>/dev/null; then
        cat >> "$GPU_OVERRIDE" <<EOF

# Looking Glass IVSHMEM
QEMU_ARGS+=(-device ivshmem-plain,memdev=ivshmem,bus=pcie.0)
QEMU_ARGS+=(-object memory-backend-file,id=ivshmem,share=on,mem-path=/dev/shm/looking-glass,size=${SHMEM_SIZE}M)
EOF
    fi
    
    # tmpfiles.d for persistent SHM
    cat > /etc/tmpfiles.d/macnix-shm.conf <<EOF
f /dev/shm/looking-glass 0660 root kvm -
EOF
    
    # 6.3 Looking Glass client service
    log_step "6.3  Creating Looking Glass service"
    cat > /etc/systemd/system/macnix-looking-glass.service <<EOF
[Unit]
Description=MacNix Looking Glass Client
After=macnix-vm.service
Requires=macnix-vm.service

[Service]
Type=simple
User=macnix
Environment=SDL_VIDEODRIVER=x11
ExecStartPre=/bin/sleep 5
ExecStart=${LG_DIR}/looking-glass-client -F -m 97 -c /etc/macnix/looking-glass.ini
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical.target
EOF
    
    # 6.4 Looking Glass config — fullscreen, no decorations
    cat > /etc/macnix/looking-glass.ini <<EOF
[app]
shmFile=/dev/shm/looking-glass
renderer=auto

[win]
fullScreen=yes
showFPS=no
noScreensaver=yes
borderless=yes
maximize=yes

[input]
escapeKey=KEY_RIGHTCTRL
grabKeyboardOnFocus=yes

[spice]
enable=no
EOF
    log_success "Looking Glass configured"
else
    log_info "Branch ${BRANCH} — Looking Glass not needed (using direct display)"
fi

# ────────────────────────────────────────────────────────────
# 6.5–6.6  Audio (already in launch script, verify PipeWire)
# ────────────────────────────────────────────────────────────
log_step "6.5  Verifying audio setup"
if command -v pipewire &>/dev/null; then
    log_success "PipeWire available"
elif command -v pulseaudio &>/dev/null; then
    log_success "PulseAudio available"
else
    log_warn "No audio daemon found — install pipewire or pulseaudio"
fi

# ────────────────────────────────────────────────────────────
# 6.7–6.8  Input (evdev passthrough)
# ────────────────────────────────────────────────────────────
log_step "6.7  Configuring input passthrough"
if [[ "$BRANCH" =~ ^[ABE]$ ]]; then
    # Find keyboard and mouse evdev paths
    log_info "Available input devices:"
    ls -la /dev/input/by-id/ 2>/dev/null | grep -E "kbd|mouse|keyboard" | head -10
    
    # evdev config will be finalized by first-boot service
    # since exact device paths depend on connected hardware
    cat > /etc/macnix/evdev.conf <<EOF
# Input device paths — populated by first-boot service
# KBD_EVDEV=/dev/input/by-id/...
# MOUSE_EVDEV=/dev/input/by-id/...
CAPTURE_KEY=KEY_RIGHTCTRL
EOF
    log_info "evdev will be configured on first boot"
fi

# ────────────────────────────────────────────────────────────
# 6.9  Boot sequence
# ────────────────────────────────────────────────────────────
log_step "6.9  Configuring boot sequence"

# GRUB: zero timeout
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub 2>/dev/null || true
update_grub_config

# 6.11 Recovery escape: Right Ctrl + F2 drops to TTY
log_step "6.11  Recovery escape configured"
log_info "  Escape: Right Ctrl releases input from Looking Glass"
log_info "  TTY access: Ctrl+Alt+F2 for Linux console"

# Install debug script
cp "${SCRIPT_DIR}/macnix-debug.sh" /usr/local/bin/macnix-debug
chmod +x /usr/local/bin/macnix-debug
log_info "  Debug Menu: type 'macnix-debug' in the TTY"

# Create macnix user for Looking Glass service
if ! id macnix &>/dev/null; then
    useradd -r -s /bin/false -G kvm,video,input macnix 2>/dev/null || true
fi

log_header "Phase 6 Complete"
log_info "UX layer configured"
log_info "After reboot: POST → macOS login in < 45s"
