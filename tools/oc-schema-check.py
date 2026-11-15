#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MacNix 2.0 — OpenCore config.plist şema denetimi

NEDEN VAR: 2026-11-15'te canlı testte şu gerçek hata yakalandı —
`macnix-oc --build` ile üretilen config.plist içinde OpenCore 1.0.8
şemasında BULUNMAYAN 7 anahtar vardı:

  Misc.Debug.SerialInit            (kaldırıldı)
  UEFI.Audio.AudioOut              → AudioOutMask
  UEFI.Audio.MinimumVolume         → MaximumGain / MinimumAssistGain
  UEFI.Audio.VoiceOver             (kaldırıldı)
  UEFI.Input.KeyMergeThreshold     → KeySwap
  UEFI.Quirks.ForceOemVolumeHack   → ForceOcWriteFlash
  UEFI.DriveInput                  (bölüm kaldırıldı)

Bu anahtarlar yüzünden OpenCore, macOS'u yüklemeye geçmeden önce
"OCS: No schema for ... ! / Halting on critical error" deyip HALT ediyordu.
Yani kullanıcı için "macOS başlamıyor" hatasının makine tarafındaki ilk
gerçek sebebi buydu (önyükleme laboratuvarında seri günlükle kanıtlandı).

Bu betik, referans şema (config/opencore-schema.json — OpenCorePkg
1.0.8 Docs/Sample.plist'ten üretilmiştir) ile karşılaştırır.

Kullanım:
    python3 tools/oc-schema-check.py /path/config.plist
Çıkış kodu: 0 = şema uyumlu, 1 = şema hatası var
"""
import json
import os
import plistlib
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA = os.path.join(os.path.dirname(HERE), "config", "opencore-schema.json")

# Bu bölümlerin anahtarları donanıma/yamaya özel (GUID, cihaz yolu) → denetlenmez
DYNAMIC = {"NVRAM.Add", "NVRAM.Delete", "DeviceProperties.Add", "DeviceProperties.Delete"}


def walk(actual, ref, path=""):
    problems = []
    if isinstance(ref, dict) and isinstance(actual, dict):
        if path in DYNAMIC:
            return problems
        for key in actual:
            if key.startswith("#"):
                continue          # OpenCore yorum satırlarını yok sayar
            child = f"{path}.{key}" if path else key
            if key not in ref:
                problems.append(
                    f"{child}: OpenCore şemasında YOK — "
                    f"açılışta 'No schema for {key}' verip HALT eder")
            else:
                problems.extend(walk(actual[key], ref[key], child))
    elif isinstance(ref, list) and isinstance(actual, list) and ref:
        for i, item in enumerate(actual):
            problems.extend(walk(item, ref[0], f"{path}[{i}]"))
    return problems


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[-2].strip())
        return 2
    target = argv[1]
    if not os.path.exists(SCHEMA):
        print(f"UYARI: şema dosyası yok ({SCHEMA}) — denetim atlandı")
        return 0
    with open(SCHEMA, encoding="utf-8") as fh:
        schema = json.load(fh)
    try:
        with open(target, "rb") as fh:
            cfg = plistlib.load(fh)
    except Exception as exc:                      # noqa: BLE001
        print(f"HATA: {target} okunamadı: {exc}")
        return 1
    problems = walk(cfg, schema)
    if problems:
        print(f"HATA: {len(problems)} şema sorunu ({target})")
        for p in problems:
            print("  -", p)
        return 1
    kexts = len(cfg.get("Kernel", {}).get("Add", []))
    drv = len(cfg.get("UEFI", {}).get("Drivers", []))
    print(f"Şema uyumlu: {target} — {kexts} kext, {drv} sürücü")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
