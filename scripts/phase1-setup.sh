#!/usr/bin/env bash
# ============================================================
# MacNix Phase 1 — Build Environment Setup
# ============================================================
# Installs all dependencies on a Debian 12 (Bookworm) host.
# Must be run as root. Idempotent — safe to re-run.
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/common.sh"

require_root
log_header "MacNix Phase 1 — Build Environment Setup"

# ────────────────────────────────────────────────────────────
# 1.1–1.3  Host hardware pre-flight checks
# ────────────────────────────────────────────────────────────
log_step "1.1  Checking CPU virtualisation support"
if check_virt_support; then
    log_success "Hardware virtualisation (VT-x / AMD-V) detected"
else
    log_error "No VT-x / AMD-V found — enable it in BIOS first"
    exit 1
fi

log_step "1.2  Checking RAM"
RAM_GB=$(get_total_ram_gb)
if (( RAM_GB < 16 )); then
    log_error "Only ${RAM_GB} GB RAM detected — 16 GB minimum required"
    exit 1
elif (( RAM_GB < 32 )); then
    log_warn "${RAM_GB} GB RAM — functional but 32 GB recommended"
else
    log_success "${RAM_GB} GB RAM — good"
fi

log_step "1.3  Checking disk space"
FREE_GB=$(get_free_space_gb /)
if (( FREE_GB < 150 )); then
    log_warn "Only ${FREE_GB} GB free on /  (150 GB recommended)"
    log_info "Will continue, but macOS image + build may run tight"
else
    log_success "${FREE_GB} GB free — good"
fi

# ────────────────────────────────────────────────────────────
# Detect package manager
# ────────────────────────────────────────────────────────────
if command -v apt-get &>/dev/null; then
    PKG="apt-get"
    PKG_INSTALL="apt-get install -y"
    PKG_UPDATE="apt-get update"
else
    log_error "apt-get not found — this script targets Debian/Ubuntu"
    exit 1
fi

log_step "Updating package index"
$PKG_UPDATE || log_warn "Package update finished with some errors (likely broken PPAs, continuing anyway)"

# ────────────────────────────────────────────────────────────
# 1.6  Virtualisation stack
# ────────────────────────────────────────────────────────────
log_step "1.6  Installing virtualisation stack"
$PKG_INSTALL \
    qemu-system-x86 \
    qemu-utils \
    libvirt-daemon-system \
    libvirt-clients \
    virtinst \
    bridge-utils \
    cpu-checker \
    ovmf \
    virt-manager

# ────────────────────────────────────────────────────────────
# 1.7  Distro build tools
# ────────────────────────────────────────────────────────────
log_step "1.7  Installing distro build tools"
$PKG_INSTALL \
    live-build \
    xorriso \
    squashfs-tools \
    debootstrap \
    syslinux-utils \
    isolinux

# ────────────────────────────────────────────────────────────
# 1.8  macOS utility dependencies
# ────────────────────────────────────────────────────────────
log_step "1.8  Installing macOS utility dependencies"
$PKG_INSTALL \
    python3 \
    python3-pip \
    python3-venv \
    dmg2img \
    qemu-utils \
    wget \
    curl \
    p7zip-full

# ────────────────────────────────────────────────────────────
# 1.9  Calamares installer framework
# ────────────────────────────────────────────────────────────
log_step "1.9  Installing Calamares"
$PKG_INSTALL \
    calamares \
    calamares-settings-debian \
    python3-yaml \
    python3-jsonschema \
    python3-libparted \
    || log_warn "Some Calamares packages may not be in default repos"

# ────────────────────────────────────────────────────────────
# Additional tools
# ────────────────────────────────────────────────────────────
log_step "Installing additional tools"
$PKG_INSTALL \
    git \
    pciutils \
    usbutils \
    jq \
    rsync \
    parted \
    dosfstools \
    grub-efi-amd64-bin \
    grub-pc-bin \
    mtools

# ────────────────────────────────────────────────────────────
# 1.10  Clone OSX-KVM
# ────────────────────────────────────────────────────────────
log_step "1.10  Cloning OSX-KVM repository"
OSXKVM_DIR="${MACNIX_ROOT}/osx-kvm"
if [[ -d "$OSXKVM_DIR/.git" ]]; then
    log_info "OSX-KVM already cloned — pulling latest"
    git -C "$OSXKVM_DIR" pull --ff-only || true
else
    git clone --depth 1 https://github.com/kholia/OSX-KVM.git "$OSXKVM_DIR"
fi
log_success "OSX-KVM ready at ${OSXKVM_DIR}"

# ────────────────────────────────────────────────────────────
# Create runtime directories
# ────────────────────────────────────────────────────────────
log_step "Creating MacNix directories"
mkdir -p /etc/macnix
mkdir -p /var/lib/macnix/{disks,snapshots,firmware}
mkdir -p /opt/macnix/{scripts,hooks,config}

# ────────────────────────────────────────────────────────────
# Enable & start libvirtd
# ────────────────────────────────────────────────────────────
log_step "Enabling libvirtd"
systemctl enable --now libvirtd 2>/dev/null || true

# ────────────────────────────────────────────────────────────
# Verify KVM works
# ────────────────────────────────────────────────────────────
log_step "Verifying KVM"
if [[ -e /dev/kvm ]]; then
    log_success "/dev/kvm exists"
else
    log_error "/dev/kvm not found — check BIOS virtualisation settings"
fi

if command -v kvm-ok &>/dev/null; then
    kvm-ok && log_success "kvm-ok passed" || log_warn "kvm-ok reports issues"
fi

# ────────────────────────────────────────────────────────────
log_header "Phase 1 Complete"
log_success "All build dependencies installed"
log_info "Next: run phase2-gpu-detect.sh to profile the GPU"
