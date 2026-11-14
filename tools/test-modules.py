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
    missing = []
    for mod in flat:
        if isinstance(mod, dict):
            conf_name = mod.get("config")
            mod_id = mod.get("id", mod.get("module", "?"))
            if not conf_name or not os.path.exists(
                    os.path.join(ROOT, "calamares", "module-conf", conf_name)):
                missing.append(mod_id)
            continue
        conf = os.path.join(ROOT, "calamares", "module-conf", f"{mod}.conf")
        if not os.path.exists(conf):
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

    # notes/notesqml: Debian'da "notes" YOK. "notesqml" QML modülleri ister.
    check("sequence 'notes' (Debian'da yok) kullanmıyor", "notes" not in flat, str(flat))
    check("notesqml notlar için kullanılıyor", "notesqml" in flat)

    # 3) kullanılmayan örnek (instances) tanımı yok
    check("settings.conf 'instances' içermiyor", "instances" not in st)

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
    fb_conf = os.path.join(ROOT, "calamares/module-conf/macnix-efi-fallback.conf")
    check("EFI yedek adımı yapılandırması var", os.path.isfile(fb_conf))
    if os.path.isfile(fb_conf):
        fbc = open(fb_conf).read()
        check("EFI yedeği BOOTX64.EFI yazıyor", "BOOTX64.EFI" in fbc)
        check("EFI yedeği BOOTIA32.EFI (32-bit UEFI) da destekliyor", "BOOTIA32.EFI" in fbc)
        check("EFI yedeği yoksa kurulumu durdurmuyor", "exit 0" in fbc)
        check("EFI yedeği hedef sistemde (chroot) çalışıyor", "dontChroot: false" in fbc)
    st = open(os.path.join(ROOT, "calamares/settings.conf")).read()
    check("EFI yedek adımı exec listesinde",
          "macnix-efi-fallback" in st and "config: macnix-efi-fallback.conf" in st)
    i_bl = st.find("- bootloader")
    i_fb = st.find("macnix-efi-fallback")
    i_um = st.find("- umount")
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
    check("build.sh GRUB EFI modüllerini sistemde var olanlardan süzüyor",
          '[[ -f "$moddir/$m.mod" ]]' in build and 'missing+=' in build)

    check("build.sh /etc sahipliğini root'a çekiyor",
          "chown -R 0:0" in build and "$ROOTFS/etc" in build)
    # sıra kritik: chown overlay kopyasından SONRA çalışmalı
    i_ov = build.find('cp -a "${ROOT}/overlay/."')
    i_fixown = build.find("fix_ownership\n  fix_lightdm_autologin")
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

    # 11) lightdm autologin: Debian'ın "user" hesabı ezilmiş olmalı
    check("build.sh lightdm.conf'taki autologin-user=user satırını etkisizleştiriyor",
          "autologin-user" in build and "lightdm.conf" in build)
    # sıra kritik: düzeltme overlay kopyasından SONRA çalışmalı
    i_overlay = build.find('cp -a "${ROOT}/overlay/."')
    i_fix = build.find("fix_lightdm_autologin\n  ok")
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


def main():
    print("\033[1m╔══════════════════════════════════════════════════╗")
    print("║  MacNix 2.0 — modül ve kütüphane testleri        ║")
    print("╚══════════════════════════════════════════════════╝\033[0m")

    test_library()
    for mod in ("macnix-gpu-detect", "macnix-gpu-config"):
        test_module(mod)
    test_configs()
    test_debian_compat()

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
