#!/usr/bin/env bash
# MacNix — Dry-Run Validation Script
# Tests the entire ISO build pipeline WITHOUT actually building the ISO
# Catches missing files, broken configs, and structural issues in ~5 seconds
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACNIX_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; FAIL=0; WARN=0

ok()   { ((PASS++)) || true; echo -e "  ${GREEN}✓${NC} $*"; }
fail() { ((FAIL++)) || true; echo -e "  ${RED}✗${NC} $*"; }
warn() { ((WARN++)) || true; echo -e "  ${YELLOW}⚠${NC} $*"; }

header() { echo -e "\n${CYAN}${BOLD}── $* ──${NC}"; }

# ──────────────────────────────────────────────
header "1. Script files exist"
# ──────────────────────────────────────────────
SCRIPTS=(
    "scripts/phase1-setup.sh"
    "scripts/phase2-gpu-detect.sh"
    "scripts/phase3-macos-fetch.sh"
    "scripts/phase4-qemu-config.sh"
    "scripts/phase5-gpu-passthrough.sh"
    "scripts/phase6-ux-setup.sh"
    "scripts/phase7-build-iso.sh"
    "scripts/macnix-debug.sh"
    "scripts/macnix-precheck.sh"
    "scripts/macnix-setup-assistant.sh"
    "scripts/build.sh"
)
for s in "${SCRIPTS[@]}"; do
    [[ -f "${MACNIX_ROOT}/${s}" ]] && ok "$s" || fail "$s — MISSING"
done

# ──────────────────────────────────────────────
header "2. Utility scripts"
# ──────────────────────────────────────────────
UTILS=("scripts/utils/common.sh" "scripts/utils/gpu-db.sh" "scripts/utils/smbios-gen.sh")
for u in "${UTILS[@]}"; do
    [[ -f "${MACNIX_ROOT}/${u}" ]] && ok "$u" || fail "$u — MISSING"
done

# ──────────────────────────────────────────────
header "3. Single-GPU hooks"
# ──────────────────────────────────────────────
HOOKS=("scripts/single-gpu-hooks/start.sh" "scripts/single-gpu-hooks/revert.sh")
for h in "${HOOKS[@]}"; do
    [[ -f "${MACNIX_ROOT}/${h}" ]] && ok "$h" || fail "$h — MISSING"
done

# ──────────────────────────────────────────────
header "4. Calamares modules (must match settings.conf sequence)"
# ──────────────────────────────────────────────
MODULES=(macnix-gpu-detect macnix-macos-fetch macnix-gpu-config)
for mod in "${MODULES[@]}"; do
    dir="${MACNIX_ROOT}/calamares/modules/${mod}"
    if [[ -d "$dir" ]]; then
        # Check required files
        [[ -f "${dir}/main.py" ]]    && ok "${mod}/main.py" || fail "${mod}/main.py — MISSING"
        [[ -f "${dir}/module.desc" ]] && ok "${mod}/module.desc" || fail "${mod}/module.desc — MISSING"
        # Verify module.desc has correct name
        if grep -q "name:.*${mod}" "${dir}/module.desc" 2>/dev/null; then
            ok "${mod}/module.desc — name matches"
        else
            fail "${mod}/module.desc — name doesn't match '${mod}'"
        fi
    else
        fail "${mod}/ — DIRECTORY MISSING"
    fi
done

# ──────────────────────────────────────────────
header "5. Calamares settings.conf"
# ──────────────────────────────────────────────
SETTINGS="${MACNIX_ROOT}/calamares/settings.conf"
if [[ -f "$SETTINGS" ]]; then
    ok "settings.conf exists"
    # Check all custom modules are referenced
    for mod in "${MODULES[@]}"; do
        grep -q "$mod" "$SETTINGS" && ok "  settings.conf references ${mod}" || fail "  settings.conf MISSING ${mod}"
    done
    # Check branding reference
    grep -q "branding: macnix" "$SETTINGS" && ok "  branding: macnix set" || fail "  branding: macnix NOT set"
else
    fail "settings.conf — MISSING"
fi

# ──────────────────────────────────────────────
header "6. Branding"
# ──────────────────────────────────────────────
BRAND_DIR="${MACNIX_ROOT}/calamares/branding/macnix"
if [[ -d "$BRAND_DIR" ]]; then
    ok "branding/macnix/ exists"
    [[ -f "${BRAND_DIR}/branding.desc" ]] && ok "  branding.desc" || fail "  branding.desc — MISSING"
    [[ -f "${BRAND_DIR}/show.qml" ]]      && ok "  show.qml" || fail "  show.qml — MISSING"
    # Check logo reference matches actual file
    if [[ -f "${BRAND_DIR}/branding.desc" ]]; then
        logo=$(grep "productLogo" "${BRAND_DIR}/branding.desc" | sed 's/.*"\(.*\)"/\1/')
        if [[ -n "$logo" && -f "${BRAND_DIR}/${logo}" ]]; then
            ok "  logo file '${logo}' exists"
        else
            fail "  logo file '${logo}' — MISSING"
        fi
    fi
    # Check slideshow references logo that exists
    if [[ -f "${BRAND_DIR}/show.qml" ]]; then
        while IFS= read -r src; do
            img=$(echo "$src" | sed 's/.*source: *"\(.*\)".*/\1/')
            if [[ -f "${BRAND_DIR}/${img}" ]]; then
                ok "  slideshow refs '${img}' — exists"
            else
                fail "  slideshow refs '${img}' — MISSING"
            fi
        done < <(grep 'source:' "${BRAND_DIR}/show.qml" 2>/dev/null || true)
    fi
else
    fail "branding/macnix/ — DIRECTORY MISSING"
fi

# ──────────────────────────────────────────────
header "7. Config templates"
# ──────────────────────────────────────────────
CONFIGS=(
    "config/gpu-profile.json.template"
    "config/opencore/config.plist.template"
)
for c in "${CONFIGS[@]}"; do
    [[ -f "${MACNIX_ROOT}/${c}" ]] && ok "$c" || fail "$c — MISSING"
done
# Branch overrides
for b in a b c d e; do
    matches=$(ls ${MACNIX_ROOT}/config/qemu/branch-overrides/branch-${b}-*.conf 2>/dev/null | wc -l || echo 0)
    (( matches > 0 )) && ok "branch-${b} override exists" || warn "branch-${b} override — not found (may be optional)"
done

# ──────────────────────────────────────────────
header "8. Systemd services"
# ──────────────────────────────────────────────
SERVICES=("systemd/macnix-firstboot.service" "systemd/macnix-vm.service")
for svc in "${SERVICES[@]}"; do
    [[ -f "${MACNIX_ROOT}/${svc}" ]] && ok "$svc" || fail "$svc — MISSING"
done

# ──────────────────────────────────────────────
header "9. Phase 7 script internal consistency"
# ──────────────────────────────────────────────
P7="${MACNIX_ROOT}/scripts/phase7-build-iso.sh"
if [[ -f "$P7" ]]; then
    if grep -q 'linux-packages.*linux-image' "$P7"; then
        ok "phase7 --linux-packages linux-image (correct)"
    else
        fail "phase7 MUST use --linux-packages 'linux-image' to ensure kernel is copied to ISO"
    fi
    # Check security repo is handled (manual or flag)
    if grep -q 'security true\|debian-security' "$P7"; then
        ok "phase7 security repo configured"
    else
        warn "phase7 --security may be disabled"
    fi
    # Check all custom modules are in the copy loop
    for mod in macnix-gpu-detect macnix-macos-fetch macnix-gpu-config; do
        if grep -q "$mod" "$P7"; then
            ok "phase7 bundles ${mod}"
        else
            fail "phase7 does NOT bundle ${mod}"
        fi
    done
    # Check branding copy
    if grep -q "branding" "$P7"; then
        ok "phase7 copies branding"
    else
        fail "phase7 does NOT copy branding"
    fi
    # Check smbios-gen.sh copy
    if grep -q "smbios-gen" "$P7"; then
        ok "phase7 copies smbios-gen.sh"
    else
        fail "phase7 does NOT copy smbios-gen.sh"
    fi
else
    fail "phase7-build-iso.sh — MISSING"
fi

# ──────────────────────────────────────────────
header "10. Python syntax check (Calamares modules)"
# ──────────────────────────────────────────────
if command -v python3 &>/dev/null; then
    for mod in "${MODULES[@]}"; do
        py="${MACNIX_ROOT}/calamares/modules/${mod}/main.py"
        if [[ -f "$py" ]]; then
            if python3 -c "import py_compile; py_compile.compile('$py', doraise=True)" 2>/dev/null; then
                ok "${mod}/main.py — syntax OK"
            else
                fail "${mod}/main.py — SYNTAX ERROR"
            fi
        fi
    done
else
    warn "python3 not available — skipping syntax checks"
fi

# ──────────────────────────────────────────────
header "11. Shell script syntax check"
# ──────────────────────────────────────────────
for s in "${SCRIPTS[@]}" "${UTILS[@]}" "${HOOKS[@]}"; do
    f="${MACNIX_ROOT}/${s}"
    [[ ! -f "$f" ]] && continue
    if bash -n "$f" 2>/dev/null; then
        ok "${s} — syntax OK"
    else
        fail "${s} — SYNTAX ERROR"
    fi
done

# ──────────────────────────────────────────────
header "12. New component files"
# ──────────────────────────────────────────────
NEW_FILES=(
    "scripts/macnix-auto-install.py"
    "scripts/macnix-fingerprint-bridge.py"
    "scripts/macnix-fingerprint"
    "scripts/macnix-setup-assistant.sh"
    "scripts/macnix-precheck.sh"
)
for nf in "${NEW_FILES[@]}"; do
    [[ -f "${MACNIX_ROOT}/${nf}" ]] && ok "$nf" || fail "$nf — MISSING"
done

# Plymouth theme
PLY_DIR="${MACNIX_ROOT}/plymouth/macnix"
if [[ -d "$PLY_DIR" ]]; then
    ok "plymouth/macnix/ theme directory exists"
    [[ -f "${PLY_DIR}/macnix.plymouth" ]] && ok "  macnix.plymouth" || fail "  macnix.plymouth — MISSING"
    [[ -f "${PLY_DIR}/macnix.script" ]]   && ok "  macnix.script"   || fail "  macnix.script — MISSING"
else
    fail "plymouth/macnix/ — DIRECTORY MISSING"
fi

# ──────────────────────────────────────────────
header "13. Required package availability"
# ──────────────────────────────────────────────
# These packages must be available in Debian Bookworm repos
REQUIRED_PKGS=(virt-viewer fprintd libpam-fprintd libsecret-tools gnome-keyring)
if command -v apt-cache &>/dev/null; then
    for pkg in "${REQUIRED_PKGS[@]}"; do
        if apt-cache show "$pkg" &>/dev/null 2>&1; then
            ok "package '${pkg}' available"
        else
            warn "package '${pkg}' not found in apt cache (may need apt update)"
        fi
    done
else
    warn "apt-cache not available — skipping package checks"
fi

# ──────────────────────────────────────────────
header "14. Host build tools check"
# ──────────────────────────────────────────────
for cmd in lb debootstrap xorriso; do
    if command -v "$cmd" &>/dev/null; then
        ok "${cmd} installed"
    else
        warn "${cmd} not installed (needed for ISO build, not for validation)"
    fi
done

# ══════════════════════════════════════════════
echo -e "\n${BOLD}═══════════════════════════════════════${NC}"
echo -e "${BOLD}  Validation Results${NC}"
echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed: ${PASS}${NC}"
echo -e "  ${YELLOW}Warnings: ${WARN}${NC}"
echo -e "  ${RED}Failed: ${FAIL}${NC}"

if (( FAIL > 0 )); then
    echo -e "\n${RED}${BOLD}  ✗ VALIDATION FAILED — fix ${FAIL} issue(s) before building ISO${NC}\n"
    exit 1
elif (( WARN > 0 )); then
    echo -e "\n${YELLOW}${BOLD}  ⚠ VALIDATION PASSED with ${WARN} warning(s)${NC}\n"
    exit 0
else
    echo -e "\n${GREEN}${BOLD}  ✓ ALL CHECKS PASSED — ready to build ISO${NC}\n"
    exit 0
fi
