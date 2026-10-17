/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import QtQuick.Layouts
import org.kde.ksysguard.sensors as Sensors

Item {
    id: root

    property bool showKernelTimes: false
    property bool perCpuHistory: false
    property int updateInterval: 1000
    property int processCount: 0

    signal resourceMonitorClicked()

    function refreshNow() {
        cpuCombinedGraph.pushSample()
        memHistoryGraph.pushSample()
        for (var i = 0; i < perCoreRepeater.count; ++i) {
            var item = perCoreRepeater.itemAt(i)
            if (item && item.pushSample) {
                item.pushSample()
            }
        }
    }

    // Sensors
    Sensors.Sensor { id: cpuUsageSensor; sensorId: "cpu/all/usage"; enabled: true }
    Sensors.Sensor { id: cpuSystemSensor; sensorId: "cpu/all/system"; enabled: true }
    Sensors.Sensor { id: cpuCoreCountSensor; sensorId: "cpu/all/coreCount"; enabled: true }

    Sensors.Sensor { id: memTotalSensor; sensorId: "memory/physical/total"; enabled: true }
    Sensors.Sensor { id: memUsedSensor; sensorId: "memory/physical/used"; enabled: true }
    Sensors.Sensor { id: memUsedPctSensor; sensorId: "memory/physical/usedPercent"; enabled: true }
    Sensors.Sensor { id: memCacheSensor; sensorId: "memory/physical/cache"; enabled: true }
    Sensors.Sensor { id: memBufferSensor; sensorId: "memory/physical/buffer"; enabled: true }
    Sensors.Sensor { id: memFreeSensor; sensorId: "memory/physical/free"; enabled: true }
    Sensors.Sensor { id: swapTotalSensor; sensorId: "memory/swap/total"; enabled: true }
    Sensors.Sensor { id: swapUsedSensor; sensorId: "memory/swap/used"; enabled: true }
    Sensors.Sensor { id: uptimeSensor; sensorId: "os/system/uptime"; enabled: true }

    readonly property real cpuUsageVal: Number(cpuUsageSensor.value) || 0
    readonly property real cpuSystemVal: Number(cpuSystemSensor.value) || 0
    readonly property int coreCount: Math.max(1, Math.min(16, Number(cpuCoreCountSensor.value) || 1))

    // Memory sensors in ksystemstats are in Bytes; convert to MB to match Win7 Task Manager
    readonly property int totalMemMB: Math.round((Number(memTotalSensor.value) || 0) / (1024 * 1024))
    readonly property int usedMemMB: Math.round((Number(memUsedSensor.value) || 0) / (1024 * 1024))
    readonly property real usedMemPct: Number(memUsedPctSensor.value) || (totalMemMB > 0 ? (usedMemMB * 100.0 / totalMemMB) : 0)
    readonly property int cachedMemMB: Math.round(((Number(memCacheSensor.value) || 0) + (Number(memBufferSensor.value) || 0)) / (1024 * 1024))
    readonly property int availMemMB: Math.max(0, totalMemMB - usedMemMB)
    readonly property int freeMemMB: Math.max(0, availMemMB - cachedMemMB)
    readonly property int swapTotalMB: Math.round((Number(swapTotalSensor.value) || 0) / (1024 * 1024))
    readonly property int swapUsedMB: Math.round((Number(swapUsedSensor.value) || 0) / (1024 * 1024))
    readonly property int commitTotalMB: totalMemMB + swapTotalMB
    readonly property int commitUsedMB: usedMemMB + swapUsedMB
    readonly property int kernelPagedMB: Math.max(16, Math.round(cachedMemMB * 0.16))
    readonly property int kernelNonpagedMB: Math.max(8, Math.round(usedMemMB * 0.035))

    function formatMemGaugeText(mb) {
        if (mb >= 2048) {
            return (mb / 1024.0).toFixed(2) + " GB"
        }
        return mb + " MB"
    }

    function formatUptime(secondsVal) {
        var s = Math.max(0, Math.floor(Number(secondsVal) || 0))
        var days = Math.floor(s / 86400)
        var hrs = Math.floor((s % 86400) / 3600)
        var mins = Math.floor((s % 3600) / 60)
        var secs = s % 60
        var hh = (hrs < 10 ? "0" : "") + hrs
        var mm = (mins < 10 ? "0" : "") + mins
        var ss = (secs < 10 ? "0" : "") + secs
        return days + ":" + hh + ":" + mm + ":" + ss
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 15
        anchors.rightMargin: 14
        anchors.topMargin: 8
        anchors.bottomMargin: 11
        spacing: 7

        // Row 1: CPU Usage + CPU Usage History
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 85
            Layout.minimumHeight: 78
            spacing: 14

            Win7GroupBox {
                title: i18n("CPU Usage")
                Layout.preferredWidth: 90
                Layout.minimumWidth: 90
                Layout.maximumWidth: 90
                Layout.fillHeight: true
                topPadding: 18
                leftPadding: 9
                rightPadding: 9
                bottomPadding: 7

                Win7Gauge {
                    anchors.fill: parent
                    value: root.cpuUsageVal
                    kernelValue: root.cpuSystemVal
                    showKernelTimes: root.showKernelTimes
                    displayText: Math.round(root.cpuUsageVal) + " %"
                }
            }

            Win7GroupBox {
                title: i18n("CPU Usage History")
                Layout.fillWidth: true
                Layout.fillHeight: true
                topPadding: 18
                leftPadding: 8
                rightPadding: 8
                bottomPadding: 7

                // Combined single CPU graph
                Win7HistoryGraph {
                    id: cpuCombinedGraph
                    anchors.fill: parent
                    visible: !root.perCpuHistory
                    currentValue: root.cpuUsageVal
                    secondaryValue: root.cpuSystemVal
                    showSecondary: root.showKernelTimes
                    primaryColor: "#00ff00"
                    secondaryColor: "#ff0000"
                    updateInterval: root.updateInterval
                }

                // Per-CPU history graphs when View -> CPU History -> One Graph Per CPU is active
                RowLayout {
                    anchors.fill: parent
                    visible: root.perCpuHistory
                    spacing: 3

                    Repeater {
                        id: perCoreRepeater
                        model: root.perCpuHistory ? Math.min(8, root.coreCount) : 0

                        Win7HistoryGraph {
                            id: coreGraph
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            currentValue: Number(coreUsageSensor.value) || 0
                            secondaryValue: Number(coreSystemSensor.value) || 0
                            showSecondary: root.showKernelTimes
                            primaryColor: "#00ff00"
                            secondaryColor: "#ff0000"
                            updateInterval: root.updateInterval

                            Sensors.Sensor {
                                id: coreUsageSensor
                                sensorId: "cpu/cpu" + coreGraph.index + "/usage"
                                enabled: root.perCpuHistory
                            }
                            Sensors.Sensor {
                                id: coreSystemSensor
                                sensorId: "cpu/cpu" + coreGraph.index + "/system"
                                enabled: root.perCpuHistory && root.showKernelTimes
                            }
                        }
                    }
                }
            }
        }

        // Row 2: Memory + Physical Memory Usage History
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 85
            Layout.minimumHeight: 78
            spacing: 14

            Win7GroupBox {
                title: i18n("Memory")
                Layout.preferredWidth: 90
                Layout.minimumWidth: 90
                Layout.maximumWidth: 90
                Layout.fillHeight: true
                topPadding: 18
                leftPadding: 9
                rightPadding: 9
                bottomPadding: 7

                Win7Gauge {
                    anchors.fill: parent
                    value: root.usedMemPct
                    displayText: root.formatMemGaugeText(root.usedMemMB)
                }
            }

            Win7GroupBox {
                title: i18n("Physical Memory Usage History")
                Layout.fillWidth: true
                Layout.fillHeight: true
                topPadding: 18
                leftPadding: 8
                rightPadding: 8
                bottomPadding: 7

                Win7HistoryGraph {
                    id: memHistoryGraph
                    anchors.fill: parent
                    currentValue: root.usedMemPct
                    // Matches our live Windows 7 VM screenshot (#0080ff, 2px line)
                    primaryColor: "#0080ff"
                    primaryLineWidth: 2
                    updateInterval: root.updateInterval
                }
            }
        }

        // Row 3: Bottom statistics GroupBoxes + Resource Monitor button
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 152
            Layout.minimumHeight: 146
            Layout.maximumHeight: 162
            spacing: 13

            // Left column: Physical Memory (MB) + Kernel Memory (MB)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 170
                spacing: 5

                Win7GroupBox {
                    title: i18n("Physical Memory (MB)")
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    topPadding: 17
                    leftPadding: 8
                    rightPadding: 9
                    bottomPadding: 6

                    GridLayout {
                        anchors.fill: parent
                        columns: 2
                        rowSpacing: 1
                        columnSpacing: 8

                        Text { text: i18n("Total"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                        Text { text: String(root.totalMemMB); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                        Text { text: i18n("Cached"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                        Text { text: String(root.cachedMemMB); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                        Text { text: i18n("Available"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                        Text { text: String(root.availMemMB); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                        Text { text: i18n("Free"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                        Text { text: String(root.freeMemMB); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                    }
                }

                Win7GroupBox {
                    title: i18n("Kernel Memory (MB)")
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    topPadding: 17
                    leftPadding: 8
                    rightPadding: 9
                    bottomPadding: 5

                    GridLayout {
                        anchors.fill: parent
                        columns: 2
                        rowSpacing: 1
                        columnSpacing: 8

                        Text { text: i18n("Paged"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                        Text { text: String(root.kernelPagedMB); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                        Text { text: i18n("Nonpaged"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                        Text { text: String(root.kernelNonpagedMB); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                    }
                }
            }

            // Right column: System GroupBox + Resource Monitor... button
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 171
                spacing: 12

                Win7GroupBox {
                    title: i18n("System")
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    topPadding: 17
                    leftPadding: 8
                    rightPadding: 10
                    bottomPadding: 6

                    GridLayout {
                        anchors.fill: parent
                        columns: 2
                        rowSpacing: 1
                        columnSpacing: 8

                        Text { text: i18n("Handles"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                        Text { text: String(Math.max(1024, root.processCount * 256)); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                        Text { text: i18n("Threads"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                        Text { text: String(Math.max(64, root.processCount * 11)); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                        Text { text: i18n("Processes"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                        Text { text: String(root.processCount); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                        Text { text: i18n("Up Time"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                        Text { text: root.formatUptime(uptimeSensor.value); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                        Text { text: i18n("Commit (MB)"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                        Text { text: root.commitUsedMB + " / " + root.commitTotalMB; font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                    }
                }

                Win7Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 23
                    showShield: true
                    mnemonicText: i18n("&Resource Monitor...")
                    text: i18n("Resource Monitor...")
                    onClicked: root.resourceMonitorClicked()
                }
            }
        }
    }
}
