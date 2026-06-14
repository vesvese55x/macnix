#!/usr/bin/env bash
# MacNix Pre-Flight Hardware Check
# Validates hardware requirements before launching Calamares installer

set -euo pipefail

# Initialize results
CRITICAL_FAIL=0
LOG=""

# Function to add to log
add_log() {
    local status="$1"
    local msg="$2"
    LOG="${LOG}${status}  ${msg}\n"
}

# 1. CPU Virtualisation
if grep -Eq 'vmx|svm' /proc/cpuinfo; then
    add_log "✅" "CPU Virtualisation (VT-x/AMD-V)"
else
    add_log "❌" "CPU Virtualisation (VT-x/AMD-V) - REQUIRED"
    CRITICAL_FAIL=1
fi

# 2. KVM
if [[ -e /dev/kvm ]]; then
    add_log "✅" "/dev/kvm available"
else
    add_log "❌" "/dev/kvm available - REQUIRED"
    CRITICAL_FAIL=1
fi

# 3. RAM
RAM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
RAM_GB=$((RAM_KB / 1024 / 1024))
if (( RAM_GB >= 16 )); then
    add_log "✅" "RAM: ${RAM_GB} GB (16 GB min)"
else
    add_log "❌" "RAM: ${RAM_GB} GB (16 GB min) - REQUIRED"
    CRITICAL_FAIL=1
fi

# 4. Disk Space
# Rough check on the root disk size (e.g. sda, nvme0n1)
ROOT_DISK=$(lsblk -no pkname $(findmnt -no SOURCE /) 2>/dev/null || echo "")
if [[ -n "$ROOT_DISK" ]]; then
    DISK_SIZE_BYTES=$(lsblk -bno SIZE "/dev/${ROOT_DISK}" | head -1)
    DISK_SIZE_GB=$((DISK_SIZE_BYTES / 1024 / 1024 / 1024))
    if (( DISK_SIZE_GB >= 150 )); then
        add_log "✅" "Disk: ${DISK_SIZE_GB} GB (150 GB min)"
    else
        add_log "⚠️" "Disk: ${DISK_SIZE_GB} GB (150 GB min recommended)"
    fi
else
    add_log "⚠️" "Disk: Unknown size"
fi

# 5. IOMMU
if [[ -d /sys/kernel/iommu_groups ]] && (( $(ls -1 /sys/kernel/iommu_groups | wc -l) > 0 )); then
    add_log "✅" "IOMMU groups detected"
else
    add_log "⚠️" "IOMMU groups not detected (maybe disabled in BIOS)"
fi

# 6. Internet
if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    add_log "✅" "Internet connection"
else
    add_log "❌" "Internet connection - REQUIRED"
    CRITICAL_FAIL=1
fi

# Show results
if command -v zenity >/dev/null 2>&1; then
    if (( CRITICAL_FAIL == 1 )); then
        zenity --question --title="MacNix - Hardware Requirements" \
            --text="<b>Some hardware requirements are not met.</b>\n\nThe following issues were detected:\n\n${LOG}\n\nOn bare-metal hardware, ensure VT-x/AMD-V and IOMMU are enabled in BIOS.\n\n<b>Continue anyway?</b>" \
            --ok-label="Continue Anyway" \
            --cancel-label="Cancel" \
            --width=500
        exit $?
    else
        zenity --info --title="MacNix - Hardware Requirements" \
            --text="<b>Hardware checks passed!</b>\n\n${LOG}\n\nClick OK to launch the MacNix Installer." \
            --width=450
        exit 0
    fi
else
    # Fallback if zenity is not available
    echo -e "$LOG"
    exit 0
fi
