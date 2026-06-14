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

    // Global pure black background
    Rectangle {
        anchors.fill: parent
        color: "#000000"
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
                color: "#FFFFFF"
                font.pixelSize: 36
                font.weight: Font.Bold
                font.family: "Inter"
                anchors.top: logo1.bottom
                anchors.topMargin: 20
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "The Ultimate macOS Virtualization Platform"
                color: "#8E8E93"
                font.pixelSize: 17
                font.family: "Inter"
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
                color: "#0A84FF"
                font.pixelSize: 30
                font.weight: Font.Bold
                font.family: "Inter"
                anchors.top: icon2.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "MacNix automatically detects your CPU, GPU, and IOMMU topology\nto select the optimal passthrough strategy for your hardware."
                color: "#8E8E93"
                font.pixelSize: 15
                font.family: "Inter"
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
                text: "Downloading macOS"
                color: "#30D158"
                font.pixelSize: 30
                font.weight: Font.Bold
                font.family: "Inter"
                anchors.top: icon3.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "Downloading the official Recovery Image\nsecurely from Apple's CDN — no third-party images."
                color: "#8E8E93"
                font.pixelSize: 15
                font.family: "Inter"
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
                text: "Native Performance"
                color: "#0A84FF"
                font.pixelSize: 30
                font.weight: Font.Bold
                font.family: "Inter"
                anchors.top: icon4.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "VFIO, CPU pinning, and NUMA alignment are configured automatically.\nEnjoy near-native macOS performance via direct passthrough."
                color: "#8E8E93"
                font.pixelSize: 15
                font.family: "Inter"
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
                color: "#FF9F0A"
                font.pixelSize: 30
                font.weight: Font.Bold
                font.family: "Inter"
                anchors.top: icon5.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "Industry-standard bootloader with unique SMBIOS identities,\nproper NVRAM emulation, and Apple Secure Boot compatibility."
                color: "#8E8E93"
                font.pixelSize: 15
                font.family: "Inter"
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
                color: "#FFFFFF"
                font.pixelSize: 36
                font.weight: Font.Bold
                font.family: "Inter"
                anchors.top: logo6.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "After reboot, macOS will automatically install itself.\nNo manual configuration required."
                color: "#8E8E93"
                font.pixelSize: 15
                font.family: "Inter"
                horizontalAlignment: Text.AlignHCenter
                anchors.top: t6.bottom
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
