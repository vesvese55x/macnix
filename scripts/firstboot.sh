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

# ── 0. Canlı ortam hesabını temizle ───────────────────────────────────────
# Calamares'in "removeuser" job'u Debian 13 (calamares 3.2.61) derlemesinde
# ETKİSİZ bir stub: userdel çağrısı içermiyor (libcalamares_job_removeuser.so
# içinde "userdel" metni yok — incelendi). Bu yüzden ISO'dan gelen canlı hesap
# "macnix-live" kurulu sistemde kalıyor ve /home/macnix-live boşuna duruyor.
# Temizliği burada, ilk açılışta yapıyoruz (idempotent).
if id -u macnix-live >/dev/null 2>&1; then
    if pkill -KILL -u macnix-live 2>/dev/null; then sleep 1; fi
    if userdel -r macnix-live 2>/dev/null; then
        log "canlı ortam hesabı macnix-live silindi"
    else
        userdel macnix-live 2>/dev/null || true
        rm -rf /home/macnix-live 2>/dev/null || true
        log "macnix-live silindi (home ayrıca temizlendi)"
    fi
fi

# ── 0b. lightdm autologin: kurulu sistemde "macnix" olmalı ────────────────
# ISO'dan gelen autologin-user=macnix-live kurulu sistemde hesap olmadığı
# için oturum açılamaz durumda kalırdı.
LDMC="/etc/lightdm/lightdm.conf.d/50-macnix.conf"
if [[ -f "$LDMC" ]] && grep -q '^autologin-user=macnix-live' "$LDMC"; then
    sed -i 's/^autologin-user=macnix-live/autologin-user=macnix/' "$LDMC"
    log "lightdm autologin macnix yapıldı"
fi

# ── 0c. Parolayı tamamen kaldır — kullanıcı adı/parola SORULMAZ ───────────
# Kullanıcı kurulum sihirbazında parola alanını boş bırakabildiği gibi, hiç
# dokunmadığı durumda da hiçbir yerde parola istenmemelidir. hesabı parolasız
# bırakıyoruz:
#   • passwd -d  → /etc/shadow'da boş parola alanı
#   • lightdm autologin zaten açık; parola yalnızca kilit ekranı/sudo için
#     gerekir ve sudo NOPASSWD kurallarıyla (/etc/sudoers.d/99-macnix) çözülür.
#   • sudo -n çalışmazsa /etc/sudoers.d/99-macnix yeniden yazılır.
TARGET_USER="macnix"
# Kullanıcı Calamares'te BAŞKA bir ad yazdıysa onu bul (yoksa parola orada
# kalır — 2026-11-15 canlı hatasının ikinci sebebi buydu).
if ! id -u "$TARGET_USER" >/dev/null 2>&1; then
    for _u in $(awk -F: '$3 >= 1000 && $3 < 65534 && $1 != "nobody" {print $1}' /etc/passwd); do
        TARGET_USER="$_u"; break
    done
    log "kurulum kullanıcısı bulundu: $TARGET_USER"
fi
if id -u "$TARGET_USER" >/dev/null 2>&1; then
    passwd -d "$TARGET_USER" >/dev/null 2>&1 && \
        log "parola kaldırıldı (macnix → parolasız)" || \
        log "parola kaldırılamadı (zararsız: autologin açık)"
    # kullanıcı adını Global Storage'dan farklı seçtiyse onu da parolasız yap
    ALT_USER="$(sed -n 's/^autologin-user=\(.*\)/\1/p' \
        /etc/lightdm/lightdm.conf 2>/dev/null | tail -1)"
    if [[ -n "${ALT_USER:-}" && "$ALT_USER" != "$TARGET_USER" ]] && id -u "$ALT_USER" >/dev/null 2>&1; then
        passwd -d "$ALT_USER" >/dev/null 2>&1 || true
        log "autologin kullanıcısı parolasız: $ALT_USER"
    fi
fi

# ── 0c-2. SIFRESIZ SUDO: kullanici adi ne olursa olsun ────────────────────
# 2026-11-15 CANLI HATA: kullanici kurulu sistemde "parola gerekli" uyarisi
# aldi. Iki ayri sebep vardi:
#   1) bu servis (macnix-firstboot) ISO'da ETKIN DEGILDI -> bu blok hic
#      calismiyordu. build.sh artik etkinlestiriyor (+ derlemede dogruluyor).
#   2) sudoers kurali yalnizca "macnix" adini kapsiyordu; kullanici kurulumda
#      farkli bir ad yazarsa hicbir NOPASSWD kurali eslesmiyordu.
# Cozum: %sudo grubuna tam NOPASSWD (Calamares kullaniciyi bu gruba ekliyor)
# + sudoers.d sahiplik/izin onarimi.
install -d -m 0750 /etc/sudoers.d
printf '%%sudo ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/99-zz-macnix-nopasswd
chmod 0440 /etc/sudoers.d/99-zz-macnix-nopasswd
# sudo, sudoers.d dosyalarini ALFABETIK okur; son eslesen kazanir.
# Calamares'in 10-installer dosyasini 99-zz ile eziyoruz.
chown root:root /etc/sudoers.d /etc/sudoers.d/* 2>/dev/null || true
chmod 0750 /etc/sudoers.d 2>/dev/null || true
chmod 0440 /etc/sudoers.d/* 2>/dev/null || true
# sozdizimi bozuksa hicbir sey calismaz -> denetle, gerekirse sadelestir
if ! visudo -cf /etc/sudoers >/dev/null 2>&1; then
    rm -f /etc/sudoers.d/99-macnix /etc/sudoers.d/99-zz-macnix-nopasswd
    printf '%%sudo ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/00-macnix
    chmod 0440 /etc/sudoers.d/00-macnix
    log "sudoers sozdizimi bozuktu - sadelestirildi (00-macnix)"
fi
log "sifresiz sudo hazir (%sudo NOPASSWD) - kullanici adindan bagimsiz"

# ── 0d. Oturum açma ekranı (lightdm) tamamen kapatılsın ───────────────────
# Autologin bir sebeple çalışmazsa (ör. kullanıcı adı değişti) kullanıcı yine
# de parola ekranıyla karşılaşmasın: greeter'ı devre dışı bırakıp oturumu
# doğrudan başlatıyoruz. lightdm autologin'i zaten destekliyor; burada ek
# güvence olarak greeter gizleniyor.
LDMC="/etc/lightdm/lightdm.conf.d/50-macnix.conf"
if [[ -f "$LDMC" ]]; then
    grep -q '^autologin-user-timeout=' "$LDMC" || echo 'autologin-user-timeout=0' >> "$LDMC"
    grep -q '^autologin-session=' "$LDMC" || echo 'autologin-session=openbox' >> "$LDMC"
    if ! grep -q '^autologin-user=' "$LDMC"; then
        echo "autologin-user=$TARGET_USER" >> "$LDMC"
    fi
    log "lightdm otomatik oturum: $(sed -n 's/^autologin-user=//p' "$LDMC" | tail -1)"
fi

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
