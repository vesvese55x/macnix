#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MacNix 2.0 — Calamares modülü: VM yapılandırması (kurulum hedefi içine)
=======================================================================
Kurulum sırasında hedef kök dosya sistemine (/root) şunları yazar:

  /etc/macnix/install-plan.json     donanım planı
  /etc/macnix/vm.conf               VM kaynakları (çekirdek/RAM/hugepage)
  /etc/macnix/smbios.json           Apple kimliği
  /etc/macnix/vfio.conf             passthrough PCI adresleri
  /etc/modprobe.d/macnix-*.conf     vfio / kvm ayarları
  /etc/modules-load.d/macnix-*.conf
  /etc/default/grub                 IOMMU parametreleri
  /opt/macnix/...                   betikler (unpackfs zaten kopyaladı)
  /var/lib/macnix/.preinstalled     hazırlık işareti

macOS indirmesi BURADA YAPILMAZ. Kurulum biter, makine yeniden başlar,
ilk açılışta "MacNix Kurulum Sihirbazı" (macnix-setup) macOS imajını indirir.
Böylece hem kurulum süresi kısalır hem de ağ hatası kurulumu bozmaz.
"""

import json
import os
import subprocess
import sys

import libcalamares

PLAN_PATH = "/var/lib/macnix/install-plan.json"


def pretty_status():
    return "MacNix yapılandırılıyor…"


def _resolve_root(root):
    """Hedef kök dizini güvenilir biçimde bul.

    ÖLÇÜLEN HATA (VM testi, kurulu sistemde macnix-doctor):
        kritik: /etc/macnix/vm.conf yok — kurulum tamamlanmamış
    Neden: Calamares 3.2 Python işleri hedefe **chroot edilmiş** olarak
    çalıştırılabilir. Bu durumda globalstorage'daki rootMountPoint
    (örn. /tmp/calamares-root-abc) chroot içinde VAR OLMAZ; os.makedirs()
    ve open() bu yüzden hata verir. Eski kod bu hatayı yakalamadığı için
    modül "başarılı" görünüp HİÇBİR ŞEY yazmıyordu.

    Sıra:
      1) rootMountPoint gerçekten varsa onu kullan (chroot'suz durum)
      2) yoksa ve "/" bir kök dosya sistemi gibi görünüyorsa "/" kullan
         (chroot içindeyiz → "/" hedefin kendisidir)
      3) ikisi de olmazsa None (bu gerçek bir hatadır, çağıran hata döndürür)
    """
    if not root:
        return None
    # 1) Verilen kök gerçekten bir hedef kök gibi mi? (chroot'suz normal durum)
    #    Calamares hedefin içine calamares/ ve tmp/ dizinleri kurar; bunların
    #    varlığı "burası hedef kök" için güçlü kanıttır.
    if os.path.isdir(root) and (os.path.isdir(os.path.join(root, "etc"))
                                or os.path.isdir(os.path.join(root, "calamares"))
                                or os.path.isdir(os.path.join(root, "tmp"))):
        return root
    # 2) chroot içindeyiz ve verilen yol yok → "/" hedefin kendisidir.
    #    (VM testinde birebir görüldü: Calamares Python işleri hedefe chroot
    #     edilmiş çalışıyor, rootMountPoint chroot içinde mevcut değil.)
    if os.path.isdir("/etc") and os.path.isdir("/usr"):
        return "/"
    # 3) Son çare: verilen yol (varsa)
    return root if os.path.isdir(root) else None


def _write(path, content, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(content)
    os.chmod(path, mode)


def _run(cmd, cwd=None):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=300, cwd=cwd)
        if res.returncode != 0:
            libcalamares.utils.warning(f"komut başarısız: {' '.join(cmd)}\n{res.stderr[:500]}")
        return res
    except Exception as exc:  # noqa: BLE001
        libcalamares.utils.warning(f"komut hatası: {' '.join(cmd)}: {exc}")
        return None


def run():
    """Calamares job girişi.

    NOT: Bu modül kurulumun EN SONUNDA çalışır. Burada yakalanmamış bir istisna
    tüm kurulumu "başarısız" gösterir. Bu yüzden çekirdek yazma işlemleri
    kendi hata korumalarını taşır; burada yalnızca hedef kök yokluğu gibi
    gerçekten kurtarılamaz durumlar hata olarak döner.
    """
    root = _resolve_root(libcalamares.globalstorage.value("rootMountPoint"))
    if not root:
        return ("Kurulum hedefi bulunamadı", "rootMountPoint boş — bölümleme başarısız olmuş olabilir.")

    # Planı bul: globalstorage → canlı ortam dosyası → güvenli varsayılan
    plan = libcalamares.globalstorage.value("macnix_plan")
    if not plan:
        for cand in (PLAN_PATH, "/etc/macnix/install-plan.json"):
            if os.path.exists(cand):
                try:
                    with open(cand) as fh:
                        plan = json.load(fh)
                    break
                except (OSError, json.JSONDecodeError):
                    pass
    if not plan:
        libcalamares.utils.warning(
            "Kurulum planı bulunamadı — yazılım render varsayılanları kullanılıyor")
        plan = {
            "arch": "virtio", "macos_version": "ventura", "vm_cores": 2, "vm_ram_mb": 4096,
            "passthrough_gpus": [], "host_gpus": [], "single_gpu": False,
            "smbios_model": "iMac19,1", "cpu_model": "host",
            "needs_amd_patches": False, "warnings": [], "recommendations": [],
        }

    libcalamares.job.setprogress(0.05)

    # ── /etc/macnix ─────────────────────────────────────────────────────────
    macnix_dir = os.path.join(root, "etc/macnix")
    os.makedirs(macnix_dir, exist_ok=True)
    _write(os.path.join(macnix_dir, "install-plan.json"),
           json.dumps(plan, indent=2, ensure_ascii=False))

    vm_ram = int(plan.get("vm_ram_mb") or 4096)
    vm_cores = int(plan.get("vm_cores") or 2)
    # 2 MB'lik sayfalar: gereken sayfa sayısı = RAM(MB) / 2
    # ESKİ HATA: (vm_ram // 2) * 512 → 4096 MB için 1 048 576 sayfa = 2 TB istek.
    # Bu, macnix-hugepages.service'in her açılışta başarısız olmasına yol açar.
    hugepages = max(1, vm_ram // 2)
    _write(os.path.join(macnix_dir, "vm.conf"), f"""# MacNix 2.0 — VM kaynakları (kurulumda otomatik hesaplandı)
VM_CORES={vm_cores}
VM_RAM_MB={vm_ram}
HUGEPAGES={hugepages}
HUGEPAGE_SIZE=2M
MACOS_VERSION={plan.get('macos_version', 'ventura')}
ARCH_PROFILE={plan.get('arch', 'virtio')}
""")

    # SMBIOS — gerçek üretim burada yapılır (macserial varsa onunla)
    serials = _generate_serials(plan.get("smbios_model", "iMac19,1"))
    _write(os.path.join(macnix_dir, "smbios.json"), json.dumps(serials, indent=2))

    libcalamares.job.setprogress(0.2)

    # ── VFIO / KVM ─────────────────────────────────────────────────────────
    passthrough = plan.get("passthrough_gpus") or []
    os.makedirs(os.path.join(root, "etc/modprobe.d"), exist_ok=True)
    os.makedirs(os.path.join(root, "etc/modules-load.d"), exist_ok=True)

    _write(os.path.join(root, "etc/modprobe.d/macnix-kvm.conf"),
           "# MacNix — macOS'un okuduğu MSR'leri yoksay\n"
           "options kvm ignore_msrs=1 report_ignored_msrs=0\n")

    if passthrough:
        ids = []
        for entry in passthrough:
            # plan sadece PCI adresi taşır; kimliği sysfs'ten tamamla
            vid = _sysfs(root, entry, "vendor")
            did = _sysfs(root, entry, "device")
            if vid and did:
                ids.append(f"{vid}:{did}")
            # aynı IOMMU grubundaki HDMI ses cihazını da ekle
            grp = _iommu_group(entry)
            for member in _group_members(grp):
                if _class_of(member).startswith("0x0403"):
                    av = _sysfs(None, member, "vendor")
                    ad = _sysfs(None, member, "device")
                    if av and ad:
                        ids.append(f"{av}:{ad}")

        if ids:
            _write(os.path.join(root, "etc/modprobe.d/macnix-vfio.conf"),
                   f"# MacNix — GPU passthrough\noptions vfio-pci ids={','.join(ids)}\n"
                   "softdep amdgpu pre: vfio-pci\nsoftdep radeon pre: vfio-pci\n"
                   "softdep nouveau pre: vfio-pci\nsoftdep nvidia pre: vfio-pci\n")
            _write(os.path.join(root, "etc/modules-load.d/macnix-vfio.conf"),
                   "vfio\nvfio_iommu_type1\nvfio_pci\n")
            _write(os.path.join(macnix_dir, "vfio.conf"),
                   f"VFIO_IDS=\"{','.join(ids)}\"\nVFIO_PCI=\"{' '.join(passthrough)}\"\n")
            libcalamares.utils.debug(f"VFIO kimlikleri: {ids}")
    else:
        libcalamares.utils.debug("Passthrough GPU yok — yazılım render yapılandırılıyor")

    libcalamares.job.setprogress(0.4)

    # ── GRUB: IOMMU + performans parametreleri ─────────────────────────────
    grub_path = os.path.join(root, "etc/default/grub")
    _patch_grub(grub_path, plan)
    libcalamares.job.setprogress(0.55)

    # ── systemd birimlerini etkinleştir ────────────────────────────────────
    wants = os.path.join(root, "etc/systemd/system/multi-user.target.wants")
    os.makedirs(wants, exist_ok=True)
    for unit in ("macnix-vm.service", "macnix-firstboot.service"):
        src = os.path.join(root, "etc/systemd/system", unit)
        if os.path.exists(src):
            link = os.path.join(wants, unit)
            if not os.path.lexists(link):
                os.symlink("/etc/systemd/system/" + unit, link)

    graphical = os.path.join(root, "etc/systemd/system/graphical.target.wants")
    os.makedirs(graphical, exist_ok=True)
    for unit in ("macnix-console.service",):
        src = os.path.join(root, "etc/systemd/system", unit)
        if os.path.exists(src):
            link = os.path.join(graphical, unit)
            if not os.path.lexists(link):
                os.symlink("/etc/systemd/system/" + unit, link)

    # hazırlık işareti: macOS imajı henüz yok
    varlib = os.path.join(root, "var/lib/macnix")
    for sub in ("disks", "firmware", "logs"):
        os.makedirs(os.path.join(varlib, sub), exist_ok=True)
    _write(os.path.join(varlib, ".preinstalled"), "yes\n")

    libcalamares.job.setprogress(0.8)

    # ── initramfs + GRUB güncelle (chroot içinde) ──────────────────────────
    for cmd in (["update-initramfs", "-u", "-k", "all"], ["update-grub"]):
        try:
            subprocess.run(["chroot", root] + cmd, capture_output=True, text=True, timeout=900)
        except Exception as exc:  # noqa: BLE001
            libcalamares.utils.warning(f"chroot {' '.join(cmd)}: {exc}")

    libcalamares.job.setprogress(1.0)
    libcalamares.utils.debug("MacNix: hedef sistem yapılandırıldı")
    return None


# ── yardımcılar ─────────────────────────────────────────────────────────────

def _sysfs(root, pci, attr):
    base = "/sys/bus/pci/devices"
    for path in ([os.path.join(base, pci, attr)] if not root else
                 [os.path.join(base, pci, attr)]):
        try:
            with open(path) as fh:
                return fh.read().strip().replace("0x", "")
        except OSError:
            continue
    return ""


def _iommu_group(pci):
    link = f"/sys/bus/pci/devices/{pci}/iommu_group"
    if os.path.islink(link):
        return os.path.basename(os.readlink(link))
    return ""


def _group_members(group):
    d = f"/sys/kernel/iommu_groups/{group}/devices"
    return sorted(os.listdir(d)) if os.path.isdir(d) else []


def _class_of(pci):
    try:
        with open(f"/sys/bus/pci/devices/{pci}/class") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def _generate_serials(model):
    sys.path.insert(0, "/opt/macnix/scripts")
    try:
        import macnix_lib as ml
        return ml.gen_serials(model)
    except Exception:  # noqa: BLE001
        import uuid
        return {"model": model,
                "serial": "C02" + os.urandom(6).hex().upper()[:6] + "JV3F",
                "mlb": "C02" + os.urandom(7).hex().upper(),
                "uuid": str(uuid.uuid4()).upper(),
                "rom": os.urandom(6).hex().upper(),
                "source": "fallback"}


def _patch_grub(path, plan):
    """GRUB komut satırına IOMMU ve performans parametreleri ekle (idempotent)."""
    params = []
    if plan.get("arch") == "vfio":
        cpu_vendor = ""
        try:
            with open("/proc/cpuinfo") as fh:
                for line in fh:
                    if line.startswith("vendor_id"):
                        cpu_vendor = line.split(":", 1)[1].strip()
                        break
        except OSError:
            pass
        params.append("intel_iommu=on" if cpu_vendor == "GenuineIntel" else "amd_iommu=on")
        params += ["iommu=pt", "vfio_iommu_type1.allow_unsafe_interrupts=1"]
    params += ["amd_pstate=active" if _is_amd_cpu() else "intel_pstate=active"]
    params += ["transparent_hugepage=always", "nowatchdog"]

    if os.path.exists(path):
        with open(path) as fh:
            lines = fh.read().splitlines()
    else:
        lines = ['GRUB_DEFAULT=0', 'GRUB_TIMEOUT=3',
                 'GRUB_CMDLINE_LINUX_DEFAULT=""', 'GRUB_CMDLINE_LINUX=""']

    out, seen = [], False
    for line in lines:
        if line.startswith("GRUB_CMDLINE_LINUX_DEFAULT="):
            seen = True
            existing = line.split("=", 1)[1].strip().strip('"')
            merged = existing
            for p in params:
                key = p.split("=")[0]
                if key not in merged:
                    merged = (merged + " " + p).strip()
            out.append(f'GRUB_CMDLINE_LINUX_DEFAULT="{merged}"')
        elif line.startswith("GRUB_TIMEOUT="):
            out.append("GRUB_TIMEOUT=3")
        elif line.startswith("GRUB_TIMEOUT_STYLE="):
            out.append("GRUB_TIMEOUT_STYLE=menu")
        elif line.startswith("GRUB_CMDLINE_LINUX="):
            out.append(line)
        else:
            out.append(line)
    if not seen:
        out.append(f'GRUB_CMDLINE_LINUX_DEFAULT="{" ".join(params)}"')

    # SAĞLAMLIK: /etc/default/grub yoksa üst dizini de yoktur (bu, Calamares'in
    # hedef kökünde beklenmedik bir durumdur). Klasik hata:
    #     FileNotFoundError: '/mnt/etc/default/grub'
    # → modül çöker, VM yapılandırması hiç yazılmaz (macnix-doctor kritik verir).
    # Artık: dizini oluştur; yine yazamazsak UYARI ver ama modülü DÜŞÜRME.
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write("\n".join(out) + "\n")
    except OSError as exc:  # noqa: BLE001
        libcalamares.utils.warning(
            f"GRUB varsayılanları yazılamadı ({path}): {exc} — "
            "IOMMU/hugepage parametreleri eklenmedi, kurulum sürüyor")


def _is_amd_cpu():
    try:
        with open("/proc/cpuinfo") as fh:
            return "AuthenticAMD" in fh.read()
    except OSError:
        return False
