#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MacNix 2.0 — Calamares modüllerini sahte `libcalamares` ile çalıştırır.

Amaç: Calamares'i (Qt + X) açmadan modüllerin gerçekten çalıştığını,
hata vermediğini ve hedef kök dosya sistemine doğru dosyaları yazdığını
doğrulamak. Bu, "kurulum patlıyor" sınıfı hataları build almadan yakalar.

Kullanım:  python3 tools/test-modules.py
Çıkış kodu: 0 = hepsi geçti
"""

import importlib.util
import json
import os
import plistlib
import shutil
import sys
import tempfile
import types

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBDIR = os.path.join(ROOT, "scripts")

PASS, FAIL = [], []


def check(name, cond, detail=""):
    if cond:
        PASS.append(name)
        print(f"  \033[0;32m✓\033[0m {name}")
    else:
        FAIL.append((name, detail))
        print(f"  \033[0;31m✗\033[0m {name}  {detail}")


# ── Sahte libcalamares ──────────────────────────────────────────────────────
class FakeGlobalStorage(dict):
    def value(self, key):
        return self.get(key)

    def insert(self, key, val):
        self[key] = val


class FakeJob:
    def __init__(self, storage):
        self.storage = storage

    def setprogress(self, value):
        self.storage["_progress"] = value


def make_fake_libcalamares():
    mod = types.ModuleType("libcalamares")
    storage = FakeGlobalStorage()

    utils = types.SimpleNamespace(
        debug=lambda *a, **k: None,
        warning=lambda *a, **k: None,
        error=lambda *a, **k: None,
        gettext_path=lambda: "/usr/share/locale",
        gettext_languages=lambda: ["en"],
        host_env_process_output=lambda *a, **k: None,
    )
    mod.globalstorage = storage
    mod.job = FakeJob(storage)
    mod.utils = utils
    mod.__dict__["_storage"] = storage
    return mod


def load_module(path, fake_lib):
    """main.py'yi libcalamares sahtesiyle yükle."""
    saved = sys.modules.get("libcalamares")
    sys.modules["libcalamares"] = fake_lib
    if LIBDIR not in sys.path:
        sys.path.insert(0, LIBDIR)
    try:
        spec = importlib.util.spec_from_file_location(
            "testmod_" + os.path.basename(os.path.dirname(path)), path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        if saved is not None:
            sys.modules["libcalamares"] = saved


# ── 1. Kütüphane testleri ───────────────────────────────────────────────────
def test_library():
    print("\n\033[1m── macnix_lib ──\033[0m")
    sys.path.insert(0, LIBDIR)
    import macnix_lib as ml

    db = ml.load_db()
    check("gpu-db.json yüklendi", bool(db.get("families")), f"{len(db.get('families', []))} aile")

    # R7 M340 (Hainan) → macOS desteği YOK olmalı
    fam = ml.classify_gpu("6660", "1002", db)
    check("R7 M340 (1002:6660) macOS-desteksiz sınıflandı",
          fam.get("macos_supported") is False, f"-> {fam.get('id')}")

    # RX 6600 (Navi 23) → destekli olmalı
    fam = ml.classify_gpu("73ff", "1002", db)
    check("RX 6600 (1002:73ff) macOS-destekli sınıflandı",
          fam.get("macos_supported") is True, f"-> {fam.get('id')}")

    # Kepler GTX 680
    fam = ml.classify_gpu("1180", "10de", db)
    check("GTX 680 (10de:1180) Kepler olarak tanındı",
          fam.get("id") == "nvidia_kepler", f"-> {fam.get('id')}")

    # RTX 3080 → desteksiz
    fam = ml.classify_gpu("2206", "10de", db)
    check("RTX 3080 (10de:2206) desteksiz", fam.get("macos_supported") is False,
          f"-> {fam.get('id')}")

    # Bilinmeyen ID → güvenli varsayılan
    fam = ml.classify_gpu("dead", "1002", db)
    check("bilinmeyen GPU güvenli varsayılana düştü",
          fam.get("macos_supported") is False)

    # Analiz gerçekten çalışıyor mu
    result = ml.analyze()
    check("analyze() çalıştı", "hardware" in result and "plan" in result)
    plan = result["plan"]
    check("plan zorunlu anahtarları içeriyor",
          all(k in plan for k in ("arch", "macos_version", "vm_cores", "vm_ram_mb",
                                  "passthrough_gpus", "warnings")))
    check("arch geçerli değer", plan["arch"] in ("vfio", "virtio"), plan["arch"])
    check("vm_cores > 0", plan["vm_cores"] >= 1, str(plan.get("vm_cores")))
    check("vm_ram_mb >= 2048", plan["vm_ram_mb"] >= 2048, str(plan.get("vm_ram_mb")))

    # OpenCore config üretimi
    serials = ml.gen_serials("iMacPro1,1")
    check("seri numarası üretildi", len(serials.get("serial", "")) >= 10,
          serials.get("serial"))
    cfg = ml.build_opencore_config(
        {"cpu_vendor": "amd", "arch": "virtio", "needs_amd_patches": True},
        serials, [{"Comment": "test"}])
    check("OpenCore config bölümleri tam",
          all(s in cfg for s in ("ACPI", "Booter", "Kernel", "Misc", "NVRAM",
                                 "PlatformInfo", "UEFI")))
    check("Kernel.Add 4 kext içeriyor", len(cfg["Kernel"]["Add"]) == 4,
          str(len(cfg["Kernel"]["Add"])))
    check("UEFI.Drivers OpenRuntime içeriyor",
          any(d["Path"] == "OpenRuntime.efi" for d in cfg["UEFI"]["Drivers"]))
    check("AMD CPU'da yamalar korundu", len(cfg["Kernel"]["Patch"]) == 1)
    check("AMD CPU'da ProvideCurrentCpuInfo açık",
          cfg["Kernel"]["Quirks"]["ProvideCurrentCpuInfo"] is True)
    check("virtio modunda yazılım render bayrakları var",
          "-igfxvesa" in cfg["NVRAM"]["Add"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"]["boot-args"])

    cfg2 = ml.build_opencore_config(
        {"cpu_vendor": "intel", "arch": "vfio"}, serials, [])
    check("vfio modunda yazılım render bayrağı yok",
          "-igfxvesa" not in cfg2["NVRAM"]["Add"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"]["boot-args"])

    # plist yazma + geri okuma (bozuk XML imkânsız)
    tmp = tempfile.mktemp(suffix=".plist")
    try:
        ml.write_plist(cfg, tmp)
        import plistlib
        with open(tmp, "rb") as fh:
            back = plistlib.load(fh)
        check("config.plist yazıldı ve geri okundu", back["Kernel"]["Add"] == cfg["Kernel"]["Add"])
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


# ── 2. Calamares modül testleri ─────────────────────────────────────────────
def test_module(name):
    print(f"\n\033[1m── calamares/modules/{name} ──\033[0m")
    path = os.path.join(ROOT, "calamares", "modules", name, "main.py")
    fake = make_fake_libcalamares()

    # Hedef kök dosya sistemi taklidi
    root = tempfile.mkdtemp(prefix="macnix-target-")
    try:
        for sub in ("etc", "etc/systemd/system", "etc/modprobe.d",
                    "etc/modules-load.d", "etc/default", "var/lib/macnix",
                    "etc/systemd/system/multi-user.target.wants",
                    "etc/systemd/system/graphical.target.wants", "opt/macnix"):
            os.makedirs(os.path.join(root, sub), exist_ok=True)
        with open(os.path.join(root, "etc/default/grub"), "w") as fh:
            fh.write('GRUB_DEFAULT=0\nGRUB_TIMEOUT=5\n'
                     'GRUB_CMDLINE_LINUX_DEFAULT="quiet"\nGRUB_CMDLINE_LINUX=""\n')

        fake.globalstorage["rootMountPoint"] = root
        fake.globalstorage["macnix_plan"] = None  # dosyadan okumaya zorla

        module = load_module(path, fake)
        try:
            result = module.run()
            check(f"{name}.run() istisna atmadı", True)
        except Exception as exc:  # noqa: BLE001
            check(f"{name}.run() istisna atmadı", False, f"{type(exc).__name__}: {exc}")
            return

        # (hata, açıklama) demeti döndürdüyse Calamares kurulumu durdurur
        if isinstance(result, tuple):
            check(f"{name}.run() hata döndürmedi", False, f"{result}")
        else:
            check(f"{name}.run() başarı döndürdü (None)", result is None)

        if name == "macnix-gpu-config":
            for rel in ("etc/macnix/install-plan.json", "etc/macnix/vm.conf",
                        "etc/macnix/smbios.json", "etc/modprobe.d/macnix-kvm.conf",
                        "etc/default/grub", "var/lib/macnix/.preinstalled"):
                check(f"hedefe yazıldı: {rel}", os.path.exists(os.path.join(root, rel)))
            # GRUB komut satırı bozulmamış mı
            grub = open(os.path.join(root, "etc/default/grub")).read()
            check("GRUB_CMDLINE_LINUX_DEFAULT hâlâ tek satır",
                  grub.count("GRUB_CMDLINE_LINUX_DEFAULT=") == 1)
            check("GRUB'a transparent_hugepage eklendi",
                  "transparent_hugepage=always" in grub, grub[-200:])
            vm = open(os.path.join(root, "etc/macnix/vm.conf")).read()
            check("vm.conf anahtarları yazıldı",
                  "VM_CORES=" in vm and "VM_RAM_MB=" in vm and "HUGEPAGES=" in vm)
            smb = json.load(open(os.path.join(root, "etc/macnix/smbios.json")))
            check("SMBIOS seri numarası dolu", bool(smb.get("serial")), str(smb)[:80])

        if name == "macnix-gpu-detect":
            plan = fake.globalstorage.value("macnix_plan")
            check("globalstorage'a plan yazıldı", isinstance(plan, dict) and "arch" in plan)
    finally:
        shutil.rmtree(root, ignore_errors=True)


# ── 3. Yapılandırma tutarlılığı ─────────────────────────────────────────────
def test_configs():
    print("\n\033[1m── Calamares yapılandırmaları ──\033[0m")
    import yaml

    settings_path = os.path.join(ROOT, "calamares", "settings.conf")
    with open(settings_path) as fh:
        raw = "\n".join(l for l in fh.read().splitlines() if not l.strip().startswith("#"))
    settings = yaml.safe_load(raw)

    seq = settings.get("sequence", [])
    flat = []
    for phase in seq:
        for key, items in phase.items():
            flat.extend(items or [])
    check("exec listesinde unpackfs var (orijinal hatanın kaynağı)",
          "unpackfs" in flat, str(flat))
    check("unpackfs mount'tan SONRA",
          flat.index("unpackfs") > flat.index("mount"),
          f"mount={flat.index('mount')}, unpackfs={flat.index('unpackfs')}")
    check("unpackfs umount'tan ÖNCE",
          flat.index("unpackfs") < flat.index("umount"))
    check("partition'dan önce mount yok (sıra mantıklı)",
          flat.index("partition") < flat.index("mount"))

    # Her modülün .conf'u var mı
    # NOT: exec listesinde bazı adımlar {"id","module","config"} sözlüğü olarak
    # yazılır (aynı modülü farklı yapılandırmayla ikinci kez kullanmak için).
    # Bu durumda .conf adı id değil, config alanıdır.
    # NOT: yerel Python job modülleri (gpu-detect, gpu-config, efi-fallback)
    # .conf gerektirmez — yapılandırmaları yoktur.
    local_jobs = {m for m in os.listdir(os.path.join(ROOT, "calamares", "modules"))
                  if os.path.isfile(os.path.join(ROOT, "calamares", "modules", m, "module.desc"))}
    missing = []
    for mod in flat:
        if mod in local_jobs:
            continue
        if isinstance(mod, dict):
            conf_name = mod.get("config")
            mod_id = mod.get("id", mod.get("module", "?"))
            if not conf_name or not os.path.exists(
                    os.path.join(ROOT, "calamares", "module-conf", conf_name)):
                missing.append(mod_id)
            continue
        # welcomeq / finishedq: QML modülleri, yapılandırma .py adıyla tutulur
        if not any(os.path.exists(os.path.join(ROOT, "calamares", "module-conf",
                                               f"{mod}{ext}"))
                   for ext in (".conf", ".py")):
            missing.append(mod)
    check(f"tüm {len(flat)} modülün .conf dosyası var", not missing, str(missing))

    # module-conf YAML olarak geçerli mi
    bad = []
    for f in sorted(os.listdir(os.path.join(ROOT, "calamares", "module-conf"))):
        if not f.endswith(".conf"):
            continue
        try:
            with open(os.path.join(ROOT, "calamares", "module-conf", f)) as fh:
                list(yaml.safe_load_all(fh))
        except Exception as exc:  # noqa: BLE001
            bad.append(f"{f}: {exc}")
    check("module-conf dosyaları geçerli YAML", not bad, str(bad))

    # unpackfs kaynağı macnix-medium'un kurduğu linke işaret ediyor mu
    with open(os.path.join(ROOT, "calamares", "module-conf", "unpackfs.conf")) as fh:
        unpack = yaml.safe_load(fh)
    src = unpack["unpack"][0]["source"]
    check("unpackfs kaynağı /run/macnix-live", src.startswith("/run/macnix-live"), src)
    with open(os.path.join(ROOT, "calamares", "module-conf", "shellprocess.conf")) as fh:
        sp = yaml.safe_load(fh)
    cmd = " ".join(sp.get("script", []))
    check("shellprocess /run/macnix-live linkini kuruyor", "/run/macnix-live" in cmd)
    check("shellprocess yeni ve eski live-boot yollarını biliyor",
          "/run/live/medium" in cmd and "/lib/live/mount/medium" in cmd)


# ── 4. Debian Calamares 3.2 uyumluluğu ─────────────────────────────────────
# Canlı önyükleme testinde bulunan GERÇEK hatalar — bir daha oluşmasın.
def test_debian_compat():
    print("\n\033[1m── Debian 12 / Calamares 3.2 uyumluluğu ──\033[0m")
    import yaml

    # 1) Python viewmodule: Debian paketi PythonQt'siz → desteklenmiyor
    mods_dir = os.path.join(ROOT, "calamares", "modules")
    bad_iface = []
    for m in sorted(os.listdir(mods_dir)):
        desc = os.path.join(mods_dir, m, "module.desc")
        if not os.path.isfile(desc):
            bad_iface.append(f"{m}: module.desc yok")
            continue
        with open(desc) as fh:
            d = yaml.safe_load(fh)
        if d.get("interface") == "python" and d.get("type") != "job":
            bad_iface.append(f"{m}: {d.get('type')}+python")
    check("hiçbir modül python viewmodule değil", not bad_iface, str(bad_iface))

    # 2) settings.conf geçerli + bilinen Debian modülleri
    with open(os.path.join(ROOT, "calamares", "settings.conf")) as fh:
        raw = "\n".join(l for l in fh.read().splitlines()
                         if not l.strip().startswith("#"))
    st = yaml.safe_load(raw)
    flat = []
    for phase in st.get("sequence", []):
        for _k, items in phase.items():
            flat.extend(items or [])

    # 2026-11-14 DÜZELTMESİ: "notes" modülü ASLINDA Debian calamares
    # paketinde VAR (packages.debian.org/bookworm/amd64/calamares/filelist:
    # modules/finished, finishedq, notesqml, welcome, welcomeq — notes
    # modülü C++ tarafta gömülü). "notes" sırada olmalı; notesqml ise
    # canlı VM'de QML yükleyemediği için kullanılmıyor.
    # 2026-11-14: "notes" modülü Calamares'te YOK (yerel 3.3.14: "notes@notes
    # could not be loaded"; Debian bookworm'da da yalnız notesqml var).
    # Bilgilendirme görevi slaytlara (show.qml) ve karşılama metnine verildi.
    check("'notes' modülü kullanılmıyor (Calamares'te yok)", "notes" not in flat, str(flat))
    check("license adımı var (zorunlu kredi ekranı)", "license" in flat)
    # LIFELINE: yan menüye sahte adım adları basılmasını önleyen kural —
    # sequence içinde "- " ile başlayan her satır gerçek bir modül adı olmalı.
    seqraw = open(os.path.join(ROOT, "calamares", "settings.conf"),
                  encoding="utf-8").read()
    seqpart = seqraw[seqraw.index("sequence:"):seqraw.index("branding:")]
    bad = [l.strip() for l in seqpart.splitlines()
           if l.strip().startswith("- ")
           and l.strip()[2:].split("#")[0].strip() not in
           (set(flat) | {"show:", "exec:"})]
    check("sequence'te açıklama satırı YOK (sahte adım adı üretmez)",
          not bad, f"şüpheli satırlar: {bad}")
    check("notesqml kullanılmıyor (QML yüklenemedi)", "notesqml" not in flat)

    # 3) instances YALNIZCA gerçekten kullanılıyorsa tanımlanmalı.
    #    (Eskiden "hiç instances olmasın" diye test ediliyordu; Calamares 3.2
    #     sırada sözlük kabul etmediği için EFI yedeği artık instances ile
    #     tanımlanıyor — kullanılan her örnek sırada da geçmeli.)
    for _inst in (st.get("instances") or []):
        check(f"instances '{_inst.get('id')}' sırada kullanılıyor",
              _inst.get("id") in flat)

    # 4) modules-search çok mimarili dizini içeriyor
    search = " ".join(st.get("modules-search", []))
    check("modules-search çok mimarili yolu içeriyor",
          "@MULTIARCH@" in search, search)

    # 5) notesqml QML dosyası var ve Material'a başvurmuyor
    qml_path = os.path.join(ROOT, "calamares", "qml", "notes.qml")
    check("notes.qml mevcut", os.path.isfile(qml_path))
    if os.path.isfile(qml_path):
        qml = open(qml_path).read()
        check("notes.qml QtQuick.Controls.Material kullanmıyor",
              "Controls.Material" not in qml)
        check("notes.qml QtQuick.Layouts kullanmıyor",
              "import QtQuick.Layouts" not in qml)

    # 6) partition.conf initialSwapChoice gerçek geçerli değerlerde
    with open(os.path.join(ROOT, "calamares", "module-conf", "partition.conf")) as fh:
        part = yaml.safe_load(fh)
    valid = set(part.get("userSwapChoices") or
                ["none", "small", "file", "suspend", "reuse", "full"])
    check("initialSwapChoice userSwapChoices içinde",
          part.get("initialSwapChoice") in valid,
          f"{part.get('initialSwapChoice')} ∉ {sorted(valid)}")

    # 7) users.conf bilinmeyen parola anahtarı içermiyor
    with open(os.path.join(ROOT, "calamares", "module-conf", "users.conf")) as fh:
        users = yaml.safe_load(fh)
    allowed = {"minLength", "maxLength"}
    req = users.get("passwordRequirements") or {}
    unknown = set(req) - allowed
    check("passwordRequirements bilinmeyen anahtar içermiyor", not unknown, str(unknown))

    # 8) machineid entropy-files (entropy kullanımdan kaldırıldı)
    with open(os.path.join(ROOT, "calamares", "module-conf", "machineid.conf")) as fh:
        mid = yaml.safe_load(fh)
    check("machineid 'entropy' değil 'entropy-files' kullanıyor",
          "entropy-files" in mid and "entropy" not in mid, str(mid))

    # 9) QML paketleri paket listesinde
    pkgs = open(os.path.join(ROOT, "packages", "01-core.list.chroot")).read()
    for p in ("qml-module-qtquick-controls2", "qml-module-qtquick-layouts",
              "qml-module-qtquick-window2"):
        check(f"paket listesinde {p}", p in pkgs)

    # 10) build.sh: modüller çok mimarili dizine kuruluyor ve chown var
    build = open(os.path.join(ROOT, "build.sh")).read()
    check("build.sh Calamares modüllerini çok mimarili dizine kuruyor",
          "MACNIX_MULTIARCH" in build and "calamares/modules" in build)
    # ── UEFI yedek önyükleyici (\EFI\BOOT\BOOTX64.EFI) ───────────────────
    # Debian Calamares'te bootloader.conf:installEFIFallback YOK SAYILIYOR;
    # VM testinde NVRAM girdisi olmayan UEFI doğrudan kabuğa düşüyordu.
    fb_main = os.path.join(ROOT, "calamares/modules/macnix-efi-fallback/main.py")
    fb_desc = os.path.join(ROOT, "calamares/modules/macnix-efi-fallback/module.desc")
    check("EFI yedeği yerel Python job modülü", os.path.isfile(fb_main) and os.path.isfile(fb_desc))
    if os.path.isfile(fb_main):
        fbc = open(fb_main).read()
        check("EFI yedeği BOOTX64.EFI yazıyor", "BOOTX64.EFI" in fbc)
        check("EFI yedeği BOOTIA32.EFI (32-bit UEFI) da destekliyor", "BOOTIA32.EFI" in fbc)
        check("EFI yedeği BIOS'ta sessizce atlıyor", "BIOS kurulumu olabilir" in fbc)
        check("EFI yedeği yazılamazsa kurulumu düşürmüyor",
              "kurulum sürüyor" in fbc)
        check("EFI yedeği hedef kökü chroot'a göre çözüyor", "_resolve_root" in fbc)
    if os.path.isfile(fb_desc):
        import yaml as _y
        _d = _y.safe_load(open(fb_desc))
        check("EFI yedeği modülü job+python arayüzünde",
              _d.get("type") == "job" and _d.get("interface") == "python", str(_d))
    st = open(os.path.join(ROOT, "calamares/settings.conf")).read()
    st_clean = "\n".join(l for l in st.splitlines() if not l.strip().startswith("#"))
    check("EFI yedek adımı exec listesinde", "- macnix-efi-fallback" in st_clean)
    check("EFI yedeği için shellprocess örneği KULLANILMIYOR (canlı testte yüklenmedi)",
          "config: macnix-efi-fallback.conf" not in st_clean)
    # Calamares 3.2: sequence öğeleri SÖZLÜK olamaz → "invalid settings".
    try:
        _st = yaml.safe_load(st_clean)
        _flat = []
        for _ph in _st.get("sequence", []):
            for _k, _v in _ph.items():
                _flat += _v or []
        check("sequence öğeleri yalnızca metin (sözlük yok)",
              all(isinstance(x, str) for x in _flat),
              str([x for x in _flat if not isinstance(x, str)]))
    except Exception as e:  # noqa: BLE001
        check("settings.conf YAML olarak okunuyor", False, str(e))
    i_bl = st_clean.find("- bootloader")
    i_fb = st_clean.find("- macnix-efi-fallback")
    i_um = st_clean.find("- umount")
    check("EFI yedeği bootloader'dan SONRA, umount'tan ÖNCE",
          0 < i_bl < i_fb < i_um, f"bootloader={i_bl} fallback={i_fb} umount={i_um}")

    # ── macnix-gpu-config sağlamlığı ───────────────────────────────────────
    # Kurulumun son adımı. /etc/default/grub yokken FileNotFoundError ile
    # çöküyordu → VM yapılandırması hiç yazılmıyordu (kurulu sistemde
    # macnix-doctor "kritik: /etc/macnix/vm.conf yok" veriyordu).
    gpu = open(os.path.join(ROOT, "calamares/modules/macnix-gpu-config/main.py")).read()
    # Calamares Python işleri hedefe chroot'lu çalışabilir → rootMountPoint
    # chroot içinde yoktur; eskiden modül sessizce hiçbir şey yazmıyordu.
    check("gpu-config hedef kökü chroot'a göre çözüyor (_resolve_root)",
          "_resolve_root" in gpu and 'return "/"' in gpu)
    check("gpu-config root çözülemezse hata döndürüyor",
          "Kurulum hedefi bulunamadı" in gpu)
    # xmessage kaçış dizisi yorumlamaz: "\n" ekranda düz metin görünür.
    ob = open(os.path.join(ROOT, "overlay/etc/xdg/openbox/autostart")).read()
    check("gözcü xmessage metni printf ile satır sonu üretiyor",
          "xmessage -center \"$(printf" in ob and 'Calamares başlatılamadı.\\n' not in ob)
    check("gözcü 3 deneme sonrası metin moduna yönlendiriyor",
          "macnix-tui" in ob and "tries\" -ge 3" in ob)
    # doctor: /dev/kvm yokluğu ve macOS imajının henüz indirilmemiş olması
    # KRİTİK değil, uyarıdır (yeni kurulmuş her sistemde kırmızı görünüyordu).
    doc = open(os.path.join(ROOT, "scripts/bin/macnix-doctor")).read()
    check("doctor /dev/kvm yokluğunu kritik saymıyor", 'wr "/dev/kvm yok' in doc)
    check("doctor /proc okunamazsa kritik demiyor", "/proc/cpuinfo okunamadı" in doc)
    check("doctor eksik macOS imajını uyarı sayıyor",
          "henüz yok (macnix-setup ile oluşturulur)" in doc)
    check("doctor eksik imaj için tek toplu ipucu veriyor", "VM_MISSING" in doc)
    check("hugepage sayısı doğru hesaplanıyor (RAM(MB)/2, 512 ile çarpım YOK)",
          "hugepages = max(1, vm_ram // 2)" in gpu)
    check("gpu-config /etc/default dizinini oluşturuyor", 'os.makedirs(os.path.dirname(path), exist_ok=True)' in gpu)
    check("gpu-config GRUB yazamazsa modülü düşürmüyor", "GRUB varsayılanları yazılamadı" in gpu)
    check("gpu-config hedef kök yoksa hata döndürüyor (tek gerçek hata)",
          'return ("Kurulum hedefi bulunamadı"' in gpu)

    # GRUB modül listesi sabit olmamalı: GRUB 2.12 efi_uga.mod'u kaldırdı ve
    # GitHub runner'da derleme "cannot open efi_uga.mod" ile patladı.
    # build.sh yerel Calamares modüllerinin HEPSİNİ kopyalamalı; sabit liste
    # yüzünden yeni modül ISO'ya hiç girmiyordu.
    check("build.sh tüm yerel Calamares modüllerini kopyalıyor (sabit liste yok)",
          'for m in $(cd "${ROOT}/calamares/modules"' in build,
          "sabit modül listesi bulundu")

    check("build.sh GRUB EFI modüllerini sistemde var olanlardan süzüyor",
          '[[ -f "$moddir/$m.mod" ]]' in build and 'missing+=' in build)

    check("build.sh /etc sahipliğini root'a çekiyor",
          "chown -R 0:0" in build and "$ROOTFS/etc" in build)
    # sıra kritik: chown overlay kopyasından SONRA çalışmalı
    i_ov = build.find('cp -a "${ROOT}/overlay/."')
    # 2026-11-14: araya finalize_calamares_config() girdi; sıra şöyle:
    #   fix_ownership → fix_lightdm_autologin → finalize_calamares_config
    i_fixown = build.find("  fix_ownership\n  fix_lightdm_autologin")
    check("sahiplik düzeltmesi overlay kopyasından SONRA çağrılıyor",
          0 < i_ov < i_fixown, f"overlay={i_ov}, fix_ownership={i_fixown}")
    check("build.sh mksquashfs'te /dev /proc /sys /run /tmp hariç tutmuyor",
          "-e dev" not in build and '"$d"' in build)

    # 10b) GRUB: kurulan sistemde hem EFI hem BIOS hedefi bulunmalı
    check("build.sh grub-pc-bin (BIOS) paketini de kuruyor",
          "grub-pc-bin" in build and "grub-efi-amd64-bin" in build)
    check("build.sh efibootmgr kuruyor", "efibootmgr" in build)
    check("build.sh grub hedeflerini doğruluyor",
          "x86_64-efi i386-pc" in build)

    # 10a) macOS İNDİRME PROTOKOLÜ (2026-11-15 canlı hata: HTTP 401)
    #   Apple, /InstallationPayload/RecoveryImage için önce ana sayfadan
    #   session çerezi almayı ZORUNLU kılıyor; ayrıca gövde
    #   "anahtar=değer" satırları biçiminde ve indirme başlığı
    #   "Cookie: AssetToken=..." olmalı (OpenCorePkg/macrecovery ile aynı).
    fm = open(os.path.join(ROOT, "scripts/bin/macnix-fetch-macos.py"),
              encoding="utf-8").read()
    check("macOS indirme: Apple OTURUM çerezi alınıyor (401'in sebebi)",
          "def get_session(" in fm and "session=" in fm)
    check("macOS indirme: gövde 'anahtar=değer' satırları biçiminde",
          "join(" in fm and '"cid"' in fm and '"bid"' in fm and "%s=%s" in fm)
    check("macOS indirme: Cookie: AssetToken=<AT> (macrecovery ile aynı)",
          "AssetToken=" in fm)
    check("macOS indirme: chunklist ile bütünlük doğrulaması",
          "def verify_chunklist_image(" in fm and "CNKL" in fm)
    check("macOS indirme: Apple imajı için UDIF kuyruk (koly) kontrolü",
          "koly" in fm and "tail" in fm)

    # 10h) OpenCore ŞEMA UYUMLULUĞU (2026-11-15 gerçek hata: Halting on critical error)
    lib = open(os.path.join(ROOT, "scripts/macnix_lib.py"), encoding="utf-8").read()
    check("lib: OpenCore 1.0.8 şemasında olmayan 'SerialInit' kaldırıldı",
          "SerialInit" not in lib)
    check("lib: UEFI.Audio 1.0.8 alanları (AudioOutMask/MaximumGain)",
          "AudioOutMask" in lib and "\"AudioOut\":" not in lib and "MinimumVolume" not in lib)
    check("lib: UEFI.Input.KeySwap (KeyMergeThreshold değil)",
          "KeySwap" in lib and "KeyMergeThreshold" not in lib)
    check("lib: UEFI.Quirks.ForceOcWriteFlash (ForceOemVolumeHack değil)",
          "ForceOcWriteFlash" in lib and "ForceOemVolumeHack" not in lib)
    check("lib: UEFI.DriveInput bölümü yok (şemada bulunmuyor)",
          "DriveInput" not in lib)
    check("lib: cpu_vendor None iken bool(None) → plist NoneType hatası yok",
          "is_amd = bool(" in lib)
    schema = json.load(open(os.path.join(ROOT, "config/opencore-schema.json")))
    check("şema referansı config/opencore-schema.json mevcut ve Debug bölümü içeriyor",
          "Misc" in schema and "Debug" in schema["Misc"] and "UEFI" in schema)
    oc = open(os.path.join(ROOT, "scripts/bin/macnix-oc"), encoding="utf-8").read()
    check("macnix-oc --check OpenCore şemasına göre denetim yapıyor",
          "opencore-schema.json" in oc and "OpenCore şemasında YOK" in oc)
    asst = open(os.path.join(ROOT, "scripts/bin/macnix-assets"), encoding="utf-8").read()
    check("macnix-assets: 3 denemeli indirme + yerel kext önbelleği",
          "denemesi" in asst and "KEXT_CACHE" in asst)


    # 10i) ŞEMA DENETLEYİCİSİ (bağımsız araç) — gerçek config üzerinde çalışıyor mu?
    import subprocess, tempfile
    sc = os.path.join(ROOT, "tools/oc-schema-check.py")
    check("tools/oc-schema-check.py repoda (GitHub 644 verir → izin bitine bakmıyoruz)",
          os.path.exists(sc) and os.path.getsize(sc) > 1000)
    # Şema uyumlu bir config → 0 dönmeli
    good = {"ACPI": {"Add": [], "Delete": [], "Patch": [], "Quirks": {
                "FadtEnableReset": False, "NormalizeHeaders": False, "RebaseRegions": False,
                "ResetHwSig": False, "ResetLogoStatus": True, "SyncTableIds": False}},
            "Booter": {"MmioWhitelist": [], "Patch": [], "Quirks": {
                "AllowRelocationBlock": False, "AvoidRuntimeDefrag": True, "DevirtualiseMmio": False,
                "DisableSingleUser": False, "DisableVariableWrite": False, "DiscardHibernateMap": False,
                "EnableSafeModeSlide": True, "EnableWriteUnprotector": False, "ForceBooterSignature": False,
                "ForceExitBootServices": False, "ProtectMemoryRegions": False, "ProtectSecureBoot": False,
                "ProtectUefiServices": True, "ProvideCustomSlide": True, "ProvideMaxSlide": 0,
                "RebuildAppleMemoryMap": True, "ResizeAppleGpuBars": -1, "SetupVirtualMap": True,
                "SignalAppleOS": False, "SyncRuntimePermissions": True}},
            "DeviceProperties": {"Add": {}, "Delete": {}},
            "Kernel": {"Add": [{"Arch": "Any", "BundlePath": "Lilu.kext", "Comment": "", "Enabled": True,
                                "ExecutablePath": "Contents/MacOS/Lilu", "MaxKernel": "", "MinKernel": "",
                                "PlistPath": "Contents/Info.plist"}],
                       "Block": [], "Emulate": {"Cpuid1Data": b"", "Cpuid1Mask": b"", "DummyPowerManagement": False,
                                                "MaxKernel": "", "MinKernel": ""},
                       "Force": [], "Patch": [],
                       "Quirks": {"AppleCpuPmCfgLock": False, "AppleXcpmCfgLock": False,
                                  "AppleXcpmExtraMsrs": False, "AppleXcpmForceBoost": False,
                                  "CustomSMBIOSGuid": False, "DisableIoMapper": True,
                                  "DisableLinkeditJettison": True, "DisableRtcChecksum": False,
                                  "ExtendBTFeatureFlags": False, "ForceAquantiaEthernet": False,
                                  "LapicKernelPanic": False, "LegacyCommpage": False, "PanicNoKextDump": True,
                                  "PowerTimeoutKernelPanic": True, "ProvideCurrentCpuInfo": False,
                                  "SetApfsTrimTimeout": -1, "ThirdPartyDrives": False, "XhciPortLimit": True},
                       "Scheme": {"FuzzyMatch": True, "KernelArch": "Auto", "KernelCache": "Auto"}},
            "Misc": {"Boot": {"ConsoleAttributes": 0, "HibernateMode": "None", "HibernateSkipsPicker": False,
                              "HideAuxiliary": True, "InstanceIdentifier": "", "LauncherOption": "Disabled",
                              "LauncherPath": "Default", "PickerAttributes": 17, "PickerAudioAssist": False,
                              "PickerMode": "Builtin", "PickerVariant": "Auto", "PollAppleHotKeys": False,
                              "ShowPicker": True, "TakeoffDelay": 0, "Timeout": 5},
                     "Debug": {"AppleDebug": False, "ApplePanic": False, "DisableWatchDog": True,
                               "DisplayDelay": 0, "DisplayLevel": 0, "SysReport": False, "Target": 3},
                     "Security": {"AllowSetDefault": True, "ApECID": 0, "AuthRestart": False,
                                  "BlacklistAppleUpdate": True, "DmgLoading": "Signed", "EnablePassword": False,
                                  "ExposeSensitiveData": 6, "HaltLevel": 2147483650, "PasswordHash": b"",
                                  "PasswordSalt": b"", "ScanPolicy": 0, "SecureBootModel": "Disabled",
                                  "Vault": "Optional"},
                     "Serial": {"Init": False, "Override": False},
                     "Tools": []},
            "NVRAM": {"Add": {}, "Delete": {}, "LegacyOverwrite": False, "LegacySchema": {},
                      "WriteFlash": True},
            "PlatformInfo": {"Automatic": True, "CustomMemory": False,
                             "Generic": {"AdviseFeatures": False, "MLB": "Y", "ROM": b"\xaa\xbb\xcc\xdd\xee\xff",
                                         "SpoofVendor": True, "SystemMemoryStatus": "Auto",
                                         "SystemProductName": "iMacPro1,1", "SystemSerialNumber": "X",
                                         "SystemUUID": "5D2E1B40-1111-2222-3333-444455556666",
                                         "MaxBIOSVersion": False, "ProcessorType": 0},
                             "UpdateDataHub": True, "UpdateNVRAM": True, "UpdateSMBIOS": True,
                             "UpdateSMBIOSMode": "Create", "UseRawUuidEncoding": False},
            "UEFI": {"APFS": {"EnableJumpstart": True, "GlobalConnect": False, "HideVerbose": True,
                              "JumpstartHotPlug": False, "MinDate": 0, "MinVersion": 0},
                     "AppleInput": {"AppleEvent": "Builtin", "CustomDelays": False, "GraphicsInputMirroring": True,
                                    "KeyInitialDelay": 0, "KeySubsequentDelay": 5, "PointerDwellClickTimeout": 0,
                                    "PointerDwellDoubleClickTimeout": 0, "PointerDwellRadius": 0,
                                    "PointerPollMax": 0, "PointerPollMin": 0, "PointerSpeedDiv": 1,
                                    "PointerSpeedMul": 1},
                     "Audio": {"AudioCodec": 0, "AudioDevice": "", "AudioOutMask": 1, "AudioSupport": False,
                               "DisconnectHda": False, "MaximumGain": 0, "MinimumAssistGain": -30,
                               "MinimumAudibleGain": -55, "PlayChime": "Auto", "ResetTrafficClass": False,
                               "SetupDelay": 0},
                     "ConnectDrivers": True,
                     "Drivers": [{"Arguments": "", "Comment": "", "Enabled": True, "LoadEarly": False,
                                  "Path": "OpenRuntime.efi"}],
                     "Input": {"KeyFiltering": False, "KeyForgetThreshold": 5, "KeySupport": True, "KeySwap": False,
                               "KeySupportMode": "Auto", "PointerSupport": False, "PointerSupportMode": "",
                               "TimerResolution": 50000},
                     "Output": {"ClearScreenOnModeSwitch": False, "ConsoleMode": "", "DirectGopRendering": False,
                                "ForceResolution": False, "GopBurstMode": False, "IgnoreTextInGraphics": False,
                                "InitialMode": "Auto", "ProvideConsoleGop": True,
                                "ReconnectGraphicsOnConnect": False, "ReconnectOnResChange": False,
                                "ReplaceTabWithSpace": False, "Resolution": "Max", "SanitiseClearScreen": False,
                                "TextRenderer": "BuiltinGraphics", "UgaPassThrough": False},
                     "ProtocolOverrides": {"AppleAudio": False, "AppleBootPolicy": False, "AppleDebugLog": False,
                                           "AppleEg2Info": False, "AppleFramebufferInfo": False,
                                           "AppleImageConversion": False, "AppleImg4Verification": False,
                                           "AppleKeyMap": False, "AppleRtcRam": False, "AppleSecureBoot": False,
                                           "AppleSmcIo": False, "AppleUserInterfaceTheme": False,
                                           "DataHub": False, "DeviceProperties": False, "FirmwareVolume": False,
                                           "HashServices": False, "OSInfo": False, "UnicodeCollation": False},
                     "Quirks": {"ActivateHpetSupport": False, "DisableSecurityPolicy": False,
                                "EnableVectorAcceleration": True, "EnableVmx": False, "ExitBootServicesDelay": 0,
                                "ForceOcWriteFlash": False, "ForgeUefiSupport": False,
                                "IgnoreInvalidFlexRatio": False, "ReleaseUsbOwnership": True,
                                "ReloadOptionRoms": False, "RequestBootVarRouting": True, "ResizeGpuBars": -1,
                                "ResizeUsePciRbIo": False, "ShimRetainProtocol": False, "TscSyncTimeout": 0,
                                "UnblockFsConnect": False},
                     "ReservedMemory": [], "Unload": []}}
    with tempfile.TemporaryDirectory() as td:
        gp = os.path.join(td, "good.plist")
        plistlib.dump(good, open(gp, "wb"))
        r = subprocess.run([sys.executable, sc, gp], capture_output=True, text=True)
        check("şema denetleyici: uyumlu config'i GEÇİRİYOR", r.returncode == 0)
        bad = json.loads(json.dumps(good, default=str))
        bad["Misc"]["Debug"]["SerialInit"] = False           # gerçek hatayı taklit et
        bp = os.path.join(td, "bad.plist")
        plistlib.dump(bad, open(bp, "wb"))
        r = subprocess.run([sys.executable, sc, bp], capture_output=True, text=True)
        check("şema denetleyici: SerialInit hatasını YAKALIYOR",
              r.returncode == 1 and "SerialInit" in r.stdout)

    st = open(os.path.join(ROOT, "scripts/bin/macnix-setup"), encoding="utf-8").read()
    check("panel: ANSI kaçış dizileri temizleniyor (ham renk kodu görünmüyor)",
          "_ANSI" in st and "def _clean" in st and "[0-9;=?]" in st)
    check("panel: terminal varsayılan kapalı + Ctrl+T ile açılıp kapanıyor",
          "toggle_terminal" in st and "term_state" in st)

    # 10j) GRUB önyükleme (2026-11-15 canlı ISO testlerinde bulunan GERÇEK hatalar)
    emb = open(os.path.join(ROOT, "config/grub/grub-efi-embed.cfg"), encoding="utf-8").read()
    emb_code = "\n".join(l for l in emb.split("\n") if not l.strip().startswith("#"))
    check("grub-efi-embed: 'insmod' YOK (gömülü modülü yeniden yükleme denemesi)",
          "insmod" not in emb_code)
    check("grub-efi-embed: saf ASCII (gömülü cfg'de UTF-8 bozuluyor)",
          all(ord(c) < 128 for c in emb))
    check("grub-efi-embed: yorum satırı YOK (GRUB '#'i komut sanıp hata basıyor)",
          emb.count("#") == 0)
    check("grub-efi-embed: configfile ile menüye devrediyor",
          "configfile" in emb and "/boot/grub/grub.cfg" in emb)
    check("grub-efi-embed: search başarısızsa true ile devam ediyor",
          "else\n    true\nfi" in emb)
    bld = open(os.path.join(ROOT, "build.sh"), encoding="utf-8").read()
    check("build.sh: BOOTX64.EFI 'grub-mkimage' ile (memdisk YOK -> recursion hatasi yok)",
          "grub-mkimage -O x86_64-efi" in bld and "grub-mkstandalone --format" not in bld)
    check("build.sh: gömülü cfg ESP'ye /EFI/BOOT/grub.cfg olarak yazılıyor",
          "::/EFI/BOOT/grub.cfg" in bld)
    check("build.sh: grub.cfg'nin insmod ettiği modüller gömülü (png/jpeg/gfxmenu)",
          " png " in bld and " jpeg " in bld and "gfxmenu" in bld)
    check("build.sh: unicode.pf2 fontu ISO'ya kopyalaniyor",
          "unicode.pf2" in bld and "/boot/grub/fonts" in bld)
    gc = open(os.path.join(ROOT, "config/grub/grub.cfg"), encoding="utf-8").read()
    check("grub.cfg: font yoksa 'terminal_output console'a düşüyor (siyah ekran hatası)",
          "if loadfont" in gc and "terminal_output gfxterm" in gc
          and "terminal_output console" in gc)
    check("grub.cfg: 'insmod font' var (loadfont için gerekli)",
          "insmod font" in gc)

    # 10d) PANEL (macnix-setup) — modern + taşınabilir/kapanabilir terminal
    #   2026-11-15 kullanıcı isteği: "terminal modern olsun, hareket ettirilebilir,
    #   kapanabilir, tekrar açılabilir olsun; sabit durup kullanımı engelliyor."
    su = open(os.path.join(ROOT, "scripts/bin/macnix-setup"), encoding="utf-8").read()
    check("panel: terminal paneli aç/kapat düğmesi var",
          "def toggle_terminal(" in su and "Konsol Aç" in su)
    check("panel: terminal ✕ ile kapanıp yeniden açılabiliyor",
          'btn_term_hide' in su and "term_show(False)" in su and "term_show(True)" in su)
    check("panel: pencere başlıktan sürüklenebiliyor",
          "begin_move_drag" in su and "_start_drag" in su)
    check("panel: klavye kısayolları (Ctrl+T terminal, Ctrl+Q kapat)",
          "Gdk.KEY_t" in su and "Gdk.KEY_q" in su)
    check("panel: modern tema (GTK CSS sağlayıcısı)",
          "CssProvider" in su and "STYLE_PROVIDER_PRIORITY_APPLICATION" in su)
    check("panel: 'macOS'u başlat' hatayı canlı günlüğe akıyor",
          '["macnix-vm", "start"]' in su and "başlatılamadı" in su)

    # 10c) VM BAŞLATMA: CPU listesi / taskset / KVM-TCG geri dönüşü
    #   2026-11-15 canlı hata: `$(( {} - 1 ))` bash aritmetiği hatası yüzünden
    #   CPU listesi boş kalıyor, taskset boş maskeyle çalışıp QEMU düşüyordu.
    vm = open(os.path.join(ROOT, "scripts/bin/macnix-vm"), encoding="utf-8").read()
    check("macnix-vm: CPU listesi bash aritmetiğiyle güvenli üretiliyor",
          "seq 0 $(( HOST_NCPU - 1 ))" in vm and "xargs -I{} seq" not in vm.split("# DİKKAT")[0])
    check("macnix-vm: taskset yalnızca liste doluysa kullanılıyor",
          'if [[ -n "$VM_CPU_LIST" ]]' in vm)
    check("macnix-vm: /dev/kvm yoksa TCG ile çalışmaya devam ediyor",
          'QEMU_ACCEL="tcg"' in vm and "accel=${QEMU_ACCEL}" in vm)
    check("macnix-vm: -cpu host yalnızca KVM modunda",
          'if [[ "$QEMU_ACCEL" == "kvm" ]]; then' in vm and "-cpu host,kvm=on" in vm)

    fb2 = open(os.path.join(ROOT, "scripts/firstboot.sh"), encoding="utf-8").read()
    check("firstboot: KVM yoksa masaüstüne uyarı bırakıyor (dürüst beklenti)",
          "MacNix-KVM-UYARI.txt" in fb2 and "macnix-vm accel" in fb2)
    check("macnix-vm: 'accel' komutu iç içe VM teşhisi veriyor",
          "ExposeVirtualizationExtensions" in vm and "host-passthrough" in vm)
    # 10g) TEŞHİS + PERFORMANS (2026-11-15)
    doc = open(os.path.join(ROOT, "scripts/bin/macnix-doctor"), encoding="utf-8").read()
    check("doctor: OpenCore seri günlüğünü yorumluyor (nerede durdu)",
          "serial.log" in doc and "OcMiscLateInit" in doc)
    check("doctor: KVM yoksa 'yazılım emülasyonu' uyarısı veriyor",
          "KVM yok" in doc and "yazılım emülasyonu" in doc)
    check("macnix-vm: KVM varken -cpu host (performans)",
          'QEMU_ACCEL" == "kvm" ]]; then' in vm and "-cpu host,kvm=on" in vm)
    check("macnix-vm: seri günlük her zaman açık (teşhis)",
          "logs/serial.log" in vm)
    fb = open(os.path.join(ROOT, "scripts/firstboot.sh"), encoding="utf-8").read()
    check("firstboot: sudo NoNewPrivs/!authenticate + polkit + pkla (parola hiç sorulmaz)",
          "!authenticate" in fb and "localauthority" in fb and "visudo -cf" in fb)

    # 10f) OPENCORE / UEFI ÖNYÜKLEME — 2026-11-15 gerçek önyükleme denemesi
    #   OSX-KVM + OpenCore 1.0.8 + gerçek OVMF ile QEMU çalıştırıldı, OpenCore
    #   config'i ayrıştırdı. Bulunan hatalar koda aktarıldı.
    oc = open(os.path.join(ROOT, "scripts/bin/macnix-oc"), encoding="utf-8").read()
    check("macnix-oc: ESP FAT16 olarak kuruluyor (FAT32'de uzun ad yazılamıyor)",
          'FAT_TYPE=16' in oc and 'mkfs.vfat -F "$FAT_TYPE"' in oc)
    check("macnix-oc: kext alt dizinleri mmd ile açılıyor",
          'Contents/MacOS' in oc and "mmd -i" in oc)
    check("macnix-oc: ESP içeriği doğrulanıyor (BOOTx64/OpenCore/config/OpenRuntime)",
          "verify_esp" in oc and "EFI/BOOT/BOOTx64.efi" in oc)
    check("macnix-oc: GPT + ESP bayraklı imaj üretiliyor (UEFI tanısın)",
          "mklabel gpt" in oc and "set 1 esp on" in oc)
    check("macnix-vm: UEFI NVRAM kalıcı (pflash qcow2)",
          "OVMF_VARS_QCOW2" in vm and "format=qcow2,file=${OVMF_VARS_QCOW2}" in vm)

    # 10e) QEMU KOMUT SATIRI — 2026-11-15 canlı bulgularla bulunan 7 gerçek hata
    #   Bunların hepsi QEMU'yu HİÇ açtırmıyordu; hepsi gerçek qemu-system-x86_64
    #   (10.0) ile tek tek doğrulandı.
    check("macnix-vm: -no-hpet kaldırıldı (QEMU 8+ geçersiz) → hpet=off",
          "-no-hpet" not in vm.split("# DİKKAT")[0] and "hpet=off" in vm)
    check("macnix-vm: SMBIOS modelindeki virgül kaçırılıyor (iMacPro1,1)",
          "SMBIOS_MODEL//,/-" in vm)
    check("macnix-vm: OpenCore diski q35'te ide.1'e bağlı (sata.2 yok)",
          'bus=ide.1,drive=OC' in vm and 'bus=sata.2' not in vm)
    check("macnix-vm: MAC adresi her zaman 6 oktet",
          "VM_MAC" in vm and "os.urandom(3)" in vm)
    check("macnix-vm: O_DIRECT desteklenmiyorsa cache=writeback",
          "O_DIRECT" in vm and 'CACHE_MODE="writeback"' in vm)
    check("macnix-vm: OpenGL yoksa virtio-vga (virtio-vga-gl değil)",
          "QEMU_GL" in vm and "virtio-vga,edid=on" in vm)
    check("macnix-vm: bellek host'a sığmıyorsa güvenli değere düşülüyor",
          "MEM_AVAIL_MB" in vm and 'MEM_LOCK="off"' in vm)
    check("macnix-vm: ses aygıtı yoksa -audiodev none",
          "audiodev none" in vm)

    # 10b) PAROLA SORULMASIN — 2026-11-15 canlı hata regresyon testleri
    #   (a) firstboot servisi ETKİNLEŞTİRİLMELİ: edilmediği için parola
    #       kaldırma/sudoers onarımı hiç çalışmıyordu.
    #   (b) sudoers'da %sudo NOPASSWD olmalı: yoksa terminalde "parola gerekli".
    #   (c) polkit kuralı olmalı: GUI araçları parola penceresi açıyordu.
    check("build.sh macnix-firstboot.service'i ETKİNLEŞTİRİYOR",
          "systemctl enable macnix-firstboot.service" in build,
          "firstboot servisi etkinleştirilmiyor → parola asla kaldırılmaz")
    check("build.sh firstboot.sh'nin çalıştırılabilir olduğunu doğruluyor",
          "-x \"$ROOTFS/opt/macnix/scripts/firstboot.sh\"" in build)
    check("sudoers: %sudo grubuna NOPASSWD (parola sorulmaz)",
          "%sudo ALL=(ALL:ALL) NOPASSWD: ALL" in build,
          "sudoers.d'de %sudo NOPASSWD yok → 'sudo: a password is required'")
    su = open(os.path.join(ROOT, "overlay/etc/sudoers.d/99-macnix"), encoding="utf-8").read()
    check("99-macnix: %sudo NOPASSWD kuralı var",
          "%sudo ALL=(ALL:ALL) NOPASSWD: ALL" in su)
    fb = open(os.path.join(ROOT, "scripts/firstboot.sh"), encoding="utf-8").read()
    check("firstboot: sudoers.d sahiplik/izin onarımı yapıyor",
          "chown root:root /etc/sudoers.d" in fb and "chmod 0440 /etc/sudoers.d/*" in fb)
    check("firstboot: parolasız sudo yazıyor (99-zz-macnix-nopasswd)",
          "99-zz-macnix-nopasswd" in fb)
    pol = os.path.join(ROOT, "overlay/etc/polkit-1/rules.d/49-macnix-nopasswd.rules")
    check("polkit kuralı var (GUI'de parola penceresi çıkmaz)",
          os.path.exists(pol) and "polkit.Result.YES" in open(pol, encoding="utf-8").read())

    # 11) lightdm autologin: Debian'ın "user" hesabı ezilmiş olmalı
    check("build.sh lightdm.conf'taki autologin-user=user satırını etkisizleştiriyor",
          "autologin-user" in build and "lightdm.conf" in build)
    # sıra kritik: düzeltme overlay kopyasından SONRA çalışmalı
    i_overlay = build.find('cp -a "${ROOT}/overlay/."')
    i_fix = build.find("  fix_lightdm_autologin\n  finalize_calamares_config")
    check("lightdm düzeltmesi overlay kopyasından SONRA çağrılıyor",
          0 < i_overlay < i_fix, f"overlay={i_overlay}, fix={i_fix}")
    # boru hattı ERR tuzağını yanıltıp aşamayı sessizce kesmemeli
    check("update-initramfs boru hattı ERR tuzağını tetiklemiyor",
          'update-initramfs -u -k all" > "$irfs" 2>&1' in build)
    check("build.sh /etc/lightdm sahipliğini de düzeltiyor",
          'chown -R 0:0 "$ROOTFS/etc/lightdm"' in build)

    # 12) live-boot.sh sudoers sahipliğini onarıyor
    lb = open(os.path.join(ROOT, "scripts", "live-boot.sh")).read()
    check("live-boot.sh sudoers sahipliğini onarıyor",
          "chown -R root:root /etc/sudoers.d" in lb)
    check("live-boot.sh lightdm autologin'i her açılışta onarıyor",
          "autologin-user" in lb and "lightdm" in lb)
    doc = open(os.path.join(ROOT, "scripts", "bin", "macnix-doctor")).read()
    check("macnix-doctor çıkış kodu sözleşmesi belgelenmiş",
          "ÇIKIŞ KODU SÖZLEŞMESİ" in doc)
    unit = open(os.path.join(ROOT, "systemd", "macnix-live.service")).read()
    check("macnix-live.service lightdm'DEN ÖNCE çalışıyor",
          "Before=lightdm.service" in unit)
    check("macnix-live.service lightdm'i yeniden başlatıyor",
          "try-restart lightdm" in unit)


# ════════════════════════════════════════════════════════════════════════════
#  Calamares YAPILANDIRMA testleri (Qt gerekmez — dosya/metin düzeyinde)
# ════════════════════════════════════════════════════════════════════════════
def config_tests():
    """modules/ altındaki conf'ların settings.conf ile tutarlılığı + kritik
    anahtarların VARLIĞI. Canlı testte her biri ayrı bir hata üretmişti."""
    import glob
    import re

    print("\n  ── Calamares yapılandırma testleri ──")
    settings = open(os.path.join(ROOT, "calamares/settings.conf"), encoding="utf-8").read()
    body = "\n".join(l for l in settings.splitlines() if not l.strip().startswith("#"))

    # 1) welcomeq / finishedq akışta (eski welcome/finished yerine)
    # Canlı VM dersi: QML view modülleri (welcomeq/finishedq/notesqml) bu
    # ortamda QML yükleyemedi → "Welcome Loading failed." C++ modüllerine
    # dönüldü. Aşağıdaki testler bunu kilitler.
    check("show: welcome (C++) kullanılıyor",
          re.search(r"^\s+-\s+welcome\b", body, re.M) is not None,
          "settings.conf show listesinde welcome yok")
    check("show: finished (C++) kullanılıyor",
          re.search(r"^\s+-\s+finished\b", body, re.M) is not None,
          "settings.conf show listesinde finished yok")
    check("QML view modülleri (welcomeq/finishedq/notesqml) AKIŞTA DEĞİL",
          not re.search(r"^\s+-\s+(welcomeq|finishedq|notesqml)\b", body, re.M),
          "QML modülü hâlâ akışta — canlı VM'de 'Loading failed' riski")
    check("slideshow QML marka dosyası var (show.qml)",
          os.path.exists(os.path.join(ROOT, "calamares/branding/macnix/show.qml")))
    _show = open(os.path.join(ROOT, "calamares/branding/macnix/show.qml"),
                 encoding="utf-8").read()
    check("show.qml slaytları bilgilendirici (en az 6 slayt)",
          _show.count("Slide {") >= 6, f"Slide sayısı: {_show.count('Slide {')}")
    # kredi şeridi TEK bir altbilgi öğesinde (tüm slaytların üstünde sabit)
    check("show.qml kredi şeridi var (altbilgi)",
          _show.count("BELGESELSEMO") >= 2 and "belgeselsemo.com.tr" in _show)

    # 2) users.conf: otomatik giriş + boş parola + sudo grubu
    users = open(os.path.join(ROOT, "calamares/module-conf/users.conf"), encoding="utf-8").read()
    check("users.conf: doAutologin: true", re.search(r"^doAutologin:\s*true", users, re.M) is not None,
          "otomatik giriş kapalı — kullanıcı parola ekranında takılır")
    check("users.conf: autologinGroup: autologin",
          re.search(r"^autologinGroup:\s*autologin", users, re.M) is not None)
    check("users.conf: allowWeakPasswords + allowWeakPasswordsDefault true",
          re.search(r"^allowWeakPasswords:\s*true", users, re.M) is not None
          and re.search(r"^allowWeakPasswordsDefault:\s*true", users, re.M) is not None,
          "boş/weak parola reddedilir → kullanıcı parola yazmak zorunda kalır")
    import yaml as _yaml
    _docs = [d for d in _yaml.safe_load_all(users) if d]   # ilk belge: --- sonrası
    _u = _docs[0] if _docs else {}
    _pr = (_u or {}).get("passwordRequirements") or {}
    check("users.conf: passwordRequirements.nonempty YOK (boş parola serbest)",
          "nonempty" not in _pr,
          "nonempty anahtarı var → boş parola reddedilir")

    # 3) finishedq.conf: yeniden başlatma
    # Bitiş ekranı artık C++ finished modülü: yeniden başlatma komutu orada.
    fin = open(os.path.join(ROOT, "calamares/module-conf/finished.conf"),
               encoding="utf-8").read()
    check("finished.conf: restartNowCommand var (systemctl -i reboot)",
          "systemctl -i reboot" in fin)

    # 4) Marka QML'leri: kredi şeridi + Dil
    brand = os.path.join(ROOT, "calamares/branding/macnix")
    show_txt = open(os.path.join(brand, "show.qml"), encoding="utf-8").read()
    check("show.qml: BELGESELSEMO + ARENA.AI kredisi var",
          "BELGESELSEMO" in show_txt and "ARENA.AI" in show_txt)
    check("show.qml: belgeselsemo.com.tr bağlantısı var",
          "belgeselsemo.com.tr" in show_txt)
    check("show.qml: 'Gelişmiş macOS Sanallaştırma Distrosu' tanımı var",
          "Gelişmiş macOS Sanallaştırma Distrosu" in show_txt)
    bd = open(os.path.join(brand, "branding.desc"), encoding="utf-8").read()
    check("branding.desc: zorunlu kredi satırı (birebir)",
          "BELGESELSEMO tarafından ARENA.AI sayesinde" in bd
          and "local-over/macnix" in bd and "belgeselsemo.com.tr" in bd)
    check("branding.desc: 'Gelişmiş macOS Sanallaştırma Distrosu' ürün adında",
          "Gelişmiş macOS Sanallaştırma Distrosu" in bd)

    # 5) Slayt görselleri: show.qml'deki her referans diskte olmalı
    show = open(os.path.join(brand, "show.qml"), encoding="utf-8").read()
    imgs = sorted(set(re.findall(r'source:\s*"([^"$]+?\.png)"', show)))
    missing = [i for i in imgs if not os.path.exists(os.path.join(brand, i))]
    check(f"show.qml görselleri tam ({len(imgs)} adet)", not missing, f"eksik: {missing}")
    check("show.qml en az 5 slayt içeriyor", show.count("Slide {") >= 5,
          f"bulunan: {show.count('Slide {')}")

    # 6) Görseller repoda mı? (üretici betik yalnızca yerelde gerekir; CI'da
    #    Pillow kurulu değil ve zaten PNG'ler depoda duruyor → bu bir HATA değil.)
    slides = [f for f in os.listdir(brand) if f.startswith("slide-") and f.endswith(".png")]
    check(f"slayt görselleri repoda ({len(slides)} adet)", len(slides) >= 6, str(slides))

    # 7) Font: Inter diskte (Qt QML font.family: "Inter")
    fonts = os.path.join(ROOT, "overlay/usr/share/fonts/truetype/inter")
    have = [f for f in ("Inter-Regular.ttf", "Inter-SemiBold.ttf", "Inter-Bold.ttf")
            if os.path.exists(os.path.join(fonts, f))]
    check("Inter fontları ISO'ya gömülü (3 ağırlık)", len(have) == 3, f"bulunan: {have}")


def main():
    print("\033[1m╔══════════════════════════════════════════════════╗")
    print("║  MacNix 2.0 — modül ve kütüphane testleri        ║")
    print("╚══════════════════════════════════════════════════╝\033[0m")

    test_library()
    for mod in ("macnix-gpu-detect", "macnix-gpu-config"):
        test_module(mod)
    test_configs()
    test_debian_compat()
    config_tests()

    print("\n\033[1m━━ Özet ━━\033[0m")
    print(f"  geçen: \033[0;32m{len(PASS)}\033[0m   hata: \033[0;31m{len(FAIL)}\033[0m")
    if FAIL:
        print("\n  Hatalar:")
        for name, detail in FAIL:
            print(f"   • {name}  {detail}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
