# GPU Gerçeği: Bu Donanımda macOS Hızlandırma Neden Mümkün Değil

**Donanım:** HP Pavilion, AMD A10-9600P, 16 GB RAM
**GPU'lar:** R5 iGPU `1002:9874` (Wani) + R7 M340 dGPU `1002:6660` (Hainan), muxless

---

## 1. Kısa cevap

**Hızlandırma imkânsız.** MacNix bu makinede kurulur ve macOS açılır, ama
grafik **yazılım render** ile çalışır: masaüstü, tarayıcı, ofis akıcı; oyun,
Final Cut, video kodlama yok.

Üç yol var, ikisi kapalı:

| Yol | Durum | Neden |
|---|---|---|
| Apple sürücüsü | ❌ yok | Hainan/Wani hiçbir macOS sürümünde desteklenmedi |
| Cihaz kimliği taklidi | ❌ siyah ekran | Sürücü yüklenir, kartı tanımaz; framebuffer gelmez |
| Sanal GPU (VirGL/SVGA3D/PVGPU) | ❌ | VirGL Linux konuk; SVGA3D'nin macOS sürücüsü yok; PVGPU macOS+Apple Silicon **host** ister |
| **GPU'suz yazılım render** | ✅ çalışır | macOS RAM/CPU ile çizer |
| **Uyumlu AMD kart takmak** | ✅ tam hız | RX 580 / 6600+ — Apple sürücüsü var |

---

## 2. Neden taklit (spoof) işe yaramıyor

Apple'ın AMD kextleri **kapalı kaynak** ve iki şeye bağlı:

1. **PCI kimliği** — kartın sürücü tablosunda olması
2. **Firmware** — kext, kartın VBIOS'undaki belirli yapıları okur
   (güç yönetimi, bellek eğitimi, display controller tanımı)

R7 M340'ın kimliğini `1002:67DF` (RX 580) yaparsanız kext yüklenir, ama Hainan
çipinin VBIOS'unda RX 580'in beklediği yapılar yoktur → sürücü iletişim
kuramaz → **çekirdek panik veya siyah ekran**. Bu, forumlarda defalarca
raporlanmış kesin bir sonuçtur; "doğru config" ile çözülmez.

OpenCore Legacy Patcher (OCLP) da çözmez: OCLP **desteklenen** donanımı yeni
macOS sürümlerinde çalıştırmak için yama yapar; hiç sürücüsü olmayan bir çip
için firmware üretmez.

**muxless** olması ayrıca kötü: dGPU görüntüyü iGPU üzerinden verir; dGPU'yu
tek başına passthrough etmek görüntü vermez, iGPU'yu macOS sürücüsü olmadığı
için kullanamazsınız.

---

## 3. "Colab GPU'su ile hızlandırma" — neden olmaz

Google Colab (ve Kaggle, RunPod) **uzak bir Linux makinesinde GPU kirasıdır**.
macOS'un grafik yığınına bağlanamaz; Metal'e erişemez; Final Cut'ı hızlandırmaz;
oyun oynatmaz. Yapabileceği tek şey **işi oraya göndermek**:

| Yapılabilir | Yapılamaz |
|---|---|
| LLM / Stable Diffusion çıkarımı | Metal, Final Cut, Xcode GPU derlemesi |
| `ffmpeg -c:v h264_nvenc` kodlama | Oyun, Blender'ın macOS Metal viewport'u |
| Blender **Cycles** render kuyruğu | macOS arayüzünün hızlanması |

Ayrıca Colab'ı tünellediğinizde (ngrok vb.) Google'ın kullanım şartlarını
ihlal edersiniz ve hesabınız kapatılır. Kaggle/RunPod ücretli seçeneklerdir
ama aynı sınır geçerli: **uzak Linux GPU = macOS GPU değil**.

---

## 4. Gerçek çözüm: macOS sürücüsü olan AMD kart

| Kart | Nerede | Maliyet | macOS |
|---|---|---|---|
| **RX 580 8 GB** | ikinci el, en yaygın | ~düşük | 10.12 → 15 (en sorunsuz) |
| RX 6600 / 6600 XT | ikinci el | orta | 11+ |
| RX 6800 / 6900 XT | ikinci el | yüksek | 11+ |
| Vega 56/64 | ikinci el | orta | 10.13+ |
| **NVIDIA (hepsi)** | — | — | ❌ 10.14 sonrası sürücü yok |
| **Intel iGPU (modern)** | — | — | ❌ yeni nesiller desteklenmez |
| RDNA3 (RX 7000) | — | — | ❌ desteklenmez |

Kartı **masaüstü kasaya** takmak gerekir. Dizüstünde MXM/Thunderbolt eGPU
teorik olarak mümkün ama bu makinede Thunderbolt yok ve BIOS'ta eGPU boot
desteği yok — pratik değil.

### MacNix ne yapıyor

- `config/gpu-db.json` (14 aile) PCI kimliğine bakar
- Uyumlu kart görürse: **VFIO modu** — kartı host'tan ayırır, macOS VM'ine verir,
  IOMMU parametrelerini GRUB'a yazar, `vfio-pci` bağlar
- Görmüyorsa: **yazılım render modu** — her şey çalışır, hızlandırma olmaz,
  bunu kurulum ekranında ve `macnix-doctor` çıktısında **açıkça söyler**

Yani MacNix bu donanımda **yanlış vaat vermiyor**: "Yazılım render modu — GPU
hızlandırma yok" yazar (VM testinde birebir görüldü).

---

## 5. Bu makinede gerçekçi beklenti

| İş | Bu donanımda |
|---|---|
| macOS kurmak, masaüstü, Safari, ofis | ✅ akıcı |
| Xcode ile küçük proje derlemek | ✅ (CPU) |
| 1080p video oynatma | ✅ genelde |
| Final Cut timeline | ❌ takılır |
| Oyun | ❌ oynanmaz |
| Blender viewport | ❌ ağır |

Karar sizin: bu makinede **denemek ve görmek** için MacNix yeterli; ciddi
grafik işi için ya uyumlu AMD kartlı bir masaüstü ya da işi Colab/RunPod'a
gönderme yolu gerekir.
