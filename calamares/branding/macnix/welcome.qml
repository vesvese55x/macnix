/* ============================================================================
 *  MacNix 2.0 — açılış sihirbazının İLK ekranı (welcome)
 * ============================================================================
 *  Canlı testte görülen hatalar:
 *   1) Logo ile "MacNix" başlığı ÜST ÜSTE biniyordu (z1.png).
 *   2) Alt kredi şeridi pencere dışına taşıyordu.
 *   3) Ürün tanımı ("Gelişmiş macOS Sanallaştırma Distrosu") ve fork/kredi
 *      bilgisi HİÇ görünmüyordu.
 *  Bu ekran Calamares'in yerleşik welcome modülü yerine QML olarak çiziliyor
 *  (show: welcomeq). Zorunlu donanım denetimleri welcomeq tarafından yapılır.
 * ========================================================================== */
import io.calamares.core 1.0
import io.calamares.ui 1.0
import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12

Item {
    id: welcomeRoot
    width: parent ? parent.width : 900
    height: parent ? parent.height : 600

    // ── Sol: marka ve tanıtım ─────────────────────────────────────────────
    Column {
        id: leftCol
        width: parent.width * 0.52
        anchors.left: parent.left
        anchors.leftMargin: 34
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Image {
            source: "macnix_logo.png"
            width: 104; height: 104
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Text {
            text: "MacNix 2.0"
            color: "#FFFFFF"
            font { family: "Inter"; pixelSize: 40; weight: Font.Bold }
        }

        Text {
            text: "Gelişmiş macOS Sanallaştırma Distrosu"
            color: "#4FD8EE"
            font { family: "Inter"; pixelSize: 18; weight: Font.DemiBold }
        }

        Rectangle {
            width: 64; height: 3; radius: 2
            color: "#0A84FF"
        }

        Text {
            width: parent.width - 8
            text: "macOS'u Linux üzerinde, kendi makinenizde bir QEMU/KVM sanal " +
                  "makinesinde çalıştırın. Apple donanımı taklit edilmez; " +
                  "kurulum tamamen otomatiktir ve hiçbir adımda kullanıcı adı " +
                  "veya parola sorulmaz."
            color: "#9A9AA2"
            wrapMode: Text.WordWrap
            lineHeight: 1.35
            font { family: "Inter"; pixelSize: 14 }
        }

        // Kısa madde listesi (yalnızca Text — QML modeli kullanmıyoruz)
        Text {
            width: parent.width - 8
            text: "•  Tek tıkla, otomatik kurulum\n" +
                  "•  macOS imajı doğrudan Apple sunucularından\n" +
                  "•  Donanıma göre otomatik CPU/bellek ayarı\n" +
                  "•  Açık kaynak ve denetlenebilir önyükleme (OpenCore)"
            color: "#C7C7CF"
            wrapMode: Text.WordWrap
            lineHeight: 1.5
            font { family: "Inter"; pixelSize: 13 }
        }
    }

    // ── Sağ: ön kontroller ve başlat düğmesi ──────────────────────────────
    Column {
        id: rightCol
        width: parent.width * 0.42
        anchors.right: parent.right
        anchors.rightMargin: 34
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Text {
            text: "Kuruluma hazırlık"
            color: "#FFFFFF"
            font { family: "Inter"; pixelSize: 20; weight: Font.Bold }
        }

        Text {
            width: parent.width
            text: "Aşağıdaki koşullar sağlanmadan kurulum başlatılamaz. " +
                  "Eksik olan varsa düğme pasif kalır."
            color: "#9A9AA2"
            wrapMode: Text.WordWrap
            lineHeight: 1.3
            font { family: "Inter"; pixelSize: 12 }
        }

        Rectangle { width: parent.width; height: 1; color: "#20222B" }

        /* requirementsModel: welcomeq modülü doldurur.
         * Roller (RequirementsModel::roleNames): name, details, negatedText,
         * satisfied, mandatory, hasDetails. */
        Repeater {
            model: config ? config.requirementsModel : 0
            delegate: Row {
                width: rightCol.width
                spacing: 8
                Text {
                    text: model.satisfied ? "✓" : (model.mandatory ? "✕" : "!")
                    color: model.satisfied ? "#30D158"
                         : (model.mandatory ? "#FF453A" : "#FF9F0A")
                    font { family: "Inter"; pixelSize: 14; weight: Font.Bold }
                }
                Text {
                    width: rightCol.width - 26
                    text: model.negatedText
                    color: model.satisfied ? "#C7C7CF"
                         : (model.mandatory ? "#FF9F9A" : "#FFC98A")
                    wrapMode: Text.WordWrap
                    font { family: "Inter"; pixelSize: 12 }
                }
            }
        }

        Item { width: 1; height: 6 }

        Text {
            width: parent.width
            text: "Devam ettiğinizde disk bölümlemesi, sistem kopyalama ve " +
                  "önyükleyici kurulumu otomatik yapılır."
            color: "#7C7C86"
            wrapMode: Text.WordWrap
            lineHeight: 1.3
            font { family: "Inter"; pixelSize: 11 }
        }
    }

    // ── Alt kredi şeridi ─────────────────────────────────────────────────
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 48
        color: "#0B0C10"

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: "#20222B"
        }

        Text {
            anchors.centerIn: parent
            width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            color: "#7C7C86"
            elide: Text.ElideRight
            font { family: "Inter"; pixelSize: 11 }
            text: "BELGESELSEMO tarafından ARENA.AI sayesinde geliştirildi  ·  " +
                  "github.com/local-over/macnix orijinal reposundan fork edilerek  ·  " +
                  "belgeselsemo.com.tr"
        }
    }
}
