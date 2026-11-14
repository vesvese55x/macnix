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
done < <(find . -type f -name '*.py' -not -path '*__pycache__*' | sort)
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
               glob.glob("calamares/**/*.desc", recursive=True))
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
used = set(re.findall(r"^\s{6,}-\s*([a-z][a-z0-9_-]+)\s*$", body, re.M))
for mod in sorted(used):
    conf = f"calamares/module-conf/{mod}.conf"
    if not os.path.exists(conf):
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

# ── Özet ───────────────────────────────────────────────────────────────────
printf '\n%s━━ Özet ━━%s\n' "$C_B" "$C_R"
printf '  geçen: %s%d%s   uyarı: %s%d%s   hata: %s%d%s\n\n' \
  "$C_OK" "$PASS" "$C_R" "$C_WA" "$WARN" "$C_R" "$C_ER" "$FAIL" "$C_R"
(( FAIL == 0 )) || exit 1
