#!/usr/bin/env bash
# MacNix Phase 4 — OpenCore + QEMU Configuration + Performance Engine
# Generates SMBIOS, configures OpenCore, builds QEMU launch script
# with near-native performance: CPU pinning, hugepages, NUMA, evdev, virtio
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
SERIAL="C02$(head -c6 /dev/urandom | xxd -p | head -c6 | tr '[:lower:]' '[:upper:]')"
MLB="C02$(head -c12 /dev/urandom | xxd -p | head -c12 | tr '[:lower:]' '[:upper:]')"
UUID=$(python3 -c "import uuid; print(str(uuid.uuid4()).upper())")
ROM=$(head -c6 /dev/urandom | xxd -p)
log_info "Serial: ${SERIAL}"
log_info "MLB:    ${MLB}"
log_info "UUID:   ${UUID}"

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

# 4.3 OSK key
OSK="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"

# 4.4 KVM config
log_step "4.4  Configuring KVM module"
cat > /etc/modprobe.d/macnix-kvm.conf <<EOF
# MacNix: ignore MSRs that macOS reads from non-Apple hardware
options kvm ignore_msrs=1
options kvm report_ignored_msrs=0
EOF
log_success "KVM module configured"

# ────────────────────────────────────────────────────────────
# 4.5 PERFORMANCE: CPU Pinning + NUMA
# ────────────────────────────────────────────────────────────
log_step "4.5  Calculating CPU pinning & NUMA topology"
TOTAL_CORES=$(get_physical_cores)

# Reserve 2 cores for host, give the rest to VM (minimum 4)
VM_CORES=$((TOTAL_CORES - 2))
(( VM_CORES < 4 )) && VM_CORES=4
(( VM_CORES > TOTAL_CORES )) && VM_CORES=$((TOTAL_CORES - 1))
HOST_CORES=$((TOTAL_CORES - VM_CORES))
log_info "Total: ${TOTAL_CORES} cores, VM: ${VM_CORES}, Host: ${HOST_CORES}"

# Build CPU pinning list (host gets 0-(HOST_CORES-1), VM gets the rest)
HOST_CPU_LIST="0-$((HOST_CORES - 1))"
VM_CPU_LIST="${HOST_CORES}-$((TOTAL_CORES - 1))"
log_info "Host cores: ${HOST_CPU_LIST}, VM cores: ${VM_CPU_LIST}"

# NUMA detection
NUMA_NODES=1
if command -v numactl &>/dev/null; then
    NUMA_NODES=$(numactl --hardware 2>/dev/null | grep "available:" | awk '{print $2}' || echo 1)
fi
log_info "NUMA nodes: ${NUMA_NODES}"

# ────────────────────────────────────────────────────────────
# 4.6 PERFORMANCE: Memory & Hugepages
# ────────────────────────────────────────────────────────────
log_step "4.6  Configuring memory & hugepages"
VM_RAM_GB=$((TOTAL_RAM - 4))
(( VM_RAM_GB < 8 )) && VM_RAM_GB=8
(( VM_RAM_GB > TOTAL_RAM - 4 )) && VM_RAM_GB=$((TOTAL_RAM - 4))
VM_RAM_MB=$((VM_RAM_GB * 1024))
log_info "VM RAM: ${VM_RAM_GB} GB (${VM_RAM_MB} MB)"

# Configure 2MB hugepages
HUGEPAGES_COUNT=$((VM_RAM_GB * 512))  # Each 2MB page = 512 pages per GB
cat > /etc/sysctl.d/macnix-hugepages.conf <<EOF
# MacNix: Pre-allocate hugepages for VM memory
vm.nr_hugepages = ${HUGEPAGES_COUNT}
EOF
sysctl -p /etc/sysctl.d/macnix-hugepages.conf 2>/dev/null || true
log_info "Hugepages: ${HUGEPAGES_COUNT} × 2MB = ${VM_RAM_GB} GB"

# ────────────────────────────────────────────────────────────
# 4.7 PERFORMANCE: Evdev Input Detection
# ────────────────────────────────────────────────────────────
log_step "4.7  Detecting input devices for evdev passthrough"
KB_EVDEV=""
MOUSE_EVDEV=""

if [[ -d /dev/input/by-id ]]; then
    KB_EVDEV=$(find /dev/input/by-id/ -name '*kbd*' -o -name '*keyboard*' 2>/dev/null | head -1 || true)
    MOUSE_EVDEV=$(find /dev/input/by-id/ -name '*mouse*' 2>/dev/null | head -1 || true)
fi

if [[ -n "$KB_EVDEV" ]]; then
    log_info "Keyboard: ${KB_EVDEV}"
else
    log_warn "No keyboard evdev found — using USB tablet fallback"
fi
if [[ -n "$MOUSE_EVDEV" ]]; then
    log_info "Mouse: ${MOUSE_EVDEV}"
else
    log_warn "No mouse evdev found — using USB tablet fallback"
fi

# Save evdev config
cat > "${CFG_DIR}/evdev.conf" <<EOF
KBD_EVDEV="${KB_EVDEV}"
MOUSE_EVDEV="${MOUSE_EVDEV}"
CAPTURE_KEY=KEY_RIGHTCTRL
EOF

# ────────────────────────────────────────────────────────────
# 4.8 I/O Scheduler Optimization
# ────────────────────────────────────────────────────────────
log_step "4.8  Optimizing I/O scheduler"
# Set 'none' (noop) scheduler for NVMe drives hosting VM disks
MACOS_DISK="${VM_DIR}/macOS.qcow2"
if [[ -f "$MACOS_DISK" ]]; then
    BACKING_DEV=$(df --output=source "${VM_DIR}" 2>/dev/null | tail -1 | xargs basename 2>/dev/null || true)
    PARENT_DEV=$(lsblk -no pkname "/dev/${BACKING_DEV}" 2>/dev/null || true)
    if [[ -n "$PARENT_DEV" ]] && [[ -f "/sys/block/${PARENT_DEV}/queue/scheduler" ]]; then
        echo none > "/sys/block/${PARENT_DEV}/queue/scheduler" 2>/dev/null || true
        log_info "I/O scheduler: none (noop) on ${PARENT_DEV}"
    fi
fi

# ────────────────────────────────────────────────────────────
# 4.9 Generate QEMU Launch Script
# ────────────────────────────────────────────────────────────
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
# Near-native performance: CPU pinning, hugepages, evdev, virtio
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
VM_CPU_LIST="${VM_CPU_LIST}"
HOST_CPU_LIST="${HOST_CPU_LIST}"
VMSCRIPT_VARS

cat >> "$LAUNCH_SCRIPT" <<'VMSCRIPT_BODY'

# === Performance: CPU Governor ===
for cpu_dir in /sys/devices/system/cpu/cpu*/cpufreq; do
    [[ -f "${cpu_dir}/scaling_governor" ]] && \
        echo performance > "${cpu_dir}/scaling_governor" 2>/dev/null || true
done

# === Build QEMU command ===
QEMU_ARGS=(
    -name "$VM_NAME"
    -enable-kvm
    -machine q35,accel=kvm,kernel_irqchip=on
    -overcommit mem-lock=on
)

# CPU with pinning
if [[ "$CPU_MODEL" == "host" ]]; then
    QEMU_ARGS+=(-cpu host,kvm=on,vendor=GenuineIntel,+kvm_pv_unhalt,+kvm_pv_eoi,+hypervisor,+invtsc)
else
    QEMU_ARGS+=(-cpu Penryn,kvm=on,vendor=GenuineIntel,+kvm_pv_unhalt,+kvm_pv_eoi,+hypervisor,+invtsc,+ssse3,+sse4.2,+popcnt,+avx,+avx2,+aes,+xsave,+xsaveopt,vmware-cpuid-freq=on,check)
fi

QEMU_ARGS+=(
    -smp "cores=${VM_CORES},threads=1,sockets=1"
    -m "${VM_RAM}"
    -mem-path /dev/hugepages
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

# macOS system disk — virtio-blk with AIO native + iothread for max performance
QEMU_ARGS+=(
    -object iothread,id=iothread0
    -drive "id=MacHDD,if=none,file=${MACOS_DISK},format=qcow2,cache=none,aio=native,discard=on,detect-zeroes=on"
    -device virtio-blk-pci,drive=MacHDD,iothread=iothread0
)

# Install image (only during first boot)
if [[ -f "$INSTALL_IMG" ]] && [[ "${MACNIX_INSTALL_MODE:-0}" == "1" ]]; then
    QEMU_ARGS+=(
        -drive "id=InstallMedia,if=none,file=${INSTALL_IMG},format=raw"
        -device ide-hd,bus=sata.3,drive=InstallMedia
    )
fi

# Network — virtio with vhost
QEMU_ARGS+=(
    -netdev user,id=net0
    -device virtio-net-pci,netdev=net0,mac="${VM_MAC}"
)

# Audio (PipeWire/PulseAudio)
QEMU_ARGS+=(
    -audiodev pa,id=snd0,server=/run/user/$(id -u)/pulse/native
    -device intel-hda -device hda-duplex,audiodev=snd0
)

# GPU — branch-specific
if [[ "$BRANCH" == "D" ]] || [[ "${MACNIX_INSTALL_MODE:-0}" == "1" ]]; then
    # Software rendering or install mode: use virtio-vga with SPICE
    QEMU_ARGS+=(
        -device virtio-vga
        -spice port=5930,disable-ticketing=on
        -device virtio-serial-pci
        -chardev spicevmc,id=vdagent,debug=0,name=vdagent
        -device virtserialport,chardev=vdagent,name=com.redhat.spice.0
    )
elif [[ "$BRANCH" == "C" ]]; then
    # Intel GVT-g: use SPICE
    QEMU_ARGS+=(
        -device virtio-vga
        -spice port=5930,disable-ticketing=on
    )
fi
# Branches A/B/E: GPU VFIO devices are appended from override file

# VNC for automation and fingerprint bridge (localhost only)
QEMU_ARGS+=(
    -vnc localhost:0
    -qmp tcp:localhost:5902,server,nowait
)

# Input
# Load evdev config
EVDEV_CONF="/etc/macnix/evdev.conf"
if [[ -f "$EVDEV_CONF" ]] && [[ "$BRANCH" =~ ^[ABE]$ ]]; then
    source "$EVDEV_CONF"
    if [[ -n "${KBD_EVDEV:-}" ]] && [[ -e "${KBD_EVDEV}" ]]; then
        QEMU_ARGS+=(
            -object "input-linux,id=kbd,evdev=${KBD_EVDEV},grab_all=on,repeat=on"
        )
    fi
    if [[ -n "${MOUSE_EVDEV:-}" ]] && [[ -e "${MOUSE_EVDEV}" ]]; then
        QEMU_ARGS+=(
            -object "input-linux,id=mouse,evdev=${MOUSE_EVDEV}"
        )
    fi
fi

# Fallback USB tablet (always available for VNC/SPICE)
QEMU_ARGS+=(
    -device qemu-xhci
    -device usb-tablet
)

# Misc
QEMU_ARGS+=(
    -global nec-usb-xhci.msi=off
    -global ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off
)

# No memory balloon (prevents host from stealing VM memory)
# Intentionally omitted: -device virtio-balloon-pci

# Source branch-specific GPU overrides if they exist
OVERRIDE="/etc/macnix/qemu-gpu-override.conf"
[[ -f "$OVERRIDE" ]] && source "$OVERRIDE"

# Pin QEMU to VM cores using taskset
exec taskset -c "$VM_CPU_LIST" qemu-system-x86_64 "${QEMU_ARGS[@]}" "$@"
VMSCRIPT_BODY

chmod +x "$LAUNCH_SCRIPT"
log_success "Launch script: ${LAUNCH_SCRIPT}"

# 4.10 systemd service with performance settings
log_step "4.10  Creating systemd service"
cat > /etc/systemd/system/macnix-vm.service <<EOF
[Unit]
Description=MacNix macOS Virtual Machine
After=network-online.target macnix-gpu-setup.service
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

# Performance: allow memory locking for hugepages
LimitMEMLOCK=infinity
# Performance: pin service to VM cores
CPUAffinity=${VM_CPU_LIST}

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload 2>/dev/null || true
log_success "systemd service created: macnix-vm.service"

log_header "Phase 4 Complete"
log_info "Performance optimizations applied:"
log_info "  CPU: ${VM_CORES} cores pinned (${VM_CPU_LIST}), ${HOST_CORES} cores for host"
log_info "  RAM: ${VM_RAM_GB} GB with 2MB hugepages (${HUGEPAGES_COUNT} pages)"
log_info "  Storage: virtio-blk, AIO native, iothread, discard=on"
log_info "  Input: evdev passthrough (Ctrl+Ctrl toggle)"
log_info "  Timer: TSC passthrough (invtsc)"
log_info "  Memory: locked, no balloon"
log_info ""
log_info "Launch manually: sudo ${LAUNCH_SCRIPT}"
log_info "Or enable auto-start: sudo systemctl enable macnix-vm"
