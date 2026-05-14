#!/usr/bin/env bash
# ============================================================
# MacNix Master Build Script
# Chains all phases to build the complete ISO
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/common.sh"

require_root
log_header "MacNix — Full Build Pipeline"

PHASE="${1:-all}"
SKIP_DOWNLOAD="${MACNIX_SKIP_DOWNLOAD:-0}"

run_phase() {
    local num="$1" name="$2" script="$3"
    log_header "Phase ${num}: ${name}"
    if bash "${SCRIPT_DIR}/${script}"; then
        log_success "Phase ${num} complete"
    else
        log_error "Phase ${num} failed!"
        log_info "Fix the issue and re-run: sudo $0 ${num}"
        exit 1
    fi
}

case "$PHASE" in
    1|setup)
        run_phase 1 "Build Environment" "phase1-setup.sh"
        ;;
    2|gpu)
        run_phase 2 "GPU Detection" "phase2-gpu-detect.sh"
        ;;
    3|fetch)
        run_phase 3 "macOS Acquisition" "phase3-macos-fetch.sh"
        ;;
    4|qemu)
        run_phase 4 "QEMU Configuration" "phase4-qemu-config.sh"
        ;;
    5|passthrough)
        run_phase 5 "GPU Passthrough" "phase5-gpu-passthrough.sh"
        ;;
    6|ux)
        run_phase 6 "UX Layer" "phase6-ux-setup.sh"
        ;;
    7|iso)
        run_phase 7 "ISO Build" "phase7-build-iso.sh"
        ;;
    all)
        run_phase 1 "Build Environment" "phase1-setup.sh"
        run_phase 2 "GPU Detection" "phase2-gpu-detect.sh"
        if [[ "$SKIP_DOWNLOAD" != "1" ]]; then
            run_phase 3 "macOS Acquisition" "phase3-macos-fetch.sh"
        else
            log_warn "Skipping Phase 3 (MACNIX_SKIP_DOWNLOAD=1)"
        fi
        run_phase 4 "QEMU Configuration" "phase4-qemu-config.sh"
        run_phase 5 "GPU Passthrough" "phase5-gpu-passthrough.sh"
        run_phase 6 "UX Layer" "phase6-ux-setup.sh"
        run_phase 7 "ISO Build" "phase7-build-iso.sh"
        ;;
    dry-run)
        log_info "Dry run — checking prerequisites without executing"
        echo ""
        echo "CPU:  $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
        echo "Virt: $(grep -qE 'vmx|svm' /proc/cpuinfo && echo 'YES' || echo 'NO')"
        echo "RAM:  $(get_total_ram_gb) GB"
        echo "Disk: $(get_free_space_gb /) GB free on /"
        echo "KVM:  $([ -e /dev/kvm ] && echo 'YES' || echo 'NO')"
        echo "OS:   $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
        echo ""
        echo "GPUs detected:"
        lspci -nn | grep -E '\[0300\]|\[0302\]' | while read -r line; do
            echo "  $line"
        done
        echo ""
        echo "Required packages:"
        for pkg in qemu-system-x86 libvirt-daemon-system ovmf live-build xorriso debootstrap python3 dmg2img; do
            if dpkg -s "$pkg" &>/dev/null; then
                echo "  ✓ $pkg"
            else
                echo "  ✗ $pkg (not installed)"
            fi
        done
        ;;
    *)
        echo "Usage: $0 {1|2|3|4|5|6|7|all|dry-run}"
        echo ""
        echo "Phases:"
        echo "  1 (setup)       Install build dependencies"
        echo "  2 (gpu)         Detect GPU and write profile"
        echo "  3 (fetch)       Download macOS from Apple CDN"
        echo "  4 (qemu)        Generate QEMU launch config"
        echo "  5 (passthrough) Configure GPU passthrough"
        echo "  6 (ux)          Set up Looking Glass, audio, input"
        echo "  7 (iso)         Build the ISO"
        echo "  all             Run everything"
        echo "  dry-run         Check prerequisites only"
        echo ""
        echo "Environment variables:"
        echo "  MACNIX_SKIP_DOWNLOAD=1  Skip macOS download (Phase 3)"
        exit 1
        ;;
esac

log_header "Done"
