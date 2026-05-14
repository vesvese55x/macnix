#!/usr/bin/env bash
# MacNix Phase 2 — GPU Detection & Profile Generation
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/common.sh"
source "${SCRIPT_DIR}/utils/gpu-db.sh"

log_header "MacNix Phase 2 — GPU Detection Engine"
OUTPUT_FILE="${1:-${MACNIX_GPU_PROFILE}}"
mkdir -p "$(dirname "$OUTPUT_FILE")"

# 2.1 Enumerate GPUs
log_step "2.1  Scanning PCI bus for GPUs"
declare -a ADDRS=() VIDS=() DIDS=() DESCS=() VNAMES=() CLASSES=() GENS=()
declare -a IOMMU_GS=() IOMMU_MS=()
gpu_count=0
while IFS='|' read -r pa vi di cc desc; do
    [[ -z "$pa" ]] && continue
    ADDRS+=("$pa"); VIDS+=("$vi"); DIDS+=("$di"); DESCS+=("$desc")
    VNAMES+=("$(gpu_vendor_name "$vi")")
    log_info "  [${vi}:${di}] ${desc} @ ${pa}"
    ((gpu_count++)) || true
done < <(list_gpus)
(( gpu_count == 0 )) && { log_error "No GPUs detected!"; exit 1; }
log_success "Found ${gpu_count} GPU(s)"

# 2.2 IOMMU groups
log_step "2.2  Mapping IOMMU groups"
for i in "${!ADDRS[@]}"; do
    g=$(get_iommu_group "${ADDRS[$i]}")
    IOMMU_GS+=("$g")
    if [[ "$g" != "none" ]]; then
        m=$(list_iommu_group_members "$g" | tr '\n' ',')
        IOMMU_MS+=("${m%,}")
    else IOMMU_MS+=(""); fi
done

# 2.3 Classify
log_step "2.3  Classifying GPUs"
has_amd=false; has_kep=false; has_mod=false; has_igpu=false
amd_i=-1; kep_i=-1; mod_i=-1; igpu_i=-1; disc=0
for i in "${!VNAMES[@]}"; do
    v="${VNAMES[$i]}"; d="${DIDS[$i]}"
    case "$v" in
        amd) CLASSES+=("amd_discrete"); GENS+=("rdna"); has_amd=true; amd_i=$i; ((disc++)) || true ;;
        nvidia)
            gen=$(get_nvidia_generation "$d"); GENS+=("$gen")
            if [[ "$gen" == "kepler" ]]; then
                CLASSES+=("nvidia_kepler"); has_kep=true; kep_i=$i; ((disc++)) || true
            else
                CLASSES+=("nvidia_modern"); has_mod=true; mod_i=$i; ((disc++)) || true
            fi ;;
        intel) CLASSES+=("intel_igpu"); GENS+=("integrated"); has_igpu=true; igpu_i=$i ;;
        *) CLASSES+=("unknown"); GENS+=("unknown") ;;
    esac
done

# 2.4 Single vs multi GPU
single=false; (( disc <= 1 && gpu_count <= 1 )) && single=true
(( disc == 0 )) && single=true

# Decision tree
BR=""; BD=""; TI=-1; PR=""; MT="sonoma"; RP=false; WN=""
if $has_amd; then
    BR="A"; BD="AMD VFIO Passthrough"; TI=$amd_i; PR="95-100%"
    $single && { BR="E"; BD="Single-GPU AMD (hooks)"; }
elif $has_kep; then
    BR="B"; BD="NVIDIA Kepler VFIO + Patcher"; TI=$kep_i; PR="85-95%"; MT="monterey"; RP=true
    WN="macOS Monterey recommended for Kepler"
    $single && { BR="E"; BD="Single-GPU Kepler (hooks)"; }
elif $has_igpu && (( disc > 0 )); then
    BR="C"; BD="Intel iGPU GVT-g"; TI=$igpu_i; PR="60-80%"
elif $has_mod; then
    BR="D"; BD="Software Rendering (virtio-gpu)"; TI=$mod_i; PR="15-30%"
    WN="No GPU acceleration — modern NVIDIA has no macOS support"
    $single && { BR="E"; BD="Single-GPU NVIDIA fallback (hooks)"; }
elif $has_igpu; then
    BR="C"; BD="Intel iGPU only (GVT-g)"; TI=$igpu_i; PR="40-60%"
else
    BR="D"; BD="Software Fallback"; TI=0; PR="15-30%"; WN="No optimal GPU strategy found"
fi

log_success "Branch ${BR}: ${BD} — ${PR}"
[[ -n "$WN" ]] && log_warn "$WN"

# 2.5 Write profile JSON
log_step "2.5  Writing GPU profile to ${OUTPUT_FILE}"
GA="["; for i in "${!ADDRS[@]}"; do
    (( i > 0 )) && GA+=","
    GA+="{\"index\":${i},\"pci\":\"${ADDRS[$i]}\",\"vid\":\"${VIDS[$i]}\",\"did\":\"${DIDS[$i]}\","
    GA+="\"vendor\":\"${VNAMES[$i]}\",\"class\":\"${CLASSES[$i]}\",\"gen\":\"${GENS[$i]}\","
    GA+="\"desc\":\"${DESCS[$i]}\",\"iommu_group\":\"${IOMMU_GS[$i]}\","
    GA+="\"iommu_members\":\"${IOMMU_MS[$i]}\",\"driver\":\"$(get_pci_driver "${ADDRS[$i]}")\"}"
done; GA+="]"

cat > "$OUTPUT_FILE" <<EOF
{
  "generated_at": "$(date -Iseconds)",
  "cpu_vendor": "$(get_cpu_vendor)",
  "total_ram_gb": $(get_total_ram_gb),
  "gpu_count": ${gpu_count},
  "discrete_count": ${disc},
  "single_gpu": ${single},
  "branch": "${BR}",
  "branch_desc": "${BD}",
  "target_gpu_idx": ${TI},
  "perf_range": "${PR}",
  "macos_target": "${MT}",
  "rom_patch": ${RP},
  "warnings": "${WN}",
  "gpus": ${GA}
}
EOF
log_success "GPU profile written"
log_header "Phase 2 Complete"
