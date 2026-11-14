#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""sudoers kural sırası regresyon testi.

GERÇEK HATA (MacNix 2.0, kurulmuş sistem, 2026-11-14):
    macnix-setup GUI'de 1. adım (Önyükleme bileşenleri):
        sudo: a password is required
    Adım 1 başarısız oldu.

KÖK NEDEN:
    sudo /etc/sudoers.d/* dosyalarını ALFABETİK okur ve aynı komut için
    SON eşleşen kural kazanır. Dosya adı "020-macnix" idi, Calamares'ın
    yazdığı "10-installer" ("%sudo ALL=(ALL:ALL) ALL") ise ondan SONRA
    okunuyordu → NOPASSWD kuralları eziliyordu.

    Diskin üzerinde yapılan deney (aynı gün):
        010-live + 10-installer          → sudo -n → "a password is required"
        010-live → 95-live yapıldı       → sudo -n → ŞİFRESİZ ÇALIŞTI

BU TEST:
    1. overlay'de 99-macnix dosyası var mı, 020-macnix kalmış mı?
    2. build.sh 99- önekini kullanıyor mu, eski adları temizliyor mu?
    3. istenirse (--canli) gerçek sudo ile davranış testi:
       geçici bir kullanıcı + "10-installer" + "99-macnix" benzeri kurallar
       yazıp `sudo -n` çalıştırır; şifre istememesi gerekir.
"""

import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUDOERS_D = os.path.join(ROOT, "overlay", "etc", "sudoers.d")
BUILD = os.path.join(ROOT, "build.sh")

gecti = 0
kaldi = 0


def kontrol(ad, kosul, detay=""):
    global gecti, kaldi
    if kosul:
        gecti += 1
        print("  \033[32m✓\033[0m %s" % ad)
    else:
        kaldi += 1
        print("  \033[31m✗\033[0m %s %s" % (ad, detay))


def statik():
    print("1) overlay dosyaları")
    adlar = sorted(os.listdir(SUDOERS_D)) if os.path.isdir(SUDOERS_D) else []
    kontrol("99-macnix var", "99-macnix" in adlar, "(bulunan: %s)" % adlar)
    kontrol("020-macnix KALDIRILMIŞ (eski ad)", "020-macnix" not in adlar)

    yol = os.path.join(SUDOERS_D, "99-macnix")
    if os.path.isfile(yol):
        icerik = open(yol, encoding="utf-8").read()
        kontrol("NOPASSWD kuralları duruyor", icerik.count("NOPASSWD:") >= 8,
                "(bulunan: %d)" % icerik.count("NOPASSWD:"))
        kontrol("neden 99- olduğu belgelenmiş",
                "alfabetik" in icerik.lower() or "ALFABET" in icerik)

    print("\n2) build.sh")
    if not os.path.isfile(BUILD):
        kontrol("build.sh var", False)
        return
    s = open(BUILD, encoding="utf-8").read()
    kontrol("99-macnix kopyalanıyor",
            "overlay/etc/sudoers.d/99-macnix" in s)
    kontrol("canlı kural 99-macnix-live adıyla yazılıyor",
            "99-macnix-live" in s)
    kontrol("eski adlar temizleniyor",
            'rm -f "$ROOTFS/etc/sudoers.d/020-macnix"' in s)
    # 010-live adıyla YENİ dosya üretilmemeli
    kontrol("010-live adıyla yeni dosya üretilmiyor",
            "> \"$ROOTFS/etc/sudoers.d/010-live\"" not in s)


def canli():
    """Gerçek sudo ile davranış testi (root gerekir)."""
    print("\n3) canlı sudo davranış testi (--canli)")
    if os.geteuid() != 0:
        kontrol("root yetkisi", False, "(sudo ile çalıştırın)")
        return

    kullanici = "macnixsudotest"
    subprocess.run(["userdel", "-r", kullanici], capture_output=True)
    subprocess.run(["useradd", "-m", kullanici], capture_output=True)

    gecici = tempfile.mkdtemp(prefix="sudoers-")
    # Calamares'ın yazdığı kural (10-installer) + bizim kuralımız (99-macnix)
    calamares = os.path.join(gecici, "10-installer")
    bizim = os.path.join(gecici, "99-macnix")
    # Not: misafir sistemde macnix "sudo" grubunda olduğu için Calamares'ın
    # "%sudo ALL=(ALL:ALL) ALL" kuralı eşleşiyordu. Burada gruba bağlı
    # kalmamak için aynı anlamdaki kullanıcıya-özel kuralı yazıyoruz.
    with open(calamares, "w") as f:
        f.write("%s ALL=(ALL:ALL) ALL\n" % kullanici)
    with open(bizim, "w") as f:
        f.write("%s ALL=(root) NOPASSWD: /bin/true\n" % kullanici)
    for p in (calamares, bizim):
        subprocess.run(["chmod", "0440", p])

    hedef = "/etc/sudoers.d"
    kopyalar = []
    try:
        for p in (calamares, bizim):
            hedef_yol = os.path.join(hedef, os.path.basename(p))
            subprocess.run(["cp", p, hedef_yol], check=True)
            subprocess.run(["chmod", "0440", hedef_yol], check=True)
            kopyalar.append(hedef_yol)

        r = subprocess.run(["sudo", "-u", kullanici, "sudo", "-n", "/bin/true"],
                           capture_output=True, text=True)
        cikti = (r.stdout + r.stderr).strip()
        kontrol("sudo -n şifre İSTEMEDİ (10-installer + 99-macnix)",
                r.returncode == 0,
                "(çıktı: %s)" % cikti if cikti else "")

        # Ters düzen: 020- (hata) — kural ezilmeli
        eski = os.path.join(hedef, "99-macnix")
        yeni = os.path.join(hedef, "020-macnix")
        os.rename(eski, yeni)
        kopyalar.remove(eski)
        kopyalar.append(yeni)
        r2 = subprocess.run(["sudo", "-u", kullanici, "sudo", "-n", "/bin/true"],
                            capture_output=True, text=True)
        cikti2 = (r2.stdout + r2.stderr).strip()
        kontrol("020- adıyla eski düzen ŞİFRE İSTİYOR (hata tekrar üretildi)",
                r2.returncode != 0 and "password" in cikti2,
                "(çıktı: %s)" % cikti2)
    finally:
        for p in kopyalar:
            try:
                os.unlink(p)
            except OSError:
                pass
        subprocess.run(["userdel", "-r", kullanici], capture_output=True)
        subprocess.run(["rm", "-rf", gecici])


def main():
    print("sudoers kural sırası regresyon testi")
    print("=" * 64)
    statik()
    if "--canli" in sys.argv:
        canli()
    print("\n" + "=" * 64)
    print("SONUÇ: %d geçti, %d kaldı" % (gecti, kaldi))
    return 0 if kaldi == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
