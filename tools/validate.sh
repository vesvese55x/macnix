#!/usr/bin/env bash
# ============================================================================
#  MacNix 2.0 — statik doğrulama (build almadan önce her şeyi denetler)
# ============================================================================
#  Kullanım: ./tools/validate.sh
#  Çıkış kodu: 0 = temiz, 1 = hata var
# ============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; WARN=0

C_OK=$'\033[0;32m'; C_ER=$'\033[0;31m'; C_WA=$'\033[1;33m'; C_B=$'\033[1m'; C_R=$'\033[0m'; C_D=$'\033[2m'
hdr()  { printf '\n%s── %s ──%s\n' "$C_B" "$*" "$C_R"; }
pass() { PASS=$((PASS+1)); printf '%s  ✓%s %s\n' "$C_OK" "$C_R" "$*"; }
fail() { FAIL=$((FAIL+1)); printf '%s  ✗%s %s\n' "$C_ER" "$C_R" "$*"; }
warn() { WARN=$((WARN+1)); printf '%s  !%s %s\n' "$C_WA" "$C_R" "$*"; }

cd "$ROOT" || exit 1

# ── 1. Kabuk betikleri: sözdizimi ───────────────────────────────────────────
hdr "1. Kabuk betikleri (bash -n)"
while IFS= read -r f; do
  if bash -n "$f" 2>/tmp/mx-err; then
    pass "$f"
  else
    fail "$f — $(head -2 /tmp/mx-err | tr '\n' ' ')"
  fi
done < <(find . -type f -name '*.sh' -not -path './build/*' | sort)
while IFS= read -r f; do
  head -1 "$f" | grep -qE '^#!.*\b(ba)?sh' || continue
  if bash -n "$f" 2>/tmp/mx-err; then
    pass "$f"
  else
    fail "$f — $(head -2 /tmp/mx-err | tr '\n' ' ')"
  fi
done < <(find ./scripts/bin -type f | sort)

# ── 2. Python: derleme ─────────────────────────────────────────────────────
hdr "2. Python dosyaları (py_compile)"
while IFS= read -r f; do
  if python3 -m py_compile "$f" 2>/tmp/mx-err; then
    pass "$f"
  else
    fail "$f — $(tail -2 /tmp/mx-err | head -1)"
  fi
done < <(find . -type f -name '*.py' -not -path '*__pycache__*' \
           -not -path './calamares/module-conf/*' | sort)
# NOT: calamares/module-conf/*.py dosyaları Python DEĞİL — Calamares'in
# welcomeq/finishedq modülleri yapılandırmasını .py adıyla arar, içerik YAML'dır.
# Bunlar aşağıdaki YAML bölümünde denetlenir.
find . -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true

# ── 3. YAML: Calamares yapılandırmaları ────────────────────────────────────
hdr "3. YAML (calamares .conf / .desc)"
python3 - <<'PY'
import glob, sys
try:
    import yaml
except ImportError:
    print("  ! PyYAML yok — YAML denetimi atlandı (pip install pyyaml)")
    sys.exit(0)
bad = 0
files = sorted(glob.glob("calamares/**/*.conf", recursive=True) +
               glob.glob("calamares/**/*.desc", recursive=True) +
               # .py adlı Calamares yapılandırmaları (welcomeq / finishedq)
               glob.glob("calamares/module-conf/*.py"))
for f in files:
    try:
        list(yaml.safe_load_all(open(f)))
        print(f"  ✓ {f}")
    except Exception as exc:
        print(f"  ✗ {f} — {exc}")
        bad += 1
sys.exit(1 if bad else 0)
PY
[[ $? -eq 0 ]] && pass "Tüm YAML dosyaları geçerli" || fail "YAML hatası var"

# ── 4. JSON veritabanı ─────────────────────────────────────────────────────
hdr "4. JSON (gpu-db)"
if python3 -c "import json;json.load(open('config/gpu-db.json'))" 2>/tmp/mx-err; then
  families=$(python3 -c "import json;print(len(json.load(open('config/gpu-db.json'))['families']))")
  pass "config/gpu-db.json (${families} GPU ailesi)"
else
  fail "config/gpu-db.json — $(cat /tmp/mx-err)"
fi

# ── 5. Calamares akış tutarlılığı ──────────────────────────────────────────
hdr "5. Calamares akış tutarlılığı"
python3 - <<'PY'
import glob, os, re, sys
settings = open("calamares/settings.conf").read()
# skip yorum satırları
lines = [l for l in settings.splitlines() if not l.strip().startswith("#")]
body = "\n".join(lines)

problems = []

# Özel modüllerin module.desc'i var mı?
for mod_dir in sorted(glob.glob("calamares/modules/*")):
    name = os.path.basename(mod_dir)
    desc = os.path.join(mod_dir, "module.desc")
    if not os.path.isfile(desc):
        problems.append(f"{name}: module.desc yok")
        continue
    if not os.path.isfile(os.path.join(mod_dir, "main.py")):
        problems.append(f"{name}: main.py yok")
    if name not in body:
        problems.append(f"{name}: settings.conf'ta hiç kullanılmıyor")

# Kullanılan her modülün yapılandırması var mı?
#
# İSTİSNA: welcomeq.py / finishedq.py / notesqml.py dosyaları .conf DEĞİL .py
# adıyla yüklenir (Calamares'te bu modüllerin yapılandırma adı böyle). Aşağıda
# hem <mod>.conf hem <mod>.py aranıyor.
CONF_SUFFIXES = (".conf", ".py")
ALIASES = {  # settings.conf'taki ad -> module-conf altındaki dosya adı
    "welcomeq": "welcomeq.py",
    "finishedq": "finishedq.py",
    "notesqml": "notesqml.py",
}
used = set(re.findall(r"^\s{6,}-\s*([a-z][a-z0-9_-]+)\s*$", body, re.M))
for mod in sorted(used):
    names = [ALIASES.get(mod, mod + s) for s in CONF_SUFFIXES]
    names.append(ALIASES.get(mod, ""))
    if not any(n and os.path.exists(f"calamares/module-conf/{n}") for n in names):
        problems.append(f"{mod}: module-conf/{mod}.conf yok (Calamares modülü atar)")

# unpackfs gerçekten var mı? (orijinal hatanın kaynağı)
if "unpackfs" not in body:
    problems.append("unpackfs exec listesinde yok — kurulum diske kopyalama yapmaz!")

# marka var mı?
brand = re.search(r"^branding:\s*(\S+)", body, re.M)
if brand:
    bdir = f"calamares/branding/{brand.group(1)}"
    if not os.path.isdir(bdir):
        problems.append(f"branding '{brand.group(1)}' dizini yok: {bdir}")
    if not os.path.exists(os.path.join(bdir, "branding.desc")):
        problems.append(f"{bdir}/branding.desc yok")
    if not os.path.exists(os.path.join(bdir, "show.qml")):
        problems.append(f"{bdir}/show.qml yok")

    # Slayt destesi: show.qml içinde geçen HER görsel marka dizininde olmalı.
    # (Canlı testte olduğu gibi eksik görsel → slayt BOŞ beyaz kalır.)
    show = open(os.path.join(bdir, "show.qml"), encoding="utf-8").read()
    imgs = set(re.findall(r'source:\s*"([^"$]+?\.(?:png|jpg|svg))"', show))
    for im in sorted(imgs):
        if not os.path.exists(os.path.join(bdir, im)):
            problems.append(f"{bdir}/{im} yok (show.qml referansı — slayt boş kalır)")

    # QML ekranları: sidebar/navigation/finishedq/welcome
    for qml in ("calamares-sidebar.qml", "calamares-navigation.qml"):
        if not os.path.exists(os.path.join(bdir, qml)):
            problems.append(f"{bdir}/{qml} yok")
    # navigation.qml "Bitir" düğmesini çizmeli (sonda kurulum kapanabilsin)
    nav_p = os.path.join(bdir, "calamares-navigation.qml")
    if os.path.exists(nav_p):
        nav = open(nav_p, encoding="utf-8").read()
        if "quitVisible" not in nav or "ViewManager.quit()" not in nav:
            problems.append(f"{nav_p}: Bitir (quit) düğmesi yok — kurulum kapatılamaz")

    # finishedq / welcomeq kendi QML'lerini marka dizininden yükler
    for qml in ("finishedq.qml", "welcome.qml"):
        if not os.path.exists(os.path.join(bdir, qml)):
            problems.append(f"{bdir}/{qml} yok")
        else:
            txt = open(os.path.join(bdir, qml), encoding="utf-8").read()
            if "BELGESELSEMO" not in txt:
                problems.append(f"{bdir}/{qml}: kredi şeridi (BELGESELSEMO) yok")

if problems:
    for p in problems:
        print(f"  ✗ {p}")
    sys.exit(1)
print(f"  ✓ {len(used)} modül akışı tutarlı")
PY
[[ $? -eq 0 ]] && pass "akış tutarlı" || fail "akış hatası"

# ── 6. Zorunlu dosyalar ────────────────────────────────────────────────────
hdr "6. Zorunlu dosyalar"
for f in VERSION build.sh packages/01-core.list.chroot \
         config/grub/grub.cfg config/grub/grub-efi-embed.cfg config/grub/isolinux.cfg \
         scripts/macnix_lib.py scripts/live-boot.sh scripts/firstboot.sh \
         scripts/bin/macnix-vm scripts/bin/macnix-doctor scripts/bin/macnix-oc \
         scripts/bin/macnix-install-macos scripts/bin/macnix-assets \
         scripts/bin/macnix-fetch-macos.py scripts/bin/macnix-setup scripts/bin/macnix-gpu-mode \
         scripts/bin/macnix-tui scripts/bin/macnix-log \
         overlay/etc/xdg/openbox/autostart overlay/etc/lightdm/lightdm.conf.d/50-macnix.conf \
         calamares/branding/macnix/macnix_logo.png \
         calamares/branding/macnix/show.qml \
         calamares/branding/macnix/welcome.qml \
         calamares/branding/macnix/finishedq.qml \
         calamares/branding/macnix/calamares-sidebar.qml \
         calamares/branding/macnix/calamares-navigation.qml \
         calamares/branding/macnix/slide-hardware.png \
         calamares/branding/macnix/slide-vm.png \
         tools/assets/gen-slide-art.py \
         overlay/usr/share/fonts/truetype/inter/Inter-Regular.ttf \
         overlay/usr/share/fonts/truetype/inter/Inter-Bold.ttf \
         systemd/macnix-live.service systemd/macnix-firstboot.service \
         systemd/macnix-vm.service systemd/macnix-console.service; do
  [[ -f "$f" ]] && pass "$f" || fail "$f YOK"
done

# çalıştırma bitleri
hdr "7. Çalıştırma bitleri"
for f in scripts/bin/* build.sh scripts/*.sh; do
  [[ -f "$f" ]] || continue
  [[ -x "$f" ]] && pass "$f" || warn "$f çalıştırılabilir değil"
done

# ── 8. Tehlikeli kalıplar ──────────────────────────────────────────────────
hdr "8. Tehlikeli kalıplar"
risky=$(grep -rn 'rm -rf "' build.sh scripts/ 2>/dev/null \
         | grep -vE 'rm -rf "(\$|\$\{)' \
         | grep -v 'rm -rf "/tmp' || true)
if [[ -n "$risky" ]]; then
  warn "kontrol edin — değişkensiz rm -rf:"
  printf '%s\n' "$risky" | head -5 | sed 's/^/      /'
else
  pass "tehlikeli rm -rf kalıbı yok"
fi
if grep -rn 'set -e' --include='*.sh' scripts/ | grep -q 'set -eu'; then
  pass "betiklerde set -e kullanımı var"
fi

# ── 9. qmlFilename / marka tutarlılığı (canlı Calamares ile doğrulandı) ────
hdr "9. qmlFilename + marka QML tutarlılığı"
python3 - <<'PYCHECK'
import glob, os, re, sys
bad = []
root = os.getcwd()
for f in glob.glob("calamares/module-conf/*.conf") + glob.glob("calamares/module-conf/*.py"):
    txt = open(f, encoding="utf-8").read()
    m = re.search(r'qmlFilename:\s*"([^"]+)"', txt)
    if not m:
        continue
    name = m.group(1)
    if name.endswith(".qml"):
        bad.append(f + ": qmlFilename uzantili — Calamares .qml.qml arar (canli VM'de 'Welcome Loading failed.')")
    if not os.path.exists(os.path.join("calamares/branding/macnix", name + ".qml")):
        bad.append(f + ": marka dizininde " + name + ".qml yok")
for qml in ("welcome.qml", "notes.qml", "finishedq.qml"):
    path = os.path.join("calamares/branding/macnix", qml)
    if not os.path.exists(path):
        bad.append(path + " yok")
        continue
    if "bgFill" not in open(path, encoding="utf-8").read():
        bad.append(qml + ": opak zemin (bgFill) yok — yazilar beyaz zeminde okunmaz")
if bad:
    for b in bad:
        print("  x " + b)
    sys.exit(1)
print("  ok qmlFilename uzantisiz, marka QML'leri ve zeminler tamam")
PYCHECK
[[ $? -eq 0 ]] && pass "qmlFilename + marka QML tutarlı" || fail "qmlFilename/marka hatası"

# ── Özet ───────────────────────────────────────────────────────────────────
printf '\n%s━━ Özet ━━%s\n' "$C_B" "$C_R"
printf '  geçen: %s%d%s   uyarı: %s%d%s   hata: %s%d%s\n\n' \
  "$C_OK" "$PASS" "$C_R" "$C_WA" "$WARN" "$C_R" "$C_ER" "$FAIL" "$C_R"
(( FAIL == 0 )) || exit 1
