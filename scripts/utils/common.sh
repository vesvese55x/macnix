#!/usr/bin/env bash
# MacNix - Common Utilities
# Shared functions used across all phases

set -euo pipefail

# ============================================================
# Colors & Output
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "${CYAN}${BOLD}[STEP]${NC} $*"; }
log_header()  { echo -e "\n${BOLD}═══════════════════════════════════════${NC}"; echo -e "${BOLD}  $*${NC}"; echo -e "${BOLD}═══════════════════════════════════════${NC}\n"; }

# ============================================================
# Paths
# ============================================================
MACNIX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MACNIX_SCRIPTS="${MACNIX_ROOT}/scripts"
MACNIX_CONFIG="${MACNIX_ROOT}/config"
MACNIX_BUILD="${MACNIX_ROOT}/build"
MACNIX_CALAMARES="${MACNIX_ROOT}/calamares"
MACNIX_SYSTEMD="${MACNIX_ROOT}/systemd"
MACNIX_OSXKVM="${MACNIX_ROOT}/osx-kvm"

# Runtime paths (on installed system)
MACNIX_INSTALL_DIR="/opt/macnix"
MACNIX_VM_DIR="/var/lib/macnix"
MACNIX_GPU_PROFILE="/etc/macnix/gpu-profile.json"
MACNIX_VM_CONFIG="/etc/macnix/vm.conf"

# ============================================================
# Checks
# ============================================================
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo)"
        exit 1
    fi
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd"
        return 1
    fi
}

check_internet() {
    if ! ping -c1 -W3 1.1.1.1 &>/dev/null; then
        log_error "No internet connection detected"
        return 1
    fi
    log_success "Internet connection OK"
}

# ============================================================
# Hardware Detection Helpers
# ============================================================

# Get CPU vendor: "intel" or "amd"
get_cpu_vendor() {
    local vendor
    vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
    case "$vendor" in
        GenuineIntel) echo "intel" ;;
        AuthenticAMD) echo "amd" ;;
        *) echo "unknown" ;;
    esac
}

# Check if VT-x/AMD-V is enabled
check_virt_support() {
    if grep -qE 'vmx|svm' /proc/cpuinfo; then
        return 0
    fi
    return 1
}

# Check if IOMMU is enabled in kernel
check_iommu_enabled() {
    if [[ -d /sys/kernel/iommu_groups ]] && [[ $(ls /sys/kernel/iommu_groups/ 2>/dev/null | wc -l) -gt 0 ]]; then
        return 0
    fi
    return 1
}

# Get total RAM in GB
get_total_ram_gb() {
    awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo
}

# Get available disk space in GB for a path
get_free_space_gb() {
    local path="${1:-/}"
    df -BG --output=avail "$path" 2>/dev/null | tail -1 | tr -d ' G'
}

# ============================================================
# GPU Detection Helpers
# ============================================================

# List all GPUs as JSON-like records
# Output format: PCI_ADDR|VENDOR_ID|DEVICE_ID|CLASS|DESCRIPTION
list_gpus() {
    lspci -nn | grep -E '\[0300\]|\[0302\]' | while IFS= read -r line; do
        local pci_addr vendor_id device_id description class_code
        pci_addr=$(echo "$line" | awk '{print $1}')
        # Extract [XXXX:XXXX] vendor:device IDs
        vendor_id=$(echo "$line" | grep -oP '\[\K[0-9a-f]{4}(?=:[0-9a-f]{4}\])' | head -1)
        device_id=$(echo "$line" | grep -oP '\[[0-9a-f]{4}:\K[0-9a-f]{4}(?=\])' | head -1)
        # Extract class code
        class_code=$(echo "$line" | grep -oP '\[\K030[02]\]' | tr -d ']' | head -1)
        # Description is everything after the class
        description=$(echo "$line" | sed 's/^[^ ]* [^:]*: //')
        echo "${pci_addr}|${vendor_id}|${device_id}|${class_code}|${description}"
    done
}

# Get IOMMU group for a PCI device
get_iommu_group() {
    local pci_addr="$1"
    local full_addr="0000:${pci_addr}"
    local group_path
    group_path=$(readlink -f "/sys/bus/pci/devices/${full_addr}/iommu_group" 2>/dev/null)
    if [[ -n "$group_path" ]]; then
        basename "$group_path"
    else
        echo "none"
    fi
}

# List all devices in an IOMMU group
list_iommu_group_members() {
    local group_num="$1"
    local group_path="/sys/kernel/iommu_groups/${group_num}/devices"
    if [[ -d "$group_path" ]]; then
        for dev in "$group_path"/*; do
            basename "$dev"
        done
    fi
}

# Get the kernel driver currently bound to a PCI device
get_pci_driver() {
    local pci_addr="$1"
    local full_addr="0000:${pci_addr}"
    local driver_path="/sys/bus/pci/devices/${full_addr}/driver"
    if [[ -L "$driver_path" ]]; then
        basename "$(readlink -f "$driver_path")"
    else
        echo "none"
    fi
}

# GPU vendor from vendor ID
gpu_vendor_name() {
    case "$1" in
        10de) echo "nvidia" ;;
        1002) echo "amd" ;;
        8086) echo "intel" ;;
        *)    echo "unknown" ;;
    esac
}

# ============================================================
# JSON Helpers (using Python for portability)
# ============================================================
json_set() {
    # Usage: json_set file.json '.key' '"value"'
    local file="$1" key="$2" value="$3"
    python3 -c "
import json, sys
with open('$file', 'r') as f:
    data = json.load(f)
keys = '$key'.strip('.').split('.')
obj = data
for k in keys[:-1]:
    obj = obj.setdefault(k, {})
try:
    obj[keys[-1]] = json.loads('$value')
except:
    obj[keys[-1]] = '$value'
with open('$file', 'w') as f:
    json.dump(data, f, indent=2)
"
}

json_get() {
    # Usage: json_get file.json '.key.subkey'
    local file="$1" key="$2"
    python3 -c "
import json
with open('$file', 'r') as f:
    data = json.load(f)
keys = '$key'.strip('.').split('.')
obj = data
for k in keys:
    obj = obj[k]
print(json.dumps(obj) if isinstance(obj, (dict, list)) else obj)
"
}

# ============================================================
# System Configuration Helpers
# ============================================================

# Add a kernel boot parameter to GRUB
add_grub_param() {
    local param="$1"
    local grub_file="/etc/default/grub"
    if ! grep -q "$param" "$grub_file"; then
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"${param} /" "$grub_file"
        log_info "Added kernel parameter: $param"
    else
        log_info "Kernel parameter already present: $param"
    fi
}

# Rebuild initramfs
rebuild_initramfs() {
    log_info "Rebuilding initramfs..."
    if command -v update-initramfs &>/dev/null; then
        update-initramfs -u -k all
    elif command -v dracut &>/dev/null; then
        dracut --force
    else
        log_error "No initramfs tool found"
        return 1
    fi
    log_success "Initramfs rebuilt"
}

# Update GRUB
update_grub_config() {
    log_info "Updating GRUB..."
    if command -v update-grub &>/dev/null; then
        update-grub
    elif command -v grub2-mkconfig &>/dev/null; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        grub-mkconfig -o /boot/grub/grub.cfg
    fi
    log_success "GRUB updated"
}

# ============================================================
# CPU Topology
# ============================================================

# Get CPU core count (physical)
get_physical_cores() {
    grep -c '^processor' /proc/cpuinfo
}

# Get the number of physical cores (no HT)
get_core_count() {
    lscpu | awk '/^Core\(s\) per socket:/ {cores=$4} /^Socket\(s\):/ {sockets=$2} END {print cores * sockets}'
}

# Get cores sharing same L3 cache (for pinning)
get_l3_cache_groups() {
    # Returns groups of CPU IDs that share L3 cache
    local -A cache_groups
    for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*/; do
        local cpu_id
        cpu_id=$(basename "$cpu_dir" | tr -dc '0-9')
        local l3_cpus
        l3_cpus=$(cat "${cpu_dir}/cache/index3/shared_cpu_list" 2>/dev/null || echo "")
        if [[ -n "$l3_cpus" ]]; then
            cache_groups["$l3_cpus"]=1
        fi
    done
    for group in "${!cache_groups[@]}"; do
        echo "$group"
    done | sort -u
}

log_info "MacNix common utilities loaded"
