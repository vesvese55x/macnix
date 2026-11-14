# MacNix 2.0 — Donanım Uyumluluğu

MacNix'in **her donanımda** kurulup çalıştığını, ama "çalışıyor" ile
"hızlandırmalı çalışıyor" arasındaki farkı dürüstçe anlatan belge.

Kısa özet: **kurulum her GPU'da (ve hiç GPU olmayan sistemlerde) başarılıdır.**
macOS içindeki grafik hızlandırma ise yalnızca Apple'ın sürücüsü olan AMD
kartlarda mümkündür.

---

## 1. Üç çalışma modu

| Mod | Ne olur | Hangi donanım |
|---|---|---|
| **VFIO passthrough** | Fiziksel GPU doğrudan macOS VM'ine verilir. Metal, oyun, video kodlama çalışır. | macOS sürücüsü olan AMD kartlar + IOMMU |
| **Yazılım render (virtio-gpu)** | macOS RAM/CPU ile çizer. Masaüstü, tarayıcı, ofis akıcı; oyun/video kodlama yok. | **Diğer her şey** — NVIDIA, Intel iGPU, eski AMD, GPU'suz sunucu |
| **Başsız (headless)** | VM açılır, ekran VNC/SPICE ile alınır. | GPU hiç yoksa |

Seçim otomatik yapılır:

- `config/gpu-db.json` (14 aile) PCI kimliğine bakar.
- `macnix_lib.py` → `arch: "vfio"` veya `arch: "virtio"` kararı verir.
- Karar Calamares'in "Donanım raporu" ekranında ve kurulum sonrası
  `/etc/macnix/install-plan.json` içinde yazılıdır.
- `sudo macnix-gpu-mode` ile elle de değiştirilebilir.

---

## 2. macOS sürücüsü OLAN AMD kartlar (tam hız)

Kaynak: Apple'ın kapalı kaynak AMD kextleri + WhateverGreen / AMD_Vanilla.

| Aile | Örnek kartlar | macOS sürümü |
|---|---|---|
| Polaris 10/20 | RX 470/480/570/580/590 | 10.12+ |
| Vega 10/20 | Vega 56/64, Radeon VII | 10.13+ |
| Navi 10 | RX 5500 XT / 5600 XT / 5700 XT | 10.15+ |
| Navi 21 | RX 6600 / 6600 XT / 6800 / 6900 XT | 11+ |
| Navi 22/23 | RX 6650 XT / 6750 XT / 6950 XT / 7600 | 12+ (kısmi) |
| RDNA3 | RX 7700/7800/7900 | **Desteklenmez** |

> RX 580 en ucuz ve en sorunsuz seçenektir; ikinci el fiyatı düşüktür.

---

## 3. Sürücüsü OLMAYAN donanım (yazılım render)

Bunlar **çalışır**, yalnızca hızlandırma olmaz:

| Donanım | Neden |
|---|---|
| **NVIDIA** (tüm modern kartlar) | macOS 10.14'dan sonra NVIDIA Web Driver yok; Apple Silicon döneminde hiç yayınlanmadı |
| **Intel iGPU** (HD/UHD/Iris) | Yalnızca çok eski nesiller (HD 4000/5000/6000) için kext var; yeni nesiller yok |
| **Eski AMD** — TeraScale (Hainan, Wani, Caicos…), GCN 1-2 | Apple sürücüsü hiç yayınlanmadı |
| **GPU yok** | Başsız mod: VNC/SPICE |

### Özel örnek: HP Pavilion, AMD A10-9600P
- R5 iGPU `1002:9874` (Wani) + R7 M340 `1002:6660` (Hainan)
- Her iki kart da **hiçbir macOS sürümünde** sürücüye sahip değil.
- Muxless tasarım: dGPU'yu tek başına passthrough etmek de görüntü vermez.
- Sonuç: **yazılım render** — MacNix bu makinede kurulur ve çalışır,
  oyun/video hızlandırma olmaz. Ayrıntı: `GPU-GERCEK.md`.

---

## 4. CPU ve sanallaştırma

| Gereksinim | Not |
|---|---|
| VT-x (Intel) / SVM (AMD) | BIOS'ta **açık olmalı** — en sık yapılan hata |
| IOMMU (VT-d / AMD-Vi) | Yalnızca VFIO için; BIOS + `amd_iommu=on iommu=pt` |
| AMD CPU'lar | macOS VM'i için AMD_Vanilla yamaları gerekir (ISO'da gömülü) |
| Çekirdek sayısı | VM'e en fazla (toplam çekirdek − 1) verilir |

`macnix-doctor` bunların hepsini denetler ve eksikse ne yapılacağını yazar.

---

## 5. Disk, ağ, çevre birimleri

- **Disk:** SATA/NVMe/USB hepsi. En az 25 GB, macOS diski için 60 GB önerilir.
- **Ağ:** QEMU kullanıcı modu (NAT) → macOS içinde internet çalışır.
  Köprü (bridge) modu `macnix-vm` ile yapılandırılabilir.
- **Ses:** AppleALC (ISO'da gömülü) — çoğu HDA codec çalışır.
- **USB:** xHCI passthrough desteklenir (`macnix-gpu-config` PCI adreslerini yazar).
- **Wi-Fi:** macOS'ta yalnızca destekli Broadcom kartları çalışır; Ethernet önerilir.

---

## 6. Hızlı karar tablosu

| Soru | Cevap |
|---|---|
| MacNix benim makinemde kurulur mu? | Evet — GPU ne olursa olsun. |
| macOS açılır mı? | Evet. 4+ GB RAM ve 25+ GB disk yeterli. |
| Oyun oynar mıyım? | Yalnızca macOS sürücüsü olan AMD kartla (RX 580/6600+). |
| Final Cut / video kodlama? | Aynı koşul. |
| GPU'm yok (sunucu)? | Başsız mod + VNC çalışır. |
| NVIDIA'da hızlandırma? | Hayır, hiçbir sürümde mümkün değil. |
