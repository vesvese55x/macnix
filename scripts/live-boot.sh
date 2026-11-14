#!/usr/bin/env bash
# ============================================================================
#  MacNix 2.0 — canlı ortam başlangıç betiği (macnix-live.service)
# ============================================================================
#  Canlı ISO açıldığında BİR KEZ çalışır. Kurulumun çalışması için gereken
#  her şeyi hazırlar:
#
#   • squashfs medyasını bulur ve /run/live/medium'a bağlar
#     (Calamares'in unpackfs'i için gerekli — orijinalde bu yüzden patlıyordu)
#   • /run/macnix-live sembolik linkini kurar
#   • ekran/konsol ayarları, geçici dosya sistemleri
#   • donanım raporunu /var/log/macnix-live.log'a yazar
#   • X'in açılıp açılmadığını denetler, açılmadıysa TTY'ye düşer
# ============================================================================
set -Eeuo pipefail

LOG="/var/log/macnix-live.log"
exec > >(tee -a "$LOG") 2>&1

C_OK=$'\033[0;32m'; C_WA=$'\033[1;33m'; C_ER=$'\033[0;31m'; C_B=$'\033[1m'; C_R=$'\033[0m'
say()  { printf '%s[macnix-live]%s %s\n' "$C_B" "$C_R" "$*"; }
ok()   { printf '%s  [ ok ]%s %s\n' "$C_OK" "$C_R" "$*"; }
warn() { printf '%s [warn]%s %s\n' "$C_WA" "$C_R" "$*"; }
bad()  { printf '%s [fail]%s %s\n' "$C_ER" "$C_R" "$*"; }

say "MacNix 2.0 canlı ortam başlıyor"

# ── 1. Medya keşfi ─────────────────────────────────────────────────────────
# live-boot ISO'yu /run/live/medium'a bağlar. Eski sürümlerde
# /lib/live/mount/medium. Ventoy / elle bağlanan durumlar için de arayalım.
MEDIA=""
for cand in /run/live/medium /lib/live/mount/medium /run/live/rootfs /cdrom /src; do
  if [[ -f "$cand/live/filesystem.squashfs" ]]; then
    MEDIA="$cand"; break
  fi
done
if [[ -z "$MEDIA" ]]; then
  # ISO'yu kendimiz bağlamayı dene
  for dev in $(blkid -t TYPE=iso9660 -o device 2>/dev/null); do
    mkdir -p /run/macnix-media
    if mount -o ro "$dev" /run/macnix-media 2>/dev/null; then
      if [[ -f /run/macnix-media/live/filesystem.squashfs ]]; then
        MEDIA="/run/macnix-media"; break
      fi
      umount /run/macnix-media
    fi
  done
fi
if [[ -z "$MEDIA" ]]; then
  # Son çare: herhangi bir bağlı dosya sisteminde ara
  found=$(findmnt -rno TARGET | while read -r m; do
    [[ -f "$m/live/filesystem.squashfs" ]] && echo "$m" && break
  done | head -1)
  [[ -n "$found" ]] && MEDIA="$found"
fi

if [[ -n "$MEDIA" ]]; then
  ok "canlı medya: $MEDIA"
  mkdir -p /run/live
  [[ -e /run/live/medium ]] || ln -sfn "$MEDIA" /run/live/medium
  ln -sfn "$MEDIA/live" /run/macnix-live
  printf '%s\n' "$MEDIA" > /run/macnix-medium.path
else
  bad "filesystem.squashfs bulunamadı — kurulum yapılamaz!"
  warn "Bu ISO'yu bir USB'ye yazdığınızdan emin olun (dd / Rufus DD modu)."
  warn "Ventoy kullanıyorsanız 'GRUB2' modunu deneyin."
fi

# ── 2. Sanal dosya sistemleri ──────────────────────────────────────────────
mkdir -p /run/macnix
mountpoint -q /run/macnix || mount -t tmpfs -o size=64M tmpfs /run/macnix 2>/dev/null || true

# ── 3. Kalıcılık (varsa persistence bölümü) ────────────────────────────────
for pl in /run/live/persistence /lib/live/mount/persistence; do
  if [[ -d "$pl" ]]; then
    ok "kalıcılık bölümü: $pl"
    break
  fi
done

# ── 4. Udev oturması — diskler ve GPU'lar algılansın ───────────────────────
udevadm settle --timeout=15 2>/dev/null || true

# ── 5. Swap'ı kapat (macOS VM RAM'i için) ──────────────────────────────────
swapoff -a 2>/dev/null || true
ok "swap kapatıldı (VM belleği için)"

# ── 6. GPU / KVM durumu ────────────────────────────────────────────────────
if [[ -e /dev/kvm ]]; then
  ok "/dev/kvm hazır"
  chmod 666 /dev/kvm 2>/dev/null || true
else
  warn "/dev/kvm yok — BIOS'ta sanallaştırma kapalı olabilir"
  modprobe kvm 2>/dev/null || true
  modprobe kvm_amd 2>/dev/null || modprobe kvm_intel 2>/dev/null || true
fi

# ── 7. Donanım raporu ──────────────────────────────────────────────────────
if [[ -x /opt/macnix/scripts/macnix_lib.py ]]; then
  say "Donanım taranıyor…"
  python3 /opt/macnix/scripts/macnix_lib.py 2>&1 | sed 's/^/    /' || true
elif [[ -f /opt/macnix/scripts/macnix_lib.py ]]; then
  say "Donanım taranıyor…"
  python3 /opt/macnix/scripts/macnix_lib.py 2>&1 | sed 's/^/    /' || true
fi

# ── 7b. Hesaplar servisi (giriş ekranı kullanıcı listesi) ──────────────────
# lightdm "Error getting user list from org.freedesktop.Accounts" uyarısı
# veriyordu; accounts-daemon yoksa greeter kullanıcı adı soruyor. Zararsız
# ama otomatik girişi geciktiriyor — varsa başlatıyoruz.
systemctl start accounts-daemon.service 2>/dev/null || true

# ── 8. Grafik ortamı ───────────────────────────────────────────────────────
if grep -q 'macnix.nox=1' /proc/cmdline; then
  say "macnix.nox=1 — metin modu (X başlatılmayacak)"
  systemctl set-default multi-user.target 2>/dev/null || true
else
  # X'in gerçekten açılıp açılmadığını denetle; açılmazsa kullanıcıyı uyar
  (
    for _ in $(seq 1 60); do
      sleep 1
      if systemctl is-active --quiet lightdm; then
        exit 0
      fi
    done
    printf '%s [warn]%s X/lightdm başlamadı. Ekran kartı sürücüsü sorunu olabilir.\n' \
      "$C_WA" "$C_R" >/dev/tty1 2>/dev/null || true
    printf 'Kurulumu metin modunda başlatmak için:\n  sudo macnix-tui\n' >/dev/tty1 2>/dev/null || true
  ) &
fi

# ── 9. İzin / sahiplik ve otomatik giriş onarımı ──────────────────────────
# ISO'nun squashfs'i tar/aktarma sırasında uid 1000 ile paketlenmiş olabilir.
# Belirtisi:
#   sudo: /etc/sudoers.d is owned by uid 1000, should be 0
#   → sudo NOPASSWD kurallarını YOK SAYAR → Calamares otomatik açılmaz.
# Her açılışta onarıyoruz (hızlıdır, sadece sahiplik değişiyor).
if [[ "$(stat -c %u /etc/sudoers.d 2>/dev/null || echo 0)" != "0" ]]; then
  warn "/etc/sudoers.d yanlış sahipli — onarılıyor"
  chown -R root:root /etc/sudoers.d 2>/dev/null || true
fi
chmod 0750 /etc/sudoers.d 2>/dev/null || true
chmod 0440 /etc/sudoers.d/* 2>/dev/null || true
for d in /etc/calamares /etc/calamares/modules /etc/calamares/branding /opt/macnix; do
  [[ -e "$d" ]] || continue
  if [[ "$(stat -c %u "$d")" != "0" ]]; then
    chown -R root:root "$d" 2>/dev/null || true
  fi
done
ok "izinler denetlendi"

# ── 9b. LightDM otomatik giriş ────────────────────────────────────────────
# Belirti: sistem giriş ekranında kalır, Calamares kendiliğinden açılmaz ve
# lightdm günlüğünde "Can't login unknown user 'user'" yazar.
# Sebep: /etc/lightdm/lightdm.conf içindeki "autologin-user=user" satırı
#        conf.d/*.conf dosyalarını EZER.
# Bu dosya kurulum sırasında bir dpkg betiği tarafından yeniden yazılabildiği
# için (gözlemlendi: açılış anında mtime güncelleniyor) düzeltmeyi her açılışta
# yeniden uyguluyoruz — kalıcı ve zararsız.
LDMC=/etc/lightdm/lightdm.conf
if [[ -f "$LDMC" ]] && grep -qE '^[[:space:]]*autologin-user=' "$LDMC"; then
  sed -i -E 's/^[[:space:]]*autologin-user([= ].*)?$/# autologin-user\1/;
             s/^[[:space:]]*autologin-user-timeout([= ].*)?$/# autologin-user-timeout\1/' "$LDMC"
  if grep -qE '^[[:space:]]*autologin-user=' "$LDMC"; then
    bad "lightdm.conf düzeltilemedi (otomatik giriş çalışmayabilir)"
  else
    ok "lightdm.conf: autologin-user=user etkisizleştirildi"
    NEED_LIGHTDM_RESTART=1
  fi
fi
if [[ "${NEED_LIGHTDM_RESTART:-0}" == "1" ]]; then
  systemctl try-restart lightdm.service 2>/dev/null || true
  ok "lightdm yeniden başlatıldı (yeni ayarlar okunsun)"
fi

ok "canlı ortam hazır"
say "Ayrıntılı günlük: $LOG"
