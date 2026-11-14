#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mount modülü yaması için regresyon testi.

GERÇEK HATA (MacNix 2.0, canlı kurulum, 2026-11-14):
    Kurulum Başarısız
    Boost.Python is hasatı "mount"
    Boost.Python.ArgumentError: Python argument types in
      libcalamares.utils.mount(str, str, str, list)
    did not match C++ signature:
      mount(std::string, std::string, std::string, std::string)

Sebep: Debian calamares 3.2.61'in mount/main.py dosyası bölüm bilgisindeki
`options` değerini normalize etmeden libcalamares.utils.mount()'a veriyor.
`options` liste ise C++ tarafı std::string beklediği için patlıyor ve
kurulum tam mount aşamasında düşüyor.

Bu test:
  1. repodaki calamares/modules/mount/main.py'nin var olduğunu,
  2. `options` listesini string'e çevirdiğini (gerçek 4x std::string
     imzasını taklit eden sahte libcalamares ile),
  3. build.sh'ın repodaki düzeltmeyi Debian'ın dosyasının ÜZERİNE
     kopyaladığını, ve kopyalamanın modül döngüsünden SONRA olduğunu
  doğrular.
"""

import importlib.util
import os
import re
import subprocess
import sys
import types

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MONTAJ = os.path.join(ROOT, "calamares", "modules", "mount", "main.py")
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


# ---------------------------------------------------------------- sahte modül
def libcalamares_kur():
    cagrilar = []

    def mount(device, mountpoint, fstype, options):
        """libcalamares.so içindeki GERÇEK imza: dört std::string."""
        for ad, v in (("device", device), ("mountpoint", mountpoint),
                      ("fstype", fstype), ("options", options)):
            if not isinstance(v, str):
                raise TypeError(
                    "Boost.Python.ArgumentError: %s bir %s, std::string bekleniyor"
                    % (ad, type(v).__name__))
        cagrilar.append((device, mountpoint, fstype, options))
        return 0

    lc = types.ModuleType("libcalamares")
    lc.utils = types.SimpleNamespace(
        mount=mount,
        warning=lambda *a, **k: None,
        error=lambda *a, **k: None,
        debug=lambda *a, **k: None,
        host_env_process_output=lambda *a, **k: None,
        gettext_path=lambda: "/tmp",
        gettext_languages=lambda: ["en"],
    )
    gs = {}
    lc.globalstorage = types.SimpleNamespace(
        value=lambda k: gs.get(k),
        insert=lambda k, v: gs.__setitem__(k, v))
    lc.job = types.SimpleNamespace(configuration={})
    lc.translation = types.SimpleNamespace(get=lambda: (lambda t: t))
    sys.modules["libcalamares"] = lc
    return cagrilar, gs


def main():
    print("mount yaması regresyon testi")
    print("=" * 62)

    print("\n1) Dosya varlığı")
    kontrol("calamares/modules/mount/main.py var", os.path.isfile(MONTAJ))
    kontrol("calamares/modules/mount/module.desc var",
            os.path.isfile(os.path.join(ROOT, "calamares", "modules", "mount",
                                        "module.desc")))
    if not os.path.isfile(MONTAJ):
        print("\nSONUÇ: BAŞARISIZ (dosya yok)")
        return 1

    print("\n2) Davranış (gerçek 4x std::string imzası taklit edilerek)")
    cagrilar, gs = libcalamares_kur()
    subprocess.call = lambda *a, **k: 0          # chcon çağrısını yut
    spec = importlib.util.spec_from_file_location("macnix_mount_main", MONTAJ)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    kontrol("_mount_options() tanımlı", hasattr(mod, "_mount_options"))
    if hasattr(mod, "_mount_options"):
        kontrol("liste → string",
                mod._mount_options({"options": ["defaults"]}) == "defaults")
        kontrol("liste (çoklu) → virgüllü string",
                mod._mount_options({"options": ["ro", "noatime"]}) == "ro,noatime")
        kontrol("string aynen korunur",
                mod._mount_options({"options": "noatime"}) == "noatime")
        kontrol("anahtar yok → boş string",
                mod._mount_options({}) == "")
        kontrol("None → boş string",
                mod._mount_options({"options": None}) == "")
        kontrol("ek seçenek öne eklenir",
                mod._mount_options({"options": ["defaults"]}, "subvol=/@")
                == "subvol=/@,defaults")

    for ad, options in (("options=['defaults'] (HATA VEREN DURUM)", ["defaults"]),
                        ("options='noatime'", "noatime"),
                        ("options=['ro','noatime']", ["ro", "noatime"]),
                        ("options yok", "")):
        cagrilar.clear()
        p = {"device": "/dev/sdb1", "fs": "ext4", "mountPoint": "/",
             "options": options}
        try:
            mod.mount_partition("/tmp/macnix-test", p, [p])
            ok = bool(cagrilar) and isinstance(cagrilar[0][3], str)
        except TypeError as e:
            ok = False
            print("      → %s" % e)
        kontrol("mount_partition: %s" % ad, ok)

    print("\n3) build.sh entegrasyonu")
    if not os.path.isfile(BUILD):
        kontrol("build.sh var", False)
    else:
        s = open(BUILD, encoding="utf-8").read()
        kontrol("repodaki mount/main.py kopyalanıyor",
                "calamares/modules/mount/main.py" in s)
        kontrol("hedef: $CAL_MOD_DIR/mount/main.py",
                "$CAL_MOD_DIR/mount/main.py" in s)
        kontrol("0'dan farklı beklenen yama mesajı var",
                "mount/main.py yaması uygulandı" in s)
        # sıra: modül döngüsü (for m in ... done) yamadan ÖNCE olmalı
        i_dongu = s.find('for m in $(cd "${ROOT}/calamares/modules"')
        i_yama = s.find("mount/main.py yaması uygulandı")
        kontrol("yama, modül döngüsünden SONRA (üzerine yazar)",
                i_dongu != -1 and i_yama != -1 and i_dongu < i_yama,
                "(dongu=%d yama=%d)" % (i_dongu, i_yama))
    # regresyon: asıl modül dosyasında normalize edilmemiş çağrı olmamalı
    # (build.sh içindeki açıklama yorumunda eski kod örnek olarak geçebilir)
    kaynak = open(MONTAJ, encoding="utf-8").read()
    kontrol("mount/main.py'de normalize edilmemiş mount() çağrısı yok",
            not re.search(r'utils\.mount\([^)]*partition\.get\("options"',
                          kaynak, re.S))
    cagri_satirlari = [ln.strip() for ln in kaynak.splitlines()
                       if ln.strip().startswith("_mount_options(partition")]
    kontrol("mount/main.py iki çağrı noktasında da _mount_options kullanıyor",
            len(cagri_satirlari) == 2,
            "(bulunan: %d)" % len(cagri_satirlari))

    print("\n" + "=" * 62)
    print("SONUÇ: %d geçti, %d kaldı" % (gecti, kaldi))
    return 0 if kaldi == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
