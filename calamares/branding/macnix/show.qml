/* ============================================================================
 *  MacNix 2.0 — Calamares slayt destesi (kurulum ilerleme ekranı)
 * ============================================================================
 *  TASARIM KURALI (canlı testte öğrenildi): bu ortamda Repeater + satır içi
 *  nesne dizisi (model: [{...}]) Calamares'i ÇÖKERTEBİLİYOR. Bu yüzden her
 *  slayt ELLE yazılmıştır; yalnızca QtQuick + calamares.slideshow kullanılır.
 *
 *  Neden slayt var: MacNix 2.0'ın önceki sürümünde ilerleme ekranının içerik
 *  bölümü TAMAMEN BEYAZ/BOŞ görünüyordu (canlı test: i2.png). Artık aynı alanda
 *  dönen tanıtım kartları (görsel + açıklama) gösteriliyor.
 *
 *  Görseller: tools/assets/gen-slide-art.py üretir (logo paleti, şeffaf PNG).
 * ========================================================================== */
import QtQuick 2.12
import calamares.slideshow 1.0

Presentation {
    id: presentation

    // Zemin: her slaytın arkasında tam siyah (logo ile aynı ton)
    Rectangle {
        anchors.fill: parent
        color: "#05060A"
        z: -1
    }

    Timer {
        id: advanceTimer
        interval: 6500
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    // ── Slayt 1 — Karşılama ───────────────────────────────────────────────
    Slide {
        Item {
            anchors.fill: parent

            Image {
                id: logo1
                source: "macnix_logo.png"
                width: 132; height: 132
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 18
            }
            Text {
                id: t1a
                text: "MacNix 2.0"
                color: "#FFFFFF"
                font.family: "Inter"; font.pixelSize: 34; font.weight: Font.Bold
                anchors.top: logo1.bottom
                anchors.topMargin: 6
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                id: t1b
                text: "Gelişmiş macOS Sanallaştırma Distrosu"
                color: "#4FD8EE"
                font.family: "Inter"; font.pixelSize: 17; font.weight: Font.DemiBold
                anchors.top: t1a.bottom
                anchors.topMargin: 6
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                id: t1c
                text: "Kurulum sürüyor — bu sırada MacNix'in ne yaptığını okuyabilirsiniz.\nBilgisayarınızı kapatmayın; işlem birkaç dakika sürer."
                color: "#9A9AA2"
                font.family: "Inter"; font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.35
                anchors.top: t1b.bottom
                anchors.topMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ── Slayt 2 — Donanım profili ─────────────────────────────────────────
    Slide {
        Item {
            anchors.fill: parent
            Image {
                id: img2
                source: "slide-hardware.png"
                width: 168; height: 168
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 8
            }
            Text {
                id: t2a
                text: "Donanımınız tanınıyor"
                color: "#FFFFFF"
                font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold
                anchors.top: img2.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                id: t2b
                text: "MacNix; CPU çekirdek sayısını, belleği ve ekran kartını okur.\n" +
                      "Sanal makineye verilecek çekirdek/RAM bu rapora göre belirlenir;\n" +
                      "böylece hem Linux hem macOS aynı anda rahat çalışır."
                color: "#9A9AA2"
                font.family: "Inter"; font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.35
                anchors.top: t2a.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ── Slayt 3 — macOS indirme ───────────────────────────────────────────
    Slide {
        Item {
            anchors.fill: parent
            Image {
                id: img3
                source: "slide-download.png"
                width: 168; height: 168
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 8
            }
            Text {
                id: t3a
                text: "macOS doğrudan Apple'dan"
                color: "#FFFFFF"
                font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold
                anchors.top: img3.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                id: t3b
                text: "macOS kurtarma imajı (yaklaşık 700 MB) Apple'ın kendi\n" +
                      "sunucularından indirilir. Üçüncü taraf imaj, torrent veya\n" +
                      "kırpılmış sürüm kullanılmaz. İnternet bağlantısı yeterlidir."
                color: "#9A9AA2"
                font.family: "Inter"; font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.35
                anchors.top: t3a.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ── Slayt 4 — Nasıl çalışır (VM) ──────────────────────────────────────
    Slide {
        Item {
            anchors.fill: parent
            Image {
                id: img4
                source: "slide-vm.png"
                width: 168; height: 168
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 8
            }
            Text {
                id: t4a
                text: "macOS bir sanal makinede çalışır"
                color: "#FFFFFF"
                font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold
                anchors.top: img4.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                id: t4b
                text: "Apple donanımı taklit edilmez; macOS, Linux üzerinde QEMU/KVM\n" +
                      "sanal makinesinde çalışır. Bu yüzden kurulum bir \"Hackintosh\"\n" +
                      "değildir: macOS kendi sanal donanımını görür ve güncellemelerini alır."
                color: "#9A9AA2"
                font.family: "Inter"; font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.35
                anchors.top: t4a.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ── Slayt 5 — Performans / GPU dürüstlüğü ─────────────────────────────
    Slide {
        Item {
            anchors.fill: parent
            Image {
                id: img5
                source: "slide-perf.png"
                width: 168; height: 168
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 8
            }
            Text {
                id: t5a
                text: "Performans beklentisi — dürüst olalım"
                color: "#FFFFFF"
                font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold
                anchors.top: img5.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                id: t5b
                text: "Masaüstü, tarayıcı ve uygulamalar akıcı çalışır. Ekran kartı\n" +
                      "hızlandırması ise yalnızca Apple sürücüsü bulunan AMD kartlarda\n" +
                      "mümkündür; diğer kartlarda yazılım render kullanılır (oyun/video\n" +
                      "hızlandırma olmaz). Bu bir hata değil, Apple'ın sürücü modelinin sonucudur."
                color: "#9A9AA2"
                font.family: "Inter"; font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.35
                anchors.top: t5a.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ── Slayt 6 — Güvenlik / OpenCore ─────────────────────────────────────
    Slide {
        Item {
            anchors.fill: parent
            Image {
                id: img6
                source: "slide-shield.png"
                width: 158; height: 158
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 6
            }
            Image {
                id: img6b
                source: "slide-opencore.png"
                width: 76; height: 76
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: 0.95
                anchors.left: img6.right
                anchors.leftMargin: -18
                anchors.verticalCenter: img6.verticalCenter
            }
            Text {
                id: t6a
                text: "Açık kaynak, denetlenebilir önyükleme"
                color: "#FFFFFF"
                font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold
                anchors.top: img6.bottom
                anchors.topMargin: 6
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                id: t6b
                text: "Sanal makinenin önyükleyicisi OpenCore'dur: benzersiz SMBIOS\n" +
                      "kimliği, düzgün NVRAM taklidi ve şeffaf yapılandırma. Tüm bileşenler\n" +
                      "açık kaynaktır ve ISO içinde incelenebilir."
                color: "#9A9AA2"
                font.family: "Inter"; font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.35
                anchors.top: t6a.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ── Kapanış slaytı — kredi ────────────────────────────────────────────
    Slide {
        Item {
            anchors.fill: parent
            Image {
                id: logo7
                source: "macnix_logo.png"
                width: 112; height: 112
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: 0.92
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 26
            }
            Text {
                id: t7a
                text: "Neredeyse bitti"
                color: "#FFFFFF"
                font.family: "Inter"; font.pixelSize: 30; font.weight: Font.Bold
                anchors.top: logo7.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                id: t7b
                text: "Kurulum tamamlandığında makine yeniden başlar ve macOS\n" +
                      "kendini otomatik olarak kurar. Hiçbir adımda kullanıcı adı\n" +
                      "veya parola sorulmaz."
                color: "#9A9AA2"
                font.family: "Inter"; font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.35
                anchors.top: t7a.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    /* Kredi şeridi — TÜM slaytlarda görünür.
     * Kaynak: proje, https://github.com/local-over/macnix adresindeki orijinal
     * MacNix deposundan fork edilerek BELGESELSEMO tarafından ARENA.AI
     * sayesinde geliştirilmiştir. */
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 44
        color: "#0B0C10"
        z: 10

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: "#20222B"
        }

        Text {
            anchors.centerIn: parent
            text: "MacNix · Gelişmiş macOS Sanallaştırma Distrosu  —  " +
                  "BELGESELSEMO tarafından ARENA.AI sayesinde geliştirildi  ·  " +
                  "github.com/local-over/macnix orijinal reposundan fork  ·  " +
                  "belgeselsemo.com.tr"
            color: "#7C7C86"
            font.family: "Inter"; font.pixelSize: 11
            elide: Text.ElideRight
            width: parent.width - 24
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
