import QtQuick 2.15
import QtQuick.Controls 2.15
import io.calamares.ui 1.0
import io.calamares.core 1.0

Rectangle {
    id: sidebarRoot
    color: "#0B0C10"
    width: 220

    Column {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        // MacNix Logo
        Image {
            source: "macnix_logo.png"
            width: 80; height: 80
            anchors.horizontalCenter: parent.horizontalCenter
            fillMode: Image.PreserveAspectFit
        }

        Text {
            text: "MacNix"
            color: "#FFFFFF"
            font { family: "Inter"; pixelSize: 22; weight: Font.Bold }
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: "macOS Virtualization Platform"
            color: "#8E8E93"
            font { family: "Inter"; pixelSize: 12 }
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Item { height: 20; width: 1 } // Spacer

        // Step indicators
        Repeater {
            model: ViewManager
            delegate: Item {
                width: parent.width
                height: 44

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    x: 16

                    // Dot indicator
                    Rectangle {
                        width: 10; height: 10
                        radius: 5
                        anchors.verticalCenter: parent.verticalCenter
                        color: {
                            if (index < ViewManager.currentStepIndex) return "#30D158"  // Done
                            if (index === ViewManager.currentStepIndex) return "#0A84FF" // Current
                            return "#3A3A3C"  // Upcoming
                        }

                        Behavior on color {
                            ColorAnimation { duration: 300; easing.type: Easing.InOutQuad }
                        }
                    }

                    // Step label
                    Text {
                        text: display
                        color: {
                            if (index === ViewManager.currentStepIndex) return "#FFFFFF"
                            if (index < ViewManager.currentStepIndex) return "#8E8E93"
                            return "#636366"
                        }
                        font {
                            family: "Inter"
                            pixelSize: 14
                            weight: index === ViewManager.currentStepIndex ? Font.SemiBold : Font.Normal
                        }
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on color {
                            ColorAnimation { duration: 300 }
                        }
                    }
                }
            }
        }

        // Bottom spacer pushes info to bottom
        Item { anchors.fill: parent; height: 1 }
    }

    // Bottom info
    Column {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 20
        spacing: 4

        Text {
            text: "Created by Hassan Elkady"
            color: "#636366"
            font { family: "Inter"; pixelSize: 11 }
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: "github.com/local-over/macnix"
            color: "#636366"
            font { family: "Inter"; pixelSize: 11 }
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
