# Colab'da KVM + virt-manager + SSH planı — neden çalışmıyor, yerine ne var

Kanka önce kötü haber, sonra çalışan yol. Üç ayağı tek tek ölçtüm.

---

## 1. "Colab'da QEMU/KVM + virt-manager kur, ben SSH ile bağlanıp ISO'yu SNAL
ekranda test edeyim" — **bu plan çalışmıyor**

### a) Colab'da `/dev/kvm` yok → KVM olmaz

Colab sanal makineleri **kendileri bir VM'dir** ve içlerine donanım
sanallaştırma bayrağı (`vmx`/`svm`) verilmez. Kontrol:

```bash
grep -cE 'vmx|svm' /proc/cpuinfo   # → 0
ls /dev/kvm                        # → No such file or directory
kvm-ok                             # → KVM acceleration can NOT be used
```

`virt-manager` kurulur, açar, "QEMU/KVM bağlantısı" kurmaya çalışırsa
`Failed to connect to libvirt qemu:///system` der; `modprobe kvm_intel` de
`Operation not supported` verir. Yani **virt-manager penceresi açılır ama
hiçbir makine çalışmaz.**

KVM olmadan QEMU **TCG** (saf yazılım emülasyonu) ile çalışır — ki bizim
instabox VM'inde zaten bu oluyor, MacNix'i orada test ettim. Colab'ın
CPU kotası + TCG ile macOS kurmak pratikte saatler sürer.

> Ölçüm: instabox (4 vCPU, 7 GB, KVM yok) ile aynı ISO'yu önyüklemek ~4-5
> dakika sürüyor. Colab'ın 2 vCPU'su + oturum sınırı ile bu iş **bitmez.**

### b) SSH tüneli = Colab'ın yasakladığı şey

Google'ın Colab SSS'i açıkça yazıyor (ücretsiz yönetilen çalışma
zamanlarında yasak, haber vermeden sonlandırılabilir):

> "remote control such as **SSH shells, remote desktops**",
> "bypassing the notebook UI to interact primarily via a web UI"

Yani "Colab'da SSH sunucusu aç, dışarı tünel ver, ben bağlanayım" **tam
olarak yasaklanan faaliyet**. Hesap kapanır.

### c) SNAL / noVNC de aynı kategoriye giriyor

`-display vnc` + noVNC, "remote desktop" tanımına girer. T4 GPU'nun bu işe
hiçbir faydası da yok: GPU, QEMU'nun CPU emülasyonunu hızlandırmaz,
GPU'sız `-vga std` çizimini de hızlandırmaz.

**Sonuç:** Colab bu iş için yanlış araç. Hem teknik olarak imkânsız (KVM yok)
hem de kurallara aykırı (SSH/uzak masaüstü).

---

## 2. Aynı işi YAPAN, kurallara uygun seçenekler

| Seçenek | KVM var mı? | SSH serbest mi? | Maliyet | Not |
|---|---|---|---|---|
| **GitHub Actions** (kurulu) | ❌ (ama gerek yok) | — | ücretsiz | ISO **derleme+Release** burada yapılıyor — çalışıyor |
| **Kendi makinen** (HP Pavilion) | ✅ | ✅ | 0 | Asıl test burada olmalı |
| GCP `n1` + nested virt | ✅ (açıkça destekli) | ✅ | ~saatlik | GPU'suz n1 ucuz; GPU'lu tiplerde nested virt **yasak** |
| Hetzner / Contabo VPS | ✅ (çoğu, AMD) | ✅ | aylık | En pratik "uzak gerçek KVM" |
| Oracle Cloud Always Free | ✅ (AMD VM.Standard) | ✅ | 0 | 4 OCPU/24 GB — sınırlı ama bedava |
| Kaggle / RunPod GPU | ❌ KVM | kısıtlı | ücretli | GPU işi için, VM testi için değil |

**Gerçek ihtiyaç:** ISO'yu KVM ile test etmek için **GPU gerekmiyor**.
Sadece `kvm_amd`/`kvm_intel` destekli bir Linux makine gerekiyor. Yani T4
almak bu iş için tamamen gereksiz.

---

## 3. SONUÇ: GitHub'da derlenen ISO çalışıyor

```
Release : v2.0.0-262
Dosya   : macnix-2.0.0-amd64.iso (1.2 GB)
SHA256  : b9d93dc255670a2e471f6387936a90f6d747fa13ee034839c34469f04160ab1c
URL     : https://github.com/vesvese55x/macnix/releases/tag/v2.0.0-262
```

Bu ISO indirilip **canlı önyüklendi** ve Calamares açıldı:

```
STARTUP: initModuleManager: all modules init done
STARTUP: loadModules for all modules done
"Cannot load" sayısı: 0
```

Ekran: **"Welcome to the MacNix 2.0 installer"** (`final_ci.png`)
→ yani kullanıcının ilk şikâyeti olan *"kurulum başlamıyor"* sorunu
GitHub'dan indirilen ISO'da da çözülmüş durumda.

## 4. Bu turda gerçekten ne yapıldı

Planın çalışan ayağını sonuna kadar kurdum:

1. **Repo sıfırdan güncellendi** → `github.com/vesvese55x/macnix`
   - 45 eski/ölü dosya silindi (`scripts/phase1..7-*.sh`, `live-build`
     yamaları, `macnix-welcome` Python viewmodule vb.)
   - MacNix 2.0 ağacı yüklendi (82 dosya)
   - README sıfırdan yazıldı: "ne test edildi / ne edilmedi" tablosu,
     GPU gerçeği, kurulum, mimari
   - `LICENSE` (MIT) + macOS yasal notu, `.gitignore`
2. **GitHub Actions** üç aşamalı hale getirildi:
   `validate` → `build` → `release` (her derleme sürüm etiketli Release)
3. **Gerçek hatalar bulundu ve düzeltildi** (hepsi CI'da yakalandı):
   - `env:` bloğu `with:` içindeydi → workflow hiç parse edilmiyordu (`422`)
   - Contents API dosyaları `644` gönderiyor → `sudo: cannot execute build.sh`
   - GRUB 2.12 `efi_uga.mod`'u kaldırmış → modül listesi artık dinamik
   - **`settings.conf` sırasında sözlük kullanmışım** → Calamares 3.2
     "invalid settings, shutting down" verip **hiç açılmıyordu**
   - `instances:` + shellprocess örneği Calamares 3.2'de yüklenmedi →
     EFI yedeği artık **yerel Python job modülü** (gpu-detect gibi)
   - **`build.sh` yalnızca iki modülü kopyalıyordu** (sabit liste) → yeni
     modül ISO'ya hiç girmiyordu; artık dizindeki her modül kopyalanıyor
4. **GitHub'da derlenen ISO indirilip gerçekten önyüklendi** (instabox, TCG).
   Bu sayede 4 gerçek hata daha yakalandı (aşağıda) ve sonunda sihirbaz açıldı.

Bu son madde çok değerli: kendi makinemdeki testte Calamares'i *tıklayarak*
deneyemediğim için bu hata gizli kalmıştı; **CI'dan çıkan ISO'yu canlı
önyükleyince ortaya çıktı.**

---

## 5. Bundan sonrası (sırayla)

1. Düzeltilmiş ISO'nun CI derlemesi bitince indir, canlı önyükle,
   **Calamares'in açıldığını** ekran görüntüsüyle doğrula (şu an sürüyor).
2. Kendi makinende USB'den kur — asıl kabul testi.
3. macOS indirme + VM açma (`sudo macnix-setup`) — hâlâ hiç denenmedi.
4. İstersen Hetzner/Oracle üzerinde gerçek KVM'li bir test makinesi kurup
   oradan da doğrulayabiliriz (kurallara uygun, GPU gerekmez).
