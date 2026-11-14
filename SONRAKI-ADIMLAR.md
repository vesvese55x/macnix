# Durum ve Sonraki Adımlar

## Nerede kaldık (14 Kasım 2026)

Kurulum uçtan uca çalışıyor ve doğrulandı:

- ISO → canlı masaüstü → Calamares → bölümleme → 57 626 dosyalık kök sistem
- GRUB **EFI ve BIOS** ikisi de kuruluyor
- Kurulu disk **BIOS'ta ve UEFI'de** açılıyor (UEFI'de boş NVRAM ile bile,
  `\EFI\BOOT\BOOTX64.EFI` yedeği sayesinde)
- Kurulu sistemde `macnix-setup` açılıyor, "Önyükleme bileşenleri ✓"

Güncel ISO: `8a8ccb9bcc13614471c30f734394656d75d76ba2d293f322acf1c692fac51c77`

## Kalan işler (öncelik sırasıyla)

1. **Gerçek donanımda kurulum testi (HP Pavilion).** ISO'yu USB'ye yaz
   (`dd`, DD modu), BIOS'tan ve UEFI'den aç. Beklenen: aynı sihirbaz.
   Bu, kalan tek büyük doğrulama.
2. **macOS indirme + VM testi.** Kurulu sistemde `sudo macnix-setup` →
   ~700 MB kurtarma imajı. Test VM'inde KVM olmadığı için bu adım hiç
   denenmedi; gerçek makinede ilk denenecek şey bu olmalı.
3. **VFIO passthrough testi** — yalnızca macOS sürücüsü olan bir AMD kart
   takılırsa (RX 580 / RX 6600+). Bu donanımda (R5 + R7 M340) mümkün değil.
4. **BIOS blocklist kırılganlığı.** Debian Calamares `bios_grub` bölümü
   oluşturmuyor; GRUB `--force` ile blocklist kullanıyor. Bu makinede çalıştı
   ama bazı firmware'lerde sorun çıkarabilir. İstenirse partition.conf'a
   `biosGrubSize` eklenip ayrı bir BIOS Boot bölümü zorlanabilir.

## Komut referansı (VM)

```bash
# tam derleme
ssh -p 2222 USER@ssh.instabox.sh 'sudo bash /data/rebuild.sh'   # /data/build.log

# kurulum exec aşaması (canlı ortamda, gerçek /dev/vda)
sudo bash /data/vm_install2.sh      # /var/log/vminstall.log

# kurulu diski BIOS / UEFI ile aç
sudo bash /data/biostest.sh         # -machine pc
sudo bash /data/uefitest.sh         # q35 + OVMF (boş NVRAM)
sudo python3 /data/shot2.py ad      # ekran görüntüsü → /data/itest/ad.png
```
