# MacNix 2.0

**macOS'u Linux üzerinde sanallaştırır.** Tek USB, tek önyükleme. GPU'su macOS
tarafından desteklenen makinelerde gerçek GPU passthrough, diğerlerinde çalışan
yazılım render.

> Bu sürüm, `vesvese55x/macnix` deposunun canlı ortamda kurulum yapamayan
> sürümünün **sıfırdan yeniden yazılmış** hâlidir. Neyin neden bozuk olduğu ve
> nasıl düzeltildiği [`../MACNIX-ANALIZ.md`](../MACNIX-ANALIZ.md) dosyasında.

---

## Ne değişti (özet)

| Alan | Orijinal | MacNix 2.0 |
|---|---|---|
| ISO derleme | live-build + 7 adet `sed` yaması | `debootstrap` + `mksquashfs` + `xorriso` (yamа yok) |
| Kurulum | `unpackfs` çağrılmıyordu → diske yazmıyordu | Akış düzeltildi, 17 modül `.conf`'u tamamlandı |
| macOS indirme | Kurulumun ortasında, hata = çökme | İlk açılışta, kaldığı yerden devam eder |
| OpenCore | OSX-KVM'nin hazır imajı kopyalanıyordu | Donanıma göre sıfırdan üretiliyor (AMD yamaları dahil) |
| GPU kararı | GPU serisine göre tahmin | 14 ailelik veritabanı + gerçek macOS sürücü bilgisi |
| Hata durumu | Sessiz bozuk ISO | `macnix-doctor` + `macnix-log --tar` |
| Grafik yoksa | Kurulum yapılamıyordu | `macnix-tui` metin modu |

---

## Derleme

Gereksinimler (Debian/Ubuntu):

```bash
sudo apt-get install -y debootstrap squashfs-tools xorriso \
    grub-efi-amd64-bin grub-pc-bin mtools dosfstools isolinux syslinux-common
```

```bash
sudo ./build.sh                     # tam ISO
sudo ./build.sh --stage rootfs      # sadece kök dosya sistemi
sudo ./build.sh --stage iso         # rootfs hazırsa ISO'yu paketle
sudo ./build.sh --clean
```

Değişkenler: `WORK` (çalışma dizini, varsayılan `/data/build`), `OUT` (çıktı,
`/data/workspace/out`), `DEBIAN_SUITE` (`bookworm`), `MACNIX_JOBS`, `USB_TREE=1`.

Çıktı:

```
out/macnix-2.0.0-amd64.iso
out/macnix-2.0.0-amd64.iso.sha256
out/usb-2.0.0/            # FAT32 USB'ye kopyala-çalıştır ağacı
```

Yazma:

```bash
sudo dd if=out/macnix-2.0.0-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Hibrit ISO: UEFI + BIOS önyükleme aynı imajda.

---

## Kurulum akışı

1. USB'den önyükle → GRUB → **"MacNix 2.0 — Kurulumu Başlat"**
2. Canlı masaüstü açılır, Calamares başlar
3. İlk ekran **donanım raporudur**: GPU passthrough mu, yazılım render mı
4. Dil, klavye, disk, kullanıcı
5. Kurulum → yeniden başlat (USB'yi çıkar)
6. İlk açılışta **MacNix Kurulum Sihirbazı** → macOS imajını indirir → macOS kurulumu

Kurulum sırasında macOS **indirilmez** — bu yüzden ağ hatası kurulumu bozmaz.

---

## Komutlar

| Komut | İş |
|---|---|
| `macnix-setup` | Grafik kurulum sihirbazı (ilk açılışta otomatik) |
| `macnix-install-macos [--step N] [--status]` | macOS hazırlığı: 7 adım, tekrar çalıştırılabilir |
| `macnix-vm {start\|install\|stop\|status\|console\|shell\|doctor}` | VM yönetimi |
| `macnix-doctor` | Tanılama: ne eksik, ne yanlış, nasıl düzeltilir |
| `macnix-gpu-mode {vm\|host\|status}` | GPU'yu VM ↔ host arasında geçir |
| `macnix-oc {--build\|--check\|--dump-config}` | OpenCore'u üret / denetle |
| `macnix-assets [--dest DIR]` | OpenCore + kextleri indir |
| `macnix-fetch-macos --list` | Desteklenen macOS sürümleri |
| `macnix-log [--tar]` | Tanılama paketi |
| `macnix-tui` | Metin modu kurulum / kurtarma |

---

## Donanım desteği — dürüst tablo

### GPU

| GPU ailesi | macOS sürücüsü | MacNix modu |
|---|---|---|
| AMD RDNA 3 (RX 7000) | ✅ Sonoma 14.4+ | **vfio** (90-100%) |
| AMD RDNA 2 (RX 6000) | ✅ Monterey+ | **vfio** (90-100%) |
| AMD RDNA 1 (RX 5000) | ✅ Catalina+ | **vfio** |
| AMD Vega | ✅ High Sierra+ | **vfio** |
| AMD Polaris (RX 400/500) | ✅ Sierra+ | **vfio** |
| NVIDIA Kepler (GTX 600/700) | ✅ Big Sur'a kadar | **vfio** (eski macOS) |
| NVIDIA Maxwell/Pascal+ | ❌ | virtio (yazılım render) |
| AMD GCN 1.0/1.2 mobil (R7 M340, R5 M330…) | ❌ 10.13'te kesildi | virtio |
| Intel iGPU | ❌ (VM'de Metal yok) | virtio |
| GPU yok / sanal makine | ❌ | virtio |

### Yazılım render modunda ne çalışır

✅ macOS masaüstü, Safari, Terminal, dosya işlemleri, App Store (SMBIOS'a bağlı)
❌ Oyun, Metal, video kodlama, Final Cut, 4K video

### Sistem gereksinimleri

| | Minimum | Önerilen |
|---|---|---|
| CPU | VT-x/AMD-V (2 çekirdek) | 6+ çekirdek |
| RAM | 8 GB | 16 GB+ |
| Disk | 40 GB | 100 GB+ |
| GPU | — (yazılım render) | AMD RX 580 / RX 6600+ |
| BIOS | UEFI | UEFI + IOMMU (AMD-Vi / VT-d) |

---

## Kurulum sonrası hata ayıklama

```bash
sudo macnix-doctor                 # tanılama
sudo macnix-vm shell               # üretilecek qemu komutunu göster
sudo macnix-vm start               # başlat
sudo macnix-vm console             # VNC ile görüntü
less /var/lib/macnix/logs/qemu.log
sudo less /var/log/macnix-firstboot.log
sudo macnix-log --tar              # her şeyi tek pakete koy
```

GRUB menüsü: açılışta **SHIFT**. Çekirdek kayıtları için menüdeki
"Çekirdek Kayıtlarını Göster" seçeneği.

---

## Bilinen sınırlar

- macOS imajı ISO'ya gömülü **değil** (boyut + lisans). İlk açılışta indirilir.
- AirDrop / Handoff / Sidecar / Apple DRM **çalışmaz**.
- Thunderbolt passthrough **desteklenmez**.
- Tek GPU (muxless laptop) senaryosunda macOS açıkken Linux görüntü veremez;
  VNC/SSH yedek yolu vardır.
- macOS, Apple'ın yazılım lisansına tabidir.

## Teşekkür

[OpenCorePkg](https://github.com/acidanthera/OpenCorePkg) ·
[OSX-KVM](https://github.com/kholia/OSX-KVM) ·
[AMD_Vanilla](https://github.com/AMD-OSX/AMD_Vanilla) ·
[Lilu](https://github.com/acidanthera/Lilu) / [VirtualSMC](https://github.com/acidanthera/VirtualSMC) /
[WhateverGreen](https://github.com/acidanthera/WhateverGreen) / [AppleALC](https://github.com/acidanthera/AppleALC) ·
[Calamares](https://calamares.io/)

macOS, Apple Inc.'in ticari markasıdır. Bu proje eğitim amaçlıdır.
