#!/usr/bin/env bash
# MacNix Phase 7 — ISO Build
# Uses live-build to construct a bootable Debian 12 ISO with all MacNix components
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/common.sh"

require_root
log_header "MacNix Phase 7 — ISO Build"

BUILD_DIR="${MACNIX_ROOT}/build"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ────────────────────────────────────────────────────────────
# 7.6  Configure live-build
# ────────────────────────────────────────────────────────────
log_step "7.6  Configuring live-build"

# Clean previous build
[[ -d config ]] && lb clean 2>/dev/null || true

lb config \
    --distribution bookworm \
    --archive-areas "main contrib non-free non-free-firmware" \
    --architectures amd64 \
    --binary-images iso-hybrid \
    --bootloaders "grub-efi,syslinux" \
    --debian-installer false \
    --memtest none \
    --iso-application "MacNix" \
    --iso-publisher "MacNix Project" \
    --iso-volume "MACNIX" \
    --apt-indices false \
    --cache true \
    --cache-packages true

# ────────────────────────────────────────────────────────────
# Package lists
# ────────────────────────────────────────────────────────────
log_step "Writing package lists"

mkdir -p config/package-lists

cat > config/package-lists/macnix.list.chroot <<EOF
# === Virtualisation stack ===
qemu-system-x86
qemu-utils
libvirt-daemon-system
libvirt-clients
ovmf
virtinst

# === GPU / VFIO ===
pciutils
vfio-pci

# === Build essentials ===
build-essential
cmake
pkg-config
git

# === macOS utilities ===
python3
python3-pip
dmg2img
wget
curl
p7zip-full

# === Looking Glass build deps ===
libsdl2-dev
libsdl2-ttf-dev
libfontconfig-dev
libx11-dev
nettle-dev
libgnutls28-dev

# === Installer ===
calamares

# === System ===
linux-image-amd64
linux-headers-amd64
grub-efi-amd64
firmware-linux
firmware-misc-nonfree
sudo
bash-completion
nano
htop
jq
rsync
EOF

# ────────────────────────────────────────────────────────────
# 7.7  Auto-launch Calamares
# ────────────────────────────────────────────────────────────
log_step "7.7  Configuring auto-launch"

mkdir -p config/includes.chroot/etc/xdg/autostart
cat > config/includes.chroot/etc/xdg/autostart/macnix-installer.desktop <<EOF
[Desktop Entry]
Type=Application
Name=MacNix Installer
Comment=Install MacNix
Exec=sudo calamares
Icon=calamares
Terminal=false
Categories=System;
X-GNOME-Autostart-enabled=true
EOF

# ────────────────────────────────────────────────────────────
# 7.8  Bundle MacNix components
# ────────────────────────────────────────────────────────────
log_step "7.8  Bundling MacNix scripts and configs"

CHROOT_BASE="config/includes.chroot"

# Scripts
mkdir -p "${CHROOT_BASE}/opt/macnix/scripts/utils"
mkdir -p "${CHROOT_BASE}/opt/macnix/scripts/single-gpu-hooks"
mkdir -p "${CHROOT_BASE}/opt/macnix/hooks"
cp "${MACNIX_ROOT}/scripts/utils/common.sh" "${CHROOT_BASE}/opt/macnix/scripts/utils/"
cp "${MACNIX_ROOT}/scripts/utils/gpu-db.sh" "${CHROOT_BASE}/opt/macnix/scripts/utils/"
cp "${MACNIX_ROOT}/scripts/phase2-gpu-detect.sh" "${CHROOT_BASE}/opt/macnix/scripts/"
cp "${MACNIX_ROOT}/scripts/phase3-macos-fetch.sh" "${CHROOT_BASE}/opt/macnix/scripts/"
cp "${MACNIX_ROOT}/scripts/phase4-qemu-config.sh" "${CHROOT_BASE}/opt/macnix/scripts/"
cp "${MACNIX_ROOT}/scripts/phase5-gpu-passthrough.sh" "${CHROOT_BASE}/opt/macnix/scripts/"
cp "${MACNIX_ROOT}/scripts/phase6-ux-setup.sh" "${CHROOT_BASE}/opt/macnix/scripts/"
cp "${MACNIX_ROOT}/scripts/macnix-debug.sh" "${CHROOT_BASE}/opt/macnix/scripts/"
cp "${MACNIX_ROOT}/scripts/single-gpu-hooks/"*.sh "${CHROOT_BASE}/opt/macnix/scripts/single-gpu-hooks/"
chmod +x "${CHROOT_BASE}/opt/macnix/scripts/"*.sh
chmod +x "${CHROOT_BASE}/opt/macnix/scripts/single-gpu-hooks/"*.sh

# Calamares modules
mkdir -p "${CHROOT_BASE}/usr/lib/calamares/modules"
for mod in macnix-gpu-detect macnix-macos-fetch macnix-gpu-config; do
    cp -r "${MACNIX_ROOT}/calamares/modules/${mod}" "${CHROOT_BASE}/usr/lib/calamares/modules/"
done

# Calamares settings
mkdir -p "${CHROOT_BASE}/etc/calamares"
cp "${MACNIX_ROOT}/calamares/settings.conf" "${CHROOT_BASE}/etc/calamares/"

# Systemd services
mkdir -p "${CHROOT_BASE}/etc/systemd/system"
for svc in "${MACNIX_ROOT}/systemd/"*.service; do
    [[ -f "$svc" ]] && cp "$svc" "${CHROOT_BASE}/etc/systemd/system/"
done

# OSX-KVM (minimal — just the fetch script and OpenCore)
if [[ -d "${MACNIX_ROOT}/osx-kvm" ]]; then
    mkdir -p "${CHROOT_BASE}/opt/macnix/osx-kvm"
    cp "${MACNIX_ROOT}/osx-kvm/fetch-macOS-v2.py" "${CHROOT_BASE}/opt/macnix/osx-kvm/" 2>/dev/null || true
    [[ -d "${MACNIX_ROOT}/osx-kvm/OpenCore" ]] && \
        cp -r "${MACNIX_ROOT}/osx-kvm/OpenCore" "${CHROOT_BASE}/opt/macnix/osx-kvm/" 2>/dev/null || true
fi

# MacNix directories
mkdir -p "${CHROOT_BASE}/etc/macnix"
mkdir -p "${CHROOT_BASE}/var/lib/macnix/disks"
mkdir -p "${CHROOT_BASE}/var/lib/macnix/firmware"

# ────────────────────────────────────────────────────────────
# 7.9  First-boot service
# ────────────────────────────────────────────────────────────
log_step "7.9  Creating first-boot service"

cat > "${CHROOT_BASE}/opt/macnix/scripts/firstboot.sh" <<'FBEOF'
#!/usr/bin/env bash
# MacNix first-boot finalizer
# Runs once after installation to configure hardware-specific settings
set -euo pipefail

MARKER="/etc/macnix/.firstboot-done"
[[ -f "$MARKER" ]] && exit 0

echo "[macnix] Running first-boot configuration..."

# 1. CPU pinning based on actual core count
TOTAL_CORES=$(nproc)
VM_CORES=$(( TOTAL_CORES / 2 ))
(( VM_CORES < 4 )) && VM_CORES=4
(( VM_CORES > TOTAL_CORES - 2 )) && VM_CORES=$(( TOTAL_CORES - 2 ))
echo "VM_CORES=${VM_CORES}" >> /etc/macnix/vm.conf

# 2. Hugepages based on RAM
TOTAL_RAM=$(awk '/MemTotal/{printf "%d", $2/1048576}' /proc/meminfo)
VM_RAM=$(( TOTAL_RAM / 2 ))
(( VM_RAM < 8 )) && VM_RAM=8
HUGEPAGES=$(( VM_RAM ))  # 1GB pages
echo "VM_RAM_GB=${VM_RAM}" >> /etc/macnix/vm.conf
echo "HUGEPAGES=${HUGEPAGES}" >> /etc/macnix/vm.conf

# Configure hugepages in sysctl
echo "vm.nr_hugepages=${HUGEPAGES}" > /etc/sysctl.d/99-macnix-hugepages.conf
sysctl -p /etc/sysctl.d/99-macnix-hugepages.conf 2>/dev/null || true

# 3. Detect input devices for evdev
KBD=$(find /dev/input/by-id/ -name "*kbd*" -o -name "*keyboard*" 2>/dev/null | head -1)
MOUSE=$(find /dev/input/by-id/ -name "*mouse*" 2>/dev/null | head -1)
if [[ -n "$KBD" ]]; then
    echo "KBD_EVDEV=${KBD}" >> /etc/macnix/evdev.conf
fi
if [[ -n "$MOUSE" ]]; then
    echo "MOUSE_EVDEV=${MOUSE}" >> /etc/macnix/evdev.conf
fi

# 4. Run Phase 4 to generate QEMU launch script
bash /opt/macnix/scripts/phase4-qemu-config.sh 2>/dev/null || true

# 5. Run Phase 5 for GPU passthrough
bash /opt/macnix/scripts/phase5-gpu-passthrough.sh 2>/dev/null || true

# 6. Run Phase 6 for UX layer
bash /opt/macnix/scripts/phase6-ux-setup.sh 2>/dev/null || true

# 7. Enable services
systemctl enable macnix-vm.service 2>/dev/null || true
systemctl enable macnix-looking-glass.service 2>/dev/null || true

# Mark done
touch "$MARKER"
echo "[macnix] First-boot configuration complete"
echo "[macnix] Reboot to start macOS"
FBEOF
chmod +x "${CHROOT_BASE}/opt/macnix/scripts/firstboot.sh"

cat > "${CHROOT_BASE}/etc/systemd/system/macnix-firstboot.service" <<EOF
[Unit]
Description=MacNix First Boot Configuration
After=network-online.target
ConditionPathExists=!/etc/macnix/.firstboot-done

[Service]
Type=oneshot
ExecStart=/opt/macnix/scripts/firstboot.sh
RemainAfterExit=yes
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

# ────────────────────────────────────────────────────────────
# Build hooks
# ────────────────────────────────────────────────────────────
mkdir -p config/hooks/live
cat > config/hooks/live/0100-macnix-setup.hook.chroot <<'HOOKEOF'
#!/bin/bash
# Enable MacNix services in the installed system
systemctl enable macnix-firstboot.service 2>/dev/null || true

# Ensure scripts are executable
chmod +x /opt/macnix/scripts/*.sh 2>/dev/null || true
chmod +x /opt/macnix/scripts/single-gpu-hooks/*.sh 2>/dev/null || true
chmod +x /opt/macnix/scripts/utils/*.sh 2>/dev/null || true
HOOKEOF
chmod +x config/hooks/live/0100-macnix-setup.hook.chroot

# ────────────────────────────────────────────────────────────
# 7.10  Build ISO
# ────────────────────────────────────────────────────────────
log_step "7.10  Building ISO"
log_info "This will take 15–30 minutes..."

lb build 2>&1 | tee "${BUILD_DIR}/build.log"

# Find output ISO
ISO_FILE=$(find "$BUILD_DIR" -maxdepth 1 -name "*.iso" | head -1)
if [[ -n "$ISO_FILE" ]]; then
    ISO_SIZE=$(du -h "$ISO_FILE" | awk '{print $1}')
    log_success "ISO built: ${ISO_FILE} (${ISO_SIZE})"
    
    # Copy to output
    mkdir -p "${BUILD_DIR}/output"
    mv "$ISO_FILE" "${BUILD_DIR}/output/macnix-$(date +%Y%m%d).iso"
    log_success "Final ISO: ${BUILD_DIR}/output/macnix-$(date +%Y%m%d).iso"
else
    log_error "ISO build failed — check ${BUILD_DIR}/build.log"
    exit 1
fi

log_header "Phase 7 Complete"
log_info "Flash the ISO to USB: sudo dd if=output/macnix-*.iso of=/dev/sdX bs=4M status=progress"
