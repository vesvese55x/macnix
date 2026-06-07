import QtQuick 2.12
import QtQuick.Controls 2.12

Presentation {
    id: presentation

    Timer {
        interval: 8000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    // Global dark background
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0B0C10" }
            GradientStop { position: 0.5; color: "#1F2833" }
            GradientStop { position: 1.0; color: "#0B0C10" }
        }
        z: -1
    }

    // ── Slide 1: Welcome ──
    Slide {
        Item {
            anchors.fill: parent

            Image {
                id: logo1
                source: "macnix_logo.png"
                width: 120; height: 120
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -80
                smooth: true
                opacity: 0.9
            }
            Text {
                id: t1
                text: "Welcome to MacNix"
                color: "#66FCF1"
                font.pixelSize: 36
                font.weight: Font.Bold
                font.family: "Sans"
                anchors.top: logo1.bottom
                anchors.topMargin: 20
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "The Ultimate macOS Virtualization Platform"
                color: "#C5C6C7"
                font.pixelSize: 17
                font.family: "Sans"
                anchors.top: t1.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ── Slide 2: Hardware Profiling ──
    Slide {
        Item {
            anchors.fill: parent
            Text {
                id: icon2
                text: "🔍"
                font.pixelSize: 64
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -70
            }
            Text {
                id: t2
                text: "Intelligent Hardware Profiling"
                color: "#45A29E"
                font.pixelSize: 30
                font.weight: Font.Bold
                font.family: "Sans"
                anchors.top: icon2.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "MacNix automatically detects your CPU, GPU, and IOMMU topology\nto select the optimal passthrough strategy for your hardware."
                color: "#C5C6C7"
                font.pixelSize: 15
                font.family: "Sans"
                horizontalAlignment: Text.AlignHCenter
                anchors.top: t2.bottom
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ── Slide 3: macOS Download ──
    Slide {
        Item {
            anchors.fill: parent
            Text {
                id: icon3
                text: "⬇️"
                font.pixelSize: 64
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -70
            }
            Text {
                id: t3
                text: "Direct from Apple"
                color: "#66FCF1"
                font.pixelSize: 30
                font.weight: Font.Bold
                font.family: "Sans"
                anchors.top: icon3.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "Downloading the official Recovery Image\nsecurely from Apple's CDN — no third-party images."
                color: "#C5C6C7"
                font.pixelSize: 15
                font.family: "Sans"
                horizontalAlignment: Text.AlignHCenter
                anchors.top: t3.bottom
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ── Slide 4: GPU Passthrough ──
    Slide {
        Item {
            anchors.fill: parent
            Text {
                id: icon4
                text: "🎮"
                font.pixelSize: 64
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -70
            }
            Text {
                id: t4
                text: "GPU Passthrough — Up to 100%"
                color: "#45A29E"
                font.pixelSize: 30
                font.weight: Font.Bold
                font.family: "Sans"
                anchors.top: icon4.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "VFIO, IOMMU groups, and Looking Glass are configured automatically.\nAMD GPUs get native macOS performance via direct passthrough."
                color: "#C5C6C7"
                font.pixelSize: 15
                font.family: "Sans"
                horizontalAlignment: Text.AlignHCenter
                anchors.top: t4.bottom
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ── Slide 5: OpenCore ──
    Slide {
        Item {
            anchors.fill: parent
            Text {
                id: icon5
                text: "⚙️"
                font.pixelSize: 64
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -70
            }
            Text {
                id: t5
                text: "Powered by OpenCore"
                color: "#66FCF1"
                font.pixelSize: 30
                font.weight: Font.Bold
                font.family: "Sans"
                anchors.top: icon5.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "Industry-standard bootloader with unique SMBIOS identities,\nproper NVRAM emulation, and Apple Secure Boot compatibility."
                color: "#C5C6C7"
                font.pixelSize: 15
                font.family: "Sans"
                horizontalAlignment: Text.AlignHCenter
                anchors.top: t5.bottom
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ── Slide 6: Ready ──
    Slide {
        Item {
            anchors.fill: parent

            Image {
                id: logo6
                source: "macnix_logo.png"
                width: 100; height: 100
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -70
                smooth: true
                opacity: 0.8
            }
            Text {
                id: t6
                text: "Almost There"
                color: "#66FCF1"
                font.pixelSize: 36
                font.weight: Font.Bold
                font.family: "Sans"
                anchors.top: logo6.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "After reboot, MacNix will finalize your hardware config\nand drop you straight into macOS."
                color: "#C5C6C7"
                font.pixelSize: 15
                font.family: "Sans"
                horizontalAlignment: Text.AlignHCenter
                anchors.top: t6.bottom
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
