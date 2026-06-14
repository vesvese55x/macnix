#!/usr/bin/env bash
# MacNix Setup Assistant — Runs once on first boot after Linux install
set -euo pipefail

FIRSTBOOT_FLAG="/etc/macnix/.firstboot-done"
if [[ -f "$FIRSTBOOT_FLAG" ]]; then
    echo "Setup already completed."
    exit 0
fi

LOG="/var/log/macnix/setup-assistant.log"
mkdir -p /var/log/macnix
exec > >(tee -a "$LOG") 2>&1

SCRIPT_DIR="/opt/macnix/scripts"

echo "===================================="
echo " MacNix Setup Assistant"
echo " $(date)"
echo "===================================="

# Phase 1: Hardware Detection
echo "[1/7] Detecting hardware..."
export MACNIX_GPU_PROFILE="/etc/macnix/gpu-profile.json"
export MACNIX_ROOT="/opt/macnix"
bash "${SCRIPT_DIR}/phase2-gpu-detect.sh" "$MACNIX_GPU_PROFILE" || echo "Warning: GPU detection had issues"

# Phase 2: GPU Passthrough Configuration
echo "[2/7] Configuring GPU passthrough..."
bash "${SCRIPT_DIR}/phase5-gpu-passthrough.sh" || echo "Warning: GPU passthrough had issues"

# Phase 3: Performance Optimization
echo "[3/7] Optimizing for near-native performance..."
export MACNIX_DISK_SIZE="80G"  # Will be overridden by actual partition size
bash "${SCRIPT_DIR}/phase4-qemu-config.sh" || echo "Warning: QEMU config had issues"

# Phase 4: UX Setup
echo "[4/7] Configuring display and input..."
bash "${SCRIPT_DIR}/phase6-ux-setup.sh" || echo "Warning: UX setup had issues"

# Phase 5: Automated macOS Installation
echo "[5/7] Installing macOS automatically (this takes 30-60 minutes)..."
python3 "${SCRIPT_DIR}/macnix-auto-install.py" \
    --vnc-port 5900 \
    --qmp-port 5902 \
    --disk /var/lib/macnix/disks/macOS.qcow2 \
    --recovery /var/lib/macnix/disks/BaseSystem.img \
    --timeout 7200 || {
    echo "ERROR: Automated macOS installation failed."
    echo "You can retry with: python3 ${SCRIPT_DIR}/macnix-auto-install.py --help"
}

# Phase 6: Fingerprint Setup (if sensor detected)
echo "[6/7] Checking for fingerprint sensor..."
if lsusb 2>/dev/null | grep -qi "fingerprint\|goodix\|validity\|elan\|synaptics\|fpc"; then
    echo "Fingerprint sensor detected! Setting up fingerprint unlock..."
    echo "Run 'macnix-fingerprint setup' to configure fingerprint authentication."
    systemctl enable macnix-fingerprint-bridge.service 2>/dev/null || true
else
    echo "No fingerprint sensor detected — skipping."
fi

# Phase 7: Enable auto-start services
echo "[7/7] Enabling services..."
systemctl enable macnix-vm.service 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true

# Mark firstboot complete
mkdir -p /etc/macnix
touch "$FIRSTBOOT_FLAG"

echo "===================================="
echo " Setup Complete!"
echo " Rebooting into macOS..."
echo "===================================="
sleep 3
reboot
