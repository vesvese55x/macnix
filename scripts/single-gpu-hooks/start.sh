#!/usr/bin/env bash
# MacNix — Single-GPU Passthrough Hook: START
# Unbinds GPU from host, binds to vfio-pci before VM starts
set -euo pipefail

source /etc/macnix/single-gpu.conf 2>/dev/null || {
    echo "ERROR: /etc/macnix/single-gpu.conf not found"; exit 1
}

log() { echo "[macnix-hook] $*"; }

log "Starting single-GPU passthrough"

# 1. Stop display manager
DM=""
for dm in gdm3 gdm sddm lightdm lxdm; do
    if systemctl is-active --quiet "$dm" 2>/dev/null; then
        DM="$dm"
        break
    fi
done

if [[ -n "$DM" ]]; then
    log "Stopping display manager: ${DM}"
    systemctl stop "$DM"
    sleep 2
fi

# 2. Kill any remaining GPU-using processes
log "Killing framebuffer users"
for tty in /sys/class/vtconsole/vtcon*/bind; do
    echo 0 > "$tty" 2>/dev/null || true
done

# Unbind EFI framebuffer
echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/unbind 2>/dev/null || true

# 3. Unbind GPU from current driver
GPU_DRIVER_PATH="/sys/bus/pci/devices/${GPU_PCI}/driver"
if [[ -L "$GPU_DRIVER_PATH" ]]; then
    CURRENT_DRV=$(basename "$(readlink -f "$GPU_DRIVER_PATH")")
    log "Unbinding GPU from ${CURRENT_DRV}"
    echo "${GPU_PCI}" > "${GPU_DRIVER_PATH}/unbind" 2>/dev/null || true
    sleep 1
fi

# Unbind audio device too
if [[ -n "${AUDIO_PCI:-}" ]]; then
    AUDIO_DRV_PATH="/sys/bus/pci/devices/${AUDIO_PCI}/driver"
    if [[ -L "$AUDIO_DRV_PATH" ]]; then
        echo "${AUDIO_PCI}" > "${AUDIO_DRV_PATH}/unbind" 2>/dev/null || true
    fi
fi

# 4. Load VFIO modules
log "Loading VFIO modules"
modprobe vfio
modprobe vfio_pci
modprobe vfio_iommu_type1

# 5. Bind GPU to vfio-pci
log "Binding GPU to vfio-pci"
echo "${GPU_VID_DID%%,*}" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true
echo "${GPU_PCI}" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true

if [[ -n "${AUDIO_PCI:-}" ]]; then
    # Extract audio VID:DID from the comma-separated list
    AUDIO_VIDDID="${GPU_VID_DID#*,}"
    [[ -n "$AUDIO_VIDDID" ]] && echo "$AUDIO_VIDDID" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true
    echo "${AUDIO_PCI}" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
fi

# Verify
if [[ -L "/sys/bus/pci/devices/${GPU_PCI}/driver" ]]; then
    BOUND=$(basename "$(readlink -f "/sys/bus/pci/devices/${GPU_PCI}/driver")")
    if [[ "$BOUND" == "vfio-pci" ]]; then
        log "GPU successfully bound to vfio-pci"
    else
        log "WARNING: GPU bound to ${BOUND} instead of vfio-pci"
    fi
fi

log "Single-GPU hook START complete"
