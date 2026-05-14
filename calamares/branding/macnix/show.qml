import QtQuick 2.0

Presentation {
    id: presentation
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }
    Slide {
        Text {
            text: "Setting up your MacNix system..."
            color: "#ffffff"
            font.pixelSize: 24
            anchors.centerIn: parent
        }
        Text {
            text: "Detecting GPU and selecting optimal passthrough strategy"
            color: "#aaaaaa"
            font.pixelSize: 14
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.verticalCenter
            anchors.topMargin: 40
        }
    }
    Slide {
        Text {
            text: "Downloading macOS from Apple"
            color: "#ffffff"
            font.pixelSize: 24
            anchors.centerIn: parent
        }
        Text {
            text: "Recovery image is fetched directly from Apple's CDN"
            color: "#aaaaaa"
            font.pixelSize: 14
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.verticalCenter
            anchors.topMargin: 40
        }
    }
    Slide {
        Text {
            text: "Configuring GPU Passthrough"
            color: "#ffffff"
            font.pixelSize: 24
            anchors.centerIn: parent
        }
        Text {
            text: "IOMMU, VFIO, and Looking Glass are being configured automatically"
            color: "#aaaaaa"
            font.pixelSize: 14
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.verticalCenter
            anchors.topMargin: 40
        }
    }
    Slide {
        Text {
            text: "Almost there!"
            color: "#ffffff"
            font.pixelSize: 24
            anchors.centerIn: parent
        }
        Text {
            text: "After reboot, macOS will start automatically"
            color: "#aaaaaa"
            font.pixelSize: 14
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.verticalCenter
            anchors.topMargin: 40
        }
    }
}
