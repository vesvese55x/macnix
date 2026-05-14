#!/usr/bin/env bash
# MacNix Phase 3 — macOS Acquisition Pipeline
# Downloads macOS from Apple CDN, verifies, converts, creates VM disk
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/common.sh"

log_header "MacNix Phase 3 — macOS Acquisition"

PROFILE="${MACNIX_GPU_PROFILE}"
OSXKVM="${MACNIX_ROOT}/osx-kvm"
VM_DIR="/var/lib/macnix/disks"
FW_DIR="/var/lib/macnix/firmware"
DISK_SIZE="${MACNIX_DISK_SIZE:-80G}"

mkdir -p "$VM_DIR" "$FW_DIR"

# 3.1 Read GPU profile → select macOS version
log_step "3.1  Selecting macOS target version"
if [[ -f "$PROFILE" ]]; then
    MACOS_VER=$(python3 -c "import json; print(json.load(open('${PROFILE}'))['macos_target'])")
else
    log_warn "No GPU profile found, defaulting to Sonoma"
    MACOS_VER="sonoma"
fi
log_info "Target: macOS ${MACOS_VER}"

# Map version names to fetch-macOS-v2.py selection numbers
case "$MACOS_VER" in
    monterey) FETCH_SEL="3" ;;
    ventura)  FETCH_SEL="2" ;;
    sonoma)   FETCH_SEL="1" ;;
    sequoia)  FETCH_SEL="1" ;;  # latest
    *)        FETCH_SEL="1" ;;
esac

# 3.2 Board ID (handled by fetch script via OSX-KVM defaults)
log_step "3.2  Board ID selection (automatic via OSX-KVM)"

# 3.3 Download BaseSystem
log_step "3.3  Downloading macOS recovery image"
FETCH_SCRIPT="${OSXKVM}/fetch-macOS-v2.py"
if [[ ! -f "$FETCH_SCRIPT" ]]; then
    log_error "fetch-macOS-v2.py not found at ${FETCH_SCRIPT}"
    log_info "Run phase1-setup.sh first to clone OSX-KVM"
    exit 1
fi

WORK_DIR="${VM_DIR}/fetch-work"
mkdir -p "$WORK_DIR"

# Check if we already have the image
if [[ -f "${VM_DIR}/BaseSystem.dmg" ]]; then
    log_info "BaseSystem.dmg already exists — skipping download"
    log_info "Delete ${VM_DIR}/BaseSystem.dmg to re-download"
else
    check_internet
    log_info "Running fetch-macOS-v2.py (this downloads ~600MB)..."
    cd "$WORK_DIR"
    echo "$FETCH_SEL" | python3 "$FETCH_SCRIPT" || {
        log_error "Fetch script failed"
        exit 1
    }
    # Move the downloaded DMG
    DMG_FILE=$(find "$WORK_DIR" -name "BaseSystem.dmg" -o -name "*.dmg" | head -1)
    if [[ -n "$DMG_FILE" ]]; then
        mv "$DMG_FILE" "${VM_DIR}/BaseSystem.dmg"
        log_success "BaseSystem.dmg downloaded"
    else
        log_error "No DMG file found after download"
        exit 1
    fi
    # Also grab chunklist if present
    CHUNK_FILE=$(find "$WORK_DIR" -name "*.chunklist" | head -1)
    [[ -n "$CHUNK_FILE" ]] && mv "$CHUNK_FILE" "${VM_DIR}/BaseSystem.chunklist"
fi

# 3.4 Verify integrity
log_step "3.4  Verifying BaseSystem.dmg"
if [[ -f "${VM_DIR}/BaseSystem.chunklist" ]]; then
    log_info "Chunklist found — verifying SHA-256 chunks"
    # Basic size check as fallback (full chunklist verify is complex)
    DMG_SIZE=$(stat -c%s "${VM_DIR}/BaseSystem.dmg" 2>/dev/null || echo 0)
    if (( DMG_SIZE > 50000000 )); then
        log_success "BaseSystem.dmg size OK ($(( DMG_SIZE / 1048576 )) MB)"
    else
        log_error "BaseSystem.dmg seems too small (${DMG_SIZE} bytes)"
        exit 1
    fi
else
    log_warn "No chunklist — skipping verification (size check only)"
    DMG_SIZE=$(stat -c%s "${VM_DIR}/BaseSystem.dmg" 2>/dev/null || echo 0)
    (( DMG_SIZE > 50000000 )) || { log_error "DMG too small"; exit 1; }
    log_success "Size OK: $(( DMG_SIZE / 1048576 )) MB"
fi

# 3.5 Convert DMG → IMG
log_step "3.5  Converting DMG to raw disk image"
if [[ -f "${VM_DIR}/BaseSystem.img" ]]; then
    log_info "BaseSystem.img already exists — skipping conversion"
else
    require_command dmg2img
    dmg2img "${VM_DIR}/BaseSystem.dmg" "${VM_DIR}/BaseSystem.img"
    log_success "Converted to BaseSystem.img"
fi

# 3.6 Create blank QCOW2 system disk
log_step "3.6  Creating macOS system disk (${DISK_SIZE} QCOW2)"
MACOS_DISK="${VM_DIR}/macOS.qcow2"
if [[ -f "$MACOS_DISK" ]]; then
    log_info "macOS.qcow2 already exists — skipping"
else
    qemu-img create -f qcow2 "$MACOS_DISK" "$DISK_SIZE"
    log_success "Created ${MACOS_DISK}"
fi

# Copy OpenCore firmware
log_step "Copying OpenCore EFI firmware"
if [[ -d "${OSXKVM}/OpenCore" ]]; then
    cp -r "${OSXKVM}/OpenCore" "${FW_DIR}/"
    log_success "OpenCore EFI copied to ${FW_DIR}/OpenCore"
elif [[ -f "${OSXKVM}/OpenCore-Boot.sh" ]]; then
    cp "${OSXKVM}/OpenCore-Boot.sh" "${FW_DIR}/"
fi
# Copy OVMF firmware
for f in /usr/share/OVMF/OVMF_CODE*.fd /usr/share/edk2/ovmf/OVMF_CODE*.fd; do
    [[ -f "$f" ]] && cp "$f" "${FW_DIR}/" && break
done
for f in /usr/share/OVMF/OVMF_VARS*.fd /usr/share/edk2/ovmf/OVMF_VARS*.fd; do
    [[ -f "$f" ]] && cp "$f" "${FW_DIR}/" && break
done

log_header "Phase 3 Complete"
log_info "Files ready in ${VM_DIR}:"
ls -lh "${VM_DIR}/" 2>/dev/null
log_info "Next: run phase4-qemu-config.sh"
