#!/usr/bin/env bash
# MacNix — Single-GPU Passthrough Hook: REVERT
# Returns GPU to host after VM stops
set -euo pipefail

source /etc/macnix/single-gpu.conf 2>/dev/null || {
    echo "ERROR: /etc/macnix/single-gpu.conf not found"; exit 1
}

log() { echo "[macnix-hook] $*"; }
log "Reverting single-GPU passthrough"

# 1. Unbind from vfio-pci
log "Unbinding GPU from vfio-pci"
echo "${GPU_PCI}" > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null || true
[[ -n "${AUDIO_PCI:-}" ]] && echo "${AUDIO_PCI}" > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null || true
sleep 1

# 2. Remove vfio-pci IDs
echo "${GPU_VID_DID%%,*}" > /sys/bus/pci/drivers/vfio-pci/remove_id 2>/dev/null || true

# 3. Rescan PCI bus
echo 1 > /sys/bus/pci/rescan

# 4. Rebind EFI framebuffer
echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/bind 2>/dev/null || true

# 5. Restore VT consoles
for tty in /sys/class/vtconsole/vtcon*/bind; do
    echo 1 > "$tty" 2>/dev/null || true
done

# 6. Restart display manager
sleep 2
for dm in gdm3 gdm sddm lightdm lxdm; do
    if systemctl list-unit-files | grep -q "^${dm}.service"; then
        log "Starting display manager: ${dm}"
        systemctl start "$dm" || true
        break
    fi
done

log "Single-GPU hook REVERT complete"
