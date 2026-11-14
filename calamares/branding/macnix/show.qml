/* ============================================================================
 *  MacNix 2.0 — Calamares slayt destesi (kurulum ilerleme ekranı)
 * ============================================================================
 *  NEDEN: MacNix 2.0'ın önceki sürümünde ilerleme ekranının içerik bölümü
 *  TAMAMEN BOŞ/BEYAZ görünüyordu (canlı test: i2.png). Artık aynı alanda dönen
 *  tanıtım kartları (görsel + açıklama) gösteriliyor.
 *
 *  TASARIM KURALLARI (canlı testlerden):
 *   • Repeater + satır içi nesne dizisi (model: [{...}]) Calamares'i
 *     ÇÖKERTEBİLİYOR → her slayt ELLE yazıldı.
 *   • Yalnızca QtQuick + calamares.slideshow kullanılır (Controls/Layouts YOK).
 *   • İçerik Column + anchors.centerIn ile DİKEY ORTALANIR.
 *   • Görseller: tools/assets/gen-slide-art.py (logo paleti, şeffaf PNG).
 *
 *  Kredi şeridi (BELGESELSEMO / ARENA.AI / fork / belgeselsemo.com.tr) her
 *  slaytta görünür.
 * ========================================================================== */
import QtQuick 2.12
import calamares.slideshow 1.0

Presentation {
    id: presentation

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

    Slide {
        Item {
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                width: parent.width - 72
                spacing: 12

            Image {
                source: "macnix_logo.png"
                width: 124; height: 124
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "MacNix 2.0 — Gelişmiş macOS Sanallaştırma Distrosu"
                    color: "#FFFFFF"
                    font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.4
                    color: "#9A9AA2"
                    font.family: "Inter"; font.pixelSize: 14
                    text: "Kurulum sürüyor. Bu sırada MacNix'in ne yaptığını okuyabilirsiniz. " +
                    "Bilgisayarınızı kapatmayın; işlem birkaç dakika sürer."
                }
            }
        }
    }

    Slide {
        Item {
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                width: parent.width - 72
                spacing: 12

            Image {
                source: "slide-hardware.png"
                width: 150; height: 150
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Donanımınız tanınıyor"
                    color: "#FFFFFF"
                    font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.4
                    color: "#9A9AA2"
                    font.family: "Inter"; font.pixelSize: 14
                    text: "MacNix; CPU çekirdek sayısını, belleği ve ekran kartını okur. " +
                    "Sanal makineye verilecek çekirdek/RAM bu rapora göre belirlenir; " +
                    "böylece hem Linux hem macOS aynı anda rahat çalışır."
                }
            }
        }
    }

    Slide {
        Item {
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                width: parent.width - 72
                spacing: 12

            Image {
                source: "slide-download.png"
                width: 150; height: 150
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "macOS doğrudan Apple'dan"
                    color: "#FFFFFF"
                    font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.4
                    color: "#9A9AA2"
                    font.family: "Inter"; font.pixelSize: 14
                    text: "macOS kurtarma imajı (yaklaşık 700 MB) Apple'ın kendi sunucularından " +
                    "indirilir. Üçüncü taraf imaj, torrent veya kırpılmış sürüm " +
                    "kullanılmaz. İnternet bağlantısı yeterlidir."
                }
            }
        }
    }

    Slide {
        Item {
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                width: parent.width - 72
                spacing: 12

            Image {
                source: "slide-vm.png"
                width: 150; height: 150
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "macOS bir sanal makinede çalışır"
                    color: "#FFFFFF"
                    font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.4
                    color: "#9A9AA2"
                    font.family: "Inter"; font.pixelSize: 14
                    text: "Apple donanımı taklit edilmez; macOS, Linux üzerinde QEMU/KVM sanal " +
                    "makinesinde çalışır. Bu yüzden kurulum bir \"Hackintosh\" değildir: " +
                    "macOS kendi sanal donanımını görür ve güncellemelerini alır."
                }
            }
        }
    }

    Slide {
        Item {
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                width: parent.width - 72
                spacing: 12

            Image {
                source: "slide-perf.png"
                width: 150; height: 150
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Performans beklentisi — dürüst olalım"
                    color: "#FFD60A"
                    font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.4
                    color: "#9A9AA2"
                    font.family: "Inter"; font.pixelSize: 14
                    text: "Masaüstü, tarayıcı ve uygulamalar akıcı çalışır. Ekran kartı hızlandırması " +
                    "ise yalnızca Apple sürücüsü bulunan AMD kartlarda mümkündür; diğer " +
                    "kartlarda yazılım render kullanılır (oyun/video hızlandırma olmaz). " +
                    "Bu bir hata değil, Apple'ın sürücü modelinin sonucudur."
                }
            }
        }
    }

    Slide {
        Item {
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                width: parent.width - 72
                spacing: 12

            Image {
                source: "slide-shield.png"
                width: 140; height: 140
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Açık kaynak, denetlenebilir önyükleme"
                    color: "#FFFFFF"
                    font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.4
                    color: "#9A9AA2"
                    font.family: "Inter"; font.pixelSize: 14
                    text: "Sanal makinenin önyükleyicisi OpenCore'dur: benzersiz SMBIOS kimliği, " +
                    "düzgün NVRAM taklidi ve şeffaf yapılandırma. Tüm bileşenler açık " +
                    "kaynaktır ve ISO içinde incelenebilir."
                }
                Image {
                    source: "slide-opencore.png"
                    width: 68; height: 68
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    opacity: 0.95
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Slide {
        Item {
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                width: parent.width - 72
                spacing: 12

            Image {
                source: "macnix_logo.png"
                width: 104; height: 104
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Neredeyse bitti"
                    color: "#FFFFFF"
                    font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.4
                    color: "#9A9AA2"
                    font.family: "Inter"; font.pixelSize: 14
                    text: "Kurulum tamamlandığında makine yeniden başlar ve macOS kendini " +
                    "otomatik olarak kurar. Hiçbir adımda kullanıcı adı veya " +
                    "parola sorulmaz."
                }
            }
        }
    }

    // ── Kredi şeridi — TÜM slaytlarda (en üst katman) ──────────────────────
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
            width: parent.width - 24
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: "#7C7C86"
            font.family: "Inter"; font.pixelSize: 11
            text: "MacNix · Gelişmiş macOS Sanallaştırma Distrosu — BELGESELSEMO " +
                  "tarafından ARENA.AI sayesinde geliştirildi · belgeselsemo.com.tr"
        }
    }
}
