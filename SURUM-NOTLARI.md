# MacNix 2.0 — Sürüm Notları

**Derleme:** `macnix-2.0.0-amd64.iso` · 1.3 GB
**SHA256:** `9383de9d3a11292bd315b89031526c1c14bbf121b69ec7baba3ad6a589ad8121`
**Önyükleme:** Hibrit — UEFI (`/boot/grub/efi.img`) + BIOS (`/boot/grub/bios.img`)
**Taban:** Debian 12 bookworm · çekirdek 6.1.0-54-amd64 · Calamares 3.3.14

---

## Bu sürümde ne düzeltildi

### Kurulumu engelleyen hatalar (hepsi giderildi)

1. **`unpackfs` modülü akışta yoktu** → kök dosya sistemi hedefe hiç
   kopyalanmıyordu. "Kurulum tamam" ekranı geliyor, makine açılmıyordu.
   *Düzeltme:* `mount → macnix-medium → unpackfs → …` sırası eklendi;
   doğrulayıcı artık bu sırayı zorunlu tutuyor.

2. **Özel Calamares modüllerinin `.conf` dosyası yoktu** → Calamares 3.3
   modülleri reddediyordu. *Düzeltme:* 22 modül yapılandırması yazıldı.

3. **`partition.conf` Calamares 3.3 şemasına uymuyordu** (`partitionLayout`,
   `availableInstallTypes` gibi var olmayan anahtarlar). *Düzeltme:* gerçek
   şema anahtarları (`initialPartitioningChoice`, `efiSystemPartitionSize`…).

4. **squashfs yolu sabit varsayılmıştı** (`/run/live/medium`). live-boot
   sürümüne / Ventoy'a göre değişir. *Düzeltme:* `macnix-medium` adımı 8 olası
   konumu tarayıp `/run/macnix-live` linkini kuruyor.

5. **`config/binary` içinde `aufs`** → modern çekirdekte yok, canlı katman
   bağlanamıyordu. MacNix 2.0 live-build kullanmıyor; `union=overlay`.

6. **macOS indirmesi kurulumun ortasındaydı** (700 MB, `timeout=3600`).
   Ağ hatası = kurulum çöküşü. *Düzeltme:* indirme ilk açılışa taşındı,
   kaldığı yerden devam ediyor.

7. **`macnix-gpu-config` modülünde `import sys` eksikti** → kurulum
   `NameError` ile düşüyordu. *(Bu hata modül testleriyle yakalandı.)*

### ISO üretimini engelleyen hatalar

8. **live-build'e 7 adet `sed` yaması**, hepsi `|| true` ile yutuluyordu →
   sessiz bozuk ISO. *Düzeltme:* live-build tamamen kaldırıldı;
   `debootstrap + mksquashfs + xorriso` ile şeffaf derleme.

9. **BIOS önyükleme yoktu** (isolinux paketi Debian'da `isolinux.bin`
   sağlamıyor). *Düzeltme:* `grub-mkimage -O i386-pc-eltorito` ile BIOS imajı
   üretiliyor → ISO artık gerçekten hibrit.

### macOS tarafı

10. **OpenCore yapılandırması hiç üretilmiyordu** (OSX-KVM'nin hazır imajı
    kopyalanıyordu, `config.plist.template` içindeki `__PLACEHOLDER__`'lar
    hiç değiştirilmiyordu). *Düzeltme:* `macnix-oc --build` donanıma göre
    sıfırdan üretiyor — AMD CPU yamaları (27 adet AMD_Vanilla), SMBIOS serisi,
    kext seti, sürücüler. `plistlib` ile yazıldığı için bozuk XML imkânsız.

11. **VirtualSMC kext'i indirilmiyordu** (paket `Kexts/` alt klasöründe).
    macOS'un açılması için zorunlu. *(Bu hata ISO içerik denetimiyle
    yakalandı.)* *Düzeltme:* özyinelemeli kext arama + zorunlu kext
    bütünlük denetimi.

12. **Hugepage yoksa VM hiç açılmıyordu** (`-mem-path /dev/hugepages` koşulsuz).
    *Düzeltme:* rezervasyon denenir, olmazsa normal belleğe düşer.

13. **CPU pinning yanlıştı** → L3 cache paylaşımı bozuluyordu.
    *Düzeltme:* `/sys/.../cache/index3/shared_cpu_list` okunur, VM tek
    CCD içinde kalır.

14. **`x-vga=on` muxless laptopta siyah ekran** veriyordu.
    *Düzeltme:* yalnızca gerçek single-GPU senaryosunda kullanılıyor.

15. **Görüntüye erişim tek yoldu** (`spice://localhost:5930` sabit).
    *Düzeltme:* VNC her modda `127.0.0.1:5900`.

---

## Doğrulama sonuçları

| Denetim | Sonuç |
|---|---|
| `tools/validate.sh` — statik | **62 geçti / 0 hata** |
| `tools/test-modules.py` — Calamares modülleri (sahte libcalamares) | **48 geçti / 0 hata** |
| El Torito — BIOS girdisi | ✅ `/boot/grub/bios.img` |
| El Torito — UEFI girdisi | ✅ `/boot/grub/efi.img` |
| `filesystem.squashfs` SHA256 ↔ ISO manifesti | ✅ birebir eşleşti |
| Zorunlu kextler (Lilu, VirtualSMC, WhateverGreen, AppleALC) | ✅ 4/4 ikili + plist |
| OpenCore varlıkları | ✅ `OpenCore.efi`, `BOOTx64.efi`, sürücüler |
| AMD yamaları ISO içinde | ✅ 27 yama |
| Calamares modül `.conf` (ISO içinde) | ✅ 22 |

### Yapılamayan tek test

**ISO'dan gerçek önyükleme.** instabox VM'inde `/dev/kvm` yok ve CPU'da
`vmx/svm` bayrağı bulunmuyor (iç içe sanallaştırma kapalı). QEMU yalnızca
TCG ile çalışabildiği için canlı ortam açılışı 30+ dakika sürer ve anlamlı
bir test olmaz. Bu test **senin makinende** yapılmalı.

İlk önyüklemede sorun çıkarsa:
- GRUB menüsünde **"Çekirdek Kayıtlarını Göster"** → hata mesajını gör
- **"Metin Modu (TTY)"** → grafik sorunuysa sistem yine açılır
- TTY'de: `sudo macnix-tui` → tanılama / elle kurulum talimatları
- `macnix-log --tar` → tanılama paketi

---

## Hedef donanım hakkında (HP Pavilion / A10-9600P)

| Bileşen | macOS sürücüsü | MacNix modu |
|---|---|---|
| Radeon R5 iGPU (`1002:9874`) | ❌ yok | konakta kalır |
| Radeon R7 M340 (`1002:6660`) | ❌ 10.13'te kesildi | kullanılmaz |
| CPU (A10-9600P, 4C) | ✅ AMD yamaları ile | KVM hızlandırma |

**Sonuç:** macOS kurulur ve çalışır; **GPU hızlandırma olmaz** (yazılım render).
Oyun / video kodlama / Metal uygulamaları çalışmaz. Bu bir yazılım eksiği değil,
Apple'ın bu çiplere sürücü vermemesinden kaynaklanır — hiçbir yamayla aşılamaz.

Gerçek GPU performansı için: masaüstü PC + AMD RX 580 / RX 6600+ (veya Vega /
RDNA). O zaman MacNix otomatik olarak `vfio` moduna geçer.

---

## Sonraki adımlar (senin kararın)

1. **Gerçek donanımda test** → çıkan hatayı `macnix-log --tar` ile gönder, düzeltirim.
2. **USB'ye yaz ve dene**:
   ```bash
   sudo dd if=macnix-2.0.0-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```
3. GitHub'a push (token gerekli) — Actions iş akışı hazır, `sed` yaması yok.
