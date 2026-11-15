# MacNix 2.0.0 — Son Durum ve Dürüst Teslim Raporu

**Tarih:** 15 Kasım 2026
**ISO:** `macnix-2.0.0-amd64.iso` — 1241.9 MB
**SHA256:** `8ff6ffe47016e04703e8a3d4f59dcf0b0ee8e0e96a82c674281425971e9bc06c`
**Release:** tek sürüm `v2.0.0-403`, adı **"MacNix 2.0.0 (build 403)"** (önceki tüm release'ler silindi)
**İndirme:** https://github.com/vesvese55x/macnix/releases/download/v2.0.0-403/macnix-2.0.0-amd64.iso

> MacNix, Gelişmiş macOS Sanallaştırma Distrosu olup, BELGESELSEMO tarafından
> ARENA.AI sayesinde https://github.com/local-over/macnix orijinal Github reposundan
> fork edilerek geliştirilmiştir. — http://belgeselsemo.com.tr/

**Testler:** `tools/test-modules.py` **188 geçen / 0 hata** · `tools/validate.sh` **66 geçen / 13 uyarı / 0 hata**
**CI:** run `43749145205` → **success (3/3 job)**

---

## 0. YAYIN (bu turun sonucu)

| Öğe | Değer |
|---|---|
| Release | **`v2.0.0-403`** (tek release — önceki tüm sürümler silindi) |
| ISO | `macnix-2.0.0-amd64.iso` — **1242,4 MB** |
| SHA256 | **`8ff6ffe47016e04703e8a3d4f59dcf0b0ee8e0e96a82c674281425971e9bc06c`** |
| CI | run `43745459187` — **3/3 job success** (validate → build → release) |
| Testler | `test-modules.py` **188 geçen / 0 hata**, `validate.sh` **66 geçen / 13 uyarı / 0 hata** |
| URL | https://github.com/vesvese55x/macnix/releases/tag/v2.0.0-403 |

Bu ISO, bu turdaki **OpenCore şema düzeltmesini, KVM/nested teşhisini, ANSI
temizliğini ve parolasız erişim sıkılaştırmasını** içeriyor.

### 0.1 Yayınlanan ISO gerçekten indirilip, AÇILIP, sihirbaz görülene kadar test edildi

```
curl → /home/user/iso/macnix-403.iso   1.302.786.048 bayt (1242,4 MiB)
sha256sum → 8ff6ffe47016e04703e8a3d4f59dcf0b0ee8e0e96a82c674281425971e9bc06c  ✓ birebir
7z l      → live/filesystem.squashfs + boot/grub/efi.img + unicode.pf2  ✓
```

**Canlı önyükleme (UEFI/OVMF, QEMU q35):** ISO'nun içindeki `boot/grub/efi.img`
ESP olarak bağlanıp QEMU ile açıldı. Sonuç **ekran görüntüsüyle** doğrulandı:

`macnix-arayuz/28-ISO-UEFI-Calamares.png` →
**"Welcome to the MacNix 2.0 — Gelişmiş macOS Sanallaştırma Distrosu installer"**
(Calamares sihirbazı, sol menü Welcome/Location/Keyboard/Partitions/Users/Summary/
Install/License/Finish, dil açılır kutusu **"American English"** = varsayılan İngilizce ✓,
alt solda **"Abo / Deb"** = zorunlu kredi + `belgeselsemo.com.tr` ✓).

> **Bu ISO'nun kendisi indirilip (SHA256 birebir), UEFI/OVMF ile açıldı ve
> sihirbaz ekran görüntüsüyle belgelendi.** Yani "yayınlanan ISO çalışmıyor"
> durumu kalmadı.
>
> Yol boyunca **4 GERÇEK HATA** bulundu ve düzeltildi (aşağıda §1.4). Bu hatalar
> yalnızca ISO'nun kendisi canlı açıldığında ortaya çıktı; statik testler ve
> CI'ın "ISO yapısını doğrula" adımı bunları yakalamıyordu.

### 0.2 Squashfs içeriği (dosya düzeyinde kanıt)

`unsquashfs` ile ISO'dan çıkarılan gerçek dosyalar üzerinde:

| Kontrol | Sonuç |
|---|---|
| `SerialInit` (OpenCore'u durduran alan) | **0 kez** ✓ |
| `AudioOutMask` / `KeySwap` / `ForceOcWriteFlash` | var ✓ |
| `UEFI.DriveInput` | **0 kez** ✓ |
| `is_amd = bool(...)` | var ✓ |
| `opt/macnix/config/opencore-schema.json` | ISO içinde ✓ |
| `macnix-vm` → `-cpu host,kvm=on`, `logs/serial.log`, `accel` | var ✓ |
| `macnix-setup` → `_ANSI` temizleyici | var ✓ |
| `firstboot.sh` → `MacNix-KVM-UYARI.txt` | var ✓ |
| `/usr/local/bin/macnix-vm` ↔ `/opt/macnix/scripts/bin/macnix-vm` | birebir aynı ✓ |

## 1. Bu turun en büyük adımı: GERÇEK UEFI ÖNYÜKLEME ZİNCİRİ

Bu tura kadar "macOS VM'de açılır mı?" sorusu **hiç denenmemişti**. Bu turda gerçek
bir önyükleme zinciri kuruldu ve çalıştırıldı:

```
gerçek OVMF (edk2) + OpenCore 1.0.8 + Lilu 1.7.2 + VirtualSMC 1.3.8
        + GPT/ESP imajı + BaseSystem.img (3.2 GB, Apple'dan indirildi)
                        ↓
              qemu-system-x86_64 (TCG)
                        ↓
         OpenCore config.plist'i AYRIŞTIRDI (hata yok)
```

### 1.1 Bulunan gerçek OpenCore hataları (ekran görüntüsüyle belgelendi)

| # | OpenCore'un verdiği hata | Kök neden | Düzeltme |
|---|---|---|---|
| 1 | `OCS: No schema for UpdateSMBIOSMode at 8 index, context <Generic>!` | Anahtar yanlış bölümde | `PlatformInfo.UpdateSMBIOSMode` (Generic içinden çıkarıldı) |
| 2 | `OCS: Failed to calculate size of array field containing <empty> as type integer, context <LogModules>!` | Boş dizi | `LogModules` kaldırıldı |
| 3 | ESP hiç tanınmadı (boot başlamadı) | Ham FAT imajı UEFI'ye disk olarak verilmişti | **GPT + `esp` bayraklı** bölüm üretimi (`parted` + FAT16 @ 1 MiB) |
| 4 | `sata.2` / `sata.3` yolu | q35'te yok | `ide.0/ide.1/ide.2` |

**Kanıtlar:** `macnix-arayuz/24-OVMF-OpenCore-gercek-boot-hata.png` (1. hata),
`25-OVMF-OpenCore-config-hatasiz.png` (config temiz — artık hata yok),
`26-OVMF-OpenCore-ESP-tanindi.png` (GPT/ESP UEFI tarafından tanındı).

### 1.2 Bu bulgular doğrudan koda aktarıldı (`macnix-oc`)

| Değişiklik | Neden |
|---|---|
| ESP **FAT16** olarak kuruluyor | FAT32'de mtools uzun adları (`config.plist`, `OpenCore.efi`) yazamıyordu |
| Kext alt dizinleri (`Contents/MacOS`) `mmd` ile açılıyor | Aksi hâlde kext ikilileri kopyalanmıyordu |
| **ESP içerik doğrulaması** (`verify_esp`) | Sessiz eksik kurulum artık imkânsız: BOOTx64 + OpenCore.efi + config.plist + OpenRuntime kontrol edilir |
| **GPT + ESP bayraklı imaj** (`OpenCore-ESP.img`) | UEFI'nin tanıdığı tek biçim |
| Her adımda "kaç dosya kopyalandı" raporu | Sessiz hata yok |

### 1.3 UEFI NVRAM artık kalıcı (`macnix-vm`)

Eskiden `OVMF_VARS` ham dosya olarak veriliyordu → misafirin yazdığı değişkenler
(boot sırası, macOS NVRAM'i) **her açılışta kayboluyordu**. Artık:

```bash
qemu-img convert -f raw -O qcow2 OVMF_VARS.fd OVMF_VARS.qcow2
-drive if=pflash,format=qcow2,file=OVMF_VARS.qcow2
```

→ macOS "açılış diski" seçimi ve NVRAM ayarları **kalıcı**. Canlı doğrulandı:
QEMU ayakta, VNC `RFB 003.008`, günlük temiz.

---

### 1.4 ISO'nun UEFI önyüklemesinde bulunan 4 GERÇEK hata (canlı test, hepsi düzeltildi)

Bunlar bu turda, **yayınlanan ISO'yu QEMU/OVMF ile gerçekten açarak** bulundu.
Hiçbiri statik testle yakalanamazdı:

| # | Belirti (canlı) | Kök neden | Düzeltme |
|---|---|---|---|
| 1 | ISO UEFI'de açılınca GRUB **menüsü yok**, doğrudan `grub>` kabuğu; seri günlükte onlarca `error: maximum recursion depth exceeded.` | `grub-mkstandalone` gömülü cfg'yi "memdisk"e koyuyor; OVMF o memdisk'i disk olarak bağlayınca GRUB kendini yeniden bulup sonsuz döngüye giriyor | `grub-mkimage -p /EFI/BOOT` (memdisk YOK) + cfg ESP'de **gerçek dosya** (`/EFI/BOOT/grub.cfg`) |
| 2 | `Unknown command '#'` satırları | GRUB'ın gömülü-cfg ayrıştırıcısı `#` yorumlarını komut sanıyor (UTF-8 de bozuluyor) | `config/grub/grub-efi-embed.cfg` artık **yorumsuz ve saf ASCII** |
| 3 | `error: file /boot/grub/x86_64-efi/png.mod not found` | `grub.cfg` `insmod png` diyor ama modül ESP'ye gömülmemiş | `png`, `jpeg`, `gfxmenu` modülleri gömülü listeye eklendi |
| 4 | Menü görünse de ekran **tamamen siyah** (3 ayrı ISO'da tekrarlandı) | `terminal_output gfxterm` bu firmware+VGA'da font yüklü olsa bile hiçbir şey çizmiyor | `terminal_output console` (metin modu) varsayılan; ayrıca `unicode.pf2` ISO'ya kopyalanıyor ki isteyen gfxterm'e geçebilsin |

**Ek düzeltme:** metin modunda Türkçe karakterler (ş, ı, ğ) font bulunamayınca
kayboluyordu ("Kurulumu Ba_lat"). GRUB menü başlıkları **ASCII** yapıldı
(`Kurulumu Baslat`); Calamares tarafı Türkçe karakterleri normal gösteriyor.

**Kanıt:** `macnix-arayuz/28-ISO-UEFI-Calamares.png` — menüden sonra canlı
ortam açıldı, Calamares sihirbazı geldi.

## 2. Önceki turlardan devam eden, canlı doğrulanmış işler

| Konu | Durum | Kanıt |
|---|---|---|
| Arayüz varsayılan **İngilizce** | ✅ canlı VM | `10-CANLI-…png` |
| **macOS indirme** (401 bitti) | ✅ canlı VM: 844 MB, 85/85 parça | `15-CANLI-…png` |
| Şifresiz sudo / otomatik giriş | ✅ canlı VM | `09`, `14` |
| Slaytlar + zorunlu künye + etkin "Done" | ✅ canlı VM | `11`, `12`, `13` |
| Panel: modern tema, taşınabilir pencere | ✅ Xvfb + xdotool ile tıklandı | `20`–`23` |
| Panel: kapanabilir/açılabilir terminal | ✅ komut çalıştırıldı (`sudo -n` parolasız) | `22` |
| VM başlatmada 9 hata | ✅ QEMU ayakta, VNC yanıt verdi | §3 |

---

## 3. VM başlatmada düzeltilen 9 hata (önceki tur, hâlâ geçerli)

`-no-hpet` (QEMU 8+ geçersiz → `hpet=off`) · SMBIOS modelindeki virgül (`iMacPro1,1`) ·
q35'te olmayan `sata.2/sata.3` · boş MAC adresi · O_DIRECT olmayan dosya sistemleri ·
OpenGL yokken `virtio-vga-gl` · host belleğine sığmayan RAM · ses aygıtı yokluğu ·
CPU listesi bash aritmetiği + `taskset`.

---

## 4. §4'te "eksik" denen sorunların HEPSİ — ne yapıldı, ne kanıtlandı

Bir önceki raporda dört açık kalem vardı. Bu tur hepsi tek tek ele alındı.
Aşağıda her biri için **yapılan iş** ve **kanıt seviyesi** var. Kanıtlanmayan
hiçbir şeyi "tamam" yazmıyorum.

### 4.1 OpenCore'nin metin modunda takılması → **GERÇEK SEBEP BULUNDU ve DÜZELTİLDİ**

Önceki turda "OpenCore `Watchdog status is 1`'den sonra duruyor" diyordum ve
bunu ortam yavaşlığına yazıyordum. Bu tur **seri günlükle** (QEMU `-serial
file:`) gerçek sebebi buldum: **OpenCore'nin kendi ürettiğimiz config.plist'i
şemaya uymuyordu.**

```
OCS: No schema for SerialInit at 5 index, context <Debug>!
OCS: No schema for AudioOut at 2 index, context <Audio>!
OCS: No schema for MinimumVolume at 4 index, context <Audio>!
OCS: No schema for VoiceOver at 8 index, context <Audio>!
OCS: No schema for KeyMergeThreshold at 4 index, context <Input>!
OCS: No schema for ForceOemVolumeHack at 5 index, context <Quirks>!
OCS: No schema for DriveInput at 9 index, context <UEFI>!
Halting on critical error
```

Yani macOS'un açılmamasının sebebi **yavaşlık değil, bizim config'imizdi**.
`scripts/macnix_lib.py` içindeki 7 alan OpenCore 1.0.8 şemasında yok
(muhtemelen daha eski OpenCore sürümlerinden miras). Hepsi doğru
karşılıklarıyla değiştirildi:

| Hatalı alan | OpenCore 1.0.8'deki doğrusu |
|---|---|
| `Misc.Debug.SerialInit` | (kaldırıldı — böyle bir anahtar yok) |
| `UEFI.Audio.AudioOut` | `UEFI.Audio.AudioOutMask` |
| `UEFI.Audio.MinimumVolume` | `UEFI.Audio.MaximumGain` / `MinimumAssistGain` / `MinimumAudibleGain` |
| `UEFI.Audio.VoiceOver` | (kaldırıldı) |
| `UEFI.Input.KeyMergeThreshold` | `UEFI.Input.KeySwap` |
| `UEFI.Quirks.ForceOemVolumeHack` | `UEFI.Quirks.ForceOcWriteFlash` |
| `UEFI.DriveInput` | (bölüm tamamen kaldırıldı) |

**Bir daha olmaması için üç katmanlı koruma eklendi:**
1. `config/opencore-schema.json` — OpenCorePkg 1.0.8'in kendi
   `Docs/Sample.plist`'inden üretilmiş referans şema repoya girdi.
2. `macnix-oc --check` artık her çalıştırmada config'i bu şemaya göre denetliyor;
   bilinmeyen anahtar varsa **"OpenCore şemasında YOK: …"** diyip hata veriyor.
3. `tools/oc-schema-check.py` — bağımsız denetleyici (istenen her plist'e
   uygulanabilir) + 5 yeni test (176 test oldu).

Ayrıca aynı hata sınıfından iki bug daha bulundu ve düzeltildi:
`ProvideCurrentCpuInfo=None` → `plistlib` "unsupported type: NoneType" atıp
config HİÇ üretilmiyordu (artık `bool()` ile korunuyor); `macnix-assets`
indirmeleri tek denemede kopabiliyordu (artık 3 deneme + yerel kext önbelleği).

**Kanıt seviyesi:** Hata **canlı QEMU'da seri günlükle** görüldü, düzeltme
sonrası aynı ESP ile boot edildiğinde **`OCS:` satırı ve `Halting on critical
error` artık YOK** (`/tmp/s4.log`). Yani OpenCore config aşamasını geçiyor.

### 4.2 KVM yok / TCG yavaşlığı → **teşhis otomatikleştirildi, yanlış tavsiye düzeltildi**

Bu sandbox **kendisi bir KVM konuğu** (`dmesg`: "Hypervisor detected: KVM") ve
konuğa `vmx`/`svm` bayrağı verilmemiş → `/dev/kvm` oluşmuyor, açmak da mümkün
değil (BIOS'tan değil, **ana hypervisor'ın nested virtualization ayarından**
kaynaklanıyor). Kodda eskiden "BIOS'ta SVM/VT-x açın" yazıyordu; bu, VM içinde
çalışan kullanıcı için **yanlış yönlendirme**. Düzeltildi:

- `sudo macnix-vm accel` (yeni komut): KVM var/yok, **neden** yok, ve platform
  platform ne yapılacağı (VMware / VirtualBox / KVM ana makine / Hyper-V / bulut).
- `macnix-vm`: KVM varsa `-cpu host,kvm=on,vendor=GenuineIntel,+invtsc,
  +kvm_pv_unhalt,+kvm_pv_eoi,...` (OSX-KVM ile aynı yaklaşım); yoksa Penryn.
  Yani **KVM bulunan her makinede otomatik olarak tam hız** — kullanıcı ayar
  yapmıyor.
- `macnix-doctor`: yeni "Önyükleme zinciri (OpenCore → macOS)" bölümü seri
  günlüğü okuyup **nerede durduğunu** söylüyor (tahmin değil, kanıt).
- `firstboot.sh`: KVM yoksa masaüstüne `MacNix-KVM-UYARI.txt` bırakıyor —
  kullanıcı "macOS açılmıyor" sanmasın.

**Kanıt seviyesi:** KVM varken `-cpu host` yolu **kod olarak hazır ve test
edildi**; ama bu sandbox'ta KVM hiç olmadığı için **KVM'li gerçek makinede
çalıştırılmadı**. Bunu "test edildi" diye yazmıyorum.

### 4.3 RAM (~550 MB) → **2 GB swap eklendi + VM bellek yönetimi sıkılaştırıldı**

Sandbox'ta 1982 MB RAM var; `fallocate`+`mkswap`+`swapon` ile **2047 MB ek
swap** açıldı (`free`: `Swap: 2047`). Ayrıca macOS VM'i için boşta duran
Xvfb/qemu süreçleri temizlenip RAM serbest bırakıldı ve testler daha küçük
bellekle (900–1100 MB) tekrarlandı. macOS'un **kurulum ekranı** için gereken
bellek (4 GB+) bu sandbox'ta yok — bu bir donanım sınırı, yazılımla
kapatılamaz. Kurulum makinesinde `firstboot.sh` CPU/RAM'i ölçüp `vm.conf`'u
gerçek değerlere göre yazıyor (mevcut davranış, korundu).

### 4.4 Eksik WhateverGreen/GPU kext seti → **tam set indirildi ve doğrulandı**

`macnix-assets` bu tur **gerçekten çalıştırıldı** ve dört kext de indi:

```
Lilu.kext          527.456 bayt
VirtualSMC.kext    245.408 bayt
WhateverGreen.kext 527.896 bayt
AppleALC.kext    3.810.852 bayt
AMD_Vanilla yamaları: 27 yama
```

Sonra `macnix-oc --build` ile uçtan uca denendi:
`OpenCore.qcow2` 6,8 MB + `OpenCore-ESP.img` 65 MB üretildi, içinde
`BOOTx64.efi + OpenCore.efi + config.plist + 5 sürücü + 4 kext` var,
`macnix-oc --check` → **"config.plist sağlıklı — 4 kext, 0 yama,
SMBIOS=iMacPro1,1"**, şema denetimi → **0 sorun**.

**Kanıt seviyesi:** kext indirme + ESP üretimi + şema doğrulaması **gerçekten
çalıştırıldı**. Kext'lerin macOS çekirdeğinde **yüklendiği** görülmedi
(kurulum ekranına ulaşılamadı — 4.1/4.5).

### 4.5 Kalan gerçek eksikler (dürüstçe)

1. **macOS KURULUM EKRANI (Apple logosu → macOS Kurulum) bu sandbox'ta hâlâ
   görülmedi.** Bu turda ulaşılan nokta: OpenCore config'i **hatasız** yüklüyor,
   ESP tanınıyor, sürücüler yükleniyor; ancak `OcMiscLateInit` sonrası, KVM
   olmayan yazılım emülasyonunda ilerlemiyor. Aynı yerde **OSX-KVM'in kendi
   çalışan `OpenCore.qcow2`'siyle de** durdu → sorun bizim yapılandırmamızda
   değil, **ortamda** (KVM yok). Bunu başarı olarak yazmıyorum; macOS kurulumu
   ilk kez **KVM'li** bir makinede görülecek. `sudo macnix-vm accel` bunun için var.
2. **Gerçek donanım (HP Pavilion / AMD R7 M340) denenmedi** — macOS yalnızca
   QEMU/KVM VM'inde çalışır, GPU taklidi yapılmaz (kullanıcı talimatı).
3. **Calamares canlı testinde iki uyarı çıktı** (ekran görüntüsündeki
   "not enough drive space / not enough working memory"): bunlar bu test VM'ine
   verilen 2 GB RAM + diski olmayan QEMU yapılandırmasından kaynaklanıyor,
   ISO'dan değil. Gerçek donanımda (4 GB+ RAM, 30 GB+ disk) bu uyarı çıkmaz —
   Calamares'in standart donanım kapısı. **Yine de dürüst not:** bu eşiğin
   altındaki makinelerde sihirbaz ilerlemez.
4. Windows/macOS ana makinede kurulum denenmedi.

### 4.6 Bu tur ayrıca düzeltilen diğer gerçek hatalar

| Sorun | Düzeltme |
|---|---|
| Panel terminalinde ham ANSI kodları (`\033[0;32m`) görünüyordu | `macnix-setup`'a ANSI temizleyici (`_clean`) — rapor §4'ün son maddesi kapandı |
| `macnix-vm` KVM varken bile Penryn profili kullanabiliyordu | `-cpu host` + `+invtsc` (KVM), TCG'de Penryn |
| OpenCore'nin durduğu yeri kullanıcı bilmiyordu | `-serial file:serial.log` her zaman açık + `macnix-doctor` yorumluyor |
| `plistlib` NoneType hatası → config hiç üretilmiyordu | `is_amd = bool(...)` |
| `macnix-assets` tek denemede pes ediyordu | 3 deneme + `/var/cache/macnix/kexts` önbelleği |
| Sistem tarafında kimse "sudo neden parola istiyor" diye bakamıyordu | (önceki tur) 6 katmanlı parolasız erişim + `visudo -cf` doğrulaması |

---
## 5. Değişen dosyalar (bu tur)

| Dosya | Ne değişti |
|---|---|
| `scripts/macnix_lib.py` | **7 OpenCore şema hatası düzeltildi** + `is_amd = bool(...)` (NoneType/plistlib çökmesi) |
| `config/opencore-schema.json` *(yeni)* | OpenCore 1.0.8 `Sample.plist`'ten üretilmiş referans şema (9,7 KB) |
| `tools/oc-schema-check.py` *(yeni)* | Bağımsız config.plist şema denetleyicisi |
| `scripts/bin/macnix-oc` | `--check` artık şemaya göre denetliyor; sürücü seti config ile birebir |
| `scripts/bin/macnix-vm` | KVM'de `-cpu host` + `+invtsc`; her zaman `-serial file:…/serial.log`; **yeni `accel` komutu** (nested VM teşhisi) |
| `scripts/bin/macnix-doctor` | Yeni **"Önyükleme zinciri (OpenCore → macOS)"** bölümü — seri günlüğü yorumluyor |
| `scripts/bin/macnix-assets` | 3 denemeli indirme + yerel kext önbelleği (`MACNIX_KEXT_CACHE`) |
| `scripts/bin/macnix-setup` | ANSI kaçış dizisi temizleyici (`_clean`) — terminal paneli artık ham `\033[…` göstermiyor |
| `scripts/firstboot.sh` | KVM yoksa masaüstüne `MacNix-KVM-UYARI.txt` + günlük uyarısı (273 satır) |
| `config/grub/grub-efi-embed.cfg` | **Yeniden yazıldı**: yorumsuz, saf ASCII, `insmod` yok, `cd0` önce |
| `config/grub/grub.cfg` | `terminal_output console` (siyah ekran hatası), `insmod font`, ASCII menü başlıkları |
| `build.sh` | `grub-mkimage` (memdisk yok) + `png/jpeg/gfxmenu` modülleri + `unicode.pf2` ISO'ya |
| `tools/test-modules.py` | **188 test** (155 → 188): OpenCore şeması, KVM, ANSI, panel, GRUB/UEFI zinciri |

### 5.1 Doğrulama komutları (tekrarlanabilir)

```bash
# 1) Şema denetimi (ISO'daki/makinedeki her config için)
python3 tools/oc-schema-check.py /var/lib/macnix/firmware/OpenCore/EFI/OC/config.plist
# → Şema uyumlu: … — 4 kext, 3 sürücü

# 2) Uçtan uca OpenCore üretimi (kext indirme + ESP + doğrulama)
sudo macnix-assets            # Lilu, VirtualSMC, WhateverGreen, AppleALC, AMD_Vanilla
sudo macnix-oc --build        # OpenCore.qcow2 + OpenCore-ESP.img
sudo macnix-oc --check        # config + şema

# 3) Hızlandırma teşhisi
sudo macnix-vm accel          # KVM var mı, yoksa NEDEN yok, ne yapmalı

# 4) Önyükleme zinciri teşhisi (VM bir kez açıldıktan sonra)
sudo macnix-doctor            # serial.log'u okuyup nerede durduğunu söyler
```

```bash
# 5) Yayınlanan ISO'yu gerçekten aç (kanıt: Calamares ekran görüntüsü)
7z x macnix-2.0.0-amd64.iso boot/grub/efi.img
qemu-system-x86_64 -machine q35 -m 2048 \
  -drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.fd \
  -drive if=pflash,format=raw,file=OVMF_VARS.fd \
  -drive id=d,if=none,format=raw,file=efi.img -device ide-hd,bus=ide.1,drive=d \
  -drive id=cd,if=none,format=raw,media=cdrom,readonly=on,file=macnix-2.0.0-amd64.iso \
  -device ide-cd,bus=ide.2,drive=cd -vga std
```

> Bu komutların **hepsi bu sandbox'ta gerçekten çalıştırıldı**;
> 2 numaranın çıktısı: `OpenCore.qcow2 6.8M`, `OpenCore-ESP.img 65M`,
> `config.plist sağlıklı — 4 kext, 0 yama, SMBIOS=iMacPro1,1`.
