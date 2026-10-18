/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import org.kde.systemmonitor
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import org.kde.ksysguard.formatter as Formatter
import org.kde.ksysguard.process as Process
import org.kde.ksysguard.table as Table
import "Win7ProcessFormat.js" as ProcessFormat

Item {
    id: root

    required property var updateController

    property bool showKernelTimes: false
    property int updateInterval: 2000
    property int processCount: 0
    property int selectedRow: 0
    property int sortColumn: 3 // Default sort by Memory % descending
    property int sortOrder: Qt.DescendingOrder

    signal switchToTabRequested(string tabId)
    signal inspectProcessRequested(int pid, string name)
    signal newTaskRequested()

    function refreshNow() {
        topProcSnapshot.refresh()
        if (root.visible) overviewHistoryGraph.pushSample()
        topProcFilterModel.invalidate()
    }

    // Live Sensors matching overview.page
    Win7Sensor { updateController: root.updateController; id: cpuUsageSensor; sensorId: "cpu/all/usage"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: cpuSystemSensor; sensorId: "cpu/all/system"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: cpuFreqSensor; sensorId: "cpu/all/averageFrequency"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: cpuCoresSensor; sensorId: "cpu/all/coreCount"; enabled: true }

    Win7Sensor { updateController: root.updateController; id: memTotalSensor; sensorId: "memory/physical/total"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: memUsedSensor; sensorId: "memory/physical/used"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: memUsedPctSensor; sensorId: "memory/physical/usedPercent"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: memCacheSensor; sensorId: "memory/physical/cache"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: swapTotalSensor; sensorId: "memory/swap/total"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: swapUsedSensor; sensorId: "memory/swap/used"; enabled: true }

    Win7Sensor { updateController: root.updateController; id: diskUsedSensor; sensorId: "disk/all/used"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: diskTotalSensor; sensorId: "disk/all/total"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: diskUsedPctSensor; sensorId: "disk/all/usedPercent"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: diskReadSensor; sensorId: "disk/all/read"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: diskWriteSensor; sensorId: "disk/all/write"; enabled: true }

    Win7Sensor { updateController: root.updateController; id: netDownSensor; sensorId: "network/all/download"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: netUpSensor; sensorId: "network/all/upload"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: gpuUsageSensor; sensorId: "gpu/all/usage"; enabled: true }
    Win7Sensor { updateController: root.updateController; id: uptimeSensor; sensorId: "os/system/uptime"; enabled: true }

    readonly property real cpuUsageVal: Number(cpuUsageSensor.value) || 0
    readonly property real cpuSystemVal: Number(cpuSystemSensor.value) || 0
    readonly property int totalMemMB: Math.round((Number(memTotalSensor.value) || 0) / (1024 * 1024))
    readonly property int usedMemMB: Math.round((Number(memUsedSensor.value) || 0) / (1024 * 1024))
    readonly property real usedMemPct: Number(memUsedPctSensor.value) || (totalMemMB > 0 ? (usedMemMB * 100.0 / totalMemMB) : 0)
    readonly property int cachedMemMB: Math.round((Number(memCacheSensor.value) || 0) / (1024 * 1024))
    readonly property int swapTotalMB: Math.round((Number(swapTotalSensor.value) || 0) / (1024 * 1024))
    readonly property int swapUsedMB: Math.round((Number(swapUsedSensor.value) || 0) / (1024 * 1024))
    readonly property bool gpuUsageAvailable: sensorValueAvailable(gpuUsageSensor.value)
    readonly property real gpuUsageVal: gpuUsageAvailable ? Math.min(100, Number(gpuUsageSensor.value)) : 0
    readonly property bool swapUsageAvailable: sensorValueAvailable(swapTotalSensor.value) && sensorValueAvailable(swapUsedSensor.value)
    readonly property real swapUsedPct: swapUsageAvailable && Number(swapTotalSensor.value) > 0
        ? Math.min(100, Number(swapUsedSensor.value) * 100 / Number(swapTotalSensor.value)) : 0
    readonly property int gaugeWidth: Math.max(58, Math.min(74, Math.floor((width - 29) / 9)))

    function sensorValueAvailable(value) {
        return value !== undefined && value !== null && value !== "" && isFinite(Number(value)) && Number(value) >= 0
    }

    readonly property real diskUsedGB: (Number(diskUsedSensor.value) || 0) / (1024 * 1024 * 1024)
    readonly property real diskTotalGB: (Number(diskTotalSensor.value) || 0) / (1024 * 1024 * 1024)
    readonly property real diskUsedPct: Number(diskUsedPctSensor.value) || (diskTotalGB > 0 ? (diskUsedGB * 100.0 / diskTotalGB) : 0)
    readonly property real ioRateBytes: (Number(diskReadSensor.value) || 0) + (Number(diskWriteSensor.value) || 0) + (Number(netDownSensor.value) || 0) + (Number(netUpSensor.value) || 0)
    readonly property real ioActivityPct: Math.min(100, Math.log10(Math.max(1, ioRateBytes / 1024)) * 20)

    function formatMemShort(mb) {
        if (mb >= 2048) {
            return (mb / 1024.0).toFixed(1) + " GB"
        }
        return mb + " MB"
    }

    function formatRateShort(bytesPerSec) {
        return Formatter.Formatter.formatValueShowNull(Number(bytesPerSec) || 0, Formatter.Units.UnitByteRate)
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

    property int modelRevision: 0
    property bool initialSortDone: false
    property var columnWidths: [110, 48, 52, 70, 96]

    function setColumnWidth(colIdx, newW) {
        var copy = root.columnWidths.slice()
        while (copy.length <= colIdx) copy.push(64)
        copy[colIdx] = Math.max(32, Math.round(newW))
        root.columnWidths = copy
    }

    readonly property real totalOverviewColumnsWidth: {
        var sum = 0
        for (var i = 0; i < root.overviewColumns.length; ++i) {
            sum += (root.columnWidths[i] !== undefined ? root.columnWidths[i] : 72)
        }
        return Math.max(ovProcList.width, sum)
    }

    function applyOverviewSort() {
        if (root.sortColumn < 0 || root.sortColumn >= root.overviewColumns.length) {
            root.sortColumn = 3
        }
        var attr = root.overviewColumns[root.sortColumn].attr
        if (attr === "memoryPercent") attr = "memory"
        var proxyCol = (topProcFilterModel.columnMapping && topProcFilterModel.columnMapping[attr] !== undefined)
            ? Number(topProcFilterModel.columnMapping[attr])
            : root.sortColumn
        if (proxyCol >= 0 && topProcFilterModel.columnCount() > proxyCol) {
            topProcFilterModel.sort(proxyCol, root.sortOrder)
            root.modelRevision++
        }
    }

    function sortByAttribute(attribute, order) {
        var column = overviewColumns.findIndex(column => column.attr === attribute)
        if (column < 0) return
        sortColumn = column
        sortOrder = order
        applyOverviewSort()
    }

    function scrollToLastColumn() {
        ovProcList.contentX = Math.max(0, ovProcList.contentWidth - ovProcList.width)
    }

    function resetHorizontalScroll() {
        ovProcList.contentX = 0
    }

    // Top Processes model for the Overview tab
    Process.ProcessDataModel {
        id: topProcModel
        enabled: root.visible
        flatList: true
        enabledAttributes: ["name", "pid", "usage", "memory", "username", "uid"]
    }

    Win7SnapshotModel {
        id: topProcSnapshot
        sourceModel: topProcModel
        keyRole: Process.ProcessDataModel.PIDs
        initialUpdatesEnabled: root.updateController ? root.updateController.updateInterval > 0 : false
    }

    Table.ProcessSortFilterModel {
        id: topProcFilterModel
        sourceModel: topProcSnapshot
        viewMode: Table.ProcessSortFilterModel.ViewUser
        hiddenAttributes: ["uid", "username"]
    }

    Timer {
        id: initialSortTimer
        interval: 650
        repeat: false
        onTriggered: {
            root.initialSortDone = true
            root.applyOverviewSort()
        }
    }

    Connections {
        target: topProcFilterModel
        function onColumnMappingChanged() {
            root.applyOverviewSort()
            if (!root.initialSortDone) {
                initialSortTimer.restart()
            }
        }
        function onRowsInserted() {
            root.modelRevision++
            if (!root.initialSortDone) {
                initialSortTimer.restart()
            }
        }
        function onRowsRemoved() { root.modelRevision++ }
        function onRowsMoved() { root.modelRevision++ }
        function onLayoutChanged() { root.modelRevision++ }
        function onModelReset() { root.modelRevision++ }
        function onSorted() { root.modelRevision++ }
    }

    Process.ProcessController {
        id: processHelper
        window: root.Window.window
    }

    function rowAttr(rowIndex, attrName, _rev) {
        return topProcFilterModel.attributeValue(rowIndex, attrName)
    }

    function rowAttrMax(rowIndex, attrName) {
        return topProcFilterModel.attributeMaximum(rowIndex, attrName)
    }

    function formatOverviewCell(rowIndex, attrName, rev) {
        var raw = rowAttr(rowIndex, attrName, rev)
        if (attrName === "usage") {
            var maxV = rowAttrMax(rowIndex, "usage")
            return ProcessFormat.percentage(raw, maxV)
        }
        if (attrName === "memoryPercent") {
            return ProcessFormat.percentage(Number(rowAttr(rowIndex, "memory", rev)) * 1024,
                                            Number(memTotalSensor.value))
        }
        if (attrName === "memory") {
            var kb = Math.round(Number(raw) || 0)
            return kb.toLocaleString(Qt.locale("en_US"), "f", 0) + " K"
        }
        return String(raw ?? "")
    }

    readonly property var overviewColumns: [
        { attr: "name", title: i18n("Image Name"), defaultWidth: 110, align: Text.AlignLeft },
        { attr: "pid", title: i18n("PID"), defaultWidth: 48, align: Text.AlignRight },
        { attr: "usage", title: i18n("CPU %"), defaultWidth: 52, align: Text.AlignRight },
        { attr: "memoryPercent", title: i18n("Memory %"), defaultWidth: 70, align: Text.AlignRight },
        { attr: "memory", title: i18n("Memory"), defaultWidth: 96, align: Text.AlignRight }
    ]

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 15
        anchors.rightMargin: 14
        anchors.topMargin: 8
        anchors.bottomMargin: 11
        spacing: 6

        // Row 1: CPU, GPU, RAM, SWAP gauges followed by resource history.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            Layout.minimumHeight: 74
            spacing: 8

            Win7GroupBox {
                title: i18n("CPU")
                Layout.preferredWidth: root.gaugeWidth
                Layout.minimumWidth: root.gaugeWidth
                Layout.maximumWidth: root.gaugeWidth
                Layout.fillHeight: true
                topPadding: 17
                leftPadding: 7
                rightPadding: 7
                bottomPadding: 6

                Win7Gauge {
                    anchors.fill: parent
                    value: root.cpuUsageVal
                    kernelValue: root.cpuSystemVal
                    showKernelTimes: root.showKernelTimes
                    displayText: Math.round(root.cpuUsageVal) + " %"
                }
            }

            Win7GroupBox {
                title: i18n("GPU")
                Layout.preferredWidth: root.gaugeWidth
                Layout.minimumWidth: root.gaugeWidth
                Layout.maximumWidth: root.gaugeWidth
                Layout.fillHeight: true
                topPadding: 17
                leftPadding: 7
                rightPadding: 7
                bottomPadding: 6

                Win7Gauge {
                    anchors.fill: parent
                    value: root.gpuUsageVal
                    displayText: root.gpuUsageAvailable ? Math.round(root.gpuUsageVal) + " %" : "—"
                }
            }

            Win7GroupBox {
                title: i18n("RAM")
                Layout.preferredWidth: root.gaugeWidth
                Layout.minimumWidth: root.gaugeWidth
                Layout.maximumWidth: root.gaugeWidth
                Layout.fillHeight: true
                topPadding: 17
                leftPadding: 7
                rightPadding: 7
                bottomPadding: 6

                Win7Gauge {
                    anchors.fill: parent
                    value: root.usedMemPct
                    displayText: root.formatMemShort(root.usedMemMB)
                }
            }

            Win7GroupBox {
                title: i18n("SWAP")
                Layout.preferredWidth: root.gaugeWidth
                Layout.minimumWidth: root.gaugeWidth
                Layout.maximumWidth: root.gaugeWidth
                Layout.fillHeight: true
                topPadding: 17
                leftPadding: 7
                rightPadding: 7
                bottomPadding: 6

                Win7Gauge {
                    anchors.fill: parent
                    value: root.swapUsedPct
                    displayText: root.swapUsageAvailable ? root.formatMemShort(root.swapUsedMB) : "—"
                }
            }

            Win7GroupBox {
                title: width >= 210 ? i18n("Resource History (CPU / Memory)")
                    : width >= 115 ? i18n("Resource History") : i18n("History")
                Layout.fillWidth: true
                Layout.fillHeight: true
                topPadding: 17
                leftPadding: 7
                rightPadding: 7
                bottomPadding: 6

                Win7HistoryGraph {
                    id: overviewHistoryGraph
                    anchors.fill: parent
                    currentValue: root.cpuUsageVal
                    secondaryValue: root.showKernelTimes ? root.cpuSystemVal : root.ioActivityPct
                    tertiaryValue: root.usedMemPct
                    showSecondary: true
                    showTertiary: true
                    primaryColor: "#00ff00"
                    secondaryColor: root.showKernelTimes ? "#ff0000" : "#ffff00"
                    tertiaryColor: "#0080ff"
                    tertiaryLineWidth: 2
                    updateInterval: root.updateInterval
                    running: false
                }
            }
        }

        // Row 2: System & Memory + Disk & Network GroupBoxes
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 84
            Layout.minimumHeight: 80
            spacing: 10

            Win7GroupBox {
                title: i18n("System & Memory")
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 172
                topPadding: 16
                leftPadding: 8
                rightPadding: 8
                bottomPadding: 5

                GridLayout {
                    anchors.fill: parent
                    columns: 2
                    rowSpacing: 1
                    columnSpacing: 6

                    Text { text: i18n("Physical (MB)"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                    Text { text: root.usedMemMB + " / " + root.totalMemMB; font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                    Text { text: i18n("Cache/Swap"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                    Text { text: root.cachedMemMB + " / " + root.swapUsedMB + " MB"; font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                    Text { text: i18n("Cores / Processes"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                    Text { text: (Number(cpuCoresSensor.value) || 1) + " / " + root.processCount; font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                    Text { text: i18n("Up Time"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                    Text { text: root.formatUptime(uptimeSensor.value); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                }
            }

            Win7GroupBox {
                title: i18n("Disk & Network")
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 172
                topPadding: 16
                leftPadding: 8
                rightPadding: 8
                bottomPadding: 5

                GridLayout {
                    anchors.fill: parent
                    columns: 2
                    rowSpacing: 1
                    columnSpacing: 6

                    Text { text: i18n("Disk Space"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                    Text { text: root.diskUsedGB.toFixed(1) + " / " + root.diskTotalGB.toFixed(1) + " GB"; font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                    Text { text: i18n("Disk Read/Write"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                    Text { text: root.formatRateShort((Number(diskReadSensor.value) || 0) + (Number(diskWriteSensor.value) || 0)); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                    Text { text: i18n("Net Down"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                    Text { text: root.formatRateShort(netDownSensor.value); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

                    Text { text: i18n("Net Up"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                    Text { text: root.formatRateShort(netUpSensor.value); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                }
            }
        }

        // Row 3: Top Resource Processes Win7 ListView
        Win7GroupBox {
            title: i18n("Top Resource Processes")
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 105
            topPadding: 16
            leftPadding: 7
            rightPadding: 7
            bottomPadding: 6

            Rectangle {
                id: overviewViewport
                anchors.fill: parent
                color: "#ffffff"
                border.width: 1
                border.color: "#828790"
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 1
                    spacing: 0

                    // Win7 22px Header Bar
                    Item {
                        id: ovHeaderClip
                        Layout.fillWidth: true
                        Layout.rightMargin: overviewVerticalScroll.visible ? 17 : 0
                        Layout.preferredHeight: 22
                        clip: true
                        Rectangle {
                            id: ovHeaderBar
                            x: -ovProcList.contentX
                            width: root.totalOverviewColumnsWidth
                            height: 22
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#ffffff" }
                                GradientStop { position: 0.42; color: "#f7f8fa" }
                                GradientStop { position: 0.92; color: "#f1f2f4" }
                                GradientStop { position: 0.96; color: "#d5d5d5" }
                                GradientStop { position: 1.0; color: "#fbfbfb" }
                            }

                            Row {
                                anchors.fill: parent

                                Repeater {
                                    model: root.overviewColumns

                                    Item {
                                        id: ovColHdr
                                        required property int index
                                        required property var modelData

                                        width: root.columnWidths[index] !== undefined ? root.columnWidths[index] : modelData.defaultWidth
                                        height: ovHeaderBar.height
                                        readonly property bool isSorted: root.sortColumn === index
                                        property bool hovered: false

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: ovColHdr.isSorted || ovColHdr.hovered
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: "#ffffff" }
                                                GradientStop { position: 0.08; color: "#f2f9fc" }
                                                GradientStop { position: 0.45; color: "#e1f1f9" }
                                                GradientStop { position: 0.92; color: "#d8ecf6" }
                                                GradientStop { position: 0.96; color: "#96d9f9" }
                                                GradientStop { position: 1.0; color: "#ffffff" }
                                            }
                                        }

                                        Canvas {
                                            id: ovSortArrow
                                            width: 7
                                            height: 4
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            y: 2
                                            visible: ovColHdr.isSorted
                                            property int currentOrder: root.sortOrder
                                            onCurrentOrderChanged: requestPaint()
                                            onVisibleChanged: if (visible) requestPaint()
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                ctx.fillStyle = "#3c596c"
                                                ctx.beginPath()
                                                if (root.sortOrder === Qt.AscendingOrder) {
                                                    ctx.moveTo(3.5, 0)
                                                    ctx.lineTo(7, 4)
                                                    ctx.lineTo(0, 4)
                                                } else {
                                                    ctx.moveTo(0, 0)
                                                    ctx.lineTo(7, 0)
                                                    ctx.lineTo(3.5, 4)
                                                }
                                                ctx.closePath()
                                                ctx.fill()
                                            }
                                        }

                                        Text {
                                            id: ovHdrText
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: ovColHdr.modelData.align === Text.AlignRight ? Text.AlignRight : Text.AlignLeft
                                            text: ovColHdr.modelData.title
                                            elide: Text.ElideRight
                                            font.family: "Segoe UI"
                                            font.pixelSize: 12
                                            font.hintingPreference: Font.PreferFullHinting
                                            color: "#000000"
                                            renderType: Text.NativeRendering
                                        }

                                        Rectangle {
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 1
                                            width: 1
                                            color: (ovColHdr.isSorted || ovColHdr.hovered) ? "#96d9f9" : "#d5d5d5"
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.rightMargin: 4
                                            hoverEnabled: true
                                            onEntered: ovColHdr.hovered = true
                                            onExited: ovColHdr.hovered = false
                                            onClicked: {
                                                if (root.sortColumn === ovColHdr.index) {
                                                    root.sortOrder = root.sortOrder === Qt.AscendingOrder ? Qt.DescendingOrder : Qt.AscendingOrder
                                                } else {
                                                    root.sortColumn = ovColHdr.index
                                                    root.sortOrder = (["usage", "memory", "memoryPercent"].indexOf(ovColHdr.modelData.attr) !== -1) ? Qt.DescendingOrder : Qt.AscendingOrder
                                                }
                                                root.applyOverviewSort()
                                            }
                                        }

                                        // Interactive right-edge column width resize handle
                                        MouseArea {
                                            id: ovResizeHandle
                                            anchors.right: parent.right
                                            anchors.rightMargin: -3
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: 6
                                            z: 10
                                            cursorShape: Qt.SplitHCursor
                                            property real startSceneX: 0
                                            property real startWidth: 0
                                            onPressed: mouse => {
                                                var pt = ovResizeHandle.mapToItem(null, mouse.x, mouse.y)
                                                startSceneX = pt.x
                                                startWidth = ovColHdr.width
                                            }
                                            onPositionChanged: mouse => {
                                                if (pressed) {
                                                    var pt = ovResizeHandle.mapToItem(null, mouse.x, mouse.y)
                                                    root.setColumnWidth(ovColHdr.index, startWidth + (pt.x - startSceneX))
                                                }
                                            }
                                            onDoubleClicked: {
                                                root.setColumnWidth(ovColHdr.index, Math.max(ovColHdr.modelData.defaultWidth, ovHdrText.implicitWidth + 16))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ListView {
                        id: ovProcList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.rightMargin: overviewVerticalScroll.visible ? 17 : 0
                        Layout.bottomMargin: overviewHorizontalScroll.visible ? 17 : 0
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: root.totalOverviewColumnsWidth
                        flickableDirection: Flickable.HorizontalAndVerticalFlick
                        model: topProcFilterModel

                        ScrollBar.vertical: Win7ScrollBar {
                            id: overviewVerticalScroll
                            parent: overviewViewport
                            x: parent.width - width - 1
                            y: 23
                            width: 17
                            height: parent.height - y - 1 - (overviewHorizontalScroll.visible ? 17 : 0)
                            policy: ScrollBar.AsNeeded
                            stepSize: 17 / Math.max(17, ovProcList.contentHeight)
                        }

                        ScrollBar.horizontal: Win7ScrollBar {
                            id: overviewHorizontalScroll
                            parent: overviewViewport
                            x: 1
                            y: parent.height - height - 1
                            width: parent.width - 2 - (overviewVerticalScroll.visible ? 17 : 0)
                            height: 17
                            policy: ScrollBar.AsNeeded
                            stepSize: 20 / Math.max(20, ovProcList.contentWidth)
                        }

                        delegate: Item {
                            id: ovRow
                            required property int index

                            width: root.totalOverviewColumnsWidth
                            height: 17

                            readonly property bool isSelected: root.selectedRow === index
                            property bool isHovered: false

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: 1
                                anchors.rightMargin: 1
                                radius: 2
                                visible: ovRow.isSelected || ovRow.isHovered
                                border.width: 1
                                border.color: ovRow.isSelected ? "#7da2ce" : "#b8d6fb"
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: ovRow.isSelected ? "#dcebfc" : "#f2f7fe" }
                                    GradientStop { position: 1.0; color: ovRow.isSelected ? "#c1dbfc" : "#e5f0fe" }
                                }
                            }

                            Row {
                                anchors.fill: parent

                                Repeater {
                                    model: root.overviewColumns

                                    Item {
                                        required property int index
                                        required property var modelData
                                        width: root.columnWidths[index] !== undefined ? root.columnWidths[index] : modelData.defaultWidth
                                        height: ovRow.height

                                        Text {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: modelData.align
                                            text: root.formatOverviewCell(ovRow.index, modelData.attr, root.modelRevision)
                                            elide: Text.ElideRight
                                            font.family: "Segoe UI"
                                            font.pixelSize: 12
                                            font.hintingPreference: Font.PreferFullHinting
                                            color: "#000000"
                                            renderType: Text.NativeRendering
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: ovRow.isHovered = true
                                onExited: ovRow.isHovered = false
                                onClicked: root.selectedRow = ovRow.index
                                onDoubleClicked: {
                                    var pid = Number(root.rowAttr(ovRow.index, "pid"))
                                    var nm = String(root.rowAttr(ovRow.index, "name") || "")
                                    if (pid > 0) {
                                        root.inspectProcessRequested(pid, nm)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Row 4: Bottom Quick Actions bar matching Win7 Task Manager buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Win7Button {
                Layout.preferredHeight: 23
                showShield: true
                mnemonicText: i18n("&Processes...")
                text: i18n("Processes...")
                onClicked: {
                    var pid = Number(root.rowAttr(root.selectedRow, "pid"))
                    var nm = String(root.rowAttr(root.selectedRow, "name") || "")
                    if (pid > 0) {
                        root.inspectProcessRequested(pid, nm)
                    } else {
                        root.switchToTabRequested("processes")
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Win7Button {
                Layout.preferredWidth: 78
                Layout.preferredHeight: 23
                mnemonicText: i18n("&End Process")
                text: i18n("End Process")
                enabled: ovProcList.count > 0 && root.selectedRow >= 0
                onClicked: {
                    var pid = Number(root.rowAttr(root.selectedRow, "pid"))
                    if (pid > 0) {
                        processHelper.sendSignal([pid], Process.Signal.TerminateSignal)
                    }
                }
            }

            Win7Button {
                Layout.preferredWidth: 78
                Layout.preferredHeight: 23
                mnemonicText: i18n("&New Task...")
                text: i18n("New Task...")
                isDefault: true
                onClicked: root.newTaskRequested()
            }
        }
    }
}
