# MacNix 2.0 — Kurulum ve İlk Açılış

Bu dosya, MacNix 2.0 ISO'sunu gerçek donanıma yazıp kurmaya kadar olan
adımları ve **kurulum sırasında ne olacağını** anlatır.

---

## 1. Gereksinimler

| Bileşen | En az | Önerilen |
|---|---|---|
| CPU | 4 çekirdek, x86-64, sanallaştırma (VT-x/AMD-V) açık | 6+ çekirdek |
| RAM | 4 GB | 16 GB (macOS VM'ine 8 GB ayrılır) |
| Disk | 25 GB | 80 GB SSD |
| GPU | Herhangi biri — **hiç olmasa da olur** | macOS sürücüsü olan AMD kart (RX 580 / RX 6600 ve üstü) |
| Önyükleme | UEFI veya BIOS (CSM) | UEFI |

> **GPU hakkında dürüst not:** MacNix her GPU'da kurulur ve çalışır. Ancak
> macOS'un kendi sürücüsü olmayan kartlarda (NVIDIA, Intel iGPU, çoğu eski AMD)
> sistem **yazılım render** ile çalışır: masaüstü ve uygulamalar akıcıdır,
> oyun ve video kodlama yavaştır. Bu bir hata değil, Apple'ın kapalı kaynak
> sürücü modelinin sonucudur. Ayrıntı: `GPU-GERCEK.md`.

---

## 2. ISO'yu USB'ye yazma

ISO'yu **DD modunda** yazın. Ventoy/Rufus "ISO modu" canlı medyayı bulamaz.

```bash
# Linux / macOS
sudo dd if=macnix-2.0.0-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync

# Windows: Rufus → "DD Image" modunu seçin
```

Yazdıktan sonra doğrulama:

```bash
sha256sum macnix-2.0.0-amd64.iso     # ISO ile birlikte gelen .sha256 dosyasıyla karşılaştırın
```

---

## 3. Önyükleme menüsü

Bilgisayarı USB'den başlatın. GRUB menüsünde şu seçenekler var:

| Seçenek | Ne zaman kullanılır |
|---|---|
| **MacNix 2.0 — Kurulumu Başlat (önerilen)** | Normal durum |
| Güvenli Mod (grafik yok) | Ekran kartı sürücüsü sorun çıkarırsa (`nomodeset`) |
| Metin Modu (TTY) | X hiç açılmazsa: `sudo macnix-tui` |
| Bellekten Çalıştır (toram) | USB yavaşsa (en az 8 GB RAM gerekir) |
| Çekirdek Kayıtlarını Göster | Önyükleme hatası teşhisi |
| Donanım bilgisi / kabuk (kurtarma) | Elle müdahale |

---

## 4. Canlı ortam ne yapar?

Açılışta `macnix-live.service` bir kez çalışır ve şunları yapar:

1. Canlı medyayı bulur (`/run/live/medium`) ve `/run/macnix-live` bağlantısını
   kurar — **kurulumun çalışması için şart**.
2. `/etc/sudoers.d` ve `/etc/lightdm` sahipliğini/izinlerini onarır.
3. LightDM otomatik girişini düzeltir (`autologin-user=user` satırını etkisizleştirir).
4. Donanımı tarar, `/var/lib/macnix/hardware-profile.json` yazar ve
   `/var/log/macnix-live.log` içine rapor basar.
5. X açılmazsa sizi TTY'ye yönlendirir.

Sonra Calamares kurulum sihirbazı **kendiliğinden** açılır
(giriş ekranı görürseniz: kullanıcı `macnix`, parola `macnix`).

---

## 5. Kurulum adımları

1. **Hoş geldiniz** — dil seçimi. Zorunlu gereksinimler: 25 GB disk, root bölümü.
2. **Donanım raporu (notesqml)** — bu makinede macOS'un nasıl çalışacağını
   (passthrough / yazılım render), kurulacak sürümü ve VM kaynaklarını yazar.
   **Hiçbir uyarı kurulumu engellemez.**
3. **Bölge / klavye** — varsayılan `Europe/Istanbul`, `tr` klavye seçilebilir.
4. **Disk bölümleme** — "Diski sil ve MacNix kur" (GPT + EFI 512 MB + ext4).
5. **Kullanıcı** — kullanıcı adı, parola, makine adı.
6. **Özet** → **Kur**.
7. **Kurulum (exec)** — sırasıyla: bölümleme, bağlama, canlı medya keşfi,
   `unpackfs` (kök dosya sistemini kopyalar), machine-id, fstab, yerel ayarlar,
   kullanıcı, görüntü yöneticisi, ağ, saat, **macnix-gpu-detect**,
   **macnix-gpu-config** (VFIO/GRUB/SMBIOS/systemd hedef sisteme yazılır),
   GRUB (EFI **ve** BIOS), ayırma.
8. **Bitti** → yeniden başlat, USB'yi çıkar.

---

## 6. İlk açılış

Kurulu sistem açıldığında:

1. `macnix-firstboot.service` çalışır, tanılama yapar.
2. **MacNix Kurulum Sihirbazı** (`macnix-setup`) açılır: macOS kurtarma imajını
   Apple sunucularından indirir (~700 MB), OpenCore yapılandırmasını üretir,
   UEFI firmware (OVMF) ve VM diskini hazırlar.
3. `sudo macnix-vm start` ile macOS kurulumu başlar.

### Sık kullanılan komutlar

```bash
macnix-doctor            # tanılama (0=sorun yok, 1=uyarı, 2=kritik)
macnix-log --tar         # günlük paketi
sudo macnix-vm start     # macOS VM'ini başlat
sudo macnix-vm shell     # VM içinde kabuk
sudo macnix-gpu-mode     # yazılım render / VFIO modu
sudo macnix-setup --repair
```

---

## 7. Sorun giderme

| Belirti | Çözüm |
|---|---|
| Açılışta siyah ekran | GRUB'da "Güvenli Mod (nomodeset)" |
| Giriş ekranında kalıyor | `macnix` / `macnix` ile girin; `sudo systemctl restart lightdm` |
| "Calamares Initialization Failed" | Bu sürümde giderildi; yine olursa `sudo macnix-tui` |
| Kurulum "filesystem.squashfs bulunamadı" | ISO'yu DD modunda yazın (Ventoy ISO modu desteklenmez) |
| Kurulum sonrası GRUB açılmıyor | UEFI'de `MacNix` girdisini seçin; BIOS'ta diski ilk sıraya alın |
| macOS VM açılmıyor | `sudo macnix-doctor`, sonra `macnix-log --tar` |

Günlükler: `/var/log/macnix-live.log`, `/tmp/calamares.log`,
`/var/lib/macnix/logs/`.
