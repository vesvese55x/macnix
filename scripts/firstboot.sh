#!/usr/bin/env bash
# ============================================================================
#  MacNix 2.0 — ilk açılış (macnix-firstboot.service)
# ============================================================================
#  Kurulumdan sonraki ilk açılışta bir kez çalışır.
#  Kurulum sırasında yazılanları doğrular, CPU topolojisine göre ince ayar
#  yapar ve grafik kurulum sihirbazının açılmasını sağlar.
#
#  Kural: hiçbir adım hata verirse sistem açılmaya devam eder. Bir donanım
#  ayrıntısı yüzünden makine açılmaz hale gelmemeli.
# ============================================================================
set -Eeuo pipefail

MARKER="/etc/macnix/.firstboot-done"
LOG="/var/log/macnix-firstboot.log"
exec > >(tee -a "$LOG") 2>&1

log() { printf '[macnix-firstboot] %s\n' "$*"; }

[[ -f "$MARKER" ]] && { log "zaten yapılmış"; exit 0; }

log "ilk açılış yapılandırması başlıyor"

# ── 1. CPU / RAM gerçek değerlerle vm.conf'u güncelle ──────────────────────
VM_CONF="/etc/macnix/vm.conf"
total_ram_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
threads=$(nproc --all)
cores=$(lscpu | awk '/Core\(s\) per socket:/ {c=$4} /Socket\(s\):/ {s=$2} END {print (c*s) ? c*s : 1}')

# macOS için gerçekçi bölüşüm: host'a en az 3 GB, VM'e geri kalanın %60'ı
host_reserve=3072
if (( total_ram_mb > 6144 )); then
  vm_mb=$(( (total_ram_mb - host_reserve) / 1024 / 1024 * 1024 ))
  vm_mb=$(( vm_mb / 1024 * 1024 ))                 # 1 GB'a yuvarla
  (( vm_mb < 4096 )) && vm_mb=4096
  (( vm_mb > total_ram_mb - host_reserve )) && vm_mb=$(( total_ram_mb - host_reserve ))
else
  vm_mb=3072
fi
# CPU: tek çekirdekli host kalmayacak şekilde
vm_cores=$(( cores > 2 ? cores - 1 : 1 ))
(( vm_cores > 16 )) && vm_cores=16

if [[ -f "$VM_CONF" ]]; then
  sed -i "s/^VM_CORES=.*/VM_CORES=${vm_cores}/" "$VM_CONF" || true
  sed -i "s/^VM_RAM_MB=.*/VM_RAM_MB=${vm_mb}/" "$VM_CONF" || true
  sed -i "s/^HUGEPAGES=.*/HUGEPAGES=$(( vm_mb / 2 ))/" "$VM_CONF" || true
  log "vm.conf: ${vm_cores} çekirdek / ${vm_mb} MB"
fi

# ── 2. Hugepage ayarı (kalıcı, ama başarısız olsa da sorun değil) ──────────
hp=$(( vm_mb / 2 ))
echo "vm.nr_hugepages=${hp}" > /etc/sysctl.d/90-macnix-hugepages.conf
sysctl -p /etc/sysctl.d/90-macnix-hugepages.conf 2>/dev/null || \
  log "hugepage rezervasyonu şimdilik yapılamadı (VM başlarken tekrar denenecek)"

# ── 3. KVM MSR yaması ──────────────────────────────────────────────────────
cat > /etc/modprobe.d/macnix-kvm.conf <<'EOF'
options kvm ignore_msrs=1 report_ignored_msrs=0
EOF
log "KVM MSR yaması yazıldı"

# ── 4. Servisleri etkinleştir ──────────────────────────────────────────────
systemctl enable macnix-console.service 2>/dev/null || true
systemctl enable macnix-hugepages.service 2>/dev/null || true
log "servisler etkinleştirildi (macOS VM otomatik açılmaz — kullanıcı başlatır)"

# ── 5. Varlıkları sessizce önceden indir (varsa ağ) ────────────────────────
# Kurulum sihirbazı bunları kullanacak; arka planda hazır olsun.
if [[ ! -d /var/lib/macnix/assets/opencore/OC ]]; then
  log "ön yükleme: önyükleme bileşenleri (arka planda)"
  ( /usr/local/bin/macnix-assets --dest /var/lib/macnix/assets \
      >> /var/log/macnix-assets.log 2>&1 & ) || true
fi

# ── 6. Tanılama özeti günlüğe ──────────────────────────────────────────────
/usr/local/bin/macnix-doctor >> "$LOG" 2>&1 || true

# ── 7. İşareti koy ─────────────────────────────────────────────────────────
mkdir -p /etc/macnix
date -Iseconds > "$MARKER"
log "tamamlandı — MacNix kurulum sihirbazı grafik oturumda açılacak"
