#!/usr/bin/env bash
# MacNix Phase 5 — GPU Passthrough Configuration
# Reads GPU profile and applies the correct branch config
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/common.sh"

require_root
log_header "MacNix Phase 5 — GPU Passthrough"

PROFILE="${MACNIX_GPU_PROFILE}"
[[ ! -f "$PROFILE" ]] && { log_error "GPU profile not found. Run phase2 first."; exit 1; }

BRANCH=$(python3 -c "import json; print(json.load(open('${PROFILE}'))['branch'])")
CPU_VENDOR=$(python3 -c "import json; print(json.load(open('${PROFILE}'))['cpu_vendor'])")
TGT_IDX=$(python3 -c "import json; print(json.load(open('${PROFILE}'))['target_gpu_idx'])")
TGT_PCI=$(python3 -c "import json; p=json.load(open('${PROFILE}')); print(p['gpus'][p['target_gpu_idx']]['pci'])")
TGT_VID=$(python3 -c "import json; p=json.load(open('${PROFILE}')); print(p['gpus'][p['target_gpu_idx']]['vid'])")
TGT_DID=$(python3 -c "import json; p=json.load(open('${PROFILE}')); print(p['gpus'][p['target_gpu_idx']]['did'])")

log_info "Branch: ${BRANCH}, GPU: ${TGT_PCI} [${TGT_VID}:${TGT_DID}]"

# ────────────────────────────────────────────────────────────
# [ALL] 5.1 — IOMMU kernel params
# ────────────────────────────────────────────────────────────
log_step "5.1  Configuring IOMMU kernel parameters"
GRUB_FILE="/etc/default/grub"
if [[ "$CPU_VENDOR" == "intel" ]]; then
    add_grub_param "intel_iommu=on"
elif [[ "$CPU_VENDOR" == "amd" ]]; then
    add_grub_param "amd_iommu=on"
fi
add_grub_param "iommu=pt"
update_grub_config

# Find companion audio device in same IOMMU group
AUDIO_PCI=""
IOMMU_GRP=$(python3 -c "import json; p=json.load(open('${PROFILE}')); print(p['gpus'][p['target_gpu_idx']]['iommu_group'])")
if [[ "$IOMMU_GRP" != "none" ]]; then
    for dev in /sys/kernel/iommu_groups/${IOMMU_GRP}/devices/*; do
        dev_addr=$(basename "$dev")
        dev_class=$(cat "${dev}/class" 2>/dev/null || echo "")
        # 0x040300 = Audio device
        if [[ "$dev_class" == "0x040300" ]]; then
            AUDIO_PCI="${dev_addr#0000:}"
            log_info "Found companion audio: ${AUDIO_PCI}"
        fi
    done
fi

# ────────────────────────────────────────────────────────────
# Branch routing
# ────────────────────────────────────────────────────────────
GPU_OVERRIDE="/etc/macnix/qemu-gpu-override.conf"

case "$BRANCH" in
# ════════════════════════════════════════════════════════════
# Branch A — AMD VFIO Passthrough
# ════════════════════════════════════════════════════════════
A)
    log_step "Branch A: AMD VFIO Passthrough"
    
    # 5.2 vfio-pci module options
    log_step "5.2  Binding GPU to vfio-pci"
    VID_DID="${TGT_VID}:${TGT_DID}"
    [[ -n "$AUDIO_PCI" ]] && {
        AUDIO_IDS=$(lspci -nn -s "$AUDIO_PCI" | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])' | tail -1)
        VID_DID="${VID_DID},${AUDIO_IDS}"
    }
    cat > /etc/modprobe.d/macnix-vfio.conf <<EOF
options vfio-pci ids=${VID_DID}
softdep amdgpu pre: vfio-pci
softdep radeon pre: vfio-pci
EOF
    
    # 5.3 initramfs modules
    log_step "5.3  Adding VFIO to initramfs"
    cat > /etc/modules-load.d/macnix-vfio.conf <<EOF
vfio
vfio_iommu_type1
vfio_pci
EOF
    rebuild_initramfs
    
    # 5.5A QEMU GPU override
    cat > "$GPU_OVERRIDE" <<EOF
# Branch A: AMD VFIO passthrough
QEMU_ARGS+=(-device vfio-pci,host=0000:${TGT_PCI},x-vga=on,multifunction=on)
EOF
    [[ -n "$AUDIO_PCI" ]] && echo "QEMU_ARGS+=(-device vfio-pci,host=0000:${AUDIO_PCI})" >> "$GPU_OVERRIDE"
    # 5.6A Remove software GPU
    echo '# Software GPU removed — AMD passthrough active' >> "$GPU_OVERRIDE"
    log_success "AMD passthrough configured"
    ;;

# ════════════════════════════════════════════════════════════
# Branch B — NVIDIA Kepler VFIO + ROM Patch
# ════════════════════════════════════════════════════════════
B)
    log_step "Branch B: NVIDIA Kepler Passthrough"
    
    VID_DID="${TGT_VID}:${TGT_DID}"
    [[ -n "$AUDIO_PCI" ]] && {
        AUDIO_IDS=$(lspci -nn -s "$AUDIO_PCI" | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])' | tail -1)
        VID_DID="${VID_DID},${AUDIO_IDS}"
    }
    cat > /etc/modprobe.d/macnix-vfio.conf <<EOF
options vfio-pci ids=${VID_DID}
softdep nouveau pre: vfio-pci
softdep nvidia pre: vfio-pci
EOF
    cat > /etc/modules-load.d/macnix-vfio.conf <<EOF
vfio
vfio_iommu_type1
vfio_pci
EOF
    rebuild_initramfs
    
    # 5.5B ROM dump placeholder
    ROM_FILE="/var/lib/macnix/firmware/gpu-vbios.rom"
    log_warn "VBIOS ROM dump required for Kepler passthrough"
    log_info "Attempting to read ROM from sysfs..."
    ROM_SYS="/sys/bus/pci/devices/0000:${TGT_PCI}/rom"
    if [[ -f "$ROM_SYS" ]]; then
        echo 1 > "$ROM_SYS" 2>/dev/null || true
        cat "$ROM_SYS" > "$ROM_FILE" 2>/dev/null || true
        echo 0 > "$ROM_SYS" 2>/dev/null || true
        if [[ -s "$ROM_FILE" ]]; then
            log_success "VBIOS ROM dumped to ${ROM_FILE}"
        else
            log_warn "ROM dump empty — manual ROM extraction may be needed"
        fi
    fi
    
    # 5.7B QEMU override with ROM
    cat > "$GPU_OVERRIDE" <<EOF
# Branch B: NVIDIA Kepler VFIO + ROM patch
QEMU_ARGS+=(-device vfio-pci,host=0000:${TGT_PCI},x-vga=on,multifunction=on,romfile=${ROM_FILE})
EOF
    [[ -n "$AUDIO_PCI" ]] && echo "QEMU_ARGS+=(-device vfio-pci,host=0000:${AUDIO_PCI})" >> "$GPU_OVERRIDE"
    log_success "Kepler passthrough configured"
    ;;

# ════════════════════════════════════════════════════════════
# Branch C — Intel iGPU GVT-g
# ════════════════════════════════════════════════════════════
C)
    log_step "Branch C: Intel iGPU GVT-g"
    
    # 5.5C Check GVT-g support
    MDEV_PATH="/sys/bus/pci/devices/0000:${TGT_PCI}/mdev_supported_types"
    if [[ -d "$MDEV_PATH" ]]; then
        # 5.6C Create mdev
        log_info "GVT-g supported — creating mediated device"
        cat > /etc/modules-load.d/macnix-gvtg.conf <<EOF
kvmgt
vfio-mdev
EOF
        # Select best mdev type (prefer V5_4 for 4K)
        MDEV_TYPE=$(ls "$MDEV_PATH" 2>/dev/null | grep -i "V5_4\|V5_8" | head -1)
        [[ -z "$MDEV_TYPE" ]] && MDEV_TYPE=$(ls "$MDEV_PATH" 2>/dev/null | head -1)
        
        if [[ -n "$MDEV_TYPE" ]]; then
            MDEV_UUID=$(python3 -c "import uuid; print(uuid.uuid4())")
            cat > "$GPU_OVERRIDE" <<EOF
# Branch C: Intel GVT-g
# Create mdev if not exists
MDEV_PATH="/sys/bus/pci/devices/0000:${TGT_PCI}/mdev_supported_types/${MDEV_TYPE}/create"
MDEV_UUID="${MDEV_UUID}"
[[ ! -d "/sys/bus/mdev/devices/\${MDEV_UUID}" ]] && echo "\${MDEV_UUID}" > "\${MDEV_PATH}" 2>/dev/null || true
QEMU_ARGS+=(-device vfio-pci,sysfsdev=/sys/bus/mdev/devices/\${MDEV_UUID},display=on,x-igd-opregion=on)
QEMU_ARGS+=(-display gtk,gl=on)
EOF
            log_success "GVT-g mdev configured (type: ${MDEV_TYPE})"
        fi
    else
        log_warn "GVT-g not available — falling back to virtio-vga"
        cat > "$GPU_OVERRIDE" <<EOF
# Branch C fallback: virtio-vga (no GVT-g)
QEMU_ARGS+=(-device virtio-vga-gl -display sdl,gl=on)
EOF
    fi
    ;;

# ════════════════════════════════════════════════════════════
# Branch D — Software Rendering
# ════════════════════════════════════════════════════════════
D)
    log_step "Branch D: Software rendering fallback"
    cat > "$GPU_OVERRIDE" <<EOF
# Branch D: Software rendering (no GPU passthrough)
QEMU_ARGS+=(-device virtio-vga-gl -display sdl,gl=on)
EOF
    log_warn "No GPU acceleration — macOS will use software rendering"
    ;;

# ════════════════════════════════════════════════════════════
# Branch E — Single-GPU Passthrough Hooks
# ════════════════════════════════════════════════════════════
E)
    log_step "Branch E: Single-GPU passthrough with hooks"
    
    VID_DID="${TGT_VID}:${TGT_DID}"
    [[ -n "$AUDIO_PCI" ]] && {
        AUDIO_IDS=$(lspci -nn -s "$AUDIO_PCI" | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])' | tail -1)
        VID_DID="${VID_DID},${AUDIO_IDS}"
    }
    
    # Install hook scripts
    HOOK_DIR="/opt/macnix/hooks"
    mkdir -p "$HOOK_DIR"
    cp "${SCRIPT_DIR}/single-gpu-hooks/start.sh" "$HOOK_DIR/"
    cp "${SCRIPT_DIR}/single-gpu-hooks/revert.sh" "$HOOK_DIR/"
    chmod +x "$HOOK_DIR"/*.sh
    
    # Write GPU info for hooks
    cat > "${CFG_DIR:-/etc/macnix}/single-gpu.conf" <<EOF
GPU_PCI="0000:${TGT_PCI}"
GPU_VID_DID="${VID_DID}"
AUDIO_PCI="${AUDIO_PCI:+0000:${AUDIO_PCI}}"
EOF
    
    # GPU override — hooks handle bind/unbind
    cat > "$GPU_OVERRIDE" <<EOF
# Branch E: Single-GPU hooks handle driver binding
QEMU_ARGS+=(-device vfio-pci,host=0000:${TGT_PCI},x-vga=on,multifunction=on)
EOF
    [[ -n "$AUDIO_PCI" ]] && echo "QEMU_ARGS+=(-device vfio-pci,host=0000:${AUDIO_PCI})" >> "$GPU_OVERRIDE"
    
    # systemd service for hooks
    cat > /etc/systemd/system/macnix-gpu-setup.service <<EOF
[Unit]
Description=MacNix Single-GPU Passthrough Setup
Before=macnix-vm.service

[Service]
Type=oneshot
ExecStart=${HOOK_DIR}/start.sh
ExecStop=${HOOK_DIR}/revert.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    log_success "Single-GPU hooks installed"
    ;;
esac

# 5.4 Verify (informational — actual verify needs reboot)
log_step "5.4  Driver binding status"
CURRENT_DRV=$(get_pci_driver "$TGT_PCI")
if [[ "$CURRENT_DRV" == "vfio-pci" ]]; then
    log_success "GPU already bound to vfio-pci"
else
    log_info "GPU currently using: ${CURRENT_DRV}"
    log_info "Will switch to vfio-pci after reboot"
fi

log_header "Phase 5 Complete"
log_info "Reboot required for IOMMU/VFIO changes to take effect"
