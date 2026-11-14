/* ============================================================================
 *  MacNix 2.0 — Calamares alt menü (QML)
 * ============================================================================
 *  CANLI TEST HATASI: kurulum bittikten sonraki "Kurulum işlemleri
 *  tamamlandı" ekranında ilerleme düğmesi ("Continue") PASİF/ölü görünüyordu
 *  ve Calamares'i kapatmanın yolu yoktu. Sebep: düğme metni sabit kodluydu ve
 *  Calamares'in "Done/Bitir" (quit) düğmesi hiç çizilmiyordu.
 *
 *  Çözüm (Calamares 3.2.61 davranışına birebir uyum):
 *   • Devam    → ViewManager.nextLabel / nextEnabled (Calamares yönetir)
 *   • Bitir    → ViewManager.quitLabel + quitVisible; YALNIZCA en sonda görünür
 *   • Geri     → ViewManager.backLabel / backEnabled
 *  Etiketler Calamares'ten geldiği için "Kurulumu Başlat" (install) ve "Bitir"
 *  (done) durumları kendiliğinden doğru yazılır.
 *  Böylece sonda kullanıcı "Bitir"e basıp kurulumu kapatabilir (veya açık
 *  kalırsa ilk açılış otomatik yapılır: macnix-firstboot.service).
 * ========================================================================== */
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import io.calamares.ui 1.0
import io.calamares.core 1.0

Rectangle {
    id: navRoot
    color: "#000000"
    height: 84

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 256       // yan menünün sağı
        anchors.rightMargin: 32
        anchors.topMargin: 18
        anchors.bottomMargin: 18
        spacing: 12

        // ── Geri ──────────────────────────────────────────────────────────
        Button {
            id: backBtn
            // Calamares'in kendi (yerelleştirilmiş) etiketi: "&Back"
            text: "← " + ViewManager.backLabel.replace("&", "")
            visible: ViewManager.backEnabled
            Layout.alignment: Qt.AlignLeft

            background: Rectangle { color: "transparent" }

            contentItem: Text {
                text: backBtn.text
                color: backBtn.hovered ? "#409CFF" : "#0A84FF"
                font { family: "Inter"; pixelSize: 14 }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            onClicked: ViewManager.back()
        }

        Item { Layout.fillWidth: true }

        // ── Bitir (yalnızca kurulumun en sonunda) ─────────────────────────
        Button {
            id: quitBtn
            visible: ViewManager.quitVisible
            enabled: ViewManager.quitEnabled
            text: ViewManager.quitLabel.replace("&", "")
            Layout.alignment: Qt.AlignRight

            background: Rectangle {
                color: !quitBtn.enabled ? "#3A3A3C"
                       : quitBtn.pressed ? "#1E8E3E"
                       : quitBtn.hovered ? "#2FB457" : "#30D158"
                radius: 14
                implicitWidth: Math.max(150, quitBtn.contentItem.implicitWidth + 44)
                implicitHeight: 44
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            contentItem: Text {
                text: quitBtn.text
                color: quitBtn.enabled ? "#04140A" : "#636366"
                font { family: "Inter"; pixelSize: 15; weight: Font.Bold }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: ViewManager.quit()
        }

        // ── Devam / Kurulumu Başlat ───────────────────────────────────────
        Button {
            id: nextBtn
            visible: ViewManager.backAndNextVisible
            enabled: ViewManager.nextEnabled
            text: ViewManager.nextLabel.replace("&", "")
            Layout.alignment: Qt.AlignRight

            background: Rectangle {
                color: !nextBtn.enabled ? "#3A3A3C"
                       : nextBtn.pressed ? "#0071E3"
                       : nextBtn.hovered ? "#409CFF" : "#0A84FF"
                radius: 14
                implicitWidth: Math.max(150, nextBtn.contentItem.implicitWidth + 44)
                implicitHeight: 44
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            contentItem: Text {
                text: nextBtn.text
                color: nextBtn.enabled ? "#FFFFFF" : "#636366"
                font { family: "Inter"; pixelSize: 15; weight: Font.DemiBold }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: ViewManager.next()
        }
    }

    // İnce üst çizgi (sayfa ile menüyü ayırır)
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: "#1A1C22"
    }
}
