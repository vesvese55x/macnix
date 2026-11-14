#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MacNix 2.0 — macOS kurulum imajı indirici
=========================================
Apple'ın kendi kurtarma (recovery) servisini kullanır; hiçbir üçüncü taraf
sunucuya bağımlı değildir.

  POST http://osrecovery.apple.com/InstallationPayload/RecoveryImage
  → "AU:" satırındaki URL'den BaseSystem/Recovery imajını indirir

Kullanım:
  macnix-fetch-macos --list
  macnix-fetch-macos --os sequoia --out /var/lib/macnix/disks
  macnix-fetch-macos --board Mac-7BA5B2D9E42DDD94 --serial C02XXXX --out .

Çıktı: <out>/BaseSystem.dmg (+ varsa .chunklist)
Sonra: dmg2img ile BaseSystem.img üretilir (macnix-setup otomatik yapar).
"""

import argparse
import hashlib
import os
import random
import string
import sys
import time
import urllib.error
import urllib.request

RECOVERY_HOST = "http://osrecovery.apple.com"
RECOVERY_PATH = "/InstallationPayload/RecoveryImage"

# macOS sürümleri → Apple board-id (VM için iMacPro1,1 kimliği kullanılır)
BOARDS = {
    "tahoe":    "Mac-7BA5B2D9E42DDD94",
    "sequoia":  "Mac-7BA5B2D9E42DDD94",
    "sonoma":   "Mac-7BA5B2D9E42DDD94",
    "ventura":  "Mac-7BA5B2D9E42DDD94",
    "monterey": "Mac-7BA5B2D9E42DDD94",
    "bigsur":   "Mac-7BA5B2D9E42DDD94",
    "catalina": "Mac-7BA5B2D9E42DDD94",
}

OS_NAMES = {
    "tahoe": "macOS 26 Tahoe", "sequoia": "macOS 15 Sequoia",
    "sonoma": "macOS 14 Sonoma", "ventura": "macOS 13 Ventura",
    "monterey": "macOS 12 Monterey", "bigsur": "macOS 11 Big Sur",
    "catalina": "macOS 10.15 Catalina",
}


def c(code, text):
    return f"\033[{code}m{text}\033[0m" if sys.stdout.isatty() else text


def info(msg):
    print(f"{c('1;36','[macnix]')} {msg}", flush=True)


def warn(msg):
    print(f"{c('1;33','[warn]')} {msg}", flush=True)


def fail(msg):
    print(f"{c('0;31','[fail]')} {msg}", file=sys.stderr, flush=True)


def rand_hex(n):
    return "".join(random.choice("0123456789ABCDEF") for _ in range(n))


def make_serial():
    year = random.choice("CDFGHJKLMNPQRSTVWXYZ")
    week = f"{random.randint(1, 52):01X}"
    uniq = rand_hex(3)
    return f"C02{year}{week}{uniq}HX87"


def request_recovery(board, serial, oem="Apple Inc."):
    """Apple kurtarma servisinden imaj URL'i ve kimlik başlıklarını al."""
    mac = rand_hex(12)
    headers = {
        "User-Agent": "Mac OS X/10.13.6 (17G66); Darwin/17.7.0; x86_64",
        "Content-Type": "text/plain",
        "oem": oem,
        "mac": mac,
        "boardid": board,
        "sn": serial,
    }
    req = urllib.request.Request(RECOVERY_HOST + RECOVERY_PATH,
                                data=b"", headers=headers, method="POST")
    info(f"Apple kurtarma servisine bağlanılıyor (board {board})…")
    with urllib.request.urlopen(req, timeout=45) as resp:
        payload = resp.read().decode("utf-8", errors="replace")
    return payload


def parse_payload(payload):
    out = {}
    for line in payload.splitlines():
        if ":" in line:
            key, _, val = line.partition(":")
            out[key.strip()] = val.strip()
    return out


def download(url, headers, dest, expected=None):
    """Devam ettirilebilir indirme (kısmi dosya varsa sürdürür)."""
    pos = os.path.getsize(dest) if os.path.exists(dest) else 0
    req_headers = dict(headers)
    if pos:
        req_headers["Range"] = f"bytes={pos}-"
        info(f"Kaldığı yerden devam: {pos / 1048576:.1f} MB")
    req = urllib.request.Request(url, headers=req_headers)
    with urllib.request.urlopen(req, timeout=120) as resp:
        total = resp.headers.get("Content-Length")
        total = int(total) + pos if total else None
        mode = "ab" if pos and resp.status == 206 else "wb"
        if mode == "wb":
            pos = 0
        done = pos
        t0 = time.time()
        with open(dest, mode) as fh:
            while True:
                chunk = resp.read(1024 * 512)
                if not chunk:
                    break
                fh.write(chunk)
                done += len(chunk)
                if sys.stdout.isatty():
                    if total:
                        pct = done * 100 / total
                        speed = done / max(1e-6, time.time() - t0) / 1048576
                        bar = "#" * int(pct / 3)
                        sys.stdout.write(
                            f"\r  [{bar:<34}] {pct:5.1f}%  "
                            f"{done/1048576:7.1f}/{total/1048576:.1f} MB  {speed:5.1f} MB/s")
                    else:
                        sys.stdout.write(f"\r  {done/1048576:7.1f} MB indirildi")
                    sys.stdout.flush()
        if sys.stdout.isatty():
            sys.stdout.write("\n")
    return dest


def main(argv=None):
    ap = argparse.ArgumentParser(description="MacNix — macOS kurulum imajı indirici")
    ap.add_argument("--os", default="sequoia",
                    choices=sorted(BOARDS.keys()), help="macOS sürümü")
    ap.add_argument("--board", default=None, help="Apple board-id (elle geçersiz kılma)")
    ap.add_argument("--serial", default=None, help="Sahte seri numarası")
    ap.add_argument("--out", default="/var/lib/macnix/disks", help="Çıktı dizini")
    ap.add_argument("--list", action="store_true", help="Desteklenen sürümleri listele")
    ap.add_argument("--force", action="store_true", help="Var olan dosyanın üzerine yaz")
    args = ap.parse_args(argv)

    if args.list:
        for k in sorted(BOARDS):
            print(f"  {k:10s} {OS_NAMES[k]}")
        return 0

    os.makedirs(args.out, exist_ok=True)
    board = args.board or BOARDS[args.os]
    serial = args.serial or make_serial()

    info(f"Hedef: {OS_NAMES[args.os]} (board {board}, serial {serial})")

    try:
        payload = request_recovery(board, serial)
    except urllib.error.URLError as exc:
        fail(f"Apple kurtarma servisine ulaşılamadı: {exc}")
        warn("İnternet bağlantısını kontrol edin. Kurumsal ağlarda osrecovery.apple.com "
             "engellenmiş olabilir.")
        return 2

    fields = parse_payload(payload)
    if not fields:
        fail("Servis yanıtı çözümlenemedi. Yanıtın ilk 200 karakteri:")
        print(payload[:200], file=sys.stderr)
        return 3

    asset_url = fields.get("AU") or fields.get("CU")
    if not asset_url:
        fail("Yanıtta indirme adresi (AU) yok. Apple bu sürüm için imaj sunmuyor olabilir.")
        print(payload[:300], file=sys.stderr)
        return 4

    # İndirme başlıkları: kurtarma oturumunun kendi kimlik bilgileri
    dl_headers = {
        "User-Agent": "Mac OS X/10.13.6 (17G66); Darwin/17.7.0; x86_64",
        "Accept": "*/*",
    }
    for key in ("AH", "AT"):
        if fields.get(key):
            dl_headers["Authorization" if key == "AH" else "X-Apple-Asset-Token"] = fields[key]

    filename = os.path.basename(asset_url.split("?")[0]) or f"{args.os}.dmg"
    if not filename.lower().endswith((".dmg", ".img")):
        filename = "BaseSystem.dmg"
    dest = os.path.join(args.out, filename)
    if os.path.exists(dest) and not args.force:
        size = os.path.getsize(dest)
        if size > 400 * 1024 * 1024:
            info(f"Zaten indirilmiş: {dest} ({size/1048576:.0f} MB) — atlanıyor")
            print(dest)
            return 0
        info(f"Eksik dosya bulundu ({size/1048576:.0f} MB) — devam ediliyor")

    info(f"İndiriliyor: {filename}")
    try:
        download(asset_url, dl_headers, dest)
    except (urllib.error.URLError, OSError) as exc:
        fail(f"İndirme hatası: {exc}")
        return 5

    size = os.path.getsize(dest)
    if size < 100 * 1024 * 1024:
        fail(f"İndirilen dosya çok küçük ({size} bayt) — imaj geçersiz")
        return 6

    info(f"Tamam: {dest} ({size/1048576:.0f} MB)")
    with open(dest, "rb") as fh:
        head = fh.read(512)
    if head[:2] == b"koly":
        info("UDIF (DMG) biçimi doğrulandı")
    elif head[:4] == b"\x1aE\xdf\xa3" or head[:4] == b"\x00\x00\x00\x00":
        info("Ham disk imajı biçimi")
    else:
        warn("Bilinmeyen dosya imzası — dmg2img adımı başarısız olabilir")

    print(dest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
