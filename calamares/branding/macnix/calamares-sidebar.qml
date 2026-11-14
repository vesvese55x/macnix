/* ============================================================================
 *  MacNix 2.0 — Calamares yan menü (QML)
 * ============================================================================
 *  Canlı testte görülen hata: logo ve "macOS Virtualization Platform" yazısı,
 *  hemen altındaki "MacNix" başlığıyla ÜST ÜSTE biniyordu (g1/z1 ekran
 *  görüntüleri). Sebep: Image/Text öğeleri Column içinde ama anchor
 *  kullanmadan çiziliyordu; Column yüksekliklerini doğru hesaplamıyordu.
 *
 *  Çözüm: tüm öğeler Column'a `width` verilerek yerleştirildi, sabit
 *  yükseklikler kaldırıldı, adım listesi Flickable içine alındı.
 * ========================================================================== */
import QtQuick 2.15
import QtQuick.Controls 2.15
import io.calamares.ui 1.0
import io.calamares.core 1.0

Rectangle {
    id: sidebarRoot
    color: "#0B0C10"
    width: 236

    // ── Üst blok: marka ───────────────────────────────────────────────────
    Column {
        id: brand
        width: parent.width - 32
        anchors.top: parent.top
        anchors.topMargin: 22
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8

        Image {
            source: "macnix_logo.png"
            width: 72; height: 72
            fillMode: Image.PreserveAspectFit
            smooth: true
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: "MacNix 2.0"
            color: "#FFFFFF"
            font { family: "Inter"; pixelSize: 21; weight: Font.Bold }
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: "Gelişmiş macOS\nSanallaştırma Distrosu"
            color: "#4FD8EE"
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 1.2
            font { family: "Inter"; pixelSize: 11; weight: Font.DemiBold }
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Rectangle {
            width: parent.width
            height: 1
            color: "#20222B"
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // ── Orta blok: adım göstergeleri ──────────────────────────────────────
    Item {
        id: stepsArea
        anchors.top: brand.bottom
        anchors.topMargin: 14
        anchors.bottom: credit.top
        anchors.bottomMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right

        ListView {
            id: stepList
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 10
            clip: true
            model: ViewManager
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
                width: stepList.width
                height: 38

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 6
                    spacing: 10

                    Rectangle {
                        width: 8; height: 8; radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: {
                            if (index < ViewManager.currentStepIndex) return "#30D158"   // bitti
                            if (index === ViewManager.currentStepIndex) return "#0A84FF" // şimdi
                            return "#3A3A3C"                                             // sırada
                        }
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }

                    Text {
                        text: display
                        color: {
                            if (index === ViewManager.currentStepIndex) return "#FFFFFF"
                            if (index < ViewManager.currentStepIndex) return "#8E8E93"
                            return "#636366"
                        }
                        font {
                            family: "Inter"
                            pixelSize: 12
                            weight: index === ViewManager.currentStepIndex ? Font.DemiBold : Font.Normal
                        }
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }
                }
            }
        }
    }

    // ── Alt blok: kredi ───────────────────────────────────────────────────
    Column {
        id: credit
        width: parent.width - 24
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 3

        Rectangle {
            width: parent.width
            height: 1
            color: "#20222B"
        }

        Text {
            width: parent.width
            text: "BELGESELSEMO tarafından\nARENA.AI sayesinde geliştirildi"
            color: "#7C7C86"
            horizontalAlignment: Text.AlignHCenter
            font { family: "Inter"; pixelSize: 9 }
            lineHeight: 1.25
        }
        Text {
            width: parent.width
            text: "github.com/local-over/macnix"
            color: "#636366"
            horizontalAlignment: Text.AlignHCenter
            font { family: "Inter"; pixelSize: 9 }
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: "orijinal repo'dan fork · belgeselsemo.com.tr"
            color: "#636366"
            horizontalAlignment: Text.AlignHCenter
            font { family: "Inter"; pixelSize: 9 }
            elide: Text.ElideRight
        }
    }
}
