#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MacNix 2.0 — Calamares modülü: Donanım taraması ve kurulum planı
================================================================
Orijinal koddaki macnix-gpu-detect modülünün yerini alır.

Farkı: hiçbir ekran çizmez, hiçbir şeyi "tahmin" etmez. Donanımı tarar,
GPU veritabanıyla eşleştirir ve planı /var/lib/macnix/install-plan.json
dosyasına yazar. Sonraki adımlar (gpu-config, chroot) bu planı okur.

Calamares tarafında herhangi bir hata kurulumu DÜŞÜRMEZ: passthrough
yapılamıyorsa yazılım render planına düşer, kurulum yine tamamlanır.
"""

import os
import sys
import traceback

import libcalamares

LIB_DIR = "/opt/macnix/scripts"
if LIB_DIR not in sys.path:
    sys.path.insert(0, LIB_DIR)

PLAN_DIR = "/var/lib/macnix"


def pretty_status():
    return "Donanım taranıyor…"


def run():
    libcalamares.utils.debug("MacNix: donanım taraması başlıyor")

    try:
        import macnix_lib as ml
    except Exception:  # noqa: BLE001
        libcalamares.utils.warning(
            "macnix_lib yüklenemedi:\n" + traceback.format_exc())
        # Kütüphane yoksa bile kurulum devam etsin: en güvenli plan
        _fallback_plan()
        return None

    try:
        result = ml.analyze()
        ml.save_profile(result)
        plan = result["plan"]

        # Raporu kurulum günlüğüne ve canlı ortam dosyasına yaz
        lines = _format_report(result)
        with open(os.path.join(PLAN_DIR, "install-plan.txt"), "w") as fh:
            fh.write("\n".join(lines) + "\n")
        for line in lines:
            libcalamares.utils.debug(line)

        libcalamares.globalstorage.insert("macnix_plan", plan)
        libcalamares.globalstorage.insert("macnix_hardware", result["hardware"])
        libcalamares.globalstorage.insert("macnix_arch", plan["arch"])
        libcalamares.globalstorage.insert("macnix_macos", plan["macos_version"])

        # Kullanıcıya uyarıları Calamares arayüzünde de göster
        for w in plan.get("warnings", []):
            libcalamares.utils.warning(w)

        libcalamares.job.setprogress(1.0)
        libcalamares.utils.debug(
            "MacNix: plan hazır — mimari=%s, macOS=%s, passthrough=%s",
            plan["arch"], plan["macos_version"],
            ", ".join(plan["passthrough_gpus"]) or "yok")

    except Exception:  # noqa: BLE001
        # ASLA kurulumu düşürme: sanal makine bir donanım detayı yüzünden
        # kurulmamazlık etmesin. Yazılım render ile devam.
        libcalamares.utils.warning(
            "Donanım analizi sırasında hata:\n" + traceback.format_exc())
        _fallback_plan()
        libcalamares.utils.warning(
            "Kurulum yazılım render (virtio-gpu) planıyla devam ediyor.")

    return None


def _fallback_plan():
    """Analiz başarısız olursa kullanılacak en güvenli plan."""
    plan = {
        "version": "2.0.0",
        "arch": "virtio",
        "performance_expectation": "25-45% (yazılım render)",
        "macos_version": "ventura",
        "macos_name": "macOS 13 Ventura",
        "vm_cores": 2,
        "vm_ram_mb": 4096,
        "passthrough_gpus": [],
        "host_gpus": [],
        "single_gpu": False,
        "needs_amd_patches": False,
        "needs_intel_patches": True,
        "smbios_model": "iMac19,1",
        "cpu_model": "host",
        "warnings": ["Donanım analizi yapılamadı — güvenli varsayılanlar kullanıldı."],
        "recommendations": [],
    }
    try:
        os.makedirs(PLAN_DIR, exist_ok=True)
        import json
        with open(os.path.join(PLAN_DIR, "install-plan.json"), "w") as fh:
            json.dump(plan, fh, indent=2)
    except OSError:
        pass
    libcalamares.globalstorage.insert("macnix_plan", plan)
    libcalamares.globalstorage.insert("macnix_arch", "virtio")


def _format_report(result):
    hw, plan = result["hardware"], result["plan"]
    out = []
    out.append("══ MacNix donanım raporu ══")
    cpu = hw["cpu"]
    out.append(f"CPU          : {cpu['model'] or cpu['vendor']} "
               f"({cpu['cores']}C/{cpu['threads']}T)")
    out.append(f"Sanallaştırma: {'var' if cpu['virt'] else 'YOK'}")
    out.append(f"IOMMU        : {'var' if hw['iommu_enabled'] else 'yok'}")
    out.append(f"RAM          : {hw['mem']['total_mb']} MB")
    for g in hw["gpus"]:
        out.append(f"GPU {g['pci']:>14}: {g['family_name'] or g['desc']}")
        out.append(f"                 macOS desteği: {'VAR' if g['macos_supported'] else 'YOK'}"
                   f" | Metal: {'var' if g['metal'] else 'yok'}")
    out.append(f"Mimari       : {plan['arch']} ({plan['performance_expectation']})")
    out.append(f"macOS        : {plan['macos_name']}")
    out.append(f"VM           : {plan['vm_cores']} çekirdek / {plan['vm_ram_mb']} MB")
    for w in plan.get("warnings", []):
        out.append(f"UYARI: {w}")
    return out
