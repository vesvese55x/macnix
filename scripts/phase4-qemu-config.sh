#!/usr/bin/env bash
# MacNix Phase 4 — OpenCore + QEMU Configuration
# Generates SMBIOS, configures OpenCore, builds QEMU launch script
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/common.sh"

log_header "MacNix Phase 4 — QEMU & OpenCore Configuration"

PROFILE="${MACNIX_GPU_PROFILE}"
VM_DIR="/var/lib/macnix/disks"
FW_DIR="/var/lib/macnix/firmware"
CFG_DIR="/etc/macnix"
LAUNCH_SCRIPT="/opt/macnix/scripts/launch-vm.sh"

mkdir -p "$CFG_DIR" /opt/macnix/scripts

# Read profile
CPU_VENDOR=$(python3 -c "import json; print(json.load(open('${PROFILE}'))['cpu_vendor'])" 2>/dev/null || echo "intel")
TOTAL_RAM=$(python3 -c "import json; print(json.load(open('${PROFILE}'))['total_ram_gb'])" 2>/dev/null || echo 16)
BRANCH=$(python3 -c "import json; print(json.load(open('${PROFILE}'))['branch'])" 2>/dev/null || echo "D")

# 4.1 Select SMBIOS model
log_step "4.1  Selecting SMBIOS model"
if [[ "$CPU_VENDOR" == "amd" ]]; then
    SMBIOS_MODEL="iMacPro1,1"
    CPU_MODEL="Penryn"
else
    SMBIOS_MODEL="iMac19,1"
    CPU_MODEL="host"
fi
log_info "Model: ${SMBIOS_MODEL}, CPU: ${CPU_MODEL}"

# 4.2 Generate serial numbers
log_step "4.2  Generating SMBIOS serial set"
SMBIOS_GEN="${SCRIPT_DIR}/utils/smbios-gen.sh"
# Simple deterministic-ish serial gen (production would use macserial)
SERIAL="C02$(head -c6 /dev/urandom | xxd -p | head -c6 | tr '[:lower:]' '[:upper:]')"
MLB="C02$(head -c12 /dev/urandom | xxd -p | head -c12 | tr '[:lower:]' '[:upper:]')"
UUID=$(python3 -c "import uuid; print(str(uuid.uuid4()).upper())")
ROM=$(head -c6 /dev/urandom | xxd -p)
log_info "Serial: ${SERIAL}"
log_info "MLB:    ${MLB}"
log_info "UUID:   ${UUID}"
log_info "ROM:    ${ROM}"

# Save SMBIOS to config
cat > "${CFG_DIR}/smbios.json" <<EOF
{
  "model": "${SMBIOS_MODEL}",
  "serial": "${SERIAL}",
  "mlb": "${MLB}",
  "uuid": "${UUID}",
  "rom": "${ROM}"
}
EOF

# 4.4 OSK key (publicly documented)
OSK="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"

# 4.5–4.6 CPU and KVM config
log_step "4.5  Configuring KVM module"
cat > /etc/modprobe.d/macnix-kvm.conf <<EOF
# MacNix: ignore MSRs that macOS reads from non-Apple hardware
options kvm ignore_msrs=1
options kvm report_ignored_msrs=0
EOF
log_success "KVM module configured"

# 4.7 CPU pinning calculation
log_step "4.7  Calculating CPU pinning"
TOTAL_CORES=$(get_physical_cores)
# Give macOS half the cores (minimum 4)
VM_CORES=$(( TOTAL_CORES / 2 ))
(( VM_CORES < 4 )) && VM_CORES=4
(( VM_CORES > TOTAL_CORES - 2 )) && VM_CORES=$(( TOTAL_CORES - 2 ))
HOST_CORES=$(( TOTAL_CORES - VM_CORES ))
log_info "Total: ${TOTAL_CORES} threads, VM: ${VM_CORES}, Host: ${HOST_CORES}"

# 4.8 Memory / hugepages
log_step "4.8  Configuring memory"
VM_RAM_GB=$(( TOTAL_RAM / 2 ))
(( VM_RAM_GB < 8 )) && VM_RAM_GB=8
(( VM_RAM_GB > TOTAL_RAM - 4 )) && VM_RAM_GB=$(( TOTAL_RAM - 4 ))
VM_RAM_MB=$(( VM_RAM_GB * 1024 ))
log_info "VM RAM: ${VM_RAM_GB} GB (${VM_RAM_MB} MB)"

# 4.9–4.11 Generate QEMU launch script
log_step "4.9  Generating QEMU launch script"

# Determine OVMF paths
OVMF_CODE=""
OVMF_VARS=""
for p in "${FW_DIR}/OVMF_CODE.fd" /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
    [[ -f "$p" ]] && OVMF_CODE="$p" && break
done
for p in "${FW_DIR}/OVMF_VARS.fd" /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
    [[ -f "$p" ]] && OVMF_VARS="$p" && break
done

# OpenCore image
OC_IMG=""
for p in "${FW_DIR}/OpenCore/OpenCore.qcow2" "${MACNIX_ROOT}/osx-kvm/OpenCore/OpenCore.qcow2"; do
    [[ -f "$p" ]] && OC_IMG="$p" && break
done

# MAC address from ROM
VM_MAC="52:54:00:${ROM:0:2}:${ROM:2:2}:${ROM:4:2}"

cat > "$LAUNCH_SCRIPT" <<'VMSCRIPT_HEAD'
#!/usr/bin/env bash
# MacNix VM Launch Script — Auto-generated
set -euo pipefail
VMSCRIPT_HEAD

cat >> "$LAUNCH_SCRIPT" <<VMSCRIPT_VARS
# === Configuration ===
VM_NAME="macnix"
VM_CORES=${VM_CORES}
VM_RAM="${VM_RAM_MB}"
VM_MAC="${VM_MAC}"
OSK="${OSK}"
OVMF_CODE="${OVMF_CODE}"
OVMF_VARS="${OVMF_VARS}"
OC_IMG="${OC_IMG}"
MACOS_DISK="${VM_DIR}/macOS.qcow2"
INSTALL_IMG="${VM_DIR}/BaseSystem.img"
SMBIOS_MODEL="${SMBIOS_MODEL}"
CPU_MODEL="${CPU_MODEL}"
BRANCH="${BRANCH}"
VMSCRIPT_VARS

cat >> "$LAUNCH_SCRIPT" <<'VMSCRIPT_BODY'

# === Build QEMU command ===
QEMU_ARGS=(
    -name "$VM_NAME"
    -enable-kvm
    -machine q35,accel=kvm,kernel_irqchip=on
)

# CPU
if [[ "$CPU_MODEL" == "host" ]]; then
    QEMU_ARGS+=(-cpu host,kvm=on,vendor=GenuineIntel,+kvm_pv_unhalt,+kvm_pv_eoi,+hypervisor,+invtsc)
else
    QEMU_ARGS+=(-cpu Penryn,kvm=on,vendor=GenuineIntel,+kvm_pv_unhalt,+kvm_pv_eoi,+hypervisor,+invtsc,+ssse3,+sse4.2,+popcnt,+avx,+avx2,+aes,+xsave,+xsaveopt,check)
fi

QEMU_ARGS+=(
    -smp "cores=${VM_CORES},threads=1,sockets=1"
    -m "${VM_RAM}"
    -device isa-applesmc,osk="$OSK"
    -smbios "type=2,manufacturer=Apple Inc.,product=${SMBIOS_MODEL}"
)

# Firmware
QEMU_ARGS+=(
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}"
    -drive "if=pflash,format=raw,file=${OVMF_VARS}"
)

# OpenCore bootloader
[[ -n "$OC_IMG" ]] && QEMU_ARGS+=(
    -drive "id=OpenCore,if=none,format=qcow2,file=${OC_IMG}"
    -device ide-hd,bus=sata.2,drive=OpenCore
)

# macOS system disk (virtio for performance)
QEMU_ARGS+=(
    -drive "id=MacHDD,if=none,file=${MACOS_DISK},format=qcow2,cache=none,aio=threads"
    -device virtio-blk-pci,drive=MacHDD
)

# Install image (only if exists and first boot)
if [[ -f "$INSTALL_IMG" ]] && [[ "${MACNIX_INSTALL_MODE:-0}" == "1" ]]; then
    QEMU_ARGS+=(
        -drive "id=InstallMedia,if=none,file=${INSTALL_IMG},format=raw"
        -device ide-hd,bus=sata.3,drive=InstallMedia
    )
fi

# Network
QEMU_ARGS+=(
    -netdev user,id=net0
    -device virtio-net-pci,netdev=net0,mac="${VM_MAC}"
)

# Audio (PipeWire/PulseAudio)
QEMU_ARGS+=(
    -audiodev pa,id=snd0,server=/run/user/$(id -u)/pulse/native
    -device intel-hda -device hda-duplex,audiodev=snd0
)

# GPU — branch-specific (Phase 5 appends VFIO devices)
# Default: software GPU for initial install
if [[ "$BRANCH" == "D" ]] || [[ "${MACNIX_INSTALL_MODE:-0}" == "1" ]]; then
    QEMU_ARGS+=(-device virtio-vga-gl -display sdl,gl=on)
fi

# USB (tablet for absolute positioning)
QEMU_ARGS+=(
    -device qemu-xhci
    -device usb-tablet
    -device usb-kbd
)

# Misc
QEMU_ARGS+=(
    -global nec-usb-xhci.msi=off
    -global ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off
)

# Source branch-specific GPU overrides if they exist
OVERRIDE="/etc/macnix/qemu-gpu-override.conf"
[[ -f "$OVERRIDE" ]] && source "$OVERRIDE"

# Launch
exec qemu-system-x86_64 "${QEMU_ARGS[@]}" "$@"
VMSCRIPT_BODY

chmod +x "$LAUNCH_SCRIPT"
log_success "Launch script: ${LAUNCH_SCRIPT}"

# 4.12 OpenCore auto-boot (config.plist patching done in OC setup)
log_step "4.12  OpenCore auto-boot configured (timeout=0)"

# 4.13 systemd service
log_step "4.13  Creating systemd service"
cat > /etc/systemd/system/macnix-vm.service <<EOF
[Unit]
Description=MacNix macOS Virtual Machine
After=network-online.target libvirtd.service macnix-gpu-setup.service
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${LAUNCH_SCRIPT}
ExecStop=/bin/kill -TERM \$MAINPID
Restart=on-failure
RestartSec=10
KillMode=mixed
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload 2>/dev/null || true
log_success "systemd service created: macnix-vm.service"

log_header "Phase 4 Complete"
log_info "Launch manually: sudo ${LAUNCH_SCRIPT}"
log_info "Or enable auto-start: sudo systemctl enable macnix-vm"
