import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import io.calamares.ui 1.0
import io.calamares.core 1.0

Rectangle {
    id: navRoot
    color: "#000000"
    height: 80

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 240  // Past sidebar
        anchors.rightMargin: 40
        anchors.topMargin: 16
        anchors.bottomMargin: 16

        // Back button (text only, Apple style)
        Button {
            id: backBtn
            text: "← Go Back"
            visible: ViewManager.backEnabled
            Layout.alignment: Qt.AlignLeft

            background: Rectangle { color: "transparent" }

            contentItem: Text {
                text: backBtn.text
                color: backBtn.hovered ? "#409CFF" : "#0A84FF"
                font { family: "Inter"; pixelSize: 15 }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                Behavior on color { ColorAnimation { duration: 150 } }
            }

            onClicked: ViewManager.back()
        }

        Item { Layout.fillWidth: true } // Spacer

        // Continue button (blue pill, Apple style)
        Button {
            id: nextBtn
            text: ViewManager.currentStep === ViewManager.stepsCount - 1
                  ? "✦ Begin Setup" : "Continue"
            Layout.alignment: Qt.AlignRight
            enabled: ViewManager.nextEnabled

            background: Rectangle {
                color: nextBtn.enabled
                    ? (nextBtn.pressed ? "#0071E3"
                       : nextBtn.hovered ? "#409CFF" : "#0A84FF")
                    : "#3A3A3C"
                radius: 14
                implicitWidth: 160
                implicitHeight: 44

                Behavior on color { ColorAnimation { duration: 150 } }
            }

            contentItem: Text {
                text: nextBtn.text
                color: nextBtn.enabled ? "#FFFFFF" : "#636366"
                font { family: "Inter"; pixelSize: 15; weight: Font.SemiBold }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: ViewManager.next()
        }
    }
}
