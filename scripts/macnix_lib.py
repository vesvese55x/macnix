#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MacNix 2.0 — paylaşılan kütüphane
=================================
Donanım algılama, GPU sınıflandırma, macOS sürüm seçimi, VFIO planı ve
OpenCore config üretimi. Hem Calamares modülleri hem de komut satırı
araçları (macnix-tool) bu kütüphaneyi kullanır.

Tek kural: burada hiçbir şey donanımı "varsaymaz". Her karar, algılanan
veriden ve GPU veritabanından (config/gpu-db.json) türetilir.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

VERSION = "2.0.0"

# ── Yollar ───────────────────────────────────────────────────────────────────
DB_CANDIDATES = (
    "/opt/macnix/config/gpu-db.json",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config", "gpu-db.json"),
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "gpu-db.json"),
)
STATE_DIR = "/var/lib/macnix"
PROFILE_PATH = os.path.join(STATE_DIR, "hardware-profile.json")
PLAN_PATH = os.path.join(STATE_DIR, "install-plan.json")

# ── Renkli çıktı ─────────────────────────────────────────────────────────────
def _c(code: str) -> str:
    return code if sys.stdout.isatty() else ""

OK, WARN, ERR, DIM, BOLD = _c("\033[0;32m"), _c("\033[1;33m"), _c("\033[0;31m"), _c("\033[2m"), _c("\033[1m")
RST = _c("\033[0m")


def info(msg: str) -> None:
    print(f"{BOLD}[macnix]{RST} {msg}", flush=True)


def good(msg: str) -> None:
    print(f"{OK}  [ ok ]{RST} {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"{WARN}  [warn]{RST} {msg}", flush=True)


def bad(msg: str) -> None:
    print(f"{ERR}  [fail]{RST} {msg}", flush=True)


# ── Komut yardımcıları ───────────────────────────────────────────────────────
def run(cmd: list[str], timeout: int = 60, check: bool = False) -> subprocess.CompletedProcess:
    """Komut çalıştır; hiçbir zaman istisna fırlatmaz (check=False)."""
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=check)
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
        return subprocess.CompletedProcess(cmd, 127, "", str(exc))


def read(path: str, default: str = "") -> str:
    try:
        with open(path, "r", errors="replace") as fh:
            return fh.read()
    except OSError:
        return default


# ── GPU veritabanı ───────────────────────────────────────────────────────────
def load_db() -> dict:
    for path in DB_CANDIDATES:
        path = os.path.abspath(path)
        if os.path.exists(path):
            try:
                with open(path) as fh:
                    return json.load(fh)
            except (OSError, json.JSONDecodeError) as exc:
                warn(f"GPU veritabanı okunamadı ({path}): {exc}")
    warn("GPU veritabanı bulunamadı — muhafazakâr varsayılanlarla devam")
    return {"families": [], "macos_releases": {}}


def _in_ranges(dev: str, ranges: list) -> bool:
    try:
        val = int(dev, 16)
    except ValueError:
        return False
    for rng in ranges or []:
        try:
            if len(rng) == 2 and isinstance(rng[0], str):
                lo, hi = int(rng[0], 16), int(rng[1], 16)
                if lo <= val <= hi:
                    return True
        except (ValueError, TypeError):
            continue
    return False


def classify_gpu(device_id: str, vendor_id: str, db: dict) -> dict:
    """PCI kimliğinden GPU ailesini bul. Bulunamazsa 'unknown' döner."""
    did = (device_id or "").lower()
    vid = (vendor_id or "").lower()
    for fam in db.get("families", []):
        if fam.get("id_vendor") and fam["id_vendor"] != vid:
            continue
        if did and did in [i.lower() for i in fam.get("ids", [])]:
            return fam
        if fam.get("id_ranges") and _in_ranges(did, fam["id_ranges"]):
            # aralık eşleşmesi sadece vendor da doğruysa geçerli
            if fam.get("vendor") == gpu_vendor_name(vid) or fam.get("id_vendor") == vid:
                return fam
    return {
        "id": "unknown",
        "vendor": gpu_vendor_name(vid),
        "name": f"Bilinmeyen GPU [{vid}:{did}]",
        "macos_supported": False,
        "metal": False,
        "macos_options": [],
        "note": "Bu PCI kimliği veritabanında yok. macOS desteği doğrulanamadı; "
                "yazılım render varsayılacak.",
    }


def gpu_vendor_name(vendor_id: str) -> str:
    return {
        "1002": "amd", "10de": "nvidia", "8086": "intel",
        "1af4": "virtio", "1234": "qemu", "15ad": "vmware", "1b36": "redhat",
    }.get((vendor_id or "").lower(), "unknown")


# ── PCI / donanım taraması ───────────────────────────────────────────────────
def list_pci_gpus() -> list[dict]:
    """lspci ile tüm VGA/3D/Display denetleyicilerini topla."""
    out = run(["lspci", "-Dnn"]).stdout
    gpus = []
    if out:
        cur = None
        for line in out.splitlines():
            m = re.match(r"^([0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7])\s+(.*)$", line)
            if m:
                cur = {"pci": m.group(1), "desc": m.group(2).strip(), "class": "", "driver": ""}
                gpus.append(cur)
                continue
            if cur is not None and line.startswith("\t"):
                if "Kernel driver in use:" in line:
                    cur["driver"] = line.split(":", 1)[1].strip()
                continue
        # sadece ekran sınıfındakiler
        keep = []
        for g in gpus:
            n = run(["lspci", "-nns", g["pci"]]).stdout
            mm = re.search(r"\[([0-9a-f]{4}):([0-9a-f]{4})\]\]?$", n.strip())
            cls = ""
            cm = re.match(r"^[0-9a-f:.]+\s+(\S+):", n.strip())
            if cm:
                cls = cm.group(1)
            g["vid"] = mm.group(1) if mm else ""
            g["did"] = mm.group(2) if mm else ""
            g["class"] = cls
            if cls.startswith("03"):
                keep.append(g)
        return keep

    # lspci yoksa sysfs'ten oku
    base = "/sys/bus/pci/devices"
    if os.path.isdir(base):
        for dev in sorted(os.listdir(base)):
            try:
                cls = read(os.path.join(base, dev, "class")).strip()
            except OSError:
                continue
            if not cls.startswith("0x03"):
                continue
            vid = read(os.path.join(base, dev, "vendor")).strip().replace("0x", "")
            did = read(os.path.join(base, dev, "device")).strip().replace("0x", "")
            drv = ""
            link = os.path.join(base, dev, "driver")
            if os.path.islink(link):
                drv = os.path.basename(os.readlink(link))
            gpus.append({"pci": dev, "desc": f"{vid}:{did}", "vid": vid, "did": did,
                         "class": cls.replace("0x", ""), "driver": drv})
    return gpus


def iommu_group_of(pci: str) -> str:
    path = f"/sys/bus/pci/devices/{pci}/iommu_group"
    if os.path.islink(path):
        return os.path.basename(os.readlink(path))
    return ""


def iommu_members(group: str) -> list[str]:
    d = f"/sys/kernel/iommu_groups/{group}/devices"
    return sorted(os.listdir(d)) if os.path.isdir(d) else []


def iommu_enabled() -> bool:
    d = "/sys/kernel/iommu_groups"
    try:
        return os.path.isdir(d) and len(os.listdir(d)) > 0
    except OSError:
        return False


def cpu_info() -> dict:
    txt = read("/proc/cpuinfo")
    vendor = "unknown"
    model = ""
    flags = set()
    for line in txt.splitlines():
        if line.startswith("vendor_id"):
            vid = line.split(":", 1)[1].strip()
            vendor = {"GenuineIntel": "intel", "AuthenticAMD": "amd"}.get(vid, vid.lower())
        elif line.startswith("model name") and not model:
            model = line.split(":", 1)[1].strip()
        elif line.startswith("flags") and not flags:
            flags = set(line.split(":", 1)[1].split())
    threads = txt.count("processor\t:") or txt.count("processor\t:\n") or len(
        [l for l in txt.splitlines() if l.startswith("processor")])
    cores = threads
    l3 = run(["lscpu"]).stdout
    m = re.search(r"Core\(s\) per socket:\s*(\d+)", l3)
    s = re.search(r"Socket\(s\):\s*(\d+)", l3)
    if m:
        cores = int(m.group(1)) * int(s.group(1)) if s else int(m.group(1))
    numa = 0
    try:
        numa = len(os.listdir("/sys/devices/system/node"))
        numa = len([n for n in os.listdir("/sys/devices/system/node") if n.startswith("node")])
    except OSError:
        numa = 0
    return {
        "vendor": vendor,
        "model": model,
        "threads": threads,
        "cores": cores or threads,
        "virt": bool({"vmx", "svm"} & flags),
        "flags_hypervisor": "hypervisor" in flags,
        "numa_nodes": numa,
        "tsc_deadline": "tsc_deadline_timer" in flags,
        "invtsc": "invtsc" in flags or "nonstop_tsc" in flags,
    }


def mem_info() -> dict:
    txt = read("/proc/meminfo")
    total = 0
    avail = 0
    for line in txt.splitlines():
        if line.startswith("MemTotal:"):
            total = int(line.split()[1]) // 1024
        elif line.startswith("MemAvailable:"):
            avail = int(line.split()[1]) // 1024
    hp_total = hp_free = 0
    for line in txt.splitlines():
        if line.startswith("HugePages_Total:"):
            hp_total = int(line.split()[1])
        elif line.startswith("HugePages_Free:"):
            hp_free = int(line.split()[1])
    return {"total_mb": total, "avail_mb": avail,
            "hugepages_total": hp_total, "hugepages_free": hp_free}


def disk_info(path: str = "/") -> dict:
    try:
        st = os.statvfs(path)
        free_gb = (st.f_bavail * st.f_frsize) / (1024 ** 3)
        total_gb = (st.f_blocks * st.f_frsize) / (1024 ** 3)
    except OSError:
        free_gb = total_gb = 0
    return {"free_gb": round(free_gb, 1), "total_gb": round(total_gb, 1)}


def is_vm() -> bool:
    """Makine zaten bir sanal makine mi? (iç içe VFIO mümkün değilse uyarırız)"""
    dmi = (read("/sys/class/dmi/id/product_name") + read("/sys/class/dmi/id/sys_vendor")).lower()
    return any(k in dmi for k in ("kvm", "qemu", "virtualbox", "vmware", "hyper-v", "bochs", "parallels"))


# ── GPU rolü & plan ──────────────────────────────────────────────────────────
def analyze(profile: dict | None = None) -> dict:
    """
    Tüm donanımı tarar ve bir kurulum planı üretir.

    Dönen sözlük:
      hardware : cpu/mem/disk/gpu/iommu ham verisi
      gpus     : her GPU için sınıflandırma + rol (passthrough|host|unsupported)
      plan     : qemu mimarisi, macOS sürümü, VFIO listesi, öneriler
    """
    db = load_db()
    cpu = cpu_info()
    mem = mem_info()
    disk = disk_info("/")
    raw_gpus = list_pci_gpus()

    gpus = []
    for g in raw_gpus:
        fam = classify_gpu(g.get("did", ""), g.get("vid", ""), db)
        entry = dict(g)
        entry["family"] = fam.get("id")
        entry["family_name"] = fam.get("name")
        entry["macos_supported"] = bool(fam.get("macos_supported"))
        entry["metal"] = bool(fam.get("metal"))
        entry["macos_options"] = fam.get("macos_options", [])
        entry["note"] = fam.get("note", "")
        entry["iommu_group"] = iommu_group_of(g["pci"])
        entry["iommu_members"] = iommu_members(entry["iommu_group"]) if entry["iommu_group"] else []
        gpus.append(entry)

    # ── Rol dağıtımı ────────────────────────────────────────────────────────
    # Bir GPU macOS'ta Metal verebiliyorsa ve IOMMU grubu temizse → passthrough
    passthrough, host_gpus = [], []
    for g in gpus:
        vendor = g.get("vendor") or gpu_vendor_name(g.get("vid", ""))
        if vendor == "virtio" or g.get("family") == "virtio":
            continue
        if g["macos_supported"] and g["class"].startswith("0300"):
            # grup izolasyonu: aynı grupta başka kritik cihaz var mı?
            others = [m for m in g["iommu_members"] if m != g["pci"]]
            g["isolation_ok"] = len(others) <= 3
            passthrough.append(g)
        else:
            host_gpus.append(g)

    # macOS hedef sürümü: donanımın desteklediği en yeni ortak sürüm
    order = ["tahoe", "sequoia", "sonoma", "ventura", "monterey", "bigsur", "catalina"]
    target = None
    if passthrough:
        sets = [set(g["macos_options"]) for g in passthrough if g["macos_options"]]
        common = set.intersection(*sets) if sets else set()
        for cand in order:
            if cand in common:
                target = cand
                break
        if target is None and sets:
            # hiç ortak yok → en yeni desteklenen
            target = next((c for c in order if any(c in s for s in sets)), "sonoma")
    if target is None:
        # passthrough yok: yazılım render, en geniş uyumluluk → Ventura
        target = "ventura"

    # QEMU mimarisi
    if passthrough:
        arch = "vfio"
        perf = "90-100%"
    elif is_vm():
        arch = "virtio"
        perf = "20-40% (VM içinde VM)"
    else:
        arch = "virtio"
        perf = "25-45% (yazılım render)"

    single_gpu = len(gpus) == 1 and len(passthrough) == 1

    # CPU/RAM bütçesi
    total_mb = mem["total_mb"]
    vm_mb = max(4096, int(total_mb * 0.5 / 1024) * 1024)
    vm_mb = min(vm_mb, max(4096, total_mb - 3072))
    vm_cores = max(2, min(cpu["cores"] - 1 if cpu["cores"] > 3 else 2, 16))

    warnings = []
    if not cpu["virt"]:
        warnings.append("CPU sanallaştırma (VT-x/AMD-V) kapalı veya BIOS'ta devre dışı. "
                        "macOS VM'i açılamaz — BIOS'tan SVM/VT-x açılmalı.")
    if not iommu_enabled():
        warnings.append("IOMMU grupları görünmüyor. Gerçek GPU passthrough için BIOS'ta "
                        "IOMMU (AMD-Vi / VT-d) açılmalı ve kernel parametresi eklenmeli.")
    if not passthrough:
        warnings.append("macOS'un sürücü desteği olan bir GPU bulunamadı → yazılım render "
                        "(virtio-gpu). Sistem çalışır ama oyun/video hızlandırma olmaz.")
    if cpu["vendor"] == "amd":
        info("AMD CPU algılandı → macOS çekirdeğine AMD yamaları (AMD_Vanilla) uygulanacak.")
    if single_gpu:
        warnings.append("Tek GPU passthrough senaryosu: macOS açıkken Linux host görüntü veremez; "
                        "çıkış için VNC/SSH yedeği kullanılacak.")
    if mem["total_mb"] < 8192:
        warnings.append(f"RAM {mem['total_mb']} MB — macOS için 8 GB önerilir.")
    if disk["free_gb"] < 60:
        warnings.append(f"Boş disk {disk['free_gb']} GB — macOS diski için en az 60 GB önerilir.")

    hardware = {
        "cpu": cpu, "mem": mem, "disk": disk,
        "iommu_enabled": iommu_enabled(),
        "gpu_count": len(gpus),
        "gpus": gpus,
        "hypervisor": is_vm(),
    }

    plan = {
        "version": VERSION,
        "arch": arch,
        "performance_expectation": perf,
        "macos_version": target,
        "macos_name": db.get("macos_releases", {}).get(target, {}).get("name", target),
        "vm_cores": vm_cores,
        "vm_ram_mb": vm_mb,
        "passthrough_gpus": [g["pci"] for g in passthrough],
        "host_gpus": [g["pci"] for g in host_gpus],
        "single_gpu": single_gpu,
        "needs_amd_patches": cpu["vendor"] == "amd",
        "needs_intel_patches": cpu["vendor"] == "intel",
        "smbios_model": "iMacPro1,1" if cpu["vendor"] == "amd" else "iMac19,1",
        "cpu_model": "Penryn" if cpu["vendor"] == "amd" else "host",
        "warnings": warnings,
        "recommendations": _recommendations(passthrough, target),
    }
    return {"hardware": hardware, "gpus": gpus, "plan": plan}


def _recommendations(passthrough: list, target: str) -> list[str]:
    recs = []
    if passthrough:
        recs.append(f"Passthrough: {', '.join(g['pci'] for g in passthrough)} → macOS {target}")
        for g in passthrough:
            if not g.get("isolation_ok", True):
                recs.append(f"{g['pci']} IOMMU grubunda {len(g['iommu_members'])} cihazla paylaşılıyor — "
                            "ACS override veya farklı PCI yuvası gerekebilir.")
    else:
        recs.append("Donanım hızlandırma için macOS uyumlu AMD kart (RX 580 / RX 6600 ve üstü) eklenebilir.")
    return recs


def save_profile(result: dict) -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(PROFILE_PATH, "w") as fh:
        json.dump(result, fh, indent=2, ensure_ascii=False)
    with open(PLAN_PATH, "w") as fh:
        json.dump(result["plan"], fh, indent=2, ensure_ascii=False)


def load_profile() -> dict | None:
    for p in (PLAN_PATH, PROFILE_PATH):
        if os.path.exists(p):
            try:
                with open(p) as fh:
                    return json.load(fh)
            except (OSError, json.JSONDecodeError):
                continue
    return None


# ── OpenCore config üretimi ──────────────────────────────────────────────────
def _uuid() -> str:
    import uuid
    return str(uuid.uuid4()).upper()


def _rand_hex(n: int) -> str:
    return os.urandom(n // 2).hex().upper()


def gen_serials(model: str) -> dict:
    """macserial varsa onu kullan (gerçek format garantisi), yoksa üret."""
    macserial = shutil.which("macserial")
    if macserial:
        out = run([macserial, "--model", model, "--generate", "--num", "1"]).stdout.strip()
        if out:
            parts = out.split()
            if len(parts) >= 2 and len(parts[0]) >= 10:
                serial, mlb = parts[0], parts[1]
                return {"model": model, "serial": serial, "mlb": mlb,
                        "uuid": _uuid(), "rom": _rand_hex(12), "source": "macserial"}
    # macserial yok: Apple formatına uygun, deterministik olmayan üretim
    year_codes = "CDFGHJKLMNPQRSTVWXYZ"
    suffix = {"iMacPro1,1": "HX87", "iMac19,1": "JV3F", "MacPro7,1": "K7GF",
              "iMac20,1": "JV3G", "Macmini8,1": "JYHT"}.get(model, _rand_hex(4)[:4])
    serial = "C02" + year_codes[os.urandom(1)[0] % len(year_codes)] + \
             f"{os.urandom(1)[0] % 52 + 1:01X}" + _rand_hex(6)[:3] + suffix
    return {"model": model, "serial": serial, "mlb": "C02" + _rand_hex(14)[:14],
            "uuid": _uuid(), "rom": _rand_hex(12), "source": "generated"}


def build_opencore_config(plan: dict, serials: dict, amd_patches: list[dict] | None = None) -> dict:
    """
    OpenCore config.plist'i sözlük olarak üretir.
    Çağıran taraf plistlib ile yazar. Şablon dosyasına bağımlı değildir;
    böylece eski şablonun bozuk/eksik anahtarları miras alınmaz.
    """
    is_amd = plan.get("cpu_vendor") == "amd" or plan.get("needs_amd_patches")
    boot_args = ["-v", "keepsyms=1", "debug=0x100", "alcid=11", "npci=0x2000"]
    if plan.get("arch") == "virtio":
        boot_args += ["-igfxvesa", "nv_disable=1"]
    if not is_amd:
        boot_args = ["-v", "keepsyms=1", "npci=0x2000", "alcid=11"]

    kernel_add = [
        {"BundlePath": "Lilu.kext", "ExecutablePath": "Contents/MacOS/Lilu",
         "PlistPath": "Contents/Info.plist", "Enabled": True, "Comment": "Temel yama altyapisi"},
        {"BundlePath": "VirtualSMC.kext", "ExecutablePath": "Contents/MacOS/VirtualSMC",
         "PlistPath": "Contents/Info.plist", "Enabled": True, "Comment": "SMC emulasyonu"},
        {"BundlePath": "WhateverGreen.kext", "ExecutablePath": "Contents/MacOS/WhateverGreen",
         "PlistPath": "Contents/Info.plist", "Enabled": True, "Comment": "GPU yamalari (AMD)"},
        {"BundlePath": "AppleALC.kext", "ExecutablePath": "Contents/MacOS/AppleALC",
         "PlistPath": "Contents/Info.plist", "Enabled": True, "Comment": "Ses"},
    ]

    cfg = {
        "ACPI": {
            "Add": [], "Delete": [], "Patch": [], "Quirks": {
                "FadtEnableReset": False, "NormalizeHeaders": False, "RebaseRegions": False,
                "ResetHwSig": False, "ResetLogoStatus": True, "SyncTableIds": False,
            },
        },
        "Booter": {
            "MmioWhitelist": [], "Patch": [], "Quirks": {
                "AvoidRuntimeDefrag": True, "DevirtualiseMmio": False, "DisableSingleUser": False,
                "DisableVariableWrite": False, "DiscardHibernateMap": False,
                "EnableSafeModeSlide": True, "EnableWriteUnprotector": False,
                "ForceBooterSignature": False, "ProtectMemoryRegions": False,
                "ProtectSecureBoot": False, "ProtectUefiServices": True,
                "ProvideCustomSlide": True, "ProvideMaxSlide": 0, "RebuildAppleMemoryMap": True,
                "ResizeAppleGpuBars": -1, "SetupVirtualMap": True, "SignalAppleOS": False,
                "SyncRuntimePermissions": True,
            },
        },
        "DeviceProperties": {"Add": {}, "Delete": {}},
        "Kernel": {
            "Add": kernel_add,
            "Block": [],
            "Emulate": {"Cpuid1Data": b"", "Cpuid1Mask": b"", "DummyPowerManagement": False,
                        "MaxKernel": "", "MinKernel": ""},
            "Force": [],
            "Patch": amd_patches or [],
            "Quirks": {
                "AppleCpuPmCfgLock": False, "AppleXcpmCfgLock": False, "AppleXcpmExtraMsrs": False,
                "AppleXcpmForceBoost": False, "CustomSMBIOSGuid": False,
                "DisableIoMapper": True, "DisableLinkeditJettison": True, "DisableRtcChecksum": False,
                "ExtendBTFeatureFlags": False, "ForceAquantiaEthernet": False,
                "LapicKernelPanic": False, "LegacyCommpage": False, "PanicNoKextDump": True,
                "PowerTimeoutKernelPanic": True, "ProvideCurrentCpuInfo": is_amd,
                "SetApfsTrimTimeout": -1, "ThirdPartyDrives": False, "XhciPortLimit": True,
            },
            "Scheme": {"FuzzyMatch": True, "KernelArch": "x86_64", "KernelCache": "Auto"},
        },
        "Misc": {
            "Boot": {"HideAuxiliary": False, "PickerMode": "Builtin", "PickerAttributes": 17,
                     "Timeout": 3, "ShowPicker": True, "PollAppleHotKeys": True,
                     "TakeoffDelay": 0, "HideAuxiliary": False},
            "Debug": {"AppleDebug": False, "ApplePanic": True, "DisableWatchDog": True,
                      "DisplayDelay": 0, "DisplayLevel": 0, "SerialInit": False,
                      "SysReport": False, "Target": 3},
            "Security": {"AllowSetDefault": True, "BlacklistAppleUpdate": True, "DmgLoading": "Signed",
                         "EnablePassword": False, "ExposeSensitiveData": 6, "HaltLevel": 2147483650,
                         "ScanPolicy": 0, "SecureBootModel": "Disabled", "Vault": "Optional"},
            "Tools": [],
        },
        "NVRAM": {
            "Add": {
                "7C436110-AB2A-4BBB-A880-FE41995C9F82": {
                    "boot-args": " ".join(boot_args),
                    "csr-active-config": bytes([0x67, 0x03, 0x00, 0x00]),
                    "prev-lang:kbd": b"en-US:0",
                    "run-efi-updater": "No",
                    "ForceDisplayRotationInEFI": 0,
                },
                "4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14": {
                    "UIScale": bytes([0x02]),
                    "DefaultBackgroundColor": bytes([0x00, 0x00, 0x00, 0x00]),
                },
            },
            "Delete": {
                "7C436110-AB2A-4BBB-A880-FE41995C9F82": ["boot-args", "csr-active-config"],
                "4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14": [],
            },
            "LegacyOverwrite": False,
            "LegacySchema": {},
            "WriteFlash": True,
        },
        "PlatformInfo": {
            "Automatic": True,
            "CustomMemory": False,
            "Generic": {
                "AdviseFeatures": True,
                "MLB": serials["mlb"],
                "ROM": bytes.fromhex(serials["rom"]),
                "SpoofVendor": True,
                "SystemMemoryStatus": "Auto",
                "SystemProductName": serials["model"],
                "SystemSerialNumber": serials["serial"],
                "SystemUUID": serials["uuid"],
            },
            "UpdateDataHub": True,
            "UpdateNVRAM": True,
            "UpdateSMBIOS": True,
            "UpdateSMBIOSMode": "Create",
            "UseRawUuidEncoding": False,
        },
        "UEFI": {
            "APFS": {"EnableJumpstart": True, "GlobalConnect": False, "HideVerbose": True,
                     "JumpstartHotPlug": False, "MinDate": 0, "MinVersion": 0},
            "Audio": {"AudioCodec": 0, "AudioDevice": "", "AudioOut": 0, "AudioSupport": False,
                      "MinimumVolume": 20, "PlayChime": "Auto", "ResetTrafficClass": False,
                      "SetupDelay": 0, "VoiceOver": False},
            "ConnectDrivers": True,
            "Drivers": [
                {"Path": "OpenRuntime.efi", "Enabled": True, "LoadEarly": False, "Comment": "Zorunlu runtime"},
                {"Path": "OpenHfsPlus.efi", "Enabled": True, "LoadEarly": False, "Comment": "HFS+ okuma"},
                {"Path": "ResetNvramEntry.efi", "Enabled": True, "LoadEarly": False, "Comment": "NVRAM sifirlama"},
            ],
            "Input": {"KeyFiltering": False, "KeyForgetThreshold": 5, "KeySupport": True,
                      "KeySupportMode": "Auto", "KeyMergeThreshold": 2, "KeySupport": True,
                      "PointerSupport": False, "PointerSupportMode": "", "TimerResolution": 50000},
            "Output": {"ClearScreenOnModeSwitch": True, "ConsoleMode": "", "DirectGopRendering": False,
                       "ForceResolution": False, "GopBurstMode": False, "IgnoreTextInGraphics": False,
                       "InitialMode": "Auto", "ProvideConsoleGop": True, "ReconnectGraphicsOnConnect": False,
                       "ReconnectOnResChange": False, "ReplaceTabWithSpace": False,
                       "Resolution": "Max", "SanitiseClearScreen": False, "TextRenderer": "BuiltinGraphics",
                       "UgaPassThrough": False},
            "ProtocolOverrides": {
                "AppleAudio": False, "AppleBootPolicy": False, "AppleDebugLog": False,
                "AppleEg2Info": False, "AppleFramebufferInfo": False, "AppleImageConversion": False,
                "AppleImg4Verification": False, "AppleKeyMap": False, "AppleRtcRam": False,
                "AppleSecureBoot": False, "AppleSmcIo": False, "AppleUserInterfaceTheme": False,
                "DataHub": False, "DeviceProperties": False, "FirmwareVolume": False,
                "HashServices": False, "OSInfo": False, "UnicodeCollation": False,
            },
            "Quirks": {
                "ActivateHpetSupport": False, "DisableSecurityPolicy": False,
                "EnableVectorAcceleration": True, "EnableVmx": False, "ExitBootServicesDelay": 0,
                "ForceOemVolumeHack": False, "IgnoreInvalidFlexRatio": False,
                "ReleaseUsbOwnership": True, "RequestBootVarRouting": True,
                "ResizeGpuBars": -1, "TscSyncTimeout": 0, "UnblockFsConnect": False,
            },
            "ReservedMemory": [],
            "DriveInput": {},
        },
    }
    return cfg


def write_plist(cfg: dict, path: str) -> None:
    import plistlib
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        plistlib.dump(cfg, fh, sort_keys=False)


def read_amd_patches(path: str) -> list[dict]:
    """AMD_Vanilla patches.plist → OpenCore Kernel.Patch dizisi."""
    import plistlib
    if not os.path.exists(path):
        return []
    try:
        with open(path, "rb") as fh:
            data = plistlib.load(fh)
        return data.get("Kernel", {}).get("Patch", [])
    except Exception as exc:  # noqa: BLE001
        warn(f"AMD yamaları okunamadı: {exc}")
        return []


# ── Human-readable rapor ─────────────────────────────────────────────────────
def print_report(result: dict) -> None:
    hw, plan = result["hardware"], result["plan"]
    print()
    print(f"{BOLD}══ Donanım ══════════════════════════════════════════════{RST}")
    cpu = hw["cpu"]
    print(f"  CPU        : {cpu['model'] or cpu['vendor']} "
          f"({cpu['cores']}C/{cpu['threads']}T, {cpu['vendor']})")
    print(f"  Sanallaştırma: {'var' if cpu['virt'] else 'YOK !'}   "
          f"IOMMU: {'var' if hw['iommu_enabled'] else 'yok'}")
    print(f"  RAM        : {hw['mem']['total_mb']} MB (boş: {hw['mem']['avail_mb']} MB)")
    print(f"  Disk (/)   : {hw['disk']['free_gb']} GB boş / {hw['disk']['total_gb']} GB")
    print()
    print(f"{BOLD}══ Grafik ═══════════════════════════════════════════════{RST}")
    if not hw["gpus"]:
        print("  GPU bulunamadı")
    for g in hw["gpus"]:
        mark = f"{OK}macOS✓{RST}" if g["macos_supported"] else f"{WARN}macOS✗{RST}"
        print(f"  {g['pci']}  {mark}  {g['family_name'] or g['desc']}")
        if g.get("note"):
            print(f"      {DIM}{g['note']}{RST}")
    print()
    print(f"{BOLD}══ Kurulum planı ════════════════════════════════════════{RST}")
    print(f"  Mimari       : {plan['arch']}  (beklenen performans: {plan['performance_expectation']})")
    print(f"  macOS        : {plan['macos_name']}")
    print(f"  VM kaynak    : {plan['vm_cores']} çekirdek, {plan['vm_ram_mb']} MB RAM")
    print(f"  SMBIOS       : {plan['smbios_model']} / CPU model: {plan['cpu_model']}")
    if plan["passthrough_gpus"]:
        print(f"  Passthrough  : {', '.join(plan['passthrough_gpus'])}")
    for r in plan.get("recommendations", []):
        print(f"  {DIM}• {r}{RST}")
    if plan["warnings"]:
        print()
        print(f"{WARN}══ Uyarılar ═════════════════════════════════════════════{RST}")
        for w in plan["warnings"]:
            print(f"  ! {w}")
    print()


if __name__ == "__main__":
    res = analyze()
    save_profile(res)
    print_report(res)
    good(f"Profil kaydedildi: {PROFILE_PATH}")
