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


def get_session():
    """Apple kurtarma servisinden OTURUM çerezi al.

    NEDEN GEREKLİ (2026-11-15, gerçek hata): Eski kod doğrudan
    /InstallationPayload/RecoveryImage adresine POST atıyordu ve Apple
    **HTTP 401** döndürüyordu. Apple's protokolü (OpenCorePkg
    Utilities/macrecovery referans uygulaması) önce ana sayfaya GET atıp
    `session=...` çerezini almayı ZORUNLU kılıyor. Çerez olmadan 401.
    """
    headers = {
        "Host": "osrecovery.apple.com",
        "Connection": "close",
        "User-Agent": "InternetRecovery/1.0",
    }
    req = urllib.request.Request(RECOVERY_HOST + "/", headers=headers)
    with urllib.request.urlopen(req, timeout=45) as resp:
        raw_headers = resp.info()
    cookies = []
    for key, value in raw_headers.items():
        if key.lower() == "set-cookie":
            for part in value.split("; "):
                if part.startswith("session="):
                    cookies.append(part)
    if not cookies:
        raise RuntimeError("Apple oturum çerezi vermedi (session= yok)")
    return cookies[0]


def request_recovery(board, serial, oem="Apple Inc.", os_type="default"):
    """RecoveryImage bilgilerini al: AU (imaj URL), AH (SHA256), AT (token).

    Gövde biçimi macrecovery ile birebir aynıdır:
        cid / sn / bid / k / fg / os  — satır başına `anahtar=değer`,
        Content-Type: text/plain
    `sn` Apple'ın beklediği MLB biçimidir (17 karakter, ortası sıfır).
    """
    session = get_session()
    info("Apple kurtarma oturumu alındı")

    post = {
        "cid": rand_hex(16),
        "sn": (serial or "00000000000")[:17].ljust(17, "0"),
        "bid": board,
        "k": rand_hex(64),
        "fg": rand_hex(64),
        "os": os_type,
    }
    body = "\n".join("%s=%s" % (k, v) for k, v in post.items()).encode()

    headers = {
        "Host": "osrecovery.apple.com",
        "Connection": "close",
        "User-Agent": "InternetRecovery/1.0",
        "Cookie": session,
        "Content-Type": "text/plain",
    }
    info("Apple kurtarma servisine bağlanılıyor (board %s)" % board)
    req = urllib.request.Request(RECOVERY_HOST + RECOVERY_PATH,
                                 data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        detail = exc.read()[:200].decode("utf-8", "replace")
        raise RuntimeError(
            "Apple kurtarma servisi HTTP %s döndürdü (%s). "
            "Olası nedenler: osrecovery.apple.com engelli, çok sayıda istek "
            "nedeniyle geçici engel, ya da seçilen board-id bu sürümü "
            "desteklemiyor. Yanıt: %s" % (exc.code, exc.reason, detail))


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


def verify_chunklist_image(dmgpath, cnkpath):
    """Apple chunklist'ine göre imajı parça parça doğrular.

    Biçim (OpenCorePkg/macrecovery ile birebir, KÜÇÜK-endian):
        başlık  : '<4sIBBBxQQQ'  (36 bayt)  → sihir 'CNKL', sürüm 1, parça sayısı
        parçalar: '<I32s'        (36 bayt)  → boyut + SHA256
        ardından: 256 baytlık RSA imza (signature_method=1) veya 32 bayt özet

    DİKKAT: İlk denemede alanlar büyük-endian okundu ve "chunklist içinde
    parça yok" hatası alındı (canlı test). Apple bu dosyayı küçük-endian
    yazıyor.
    """
    import struct
    HDR = struct.Struct("<4sIBBBxQQQ")
    CHUNK = struct.Struct("<I32s")

    with open(cnkpath, "rb") as cf:
        raw = cf.read(HDR.size)
        if len(raw) < HDR.size:
            raise RuntimeError("chunklist bozuk (başlık eksik)")
        magic, hdr_size, ver, chunk_method, sig_method, count, c_off, s_off = \
            HDR.unpack(raw)
        if magic != b"CNKL":
            raise RuntimeError("chunklist sihirli sayısı yanlış (%r)" % magic)
        if ver != 1:
            raise RuntimeError("desteklenmeyen chunklist sürümü: %d" % ver)
        if count <= 0:
            raise RuntimeError("chunklist içinde parça yok")
        chunks = []
        for _ in range(count):
            rec = cf.read(CHUNK.size)
            if len(rec) < CHUNK.size:
                raise RuntimeError("chunklist eksik (parça kaydı kesildi)")
            size, digest = CHUNK.unpack(rec)
            chunks.append((size, digest))

    total_expected = sum(s for s, _ in chunks)
    actual = os.path.getsize(dmgpath)
    if actual != total_expected:
        raise RuntimeError("boyut uyuşmuyor (dosya %d, chunklist %d)"
                           % (actual, total_expected))

    with open(dmgpath, "rb") as df:
        for idx, (size, digest) in enumerate(chunks, 1):
            block = df.read(size)
            if len(block) != size:
                raise RuntimeError("parça %d eksik" % idx)
            if hashlib.sha256(block).digest() != digest:
                return False
            if idx % 10 == 0 or idx == len(chunks):
                info("  parça %d/%d doğrulandı" % (idx, len(chunks)))
        if df.read(1):
            raise RuntimeError("dosya chunklist'ten uzun")
    return True


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

    # İndirme başlıkları — macrecovery ile BİREBİR aynı:
    #   Cookie: AssetToken=<AT>    (AT alanı "expires=..." ile başlar)
    #   User-Agent: InternetRecovery/1.0
    # Eski kod "X-Apple-Asset-Token"/"Authorization" kullanıyordu; Apple bunu
    # kabul etmiyor (indirme 401/403 verirdi).
    dl_headers = {
        "User-Agent": "InternetRecovery/1.0",
        "Cookie": "AssetToken=%s" % fields.get("AT", ""),
        "Accept": "*/*",
    }

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

    # ── Bütünlük: Apple CHUNKLIST doğrulaması ──────────────────────────────
    # ÖNEMLİ (2026-11-15, gerçek ölçüm): Apple'ın `AH` alanı BaseSystem.dmg'nin
    # TAM dosya SHA256'sı DEĞİLDİR. 884 MB'lık indirme, AH ile
    # karşılaştırıldığında "uyuşmuyor" görünüyordu — oysa dosya kusursuzdu:
    # Apple'ın kendi BaseSystem.chunklist'i ile 85/85 parça BİREBİR eşleşti.
    # Doğru yöntem (OpenCorePkg/macrecovery → verify_image): chunklist'i indir,
    # dosyayı parça parça oku ve her parçanın SHA256'sını karşılaştır.
    chunk_ok = None
    cu, ct = fields.get("CU"), fields.get("CT")
    if cu and ct:
        cnk_path = dest + ".chunklist"
        try:
            from urllib.parse import urlparse as _up
            _p = _up(cu)
            cnk_headers = {
                "Host": _p.hostname,
                "Connection": "close",
                "User-Agent": "InternetRecovery/1.0",
                "Cookie": "AssetToken=%s" % ct,
            }
            info("Bütünlük listesi (chunklist) indiriliyor")
            with urllib.request.urlopen(
                    urllib.request.Request(cu, headers=cnk_headers),
                    timeout=120) as resp, open(cnk_path, "wb") as fh:
                fh.write(resp.read())
            chunk_ok = verify_chunklist_image(dest, cnk_path)
            if chunk_ok:
                info("Chunklist doğrulaması BAŞARILI — imaj Apple ile birebir")
            else:
                fail("Chunklist doğrulaması BAŞARISIZ — indirme bozuk")
                warn("Tekrar denemek için: macnix-fetch-macos --force")
                return 7
        except Exception as exc:            # noqa: BLE001 — tanılama
            warn("Chunklist doğrulanamadı: %s" % exc)
            chunk_ok = None

    if chunk_ok is None:
        warn("Bütünlük doğrulaması YAPILAMADI (chunklist alınamadı) — "
             "imaj boyutu doğru ama içerik doğrulanmadı")

    info(f"Tamam: {dest} ({size/1048576:.0f} MB)")

    # ── Biçim tespiti ──────────────────────────────────────────────────────
    # DİKKAT (2026-11-15, canlı test): Apple'ın BaseSystem.dmg dosyası
    # "koly" imzasını BAŞTA değil SONDA (512 baytlık UDIF kuyruğu) taşır ve
    # gövdesi zlib (78 da) ile sıkıştırılmıştır. Eski kontrol baştan
    # baktığı için "Bilinmeyen dosya imzası" uyarısı veriyordu — dosya
    # aslında kusursuzdu (chunklist 85/85 doğruladı).
    with open(dest, "rb") as fh:
        head = fh.read(4)
        fh.seek(max(0, size - 512))
        tail = fh.read(512)
    if b"koly" in tail:
        info("UDIF (DMG) biçimi doğrulandı — sıkıştırılmış disk imajı")
    elif head[:4] == b"\x1aE\xdf\xa3":
        info("Ham disk imajı biçimi (raw)")
    elif head[:2] == b"\x78\xda" or head[:2] == b"\x78\x9c":
        warn("zlib ile sıkıştırılmış veri — UDIF kuyruğu yok, dmg2img "
             "açamayabilir (imaj eksik indirilmiş olabilir)")
    else:
        warn("Bilinmeyen dosya imzası — dmg2img adımı başarısız olabilir")

    print(dest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
