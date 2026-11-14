#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
MacNix 2.0 — Calamares job: UEFI yedek önyükleyici (\EFI\BOOT\BOOTX64.EFI)
==========================================================================

NEDEN GEREKLİ (ölçüldü, tahmin değil)
-------------------------------------
bootloader.conf içindeki `installEFIFallback: true` anahtarı Debian'ın
Calamares 3.2 derlemesinde TANINMIYOR. Sonuç: GRUB yalnızca
\EFI\MacNix\grubx64.efi olarak yazılıyor. NVRAM girdisi olmayan (veya UEFI
menüsünden girdisi silinmiş) makinelerde firmware diskteki tek yedek yolu,
yani \EFI\BOOT\BOOTX64.EFI'yi arar ve bulamayınca doğrudan UEFI kabuğuna düşer:

    UEFI Interactive Shell v2.2
    Shell> _                        ← sistem açılmıyor

Aynı diskte elle `fs0:\EFI\MacNix\grubx64.efi` çalıştırıldığında GRUB açılıp
sistem sorunsuz önyükleniyor → sorun GRUB'da değil, yedek yolun eksikliğinde.

NEDEN shellprocess DEĞİL
------------------------
Bu adım önce `settings.conf` içinde `instances:` + shellprocess örneği olarak
tanımlandı. Canlı testte Calamares şunu verdi:

    Calamares Initialization Failed
    The following modules could not be loaded:
      • macnix-efi-fallback@macnix-efi-fallback

Yani Debian Calamares 3.2'de shellprocess örnekleri güvenilir yüklenmiyor.
Yerel **Python job** modülleri ise (macnix-gpu-detect, macnix-gpu-config)
sorunsuz yükleniyor; bu yüzden aynı iş burada saf Python ile yapılıyor:
harici komut, yapılandırma dosyası ve örnek mekanizması yok.

DAVRANIŞ
--------
- Hata durumunda kurulumu DURDURMAZ: uyarı yazar, devam eder.
- BIOS kurulumunda EFI bölümü yoktur → sessizce atlar.
- Idempotent: yedek zaten varsa üzerine yazmaz.
"""

import os
import shutil

import libcalamares

EFI_DIR = "/boot/efi/EFI"
# GRUB'un yazdığı olası yollar (önyükleyici kimliği değişebilir)
SOURCE_NAMES = ("grubx64.efi", "grubia32.efi", "grubaa64.efi")
DEST = {
    "grubx64.efi": "BOOTX64.EFI",
    "grubia32.efi": "BOOTIA32.EFI",
    "grubaa64.efi": "BOOTAA64.EFI",
}


def _resolve_root(root):
    """Hedef kök dizini bul (chroot'lu çalışma dahil).

    Calamares Python işleri hedefe chroot edilmiş çalışabilir; o durumda
    globalstorage'daki rootMountPoint chroot içinde yoktur ve "/" hedefin
    kendisidir.
    """
    if not root:
        return None
    if os.path.isdir(root) and (os.path.isdir(os.path.join(root, "etc"))
                                or os.path.isdir(os.path.join(root, "tmp"))):
        return root
    if os.path.isdir("/etc") and os.path.isdir("/usr"):
        return "/"
    return root if os.path.isdir(root) else None


def _find_source(efi_root):
    """GRUB'un yazdığı EFI ikilisini bul; aynı zamanda BIOS'ta atlanır."""
    if not os.path.isdir(efi_root):
        return None
    for vendor in sorted(os.listdir(efi_root)):
        vendor_dir = os.path.join(efi_root, vendor)
        if not os.path.isdir(vendor_dir) or vendor.upper() == "BOOT":
            continue
        for name in SOURCE_NAMES:
            path = os.path.join(vendor_dir, name)
            if os.path.isfile(path):
                return path, name
    return None


def run():
    root = _resolve_root(libcalamares.globalstorage.value("rootMountPoint"))
    if not root:
        return ("Kurulum hedefi bulunamadı",
                "rootMountPoint boş — bölümleme başarısız olmuş olabilir.")

    efi_root = os.path.join(root, "boot/efi/EFI")
    found = _find_source(efi_root)
    if not found:
        # BIOS kurulumu ya da EFI bölümü bağlı değil: bu bir HATA değil.
        libcalamares.utils.debug(
            "MacNix: GRUB EFI ikilisi yok — yedek atlandı (BIOS kurulumu olabilir)")
        return None

    src, name = found
    dest_dir = os.path.join(efi_root, "BOOT")
    dest = os.path.join(dest_dir, DEST[name])
    try:
        os.makedirs(dest_dir, exist_ok=True)
        if os.path.isfile(dest):
            libcalamares.utils.debug(f"MacNix: UEFI yedeği zaten var -> {dest}")
        else:
            shutil.copy2(src, dest)
            libcalamares.utils.debug(f"MacNix: UEFI yedeği oluşturuldu -> {dest}")
    except OSError as exc:  # noqa: BLE001
        # Kurulumu DÜŞÜRME: yedek yalnızca NVRAM'i boş makineler için gerekli.
        libcalamares.utils.warning(
            f"UEFI yedek önyükleyici yazılamadı ({dest}): {exc} — kurulum sürüyor")
    return None
