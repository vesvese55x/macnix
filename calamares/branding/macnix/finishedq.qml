/* ============================================================================
 *  MacNix 2.0 — kurulum bitti ekranı (finishedq)
 * ============================================================================
 *  Canlı testte görülen hata: standart "finished" ekranında düğme PASİF
 *  görünüyordu (FinishedViewStep.isNextEnabled() her zaman false) ve
 *  kullanıcı kurulumu kapatamıyordu. finishedq + kendi QML'imiz ile:
 *   • büyük yeşil "Bitir ve Yeniden Başlat"  → ViewManager.quit()
 *     (Calamares kapanırken finished modülü yeniden başlatmayı çalıştırır)
 *   • "Bitir"                                → yalnızca kapatır
 *   • başarısızlık durumunda kırmızı uyarı ve "Günlüğü göster" metni
 *  KRİTİK: yeniden başlatma, geri sayım ve "restartNowCommand" Calamares'in
 *  finished modülünde kalır (doğrulanmış yol). Bu QML yalnızca görünüm.
 * ========================================================================== */
import io.calamares.core 1.0
import io.calamares.ui 1.0
import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12

Item {
    id: doneRoot
    // OPAK ZEMİN ŞART: Calamares'in sayfa zemini beyaz olabiliyor; metin
    // renklerimiz koyu tema için seçildi. Zemin yoksa yazılar okunmuyor
    // (gerçek Calamares 3.3.14 çalıştırmasında birebir görüldü).
    Rectangle {
        id: bgFill
        anchors.fill: parent
        color: "#08090D"
        z: -1
    }

    width: parent ? parent.width : 900
    height: parent ? parent.height : 600

    // Geri sayım: kullanıcı hiçbir şeye basmazsa kurulum kendini kapatır,
    // böylece makine yeniden başlar ve macOS kurulumu kendiliğinden başlar.
    property int seconds: 30
    // finished modülünün Config nesnesi: failed / failureMessage / failureDetails
    // / restartNowWanted / doRestart(). (Q_PROPERTY + public slot — doğrulandı.)
    // config QML bağlam özelliği olarak gelir (QmlViewStep::setContextProperty).
    property bool failed: (typeof config !== 'undefined' && config) ? config.failed : false
    property bool counting: !doneRoot.failed

    Timer {
        interval: 1000
        repeat: true
        running: doneRoot.counting
        onTriggered: {
            if (doneRoot.seconds > 0) {
                doneRoot.seconds -= 1
            } else {
                doneRoot.counting = false
                ViewManager.quit()
            }
        }
    }

    Column {
        id: main
        width: Math.min(parent.width - 80, 720)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 30
        spacing: 12

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16

            Image {
                source: "macnix_logo.png"
                visible: !doneRoot.failed
                width: 72; height: 72
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: doneRoot.failed ? "Kurulum tamamlanamadı" : "Kurulum tamamlandı"
                color: doneRoot.failed ? "#FF453A" : "#FFFFFF"
                font { family: "Inter"; pixelSize: 30; weight: Font.Bold }
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.35
            color: "#9A9AA2"
            font { family: "Inter"; pixelSize: 14 }
            text: doneRoot.failed
                  ? ("MacNix kurulamadı. Ayrıntı: " +
                     (config ? (config.failureDetails || config.failureMessage) : "") +
                     "\nTam günlük: /tmp/calamares.log")
                  : ("MacNix 2.0 bilgisayarınıza kuruldu.\n" +
                     "Yeniden başlattığınızda karşınıza çıkan masaüstünde macOS " +
                     "kurulumu kendiliğinden başlar; hiçbir kullanıcı adı, parola " +
                     "veya ek ayar istenmez.")
        }

        Rectangle {
            visible: !doneRoot.failed
            width: parent.width
            height: 64
            radius: 14
            color: "#12141A"
            border.width: 1
            border.color: "#20222B"

            Column {
                anchors.centerIn: parent
                spacing: 4
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: doneRoot.seconds + " saniye içinde kendini kapatıp yeniden başlatacak"
                    color: "#C7C7CF"
                    font { family: "Inter"; pixelSize: 13 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Makine yeniden başlayacak ve macOS kurulumu başlayacak."
                    color: "#7C7C86"
                    font { family: "Inter"; pixelSize: 11 }
                }
            }
        }
    }

    // ── Düğmeler ─────────────────────────────────────────────────────────
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: credit.top
        anchors.bottomMargin: 18
        spacing: 12

        Button {
            id: restartBtn
            visible: !doneRoot.failed
            text: "Bitir ve Yeniden Başlat"
            // KRİTİK: yeniden başlatmayı Calamares'in finished modülü yapar.
            // restartNowWanted = true → uygulama kapanırken doRestart()
            // restartNowCommand'i ("systemctl -i reboot") çalıştırır.
            onClicked: {
                doneRoot.counting = false;
                if (config) { config.restartNowWanted = true; }
                ViewManager.quit();
            }

            background: Rectangle {
                color: restartBtn.pressed ? "#1E8E3E"
                       : restartBtn.hovered ? "#2FB457" : "#30D158"
                radius: 14
                implicitWidth: restartBtn.contentItem.implicitWidth + 48
                implicitHeight: 46
            }
            contentItem: Text {
                text: restartBtn.text
                color: "#04140A"
                font { family: "Inter"; pixelSize: 15; weight: Font.Bold }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Button {
            id: closeBtn
            text: doneRoot.failed ? "Kapat" : "Sadece kapat"
            onClicked: {
                doneRoot.counting = false;
                ViewManager.quit();
            }

            background: Rectangle {
                color: closeBtn.pressed ? "#1C1C1E"
                       : closeBtn.hovered ? "#26262A" : "#1C1C1E"
                radius: 14
                border.width: 1
                border.color: "#2C2C2E"
                implicitWidth: closeBtn.contentItem.implicitWidth + 44
                implicitHeight: 46
            }
            contentItem: Text {
                text: closeBtn.text
                color: "#C7C7CF"
                font { family: "Inter"; pixelSize: 14 }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // ── Alt kredi şeridi ─────────────────────────────────────────────────
    Rectangle {
        id: credit
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 46
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
            elide: Text.ElideRight
            color: "#7C7C86"
            font { family: "Inter"; pixelSize: 11 }
            text: "MacNix · Gelişmiş macOS Sanallaştırma Distrosu — BELGESELSEMO " +
                  "tarafından ARENA.AI sayesinde geliştirildi · belgeselsemo.com.tr"
        }
    }
}
