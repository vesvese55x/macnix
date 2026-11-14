#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""notes.qml dosyasını hedef kök dosya sistemine yerleştirir.

Calamares 3.2'nin notesqml modülü, modül dizininde `notes.qml` arar; yoksa
../../share/calamares/qml/notes.qml dosyasına düşer. Derleme sırasında
şablonu her iki olası konuma da kopyalıyoruz ki hangi sürüm olursa olsun
notlar görünsün.
"""
import argparse
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, os.pardir, "calamares", "qml", "notes.qml")


def place(src: str, dest: str) -> None:
    if not dest:
        return
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.copyfile(src, dest)
    os.chmod(dest, 0o644)
    print(f"  notes.qml → {dest}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", default="")
    ap.add_argument("--dest2", default="")
    a = ap.parse_args()

    src = os.path.normpath(TEMPLATE)
    if not os.path.isfile(src):
        print(f"HATA: şablon yok: {src}", file=sys.stderr)
        return 1
    for d in (a.dest, a.dest2):
        place(src, d)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
