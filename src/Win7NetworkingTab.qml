/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import QtQuick.Layouts
import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.formatter as Formatter

Item {
    id: root

    property int updateInterval: 1000
    // 0 = Bytes Total, 1 = Bytes Sent, 2 = Bytes Received
    property int networkHistoryMode: 0

    function refreshNow() {
        netHistoryGraph.pushSample()
    }

    Sensors.Sensor { id: netDownSensor; sensorId: "network/all/download"; enabled: true }
    Sensors.Sensor { id: netUpSensor; sensorId: "network/all/upload"; enabled: true }
    Sensors.Sensor { id: netDownBitsSensor; sensorId: "network/all/downloadBits"; enabled: true }
    Sensors.Sensor { id: netUpBitsSensor; sensorId: "network/all/uploadBits"; enabled: true }
    Sensors.Sensor { id: netTotalDownSensor; sensorId: "network/all/totalDownload"; enabled: true }
    Sensors.Sensor { id: netTotalUpSensor; sensorId: "network/all/totalUpload"; enabled: true }
    Sensors.Sensor { id: wlanNameSensor; sensorId: "network/wlp2s0/network"; enabled: true }
    Sensors.Sensor { id: wlanIpv4Sensor; sensorId: "network/wlp2s0/ipv4address"; enabled: true }

    // 100 Mbps nominal link speed (100,000,000 bps) for utilization %
    readonly property real linkSpeedBps: 100 * 1000 * 1000
    readonly property real downBps: (Number(netDownBitsSensor.value) || ((Number(netDownSensor.value) || 0) * 8))
    readonly property real upBps: (Number(netUpBitsSensor.value) || ((Number(netUpSensor.value) || 0) * 8))
    readonly property real totalBps: downBps + upBps

    // Auto-scaled graph percentage (0..100% of current scale ceiling, min 1 Mbps so small traffic is clearly visible)
    readonly property real scaleBps: Math.max(1000 * 1000, Math.pow(10, Math.ceil(Math.log10(Math.max(1000, totalBps * 2)))))
    readonly property real downPct: Math.min(100, (downBps / scaleBps) * 100)
    readonly property real upPct: Math.min(100, (upBps / scaleBps) * 100)
    readonly property real totalPct: Math.min(100, (totalBps / scaleBps) * 100)
    readonly property real utilizationPct: (totalBps / linkSpeedBps) * 100

    readonly property string adapterDisplayName: {
        if (wlanNameSensor.value && String(wlanNameSensor.value).length > 0) {
            return "Wireless Network Connection (" + wlanNameSensor.value + ")"
        }
        return "Local Area / Wireless Network Connection"
    }

    function formatRate(bytesPerSec) {
        return Formatter.Formatter.formatValueShowNull(Number(bytesPerSec) || 0, Formatter.Units.UnitByteRate)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 11
        anchors.rightMargin: 11
        anchors.topMargin: 8
        anchors.bottomMargin: 11
        spacing: 10

        // Top: Network Adapter History GroupBox matching Win7 Task Manager Networking tab
        Win7GroupBox {
            title: root.adapterDisplayName
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 160
            topPadding: 18
            leftPadding: 8
            rightPadding: 8
            bottomPadding: 8

            RowLayout {
                anchors.fill: parent
                spacing: 4

                // Left vertical scale labels (100%, 50%, 0) matching Win7 Networking tab
                ColumnLayout {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 34
                    spacing: 0

                    Text {
                        text: root.scaleBps >= linkSpeedBps ? "100%" : ((root.scaleBps / linkSpeedBps) * 100).toFixed(root.scaleBps / linkSpeedBps < 0.1 ? 2 : 0) + "%"
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        color: "#000000"
                        Layout.alignment: Qt.AlignRight | Qt.AlignTop
                    }
                    Item { Layout.fillHeight: true }
                    Text {
                        text: root.scaleBps >= linkSpeedBps ? "50%" : ((root.scaleBps / linkSpeedBps) * 50).toFixed(root.scaleBps / linkSpeedBps < 0.1 ? 2 : 1) + "%"
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        color: "#000000"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }
                    Item { Layout.fillHeight: true }
                    Text {
                        text: "0"
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        color: "#000000"
                        Layout.alignment: Qt.AlignRight | Qt.AlignBottom
                    }
                }

                Win7HistoryGraph {
                    id: netHistoryGraph
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentValue: root.networkHistoryMode === 1 ? root.upPct : (root.networkHistoryMode === 2 ? root.downPct : root.totalPct)
                    secondaryValue: root.upPct
                    showSecondary: root.networkHistoryMode === 0
                    // Classic Win7 Networking colors: Yellow for total/received, Red for sent
                    primaryColor: "#ffff00"
                    secondaryColor: "#ff0000"
                    updateInterval: root.updateInterval
                }
            }
        }

        // Bottom: Classic Win7 Networking Adapter ListView table
        Rectangle {
            id: netTableContainer
            Layout.fillWidth: true
            Layout.preferredHeight: 112
            Layout.minimumHeight: 96
            color: "#ffffff"
            border.width: 1
            border.color: "#828790"
            clip: true

            property var columnWidths: [115, 92, 68, 72]

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                // Win7 Table Header (25px tall) with adjustable column widths
                Rectangle {
                    id: netHeaderBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 25
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#ffffff" }
                        GradientStop { position: 0.45; color: "#f7f8fa" }
                        GradientStop { position: 0.92; color: "#f1f2f4" }
                        GradientStop { position: 0.96; color: "#d5d5d5" }
                        GradientStop { position: 1.0; color: "#fbfbfb" }
                    }

                    Row {
                        anchors.fill: parent
                        spacing: 0

                        Repeater {
                            model: [
                                { title: i18n("Adapter Name"), align: Text.AlignLeft },
                                { title: i18n("Network Utilization"), align: Text.AlignRight },
                                { title: i18n("Link Speed"), align: Text.AlignRight },
                                { title: i18n("State"), align: Text.AlignLeft }
                            ]

                            Item {
                                id: netColHeader
                                required property var modelData
                                required property int index
                                width: netTableContainer.columnWidths[index] || 75
                                height: parent.height

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 5
                                    anchors.rightMargin: 5
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: modelData.align
                                    text: modelData.title
                                    elide: Text.ElideRight
                                    font.family: "Segoe UI"
                                    font.pixelSize: 12
                                    color: "#000000"
                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 1
                                    width: 1
                                    color: "#e5e5e5"
                                }

                                MouseArea {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 6
                                    cursorShape: Qt.SplitHCursor
                                    preventStealing: true
                                    property real startX: 0
                                    property real startW: 0
                                    onPressed: mouse => {
                                        startX = mapToItem(netHeaderBar, mouse.x, 0).x
                                        startW = netTableContainer.columnWidths[netColHeader.index]
                                    }
                                    onPositionChanged: mouse => {
                                        if (pressed) {
                                            var curX = mapToItem(netHeaderBar, mouse.x, 0).x
                                            var next = netTableContainer.columnWidths.slice()
                                            next[netColHeader.index] = Math.max(42, Math.round(startW + (curX - startX)))
                                            netTableContainer.columnWidths = next
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Adapter Row: Primary Interface matching Win7 VM (crop_networking.png)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18
                    color: "#ffffff"

                    Row {
                        anchors.fill: parent
                        spacing: 0

                        Text {
                            width: netTableContainer.columnWidths[0]
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 5
                            rightPadding: 5
                            text: root.adapterDisplayName
                            elide: Text.ElideRight
                            font.family: "Segoe UI"
                            font.pixelSize: 12
                            color: "#000000"
                        }
                        Text {
                            width: netTableContainer.columnWidths[1]
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 5
                            rightPadding: 5
                            horizontalAlignment: Text.AlignRight
                            text: root.utilizationPct < 0.01 && root.totalBps > 0 ? "0.01 %" : Math.round(root.utilizationPct) + " %"
                            elide: Text.ElideRight
                            font.family: "Segoe UI"
                            font.pixelSize: 12
                            color: "#000000"
                        }
                        Text {
                            width: netTableContainer.columnWidths[2]
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 5
                            rightPadding: 5
                            horizontalAlignment: Text.AlignRight
                            text: "100 Mbps"
                            elide: Text.ElideRight
                            font.family: "Segoe UI"
                            font.pixelSize: 12
                            color: "#000000"
                        }
                        Text {
                            width: netTableContainer.columnWidths[3]
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 5
                            rightPadding: 5
                            text: i18n("Connected")
                            elide: Text.ElideRight
                            font.family: "Segoe UI"
                            font.pixelSize: 12
                            color: "#000000"
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
