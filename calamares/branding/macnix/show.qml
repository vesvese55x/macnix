import QtQuick 2.12
import QtQuick.Controls 2.12
import QtGraphicalEffects 1.12

Presentation {
    id: presentation
    
    Timer {
        interval: 6000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }
    
    // Background Gradient for a "cool" premium feel
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0B0C10" }
            GradientStop { position: 1.0; color: "#1F2833" }
        }
        z: -1
    }

    Slide {
        Item {
            anchors.fill: parent
            Text {
                id: t1
                text: "Welcome to MacNix"
                color: "#66FCF1"
                font.pixelSize: 36
                font.weight: Font.Bold
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -20
            }
            Text {
                text: "The Ultimate macOS Virtualization Distro"
                color: "#C5C6C7"
                font.pixelSize: 18
                anchors.top: t1.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
    Slide {
        Item {
            anchors.fill: parent
            Text {
                id: t2
                text: "Hardware Profiling Active"
                color: "#45A29E"
                font.pixelSize: 32
                font.weight: Font.Bold
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -20
            }
            Text {
                text: "Analyzing your CPU and GPU to select the optimal macOS version..."
                color: "#C5C6C7"
                font.pixelSize: 18
                anchors.top: t2.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
    Slide {
        Item {
            anchors.fill: parent
            Text {
                id: t3
                text: "Direct from Apple"
                color: "#66FCF1"
                font.pixelSize: 32
                font.weight: Font.Bold
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -20
            }
            Text {
                text: "Downloading the official Recovery Image securely from Apple's CDN."
                color: "#C5C6C7"
                font.pixelSize: 18
                anchors.top: t3.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
    Slide {
        Item {
            anchors.fill: parent
            Text {
                id: t4
                text: "Zero Configuration"
                color: "#45A29E"
                font.pixelSize: 32
                font.weight: Font.Bold
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -20
            }
            Text {
                text: "IOMMU, VFIO Passthrough, and Looking Glass are handled automatically."
                color: "#C5C6C7"
                font.pixelSize: 18
                anchors.top: t4.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
    Slide {
        Item {
            anchors.fill: parent
            Text {
                id: t5
                text: "Get Ready."
                color: "#66FCF1"
                font.pixelSize: 36
                font.weight: Font.Bold
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -20
            }
            Text {
                text: "After reboot, you will be dropped straight into macOS."
                color: "#C5C6C7"
                font.pixelSize: 18
                anchors.top: t5.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
