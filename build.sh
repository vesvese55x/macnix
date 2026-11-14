#!/usr/bin/env bash
# ============================================================================
#  MacNix 2.0 — ISO build engine
# ============================================================================
#  Kendi kendine yeten, live-build BAĞIMSIZ üretici.
#
#  Neden live-build değil?
#  ----------------------
#  Orijinal MacNix, live-build'e 7 adet `sed` yaması uyguluyordu
#  (isohybrid maskesi, kernel rename, hooks köprüsü...). Bu yamalar
#  upstream sürümlerle uyuşmadığı için ISO ya hiç üretilmiyor ya da
#  üretilen ISO'nun canlı ortamında unpackfs patlıyordu.
#  Bu motor o katmanı tamamen kaldırır: debootstrap + mksquashfs + xorriso.
#
#  Kullanım:
#     sudo ./build.sh                  # tam ISO
#     sudo ./build.sh --stage rootfs   # sadece kök dosya sistemi
#     sudo ./build.sh --stage iso      # rootfs hazırsa ISO'yu paketle
#     sudo ./build.sh --clean
#
#  Ortam değişkenleri:
#     WORK=/data/build          çalışma dizini
#     OUT=/data/workspace/out   çıktı dizini
#     USB_TREE=1                USB ağacı da üret
#     KEEP_ROOTFS=1             rootfs'i silme
# ============================================================================
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(cat "${ROOT}/VERSION" 2>/dev/null || echo 2.0.0)"
WORK="${WORK:-/data/build}"
OUT="${OUT:-/data/workspace/out}"
ROOTFS="${WORK}/rootfs"
ISOTREE="${WORK}/isotree"
CACHE="${WORK}/cache"
JOBS="${MACNIX_JOBS:-$(nproc)}"

DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
DEB_MIRROR="${DEB_MIRROR:-http://deb.debian.org/debian}"
SEC_MIRROR="${SEC_MIRROR:-http://security.debian.org/debian-security}"
ARCH="${ARCH:-amd64}"
# Debian çok mimarili dizin adı — Calamares modülleri buraya kurulur.
case "$ARCH" in
  amd64) MACNIX_MULTIARCH="x86_64-linux-gnu" ;;
  arm64) MACNIX_MULTIARCH="aarch64-linux-gnu" ;;
  i386)  MACNIX_MULTIARCH="i386-linux-gnu" ;;
  *)     MACNIX_MULTIARCH="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)" ;;
esac
export MACNIX_MULTIARCH
ISO_NAME="macnix-${VERSION}-${ARCH}.iso"
VOLID="MACNIX"
USB_TREE="${USB_TREE:-1}"

c_reset=$'\033[0m'; c_b=$'\033[1m'; c_ok=$'\033[0;32m'; c_wa=$'\033[1;33m'
c_er=$'\033[0;31m'; c_st=$'\033[0;36m'
log()   { printf '%s[macnix]%s %s\n' "$c_st" "$c_reset" "$*"; }
ok()    { printf '%s[  ok   ]%s %s\n' "$c_ok" "$c_reset" "$*"; }
warn()  { printf '%s[ warn  ]%s %s\n' "$c_wa" "$c_reset" "$*"; }
die()   { printf '%s[ FAIL  ]%s %s\n' "$c_er" "$c_reset" "$*" >&2; exit 1; }
step()  { printf '\n%s━━ %s ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$c_b" "$*" "$c_reset"; }

on_error() {
  local ec=$? line=${1:-?}
  printf '%s[ FAIL  ]%s build.sh satır %s (çıkış kodu %s)\n' "$c_er" "$c_reset" "$line" "$ec" >&2
  printf 'İpucu: chroot kilidi kaldıysa: sudo rm -f %s/rootfs/var/lib/dpkg/lock*\n' "$WORK" >&2
}
trap 'on_error $LINENO' ERR

[[ $EUID -eq 0 ]] || die "Bu script root ile çalışmalı: sudo $0 $*"

STAGE="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage) STAGE="${2:?}"; shift 2 ;;
    --clean) STAGE="clean"; shift ;;
    --keep-rootfs) KEEP_ROOTFS=1; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) die "Bilinmeyen argüman: $1" ;;
  esac
done

mkdir -p "$WORK" "$OUT" "$CACHE"

preflight() {
  step "0. Ön kontroller"
  local miss=0
  for t in debootstrap mksquashfs xorriso grub-mkstandalone grub-mkimage mkfs.vfat mmd mcopy chroot mount sha256sum; do
    command -v "$t" >/dev/null 2>&1 || { printf '  eksik: %s\n' "$t"; miss=1; }
  done
  (( miss == 0 )) || die "Eksik araçlar. Kurulum:
apt-get install -y debootstrap squashfs-tools xorriso grub-efi-amd64-bin grub-pc-bin mtools dosfstools isolinux syslinux-common"
  ok "araçlar tamam"
  log "Debian: ${DEBIAN_SUITE}  •  iş: ${JOBS}  •  çıktı: ${OUT}"
}

mount_chroot() {
  mountpoint -q "$ROOTFS/proc"    || mount -t proc  proc  "$ROOTFS/proc"
  mountpoint -q "$ROOTFS/sys"     || mount -t sysfs sysfs "$ROOTFS/sys"
  mountpoint -q "$ROOTFS/dev"     || mount --bind /dev  "$ROOTFS/dev"
  mountpoint -q "$ROOTFS/dev/pts" || mount --bind /dev/pts "$ROOTFS/dev/pts"
  mountpoint -q "$ROOTFS/run"     || mount --bind /run "$ROOTFS/run" 2>/dev/null || \
                                     mount -t tmpfs tmpfs "$ROOTFS/run"
}
umount_chroot() {
  for m in "$ROOTFS/run" "$ROOTFS/dev/pts" "$ROOTFS/dev" "$ROOTFS/sys" "$ROOTFS/proc"; do
    mountpoint -q "$m" && umount -lf "$m" 2>/dev/null || true
  done
}
# NOT: chroot içine TMPDIR SIZMAMALI. Ev sahibinde /tmp küçük olduğu için
# TMPDIR=/data/tmp veriyoruz; ama chroot içinde /data/tmp YOK → dpkg
# postinst'leri "mktemp: failed to create file via template" ile patlıyor
# (ca-certificates kurulumu başarısız oluyordu). env -u TMPDIR ile siliyoruz.
chroot_run() { chroot "$ROOTFS" /usr/bin/env -u TMPDIR -u MAKEFLAGS /bin/bash -c "$1"; }

# ── Paket listesi ───────────────────────────────────────────────────────────
collect_packages() {
  local out="$WORK/packages.txt"
  : > "$out"
  local f line
  for f in "$ROOT"/packages/*.list.chroot; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="$(printf '%s' "$line" | tr -d '\r' | xargs)"
      [[ -z "$line" ]] && continue
      # grub-efi-amd64 ayrı geçişte kurulur
      [[ "$line" == "grub-efi-amd64" ]] && continue
      printf '%s\n' "$line" >> "$out"
    done < "$f"
  done
  sort -u "$out" -o "$out"
  wc -l < "$out"
}

stage_rootfs() {
  step "1. Kök dosya sistemi — debootstrap ${DEBIAN_SUITE}"
  if [[ -d "$ROOTFS/etc" ]]; then
    log "mevcut rootfs bulundu, atlanıyor (sıfırdan: --clean)"
  else
    rm -rf "$ROOTFS"; mkdir -p "$ROOTFS" "$CACHE/debootstrap"
    log "debootstrap ${DEBIAN_SUITE} (main) — 1-3 dk"
    debootstrap --variant=minbase --arch="$ARCH" --components=main --merged-usr \
      --cache-dir="$CACHE/debootstrap" \
      "$DEBIAN_SUITE" "$ROOTFS" "$DEB_MIRROR" > "$WORK/debootstrap.log" 2>&1 \
      || { tail -20 "$WORK/debootstrap.log" >&2; die "debootstrap başarısız (günlük: $WORK/debootstrap.log)"; }
    # contrib / non-free / non-free-firmware paketleri ikinci geçişte apt ile gelir
    # (debootstrap --components ile hepsini birden istemek bazı imajlarda
    #  "Valid Release signature" sonrasında sessizce çıkar)
    ok "debootstrap tamamlandı"
  fi

  cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb ${DEB_MIRROR}/ ${DEBIAN_SUITE} main contrib non-free non-free-firmware
deb ${DEB_MIRROR}/ ${DEBIAN_SUITE}-updates main contrib non-free non-free-firmware
deb ${SEC_MIRROR}/ ${DEBIAN_SUITE}-security main contrib non-free non-free-firmware
EOF
  cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
  printf '127.0.0.1 localhost\n127.0.1.1 macnix-live\n' > "$ROOTFS/etc/hosts"
  printf 'MACNIX-LIVE\n' > "$ROOTFS/etc/hostname"

  mount_chroot
  # NOT: apt çıktısı artık yutulmuyor. Önceden `| tail -2` kullanılıyordu;
  # boru hattı başarısız olduğunda ERR tuzağı yalnızca "satır 109" yazıyor,
  # GERÇEK sebep (ağ, imza, kilit) kayboluyordu. Artık günlüğe yazılıyor.
  if ! chroot_run "export DEBIAN_FRONTEND=noninteractive
                   apt-get update -qq &&
                   apt-get -y -qq --no-install-recommends install ca-certificates gnupg apt-utils" \
        > "$WORK/apt-base.log" 2>&1; then
    tail -25 "$WORK/apt-base.log" >&2 || true
    umount_chroot
    die "apt tabanı kurulamadı (günlük: $WORK/apt-base.log)"
  fi
  ok "apt tabanı hazır"
}

install_packages() {
  step "2. Paketler"
  local n; n="$(collect_packages)"
  log "liste: ${n} paket"

  cp "$WORK/packages.txt" "$ROOTFS/tmp/packages.txt"
  chroot_run "export DEBIAN_FRONTEND=noninteractive
              apt-get update -qq
              xargs -a /tmp/packages.txt apt-get -y -qq --no-install-recommends \
                -o Dpkg::Options::=--force-confold install" 2>&1 | tail -25 \
    || warn "bazı paketler kurulamadı (yukarıya bakın)"

  # ── Önyükleme yükleyici paketleri (HEM EFI HEM BIOS) ────────────────────
  # Sadece grub-efi-* kuruluydu → kurulan sistemde
  #   /usr/lib/grub/i386-pc bulunmuyordu →
  #   "grub-install: error: /usr/lib/grub/i386-pc/modinfo.sh doesn't exist"
  # yani BIOS/legacy makinelerde GRUB kurulumu BAŞARISIZ oluyordu.
  # Canlı testte (kurulum exec aşaması) yakalandı. Artık grub-pc-bin de var.
  # efibootmgr: Calamares'in EFI önyükleme kaydı için gerekli.
  # grub2-common: grub-mkconfig / grub-mkimage araçları.
  log "önyükleme yükleyici paketleri (EFI + BIOS)"
  chroot_run "export DEBIAN_FRONTEND=noninteractive
              apt-get -y -qq --no-install-recommends -o Dpkg::Options::=--force-confold \
                install grub-efi-amd64 grub-efi-amd64-bin grub-pc-bin grub2-common efibootmgr" \
    2>&1 | tail -5 || warn "grub postinst uyardı (ISO için zararsız)"
  for d in x86_64-efi i386-pc; do
    [[ -d "$ROOTFS/usr/lib/grub/$d" ]] && ok "grub hedefi hazır: $d" \
      || warn "grub hedefi EKSİK: $d (kurulum sonrası grub-install başarısız olur)"
  done

  ls "$ROOTFS"/boot/vmlinuz-* >/dev/null 2>&1 || die "çekirdek kurulamadı (linux-image-amd64)"
  ok "paketler kuruldu"
}

stage_overlay() {
  step "3. MacNix katmanı"

  install -d "$ROOTFS/opt/macnix"
  rm -rf "$ROOTFS/opt/macnix/config" "$ROOTFS/opt/macnix/scripts" "$ROOTFS/opt/macnix/calamares"
  mkdir -p "$ROOTFS/opt/macnix"/{scripts,config,calamares,assets}
  cp -a "${ROOT}/config/."    "$ROOTFS/opt/macnix/config/"
  cp -a "${ROOT}/scripts/."   "$ROOTFS/opt/macnix/scripts/"
  cp -a "${ROOT}/calamares/." "$ROOTFS/opt/macnix/calamares/"
  find "$ROOTFS/opt/macnix/scripts" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod 0755 {} +

  install -d "$ROOTFS/usr/local/bin"
  local f base
  for f in "$ROOT"/scripts/bin/*; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    case "$base" in
      # kaynak dosyanın adı macnix-fetch-macos.py → komut macnix-fetch-macos
      *.py) base="${base%.py}" ;;
    esac
    install -m 0755 "$f" "$ROOTFS/usr/local/bin/$base"
  done
  # ayrıca kütüphaneyi de getir (Calamares ve araçlar sys.path ile bulur)
  [[ -f "$ROOT"/scripts/macnix_lib.py ]] && \
    install -m 0644 "$ROOT"/scripts/macnix_lib.py "$ROOTFS/opt/macnix/scripts/macnix_lib.py"

  # ── Calamares yerleşimi ────────────────────────────────────────────────
  # Debian'ın `calamares` paketi /etc/calamares/modules dizinini oluşturmaz
  # (o dizin calamares-settings-* paketlerinden gelir) → kendimiz kuruyoruz.
  #
  # ÖNEMLİ: modüller ÇOK MİMARİLİ dizine kurulmalı
  #   /usr/lib/x86_64-linux-gnu/calamares/modules
  # çünkü Calamares yalnızca oraya ve "local" yoluna bakar. Eski build.sh
  # /usr/lib/calamares/modules kullanıyordu → python modülleri hiç bulunamıyordu
  # ("Module ... not found in module search paths").
  local CAL_MOD_DIR
  CAL_MOD_DIR="$ROOTFS/usr/lib/${MACNIX_MULTIARCH:-$(gcc -dumpmachine)}/calamares/modules"
  install -d "$ROOTFS/etc/calamares/modules" "$CAL_MOD_DIR"
  rm -rf "$ROOTFS/etc/calamares/branding"

  # settings.conf içindeki @MULTIARCH@ yer tutucusunu gerçek değerle değiştir
  sed "s/@MULTIARCH@/${MACNIX_MULTIARCH:-$(gcc -dumpmachine)}/g" \
      "${ROOT}/calamares/settings.conf" > "$ROOTFS/etc/calamares/settings.conf"
  chmod 0644 "$ROOTFS/etc/calamares/settings.conf"

  cp -a "${ROOT}/calamares/branding" "$ROOTFS/etc/calamares/branding"

  # Python job modülleri (macnix-welcome KALDIRILDI: Debian Calamares'i
  # PythonQt olmadan derlenmiş, "interface: python" + viewmodule desteklenmiyor)
  # ÖNEMLİ: liste SABİT olmamalı. Yeni bir modül (örn. macnix-efi-fallback)
  # eklendiğinde burada da elle yazılması gerekiyordu ve unutulduğunda
  # Calamares "The following modules could not be loaded" diyerek hiç
  # açılmıyordu (canlı testte birebir yakalandı). Artık dizindeki HER modül
  # kopyalanıyor.
  local m
  for m in $(cd "${ROOT}/calamares/modules" && ls -d */ 2>/dev/null | tr -d /); do
    [[ -d "${ROOT}/calamares/modules/$m" ]] || continue
    install -d "$CAL_MOD_DIR/$m"
    install -m 0644 "${ROOT}/calamares/modules/$m/main.py"      "$CAL_MOD_DIR/$m/main.py"
    install -m 0644 "${ROOT}/calamares/modules/$m/module.desc"  "$CAL_MOD_DIR/$m/module.desc"
    chmod 0755 "$CAL_MOD_DIR/$m/main.py"
  done

  # ---------------------------------------------------------------------
  # mount modülü YAMASI (MacNix 2.0 — canlı kurulumda yakalanan hata)
  # ---------------------------------------------------------------------
  # Debian calamares 3.2.61'in mount/main.py dosyası, bölüm bilgisindeki
  # `options` değerini olduğu gibi libcalamares.utils.mount()'a veriyor:
  #
  #     libcalamares.utils.mount(device, mount_point, fstype,
  #                              partition.get("options", ""))
  #
  # C++ tarafındaki imza DÖRT std::string istiyor:
  #     CalamaresPython::mount(string, string, string, string)
  # `options` bir liste olduğunda (bölümleme modülü bazı akışlarda liste
  # üretiyor) Boost.Python şu hatayı fırlatıyor ve kurulum TAM O NOKTADA
  # düşüyor ("Kurulum Başarısız · Boost.Python is hasatı mount"):
  #
  #     Boost.Python.ArgumentError: Python argument types in
  #       libcalamares.utils.mount(str, str, str, list)
  #     did not match C++ signature: ... mount(std::string x4)
  #
  # Aşağıdaki döngü, ISO'ya giren mount modülünü kopyaladıktan hemen
  # SONRA (yani son söz bizim olsun diye) repodaki düzeltilmiş sürümle
  # değiştirir. Düzeltme: options her zaman string'e normalize edilir
  # (bkz. calamares/modules/mount/main.py -> _mount_options()).
  local MOUNT_SRC MOUNT_DST
  MOUNT_SRC="${ROOT}/calamares/modules/mount/main.py"
  MOUNT_DST="$CAL_MOD_DIR/mount/main.py"
  if [[ -f "$MOUNT_SRC" ]]; then
    install -d "$CAL_MOD_DIR/mount"
    install -m 0755 "$MOUNT_SRC" "$MOUNT_DST"
    ok "mount/main.py yaması uygulandı (options → string normalizasyonu)"
  else
    warn "calamares/modules/mount/main.py yok — mount hatası tekrar edebilir"
  fi


  # Modül yapılandırmaları: .conf VE .py (welcomeq/finishedq gibi QML
  # modüllerinin yapılandırması Calamares'te .py adıyla da yüklenir; ikisini
  # de kopyalıyoruz ki hangi dosya adını ararsa bulsun).
  for f in "${ROOT}"/calamares/module-conf/*.conf "${ROOT}"/calamares/module-conf/*.py; do
    [[ -f "$f" ]] || continue
    case "$(basename "$f")" in
      *.py) continue ;;   # aşağıdaki özel blokta işleniyor
    esac
    install -m 0644 "$f" "$ROOTFS/etc/calamares/modules/$(basename "$f")"
  done

  # ── QML modülleri: welcomeq / finishedq ────────────────────────────────
  # Calamares 3.2.61 bu iki modülün yapılandırmasını
  #   <modül>.conf  VEYA  <modül>.py
  # adıyla arar (modül Adı "welcomeq"/"finishedq"). İki adı da yazıyoruz;
  # içerik birebir aynı. Eksik bırakılırsa Calamares açılışta
  #   "The following modules could not be loaded: welcomeq"
  # diyerek HİÇ AÇILMAZ (canlı testte yaşandı).
  local q
  for q in welcomeq finishedq; do
    if [[ -f "${ROOT}/calamares/module-conf/${q}.py" ]]; then
      install -m 0644 "${ROOT}/calamares/module-conf/${q}.py" \
          "$ROOTFS/etc/calamares/modules/${q}.conf"
      install -m 0644 "${ROOT}/calamares/module-conf/${q}.py" \
          "$ROOTFS/etc/calamares/modules/${q}.py"
    else
      warn "${q} yapılandırması yok — Calamares açılışta modülü bulamaz!"
    fi
  done

  # notesqml: Debian'da "notes" modülü yok; notlar QML ile gösterilir.
  # Metinler derleme sırasında (canlı ortamda değil) burada üretilir.
  # ── notesqml: marka dizinindeki notes.qml ────────────────────────────────
  # Calamares marka QML'ini BRANDING DİZİNİNİN KÖKÜNDE arar
  # (Branding::componentDirectory()), "qml/" alt dizininde DEĞİL. Eski
  # build.sh dosyayı branding/macnix/qml/notes.qml konumuna kopyalıyordu →
  # notesqml kendi varsayılan QML'ine düşüyor ve ekranda ham metin yığını
  # görünüyordu (canlı test: h1.png). Doğru konum: branding/macnix/notes.qml
  install -d "$ROOTFS/etc/calamares/branding/macnix"
  install -m 0644 "${ROOT}/calamares/branding/macnix/notes.qml" \
      "$ROOTFS/etc/calamares/branding/macnix/notes.qml" 2>/dev/null || \
      warn "notes.qml marka dizinine kopyalanamadı"
  # Geriye dönük uyumluluk: eski konum da dursun
  install -d "$ROOTFS/etc/calamares/branding/macnix/qml" "$ROOTFS/etc/calamares/qml"
  install -m 0644 "${ROOT}/calamares/branding/macnix/notes.qml" \
      "$ROOTFS/etc/calamares/branding/macnix/qml/notes.qml" 2>/dev/null || true
  install -m 0644 "${ROOT}/calamares/branding/macnix/notes.qml" \
      "$ROOTFS/etc/calamares/qml/notes.qml" 2>/dev/null || true

  # ── KİMLİK: users modülünün önerdiği ad/makine adı ────────────────────
  # Kullanıcı hiçbir şey yazmak zorunda değil: alanlar "macnix" ile dolu gelir.
  # (Calamares 3.2.61'de otomatik doldurma için JSON preset mekanizması YOK —
  #  yalnızca 3.3'te var. Bu yüzden .conf içinde yalnızca davranış anahtarları
  #  kullanılıyor; alanların öneri değerleri zaten "macnix" hosts/DMI'dan gelir.)
  install -d "$ROOTFS/etc/macnix"
  cat > "$ROOTFS/etc/macnix/kimlik.conf" <<'KIMLIK'
# MacNix 2.0 — kurulum kimliği (bilgi amaçlı; Calamares okumaz)
ONERILEN_KULLANICI=macnix
ONERILEN_MAKINE=macnix
PAROLA_POLITIKASI=parolasiz   # kurulum sonrası passwd -d ile kaldırılır
AUTOLOGIN=acik
KIMLIK
  chmod 0644 "$ROOTFS/etc/macnix/kimlik.conf"

  # NOT: sahiplik düzeltmesi BURADA YAPILMAZ. overlay/ ağacı bu satırdan
  # SONRA kopyalandığı için (aşağıya bakın) düzeltme eziliyordu. Nihai
  # düzeltme stage_chroot_setup içindeki fix_ownership() ile yapılır.

  chmod 0750 "$ROOTFS/etc/sudoers.d" 2>/dev/null || true
  chmod 0440 "$ROOTFS"/etc/sudoers.d/* 2>/dev/null || true

  if [[ -d "${ROOT}/plymouth/macnix" ]]; then
    install -d "$ROOTFS/usr/share/plymouth/themes/macnix"
    cp -a "${ROOT}/plymouth/macnix/." "$ROOTFS/usr/share/plymouth/themes/macnix/"
  fi

  install -d "$ROOTFS/etc/systemd/system"
  for f in "$ROOT"/systemd/*.service; do
    [[ -f "$f" ]] && install -m 0644 "$f" "$ROOTFS/etc/systemd/system/"
  done

  cp -a "${ROOT}/overlay/." "$ROOTFS/"

  # ── Canlı ortam hesabı: "macnix-live" OLMALI, "macnix" DEĞİL ─────────────
  # Neden: Calamares'in `users` job'u hedefe "macnix" hesabını oluşturmaya
  # çalışıyor (install-plan.json -> users). Eğer canlı ortamda da "macnix"
  # adlı bir hesap varsa, unpackfs kök dosya sistemini hedefe kopyaladığında
  # /etc/passwd de birlikte geliyor ve kurulum şu hatayla DÜŞÜYOR:
  #     useradd: user 'macnix' already exists
  #     Command <i>useradd -m -U -s /bin/bash -c … macnix</i> exit code 9
  # (canlı testte birebir yakalandı, 2026-11-14 — kurulum %50'de öldü)
  # Çözüm: canlı hesabın adı macnix-live. Ayrıca settings.conf'ta unpackfs'ten
  # hemen sonra `removeuser` job'u çalışıp bu hesabı hedeften siliyor;
  # böylece hem çakışma olmuyor hem de kurulu sistemde artık hesap kalmıyor.
  chroot_run "id -u macnix-live >/dev/null 2>&1 || \
      useradd -m -s /bin/bash -c 'MacNix Live' -G sudo,audio,video,plugdev,netdev,cdrom,disk,input,kvm macnix-live
    echo 'macnix-live:macnix' | chpasswd
    echo 'root:root' | chpasswd" || warn "kullanıcı oluşturma uyarı"

  # ── sudoers: DOSYA ADI SIRASI KRİTİK ────────────────────────────────────
  # sudo /etc/sudoers.d/* dosyalarını ALFABETİK okur; aynı komut için SON
  # eşleşen kural kazanır. Calamares kurulum sırasında 10-installer dosyasını
  # "%sudo ALL=(ALL:ALL) ALL" ile yazıyor. Kurallarımız ondan ÖNCE okunursa
  # NOPASSWD ezilir ve macnix-setup içindeki her "sudo -n" çağrısı
  #   "sudo: a password is required"
  # hatasıyla düşer (canlı testte birebir yakalandı, 2026-11-14).
  # Bu yüzden dosya adları 99- önekli: 10-installer'dan SONRA okunurlar.
  #   • 99-macnix    → yalnızca MacNix araçları için NOPASSWD (kurulu sistem)
  #   • 99-macnix-live → canlı ortamda tam NOPASSWD (010-live'dan taşındı)
  install -d -m 0750 "$ROOTFS/etc/sudoers.d"
  install -m 0440 "${ROOT}/overlay/etc/sudoers.d/99-macnix" "$ROOTFS/etc/sudoers.d/99-macnix"
  printf 'macnix ALL=(ALL) NOPASSWD: ALL\nmacnix-live ALL=(ALL) NOPASSWD: ALL\n' > "$ROOTFS/etc/sudoers.d/99-macnix-live"
  chmod 0440 "$ROOTFS/etc/sudoers.d/99-macnix-live"
  # Eski adlar kalırsa (yükseltme/önbellek) sudo karışabilir: temizle
  rm -f "$ROOTFS/etc/sudoers.d/020-macnix" "$ROOTFS/etc/sudoers.d/010-live"

  # OpenCore + kextleri ISO'ya göm: ilk açılışta internet gerekmesin
  if [[ "${BUNDLE_ASSETS:-1}" == "1" ]]; then
    log "Önyükleme bileşenleri ISO'ya gömülüyor (OpenCore + kextler + AMD yamaları)"
    if MACNIX_ASSETS="$ROOTFS/opt/macnix/assets" \
       bash "${ROOT}/scripts/bin/macnix-assets" \
            --dest "$ROOTFS/opt/macnix/assets" > "$WORK/assets.log" 2>&1; then
      ok "gömülü bileşenler: $(du -sh "$ROOTFS/opt/macnix/assets" | cut -f1)"
      touch "$ROOTFS/opt/macnix/assets/.complete"
    else
      warn "bileşenler indirilemedi — ilk açılışta internetten alınacak"
      tail -3 "$WORK/assets.log" 2>/dev/null | sed 's/^/    /' || true
    fi
  fi

  ok "MacNix katmanı yerleşti"
}

stage_chroot_setup() {
  step "4. chroot yapılandırması"

  cat > "$ROOTFS/etc/locale.gen" <<'EOF'
en_US.UTF-8 UTF-8
tr_TR.UTF-8 UTF-8
EOF
  # Canlı ortamın varsayılan dili: Türkçe. Calamares arayüzü de bu locale ile
  # Türkçe açılır (masaüstü düğmeleri "İleri/Geri/Bitir"). Kurulumda kullanıcı
  # dil ekranından değiştirebilir; kurulu sistemde seçtiği dil geçerli olur.
  printf 'LANG=tr_TR.UTF-8\nLANGUAGE=tr_TR:tr\n' > "$ROOTFS/etc/default/locale"
  chroot_run "locale-gen" >/dev/null 2>&1 || true

  install -d "$ROOTFS/etc/initramfs-tools/conf.d" "$ROOTFS/etc/initramfs-tools/hooks"
  cat > "$ROOTFS/etc/initramfs-tools/conf.d/macnix.conf" <<'EOF'
MODULES=most
COMPRESS=xz
EOF
  cat > "$ROOTFS/etc/initramfs-tools/hooks/macnix" <<'EOF'
#!/bin/sh
set -e
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
manual_add_modules squashfs overlay loop
manual_add_modules xhci_pci xhci_hcd ehci_pci ehci_hcd usbhid hid_generic
manual_add_modules vfat fat nls_cp437 nls_ascii nls_utf8 ntfs3 exfat isofs udf
manual_add_modules ahci libahci sd_mod sr_mod nvme nvme_core
manual_add_modules dm_mod dm_crypt
exit 0
EOF
  chmod 0755 "$ROOTFS/etc/initramfs-tools/hooks/macnix"
  : > "$ROOTFS/etc/fstab"

  if [[ -d "$ROOTFS/usr/share/plymouth/themes/macnix" ]]; then
    chroot_run "command -v plymouth-set-default-theme >/dev/null && plymouth-set-default-theme macnix || true" || true
  fi

  chroot_run "systemctl enable macnix-live.service      >/dev/null 2>&1 || true
              systemctl enable lightdm.service        >/dev/null 2>&1 || true
              systemctl enable NetworkManager.service >/dev/null 2>&1 || true
              systemctl set-default graphical.target  >/dev/null 2>&1 || true
              systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true" || true

  # NOT: `komut | tail` yazımı ERR tuzağını yanıltıyordu; chroot içinde
  # update-initramfs sıfırdan farklı dönerse aşama SESSİZCE kesiliyor ve
  # sonraki düzeltmeler (lightdm otomatik giriş) hiç uygulanmıyordu.
  local irfs="$WORK/update-initramfs.log"
  if ! chroot_run "update-initramfs -u -k all" > "$irfs" 2>&1; then
    tail -5 "$irfs" 2>/dev/null | sed 's/^/    /' || true
    warn "update-initramfs uyarı (günlük: $irfs)"
  fi

  fix_ownership
  fix_lightdm_autologin
  finalize_calamares_config
  ok "chroot yapılandırması tamam"
}

# ── Son rötuş: sahiplik ────────────────────────────────────────────────────
# TAR GEÇMİŞİ: overlay/ ağacı scp/tar ile uid 1000 olarak geldi ve
# /etc/sudoers.d 1000:1000 kaldı. Belirtisi:
#     sudo: /etc/sudoers.d is owned by uid 1000, should be 0
#     → sudo NOPASSWD kurallarını YOK SAYAR → Calamares hiç açılmaz.
# Bu yüzden rootfs'e yazılan her şeyden SONRA (overlay kopyası ve chroot
# betiklerinden sonra) sahipliği root'a çekiyoruz.
fix_ownership() {
  local bad=0
  chown -R 0:0 "$ROOTFS/etc" "$ROOTFS/opt" "$ROOTFS/usr/local" 2>/dev/null || true
  chmod 0750 "$ROOTFS/etc/sudoers.d" 2>/dev/null || true
  chmod 0440 "$ROOTFS"/etc/sudoers.d/* 2>/dev/null || true
  [[ "$(stat -c %u "$ROOTFS/etc/sudoers.d" 2>/dev/null || echo 0)" != "0" ]] && bad=1
  [[ "$(stat -c %u "$ROOTFS/etc" 2>/dev/null || echo 0)" != "0" ]] && bad=1
  if (( bad )); then
    warn "sahiplik düzeltilemedi (sudo çalışmayabilir!)"
  else
    ok "sahiplikler root:root (sudo/sudoers.d dahil)"
  fi
}

# ── Son rötuş: Calamares yapılandırması ────────────────────────────────────
# TARİHÇE (2026-11-14): Repodaki calamares/module-conf/*.py dosyalarında
# `qmlFilename: "welcome"` olmasına rağmen ISO içinde "welcome.qml" çıkıyordu;
# branding.desc da eski `sidebar: qml` satırıyla geliyordu. Yani bir aşama bu
# dosyaları repo sürümüyle EZMİYORDU (kaynaktan kopyalama sırası). Artık
# chroot kurulumunun EN SONUNDA, dosyalar TEK TEK ve açıkça yazılıyor;
# sonra içerikleri doğrulanıyor (yanlış içerik → derleme UYARIYLA değil,
# doğrulama çıktısıyla görünür).
finalize_calamares_config() {
  local d="$ROOTFS/etc/calamares"
  install -d "$d/modules" "$d/branding/macnix"

  # qmlFilename UZANTISIZ olmalı: Calamares ".qml" ekini kendisi ekler.
  # Her iki adı da yaz (Calamares <modül>.conf ya da <modül>.py arar).
  local q
  for q in welcomeq finishedq; do
    [[ -f "${ROOT}/calamares/module-conf/${q}.conf" ]] && \
      install -m 0644 "${ROOT}/calamares/module-conf/${q}.conf" "$d/modules/${q}.conf"
    [[ -f "${ROOT}/calamares/module-conf/${q}.py" ]] && \
      install -m 0644 "${ROOT}/calamares/module-conf/${q}.py"   "$d/modules/${q}.py"
  done
  install -m 0644 "${ROOT}/calamares/module-conf/notesqml.conf" "$d/modules/notesqml.conf"

  # marka dosyaları (QML + görseller) — QML paneli kullanılmıyor (varsayılan menü)
  local f
  for f in "${ROOT}"/calamares/branding/macnix/*; do
    [[ -f "$f" ]] || continue
    install -m 0644 "$f" "$d/branding/macnix/$(basename "$f")"
  done

  # settings.conf: @MULTIARCH@ yer tutucusu + welcomeq/finishedq sırası
  sed "s/@MULTIARCH@/${MACNIX_MULTIARCH:-$(gcc -dumpmachine)}/g" \
      "${ROOT}/calamares/settings.conf" > "$d/settings.conf"
  chmod 0644 "$d/settings.conf"

  # ── Doğrulama: yanlış içerik derlemeyi durdurur (sessiz kalmaktansa) ────
  local err=0
  grep -q 'qmlFilename: "welcome"'   "$d/modules/welcomeq.conf"  || { warn "welcomeq.conf: qmlFilename uzantılı!"; err=1; }
  grep -q 'qmlFilename: "finishedq"' "$d/modules/finishedq.conf" || { warn "finishedq.conf: qmlFilename uzantılı!"; err=1; }
  grep -q 'qmlFilename: "notes"'     "$d/modules/notesqml.conf"  || { warn "notesqml.conf: qmlFilename yok/uzantılı"; err=1; }
  grep -q '^sidebar:.*qml'           "$d/branding/macnix/branding.desc" && \
      warn "branding.desc: QML yan menü etkin (kırpılma riski)"
  grep -q 'bgFill'                   "$d/branding/macnix/welcome.qml"   || { warn "welcome.qml: opak zemin yok"; err=1; }
  grep -q 'bgFill'                   "$d/branding/macnix/finishedq.qml" || { warn "finishedq.qml: opak zemin yok"; err=1; }
  [[ -f "$d/branding/macnix/notes.qml" ]] || { warn "notes.qml marka dizininde yok"; err=1; }
  (( err == 0 )) && ok "Calamares yapılandırması son hâli yazıldı ve doğrulandı"
}

# ── Son rötuş: LightDM otomatik giriş ──────────────────────────────────────
# SIRA ÖNEMLİ: bu düzeltme rootfs'e yazılan HER ŞEYDEN (paket kurulumu,
# overlay kopyası, chroot betikleri) SONRA çalışmalı.
#
# Sorun: Debian'ın /etc/lightdm/lightdm.conf dosyasında
#        autologin-user=user
# satırı YORUMDAN ÇIKARILMIŞ geliyor. lightdm.conf, conf.d/*.conf dosyalarını
# EZER; dolayısıyla 50-macnix.conf içindeki autologin-user=macnix yok sayılır,
# olmayan "user" hesabıyla giriş denenir ve canlı ortam GİRİŞ EKRANINDA KALIR
# (Calamares kendiliğinden açılmaz). Canlı testte birebir bu yaşandı.
fix_lightdm_autologin() {
  local f="$ROOTFS/etc/lightdm/lightdm.conf"
  if [[ -f "$f" ]]; then
    sed -i -E 's/^[[:space:]]*autologin-user([= ].*)?$/# autologin-user\1/;
               s/^[[:space:]]*autologin-user-timeout([= ].*)?$/# autologin-user-timeout\1/' "$f"
    if grep -qE '^[[:space:]]*autologin-user=' "$f"; then
      warn "lightdm.conf hâlâ autologin-user içeriyor"
    else
      ok "lightdm.conf temizlendi (autologin-user=user etkisizleştirildi)"
    fi
  fi
  install -d -m 0755 "$ROOTFS/etc/lightdm/lightdm.conf.d"
  chown -R 0:0 "$ROOTFS/etc/lightdm" 2>/dev/null || true
  chmod 0644 "$ROOTFS/etc/lightdm/lightdm.conf.d/"*.conf 2>/dev/null || true
}

stage_isotree() {
  step "5. ISO ağacı"
  rm -rf "$ISOTREE"
  install -d "$ISOTREE"/{live,boot/grub,EFI/BOOT,.disk,isolinux}

  local kver iimg
  kver="$(ls "$ROOTFS"/boot/vmlinuz-* 2>/dev/null | sed 's|.*/vmlinuz-||' | sort -V | tail -1)"
  [[ -n "$kver" ]] || die "çekirdek bulunamadı"
  iimg="$ROOTFS/boot/initrd.img-${kver}"
  [[ -f "$iimg" ]] || die "initramfs bulunamadı: $iimg"
  cp -L "$ROOTFS/boot/vmlinuz-${kver}" "$ISOTREE/live/vmlinuz"
  cp -L "$iimg" "$ISOTREE/live/initrd.img"
  log "çekirdek ${kver} / initramfs $(du -h "$ISOTREE/live/initrd.img" | cut -f1)"

  # ── Canlı önyükleme için kritik nokta ────────────────────────────────────
  # live-boot'un init-bottom betiği şunu yapar:
  #     mount --move /dev  /root/dev
  #     mount --move /proc /root/proc   ...
  # Bu yüzden bu DİZİNLER squashfs içinde VAR OLMALIDIR (boş olsalar bile).
  # Daha önce mksquashfs'e -e ile tamamen hariç tutuldukları için canlı
  # sistem "mount: /root/dev: mount point does not exist" ile panic veriyordu.
  # Doğrusu: dizinleri koru, ÇALIŞMA ANINDAKİ içeriklerini boşalt.
  for d in dev proc sys run tmp; do
    if [[ -d "$ROOTFS/$d" ]]; then
      find "$ROOTFS/$d" -mindepth 1 -delete 2>/dev/null || \
        find "$ROOTFS/$d" -mindepth 1 -exec rm -rf {} + 2>/dev/null || true
    else
      mkdir -p "$ROOTFS/$d"
    fi
  done
  # /dev ve /proc boş kalacak; sistem açılışta devtmpfs/procfs ile doldurur.
  chmod 0755 "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/run" 2>/dev/null || true
  chmod 1777 "$ROOTFS/tmp" 2>/dev/null || true

  log "squashfs sıkıştırılıyor (xz, ${JOBS} iş) — uzun sürer…"
  mksquashfs "$ROOTFS" "$ISOTREE/live/filesystem.squashfs" \
      -comp xz -b 1M -noappend -processors "$JOBS" >/dev/null
  ok "filesystem.squashfs: $(du -h "$ISOTREE/live/filesystem.squashfs" | cut -f1)"

  install -m 0644 "${ROOT}/config/grub/grub.cfg" "$ISOTREE/boot/grub/grub.cfg"
  [[ -f "${ROOT}/calamares/branding/macnix/macnix_logo.png" ]] && \
    cp "${ROOT}/calamares/branding/macnix/macnix_logo.png" "$ISOTREE/.disk/logo.png" || true
  printf 'MacNix %s — macOS Virtualization Platform\n' "$VERSION" > "$ISOTREE/.disk/info"

  build_efi
  build_bios

  ( cd "$ISOTREE" && find . -type f ! -name 'sha256sum.txt' -print0 |
      xargs -0 sha256sum > sha256sum.txt ) 2>/dev/null || true
  ok "ISO ağacı hazır"
}

build_efi() {
  log "EFI önyükleyici üretiliyor"
  local efi="$ISOTREE/EFI/BOOT/BOOTX64.EFI"

  # GRUB modülleri sürümden sürüme değişir. Örnek (gerçek hata, GitHub
  # ubuntu-latest runner'da yakalandı):
  #   grub-mkstandalone: error: cannot open
  #       `/usr/lib/grub/x86_64-efi/efi_uga.mod': No such file or directory
  # GRUB 2.12 efi_uga.mod'u kaldırdı. Bu yüzden modül listesi SABİT değil,
  # sistemde GERÇEKTEN bulunan modüllerden süzülüyor.
  local moddir="/usr/lib/grub/x86_64-efi"
  local want="part_gpt part_msdos fat ext2 iso9660 udf ntfs normal linux all_video
              gfxterm gfxmenu font search search_label search_fs_uuid search_fs_file
              configfile loopback chain efi_gop efi_uga video_bochs video_cirrus
              echo test sleep reboot halt serial terminal minicmd"
  local modules=() m missing=()
  for m in $want; do
    [[ -f "$moddir/$m.mod" ]] && modules+=("$m") || missing+=("$m")
  done
  (( ${#modules[@]} )) || die "hiç GRUB EFI modülü bulunamadı ($moddir)"
  [[ ${#missing[@]} -gt 0 ]] && warn "bu GRUB sürümünde yok (atlandı): ${missing[*]}"
  log "EFI modülleri: ${#modules[@]} adet"

  grub-mkstandalone --format=x86_64-efi --output="$efi" \
    --modules="${modules[*]}" \
    --locales="" --themes="" --fonts="" \
    "boot/grub/grub.cfg=${ROOT}/config/grub/grub-efi-embed.cfg"
  ok "BOOTX64.EFI ($(du -h "$efi" | cut -f1))"

  local img="$ISOTREE/boot/grub/efi.img"
  rm -f "$img"
  local sz_kb=$(( ($(stat -c%s "$efi") / 1024) + 8192 ))
  dd if=/dev/zero of="$img" bs=1k count="$sz_kb" status=none
  mkfs.vfat -n MACNIX_EFI "$img" >/dev/null
  mmd -i "$img" ::/EFI ::/EFI/BOOT
  mcopy -i "$img" "$efi" ::/EFI/BOOT/BOOTX64.EFI
  ok "efiboot.img ($(du -h "$img" | cut -f1))"
}

# BIOS (legacy) önyükleme — iki yol:
#   1) isolinux varsa onu kullan (klasik, en uyumlu)
#   2) yoksa GRUB'ın kendi El Torito imajını üret (grub-pc-bin yeterli)
# Hiçbiri yoksa ISO yalnızca UEFI önyükler — bu modern makineler için yeterlidir.
build_bios() {
  local isodir="$ROOTFS/usr/lib/ISOLINUX"
  local sysdir="$ROOTFS/usr/lib/syslinux/modules/bios"

  if [[ -f "$isodir/isolinux.bin" ]]; then
    log "BIOS önyükleme: isolinux"
    cp "$isodir/isolinux.bin" "$ISOTREE/isolinux/"
    local m
    for m in ldlinux.c32 libutil.c32 libcom32.c32 menu.c32 vesamenu.c32; do
      if [[ -f "$sysdir/$m" ]]; then cp "$sysdir/$m" "$ISOTREE/isolinux/"
      elif [[ -f "$isodir/$m" ]]; then cp "$isodir/$m" "$ISOTREE/isolinux/"; fi
    done
    install -m 0644 "${ROOT}/config/grub/isolinux.cfg" "$ISOTREE/isolinux/isolinux.cfg"
    install -m 0644 "${ROOT}/config/grub/isolinux.cfg" "$ISOTREE/isolinux.cfg"
    BIOS_IMAGE="isolinux/isolinux.bin"
    BIOS_CAT="isolinux/boot.cat"
    ok "isolinux hazır"
    return 0
  fi

  # GRUB El Torito (i386-pc) — isolinux paketi olmadan BIOS önyükleme
  local modules_dir="/usr/lib/grub/i386-pc"
  if [[ -d "$modules_dir" ]] && command -v grub-mkimage >/dev/null 2>&1; then
    log "BIOS önyükleme: GRUB eltorito (i386-pc)"
    mkdir -p "$ISOTREE/boot/grub/i386-pc"
    cp -a "${ROOT}/config/grub/grub.cfg" "$ISOTREE/boot/grub/grub-bios.cfg"
    # BIOS'ta ayrı yapılandırma: gfxmenu yok, gfxterm yeterli
    grub-mkimage \
      -O i386-pc-eltorito \
      -o "$ISOTREE/boot/grub/bios.img" \
      --prefix=/boot/grub \
      -d "$modules_dir" \
      biosdisk iso9660 part_msdos part_gpt fat ext2 normal configfile linux \
      search search_label search_fs_uuid search_fs_file echo test sleep reboot \
      all_video gfxterm font || { warn "grub-mkimage başarısız — UEFI-only"; return 0; }
    install -m 0644 "${ROOT}/config/grub/grub-bios.cfg" "$ISOTREE/boot/grub/grub.cfg.bios"
    BIOS_IMAGE="boot/grub/bios.img"
    BIOS_CAT="boot/grub/boot.cat"
    ok "GRUB BIOS imajı hazır ($(du -h "$ISOTREE/boot/grub/bios.img" | cut -f1))"
    return 0
  fi

  warn "BIOS önyükleme desteklenmiyor (isolinux yok, grub-pc-bin yok)"
  warn "→ ISO yalnızca UEFI önyükler. Kurmak için: apt-get install -y isolinux"
  BIOS_IMAGE=""
  BIOS_CAT=""
}

stage_iso() {
  step "6. ISO paketleniyor"
  [[ -f "$ISOTREE/live/filesystem.squashfs" ]] || die "squashfs yok — önce --stage rootfs"

  local bios_args=()
  if [[ -n "${BIOS_IMAGE:-}" && -f "$ISOTREE/$BIOS_IMAGE" ]]; then
    bios_args=(-b "$BIOS_IMAGE" -no-emul-boot -boot-load-size 4 -boot-info-table)
    [[ -n "${BIOS_CAT:-}" ]] && mkdir -p "$(dirname "$ISOTREE/$BIOS_CAT")"
  fi

  rm -f "$OUT/$ISO_NAME"
  xorriso -as mkisofs \
    -iso-level 3 -full-iso9660-filenames -volid "$VOLID" \
    -appid "MacNix ${VERSION}" -publisher "MacNix Project" -p "MacNix ${VERSION}" \
    "${bios_args[@]}" \
    -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "$OUT/$ISO_NAME" "$ISOTREE" 2>&1 | tail -3

  [[ -f "$OUT/$ISO_NAME" ]] || die "ISO üretilemedi"
  ok "ISO: $OUT/$ISO_NAME ($(du -h "$OUT/$ISO_NAME" | cut -f1))"
  ( cd "$OUT" && sha256sum "$ISO_NAME" > "$ISO_NAME.sha256" )
  ok "SHA256: $(cut -d' ' -f1 "$OUT/$ISO_NAME.sha256")"

  [[ "$USB_TREE" == "1" ]] && stage_usbtree
}

stage_usbtree() {
  step "7. UEFI USB ağacı"
  local d="$OUT/usb-${VERSION}"
  rm -rf "$d"
  install -d "$d"/{EFI/BOOT,boot/grub,live}
  cp "$ISOTREE/EFI/BOOT/BOOTX64.EFI" "$d/EFI/BOOT/"
  cp "$ISOTREE/boot/grub/grub.cfg"   "$d/boot/grub/"
  cp "$ISOTREE/live/vmlinuz"         "$d/live/"
  cp "$ISOTREE/live/initrd.img"      "$d/live/"
  cat > "$d/USB-KURULUM.txt" <<EOF
MacNix ${VERSION} — UEFI USB kurulumu
=====================================
1) USB belleği FAT32 biçimlendir (etiket: MACNIX)
2) Bu klasörün TÜM içeriğini USB köküne kopyala
3) filesystem.squashfs dosyasını ISO'dan çıkarıp live/ içine koy:
   xorriso -osirrox on -indev macnix-${VERSION}-amd64.iso \\
           -extract /live/filesystem.squashfs ./live/filesystem.squashfs
4) USB'den UEFI önyükle.

Alternatif (tek komut):
   sudo dd if=macnix-${VERSION}-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
EOF
  ok "USB ağacı: $d"
}

do_clean() {
  step "Temizlik"
  umount_chroot || true
  rm -rf "$WORK/rootfs" "$WORK/isotree" "$WORK/grub-standalone"
  ok "rootfs ve geçici dosyalar silindi"
}

main() {
  printf '\n%s╔══════════════════════════════════════════════════════════════╗\n' "$c_b"
  printf '║   MacNix %-10s — ISO Build Engine                     ║\n' "$VERSION"
  printf '╚══════════════════════════════════════════════════════════════╝%s\n' "$c_reset"

  case "$STAGE" in
    clean) do_clean; exit 0 ;;
    rootfs)
      preflight; stage_rootfs; install_packages; stage_overlay; stage_chroot_setup
      umount_chroot; ok "rootfs hazır: $ROOTFS" ;;
    iso) preflight; stage_isotree; stage_iso ;;
    all)
      preflight; stage_rootfs; install_packages; stage_overlay; stage_chroot_setup
      umount_chroot; stage_isotree; stage_iso
      if [[ "${KEEP_ROOTFS:-0}" != "1" ]]; then rm -rf "$ROOTFS"; log "rootfs silindi"; fi ;;
    *) die "bilinmeyen aşama: $STAGE" ;;
  esac

  printf '\n%s━━ TAMAM ━━%s\n' "$c_ok" "$c_reset"
  printf '  ISO     : %s\n' "$OUT/$ISO_NAME"
  [[ -f "$OUT/$ISO_NAME.sha256" ]] && printf '  SHA256  : %s\n' "$(cut -d' ' -f1 "$OUT/$ISO_NAME.sha256")"
  printf '  USB yaz : sudo dd if=%s of=/dev/sdX bs=4M status=progress oflag=sync\n\n' "$OUT/$ISO_NAME"
}

main "$@"
