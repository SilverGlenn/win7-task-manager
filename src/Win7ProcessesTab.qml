/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import org.kde.ksysguard.formatter as Formatter
import org.kde.ksysguard.process as Process
import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.table as Table
import "Win7ProcessFormat.js" as ProcessFormat

Item {
    id: root

    property bool showAllUsers: false
    property int selectedRow: 0
    property int sortColumn: 0
    property int sortOrder: Qt.AscendingOrder
    property int totalProcessCount: 0
    property int modelRevision: 0
    property bool initialSortDone: false
    readonly property int visibleProcessCount: procListView.count
    readonly property var debugCaptureWindow: selectColumnsWindow.visible ? selectColumnsWindow : propertiesWindow.visible ? propertiesWindow : null

    Sensors.Sensor { id: physicalMemorySensor; sensorId: "memory/physical/total"; enabled: true }

    // Master catalog of selectable Win7 Process columns
    readonly property var allColumnCatalog: [
        { attr: "name", title: i18n("Image Name"), checkLabel: i18n("Image Name (Process Name)"), defaultWidth: 104, align: Text.AlignLeft, locked: true },
        { attr: "pid", title: i18n("PID"), checkLabel: i18n("PID (Process Identifier)"), defaultWidth: 52, align: Text.AlignRight, locked: false },
        { attr: "username", title: i18n("User Name"), checkLabel: i18n("User Name"), defaultWidth: 68, align: Text.AlignLeft, locked: false },
        { attr: "uid", title: i18n("Session / UID"), checkLabel: i18n("Session ID (UID)"), defaultWidth: 56, align: Text.AlignRight, locked: false },
        { attr: "usage", title: i18n("CPU %"), checkLabel: i18n("CPU Usage (%)"), defaultWidth: 52, align: Text.AlignRight, locked: false },
        { attr: "memoryPercent", title: i18n("Memory %"), checkLabel: i18n("Memory - Physical RAM (%)"), defaultWidth: 70, align: Text.AlignRight, locked: false },
        { attr: "memory", title: i18n("Memory (Private Working Set)"), checkLabel: i18n("Memory - Private Working Set"), defaultWidth: 82, align: Text.AlignRight, locked: false },
        { attr: "vmSize", title: i18n("Commit Size"), checkLabel: i18n("Memory - Commit Size (VM)"), defaultWidth: 78, align: Text.AlignRight, locked: false },
        { attr: "sharedMemory", title: i18n("Shared Memory"), checkLabel: i18n("Memory - Shared Working Set"), defaultWidth: 78, align: Text.AlignRight, locked: false },
        { attr: "niceLevel", title: i18n("Base Priority"), checkLabel: i18n("Base Priority (Nice)"), defaultWidth: 64, align: Text.AlignRight, locked: false },
        { attr: "tty", title: i18n("TTY"), checkLabel: i18n("Terminal (TTY)"), defaultWidth: 54, align: Text.AlignLeft, locked: false },
        { attr: "command", title: i18n("Description"), checkLabel: i18n("Description / Command Line"), defaultWidth: 96, align: Text.AlignLeft, locked: false }
    ]

    property var activeColumnAttrs: ["name", "username", "usage", "memoryPercent", "memory", "command"]

    // The percentage column is derived from memory, not a backend attribute.
    readonly property var backendColumnAttrs: activeColumnAttrs.map(attr => attr === "memoryPercent" ? "memory" : attr)

    readonly property var columnDefs: {
        var list = []
        for (var i = 0; i < activeColumnAttrs.length; ++i) {
            var a = activeColumnAttrs[i]
            for (var j = 0; j < allColumnCatalog.length; ++j) {
                if (allColumnCatalog[j].attr === a) {
                    list.push(allColumnCatalog[j])
                    break
                }
            }
        }
        return list
    }

    // Adjustable pixel widths for each visible column
    property var columnWidths: [104, 68, 52, 70, 96, 128]
    property var savedColumnWidths: ({})

    function syncColumnWidths() {
        var defs = root.columnDefs
        var next = []
        for (var i = 0; i < defs.length; ++i) {
            next.push(root.savedColumnWidths[defs[i].attr] || defs[i].defaultWidth)
        }
        root.columnWidths = next
    }

    function setColumnWidth(colIdx, newW) {
        var copy = root.columnWidths.slice()
        while (copy.length <= colIdx) {
            copy.push(72)
        }
        copy[colIdx] = Math.max(30, Math.round(newW))
        root.columnWidths = copy
        var saved = Object.assign({}, root.savedColumnWidths)
        saved[root.columnDefs[colIdx].attr] = copy[colIdx]
        root.savedColumnWidths = saved
    }

    readonly property real totalColumnsWidth: {
        var sum = 0
        for (var i = 0; i < root.columnDefs.length; ++i) {
            sum += (root.columnWidths[i] !== undefined ? root.columnWidths[i] : root.columnDefs[i].defaultWidth)
        }
        return Math.max(procListView.width, sum)
    }

    function updateCounts() {
        root.totalProcessCount = allProcessesModel.rowCount()
    }

    function applySort() {
        if (root.sortColumn < 0 || root.sortColumn >= root.columnDefs.length) {
            root.sortColumn = 0
        }
        var attr = root.columnDefs[root.sortColumn].attr
        if (attr === "memoryPercent") attr = "memory"
        var proxyCol = (filterModel.columnMapping && filterModel.columnMapping[attr] !== undefined)
            ? Number(filterModel.columnMapping[attr])
            : root.sortColumn
        if (proxyCol >= 0 && filterModel.columnCount() > proxyCol) {
            filterModel.sort(proxyCol, root.sortOrder)
            root.modelRevision++
        }
    }

    function openSelectColumnsDialog() {
        selectColumnsWindow.openDialog()
    }

    function sortByAttribute(attribute, order) {
        var column = activeColumnAttrs.indexOf(attribute)
        if (column < 0) return
        sortColumn = column
        sortOrder = order
        applySort()
    }

    function scrollToLastColumn() {
        procListView.contentX = Math.max(0, procListView.contentWidth - procListView.width)
    }

    function resetHorizontalScroll() {
        procListView.contentX = 0
    }

    function openPropertiesDialog() {
        propertiesWindow.openDialog()
    }

    function openFileLocationForSelected() {
        var cmd = String(rowAttributeValue(root.selectedRow, "command") || "").trim()
        var exe = cmd.split(" ")[0]
        if (exe.indexOf("/") === 0) {
            var lastSlash = exe.lastIndexOf("/")
            var dirPath = lastSlash > 0 ? exe.substring(0, lastSlash) : "/"
            Qt.openUrlExternally("file://" + dirPath)
        } else {
            propertiesWindow.openDialog()
        }
    }

    function refreshNow() {
        filterModel.invalidate()
        root.applySort()
        root.updateCounts()
        root.modelRevision++
    }

    function openContextMenuAt(xPos, yPos) {
        procContextMenu.popup(root, xPos, yPos)
    }

    function closeContextMenu() {
        procContextMenu.close()
    }

    function selectProcessByPid(targetPid, targetName) {
        for (var r = 0; r < filterModel.rowCount(); ++r) {
            var pidVal = rowAttributeValue(r, "pid")
            var nameVal = rowAttributeValue(r, "name")
            if (Number(pidVal) === Number(targetPid) || (targetName && String(nameVal) === String(targetName))) {
                root.selectedRow = r
                procListView.positionViewAtIndex(r, ListView.Center)
                return
            }
        }
        if (!root.showAllUsers) {
            root.showAllUsers = true
            Qt.callLater(function() {
                for (var r2 = 0; r2 < filterModel.rowCount(); ++r2) {
                    var pidVal2 = rowAttributeValue(r2, "pid")
                    if (Number(pidVal2) === Number(targetPid)) {
                        root.selectedRow = r2
                        procListView.positionViewAtIndex(r2, ListView.Center)
                        return
                    }
                }
            })
        }
    }

    function endSelectedProcess(forceKill) {
        var pid = Number(rowAttributeValue(root.selectedRow, "pid"))
        var name = String(rowAttributeValue(root.selectedRow, "name") || "")
        if (!pid) return
        killConfirmWindow.targetPid = pid
        killConfirmWindow.targetName = name
        killConfirmWindow.signalToSend = forceKill ? Process.Signal.KillSignal : Process.Signal.TerminateSignal
        killConfirmWindow.openDialog()
    }

    function setSelectedPriority(niceValue) {
        var pid = Number(rowAttributeValue(root.selectedRow, "pid"))
        if (!pid) return
        processHelper.setPriority([pid], niceValue)
        root.modelRevision++
    }

    function openSelectedReniceDialog() {
        var pid = Number(rowAttributeValue(root.selectedRow, "pid"))
        if (!pid) return
        var name = String(rowAttributeValue(root.selectedRow, "name") || "")
        var pids = [pid]
        reniceWindow.targetPid = pid
        reniceWindow.targetName = name
        reniceWindow.niceValue = (processHelper.priority(pids) ?? 0)
        reniceWindow.cpuMode = (processHelper.cpuScheduler(pids) ?? 0)
        reniceWindow.ioMode = (processHelper.ioScheduler(pids) ?? 0)
        reniceWindow.openDialog()
    }

    function openSelectedAffinityDialog() {
        var pid = Number(rowAttributeValue(root.selectedRow, "pid"))
        if (!pid) return
        var name = String(rowAttributeValue(root.selectedRow, "name") || "")
        affinityWindow.targetPid = pid
        affinityWindow.targetName = name
        affinityWindow.currentAffinity = processHelper.affinity([pid])
        affinityWindow.openDialog()
    }

    // Always-enabled lightweight model for accurate total system process count in status bar
    Process.ProcessDataModel {
        id: allProcessesModel
        enabled: true
        flatList: true
        enabledAttributes: ["pid"]
    }

    Connections {
        target: allProcessesModel
        function onRowsInserted() { root.updateCounts() }
        function onRowsRemoved() { root.updateCounts() }
        function onModelReset() { root.updateCounts() }
        function onLayoutChanged() { root.updateCounts() }
    }

    // Main Processes table model
    Process.ProcessDataModel {
        id: processModel
        enabled: true
        flatList: true

        property var requiredAttrs: ["pid", "uid", "name", "username", "usage", "memory", "command"]

        enabledAttributes: {
            var cols = [...new Set(root.backendColumnAttrs)]
            for (var i = 0; i < requiredAttrs.length; ++i) {
                if (cols.indexOf(requiredAttrs[i]) === -1) {
                    cols.push(requiredAttrs[i])
                }
            }
            return cols
        }
    }

    Table.ProcessSortFilterModel {
        id: filterModel
        sourceModel: processModel
        viewMode: root.showAllUsers ? Table.ProcessSortFilterModel.ViewAll : Table.ProcessSortFilterModel.ViewOwn
        hiddenAttributes: {
            var hidden = []
            var enabled = processModel.enabledAttributes
            for (var i = 0; i < enabled.length; ++i) {
                if (root.backendColumnAttrs.indexOf(enabled[i]) === -1) {
                    hidden.push(enabled[i])
                }
            }
            return hidden
        }
    }

    Timer {
        id: procInitialSortTimer
        interval: 650
        repeat: false
        onTriggered: {
            root.initialSortDone = true
            root.applySort()
        }
    }

    // Periodic live cell value refresh so CPU/Memory numbers update smoothly
    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        onTriggered: root.modelRevision++
    }

    Connections {
        target: filterModel
        function onColumnMappingChanged() {
            root.applySort()
            if (!root.initialSortDone) {
                procInitialSortTimer.restart()
            }
        }
        function onRowsInserted() {
            root.modelRevision++
            if (!root.initialSortDone) {
                procInitialSortTimer.restart()
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

    function rowAttributeValue(rowIndex, attrName, _rev) {
        return filterModel.attributeValue(rowIndex, attrName)
    }

    function rowAttributeMax(rowIndex, attrName) {
        return filterModel.attributeMaximum(rowIndex, attrName)
    }

    function formatCellText(rowIndex, attrName, rev) {
        var raw = rowAttributeValue(rowIndex, attrName, rev)
        if (attrName === "usage") {
            var maxVal = rowAttributeMax(rowIndex, "usage")
            return ProcessFormat.percentage(raw, maxVal)
        }
        if (attrName === "memoryPercent") {
            // Process memory is KiB; the physical-memory sensor reports bytes.
            return ProcessFormat.percentage(Number(rowAttributeValue(rowIndex, "memory", rev)) * 1024,
                                            Number(physicalMemorySensor.value))
        }
        if (attrName === "memory" || attrName === "vmSize" || attrName === "sharedMemory") {
            var kb = Math.round(Number(raw) || 0)
            return kb.toLocaleString(Qt.locale("en_US"), "f", 0) + " K"
        }
        if (attrName === "command") {
            var cmd = String(raw || "")
            if (cmd.length === 0) {
                return String(rowAttributeValue(rowIndex, "name", rev) || "")
            }
            return cmd
        }
        return String(raw ?? "")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 17
        anchors.rightMargin: 14
        anchors.topMargin: 17
        anchors.bottomMargin: 15
        spacing: 8

        // Classic Win7 Processes ListView container (#828790 1px border)
        Rectangle {
            id: procListViewport
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#ffffff"
            border.width: 1
            border.color: "#828790"
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                // Classic Win7 25px Column Header Bar (horizontally synced with procListView.contentX)
                Item {
                    id: procHeaderClip
                    Layout.fillWidth: true
                    Layout.rightMargin: procVerticalScroll.visible ? 17 : 0
                    Layout.preferredHeight: 25
                    clip: true

                    Rectangle {
                        id: procHeaderBar
                        x: -procListView.contentX
                        width: Math.max(procHeaderClip.width, root.totalColumnsWidth + 16)
                        height: 25
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#ffffff" }
                            GradientStop { position: 0.42; color: "#f7f8fa" }
                            GradientStop { position: 0.92; color: "#f1f2f4" }
                            GradientStop { position: 0.96; color: "#d5d5d5" }
                            GradientStop { position: 1.0; color: "#fbfbfb" }
                        }

                        Row {
                            id: headerColumnsRow
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left

                            Repeater {
                                model: root.columnDefs

                                Item {
                                    id: colHeaderItem
                                    required property int index
                                    required property var modelData

                                    width: root.columnWidths[index] !== undefined ? root.columnWidths[index] : modelData.defaultWidth
                                    height: procHeaderBar.height

                                    readonly property bool isSorted: root.sortColumn === index
                                    property bool hovered: false

                                    // Sorted or hovered column icy-blue gradient (#f2f9fc -> #d8ecf6 with #96d9f9 bottom line)
                                    Rectangle {
                                        anchors.fill: parent
                                        visible: colHeaderItem.isSorted || colHeaderItem.hovered
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "#ffffff" }
                                            GradientStop { position: 0.08; color: colHeaderItem.isSorted ? "#f2f9fc" : "#f5fbfe" }
                                            GradientStop { position: 0.45; color: colHeaderItem.isSorted ? "#e1f1f9" : "#eaf6fd" }
                                            GradientStop { position: 0.92; color: colHeaderItem.isSorted ? "#d8ecf6" : "#def0fa" }
                                            GradientStop { position: 0.96; color: "#96d9f9" }
                                            GradientStop { position: 1.0; color: "#ffffff" }
                                        }
                                    }

                                    // Top-center sort arrow triangle
                                    Canvas {
                                        id: sortArrowCanvas
                                        width: 7
                                        height: 4
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 3
                                        visible: colHeaderItem.isSorted
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
                                        id: hdrLabelText
                                        anchors.fill: parent
                                        anchors.leftMargin: 5
                                        anchors.rightMargin: 5
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: colHeaderItem.modelData.align === Text.AlignRight ? Text.AlignRight : Text.AlignLeft
                                        text: colHeaderItem.modelData.title
                                        elide: Text.ElideRight
                                        font.family: "Segoe UI"
                                        font.pixelSize: 12
                                        font.hintingPreference: Font.PreferFullHinting
                                        color: "#000000"
                                        renderType: Text.NativeRendering
                                    }

                                    // Right column border line
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 1
                                        width: 1
                                        color: (colHeaderItem.isSorted || colHeaderItem.hovered) ? "#96d9f9" : "#d5d5d5"
                                    }

                                    // Click to sort / right-click to Select Columns
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.rightMargin: 4
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onEntered: colHeaderItem.hovered = true
                                        onExited: colHeaderItem.hovered = false
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.RightButton) {
                                                root.openSelectColumnsDialog()
                                                return
                                            }
                                            if (root.sortColumn === colHeaderItem.index) {
                                                root.sortOrder = (root.sortOrder === Qt.AscendingOrder) ? Qt.DescendingOrder : Qt.AscendingOrder
                                            } else {
                                                root.sortColumn = colHeaderItem.index
                                                root.sortOrder = (["usage", "memory", "memoryPercent"].indexOf(colHeaderItem.modelData.attr) !== -1)
                                                    ? Qt.DescendingOrder
                                                    : Qt.AscendingOrder
                                            }
                                            root.applySort()
                                        }
                                    }

                                    // Interactive right-edge column width resize handle (Win32 SysHeader32 behavior)
                                    MouseArea {
                                        id: colResizeHandle
                                        anchors.right: parent.right
                                        anchors.rightMargin: -3
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 6
                                        z: 10
                                        cursorShape: Qt.SplitHCursor
                                        acceptedButtons: Qt.LeftButton
                                        property real startSceneX: 0
                                        property real startWidth: 0
                                        onPressed: mouse => {
                                            var pt = colResizeHandle.mapToItem(null, mouse.x, mouse.y)
                                            startSceneX = pt.x
                                            startWidth = colHeaderItem.width
                                        }
                                        onPositionChanged: mouse => {
                                            if (pressed) {
                                                var pt = colResizeHandle.mapToItem(null, mouse.x, mouse.y)
                                                root.setColumnWidth(colHeaderItem.index, startWidth + (pt.x - startSceneX))
                                            }
                                        }
                                        onDoubleClicked: {
                                            root.setColumnWidth(colHeaderItem.index, Math.max(colHeaderItem.modelData.defaultWidth, hdrLabelText.implicitWidth + 16))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Process Rows ListView
                ListView {
                    id: procListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.rightMargin: procVerticalScroll.visible ? 17 : 0
                    Layout.bottomMargin: procHorizontalScroll.visible ? 17 : 0
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: root.totalColumnsWidth
                    flickableDirection: Flickable.HorizontalAndVerticalFlick
                    model: filterModel

                    ScrollBar.vertical: Win7ScrollBar {
                        id: procVerticalScroll
                        parent: procListViewport
                        x: parent.width - width - 1
                        y: 26
                        height: parent.height - y - 1 - (procHorizontalScroll.visible ? 17 : 0)
                        policy: ScrollBar.AsNeeded
                        width: 17
                        stepSize: 17 / Math.max(17, procListView.contentHeight)
                    }

                    ScrollBar.horizontal: Win7ScrollBar {
                        id: procHorizontalScroll
                        parent: procListViewport
                        x: 1
                        y: parent.height - height - 1
                        width: parent.width - 2 - (procVerticalScroll.visible ? 17 : 0)
                        policy: ScrollBar.AsNeeded
                        height: 17
                        stepSize: 20 / Math.max(20, procListView.contentWidth)
                    }

                    // Subtle vertical column separator lines (#f2f5f9) matching Win7 Processes tab
                    Row {
                        x: 0
                        height: procListView.height
                        z: 0
                        Repeater {
                            model: root.columnDefs
                            Item {
                                required property int index
                                required property var modelData
                                width: root.columnWidths[index] !== undefined ? root.columnWidths[index] : modelData.defaultWidth
                                height: procListView.height
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 1
                                    color: "#f2f5f9"
                                }
                            }
                        }
                    }

                    delegate: Item {
                        id: procRowDelegate
                        required property int index

                        width: root.totalColumnsWidth
                        height: 17

                        readonly property bool isSelected: root.selectedRow === index
                        property bool isHovered: false

                        // Win7 row selection / hover pill
                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 1
                            anchors.rightMargin: 1
                            radius: 2
                            visible: procRowDelegate.isSelected || procRowDelegate.isHovered
                            border.width: 1
                            border.color: procRowDelegate.isSelected ? (procListView.activeFocus ? "#7da2ce" : "#dadada") : "#b8d6fb"
                            gradient: Gradient {
                                GradientStop {
                                    position: 0.0
                                    color: procRowDelegate.isSelected ? (procListView.activeFocus ? "#dcebfc" : "#f9f9f9") : "#f2f7fe"
                                }
                                GradientStop {
                                    position: 1.0
                                    color: procRowDelegate.isSelected ? (procListView.activeFocus ? "#c1dbfc" : "#e6e6e6") : "#e5f0fe"
                                }
                            }
                        }

                        Row {
                            anchors.fill: parent

                            Repeater {
                                model: root.columnDefs

                                Item {
                                    required property int index
                                    required property var modelData

                                    width: root.columnWidths[index] !== undefined ? root.columnWidths[index] : modelData.defaultWidth
                                    height: procRowDelegate.height

                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: modelData.align
                                        text: root.formatCellText(procRowDelegate.index, modelData.attr, root.modelRevision)
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
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onEntered: procRowDelegate.isHovered = true
                            onExited: procRowDelegate.isHovered = false
                            onPressed: mouse => {
                                procListView.forceActiveFocus()
                                root.selectedRow = procRowDelegate.index
                                if (mouse.button === Qt.RightButton) {
                                    procContextMenu.popup()
                                }
                            }
                            onDoubleClicked: root.openPropertiesDialog()
                        }
                    }

                    Keys.onUpPressed: {
                        if (root.selectedRow > 0) {
                            root.selectedRow--
                            procListView.positionViewAtIndex(root.selectedRow, ListView.Contain)
                        }
                    }
                    Keys.onDownPressed: {
                        if (root.selectedRow < filterModel.rowCount() - 1) {
                            root.selectedRow++
                            procListView.positionViewAtIndex(root.selectedRow, ListView.Contain)
                        }
                    }
                    Keys.onDeletePressed: root.endSelectedProcess(false)
                }
            }
        }

        // Bottom bar: [UAC Shield] Show processes from all users | End Process
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Win7Button {
                Layout.preferredHeight: 23
                showShield: true
                visible: !root.showAllUsers
                mnemonicText: i18n("&Show processes from all users")
                text: i18n("Show processes from all users")
                onClicked: root.showAllUsers = true
            }

            // Authentic Windows 7 13x13 CheckBox when all users are shown
            Item {
                visible: root.showAllUsers
                Layout.preferredWidth: allUsersChkText.implicitWidth + 19
                Layout.preferredHeight: 21

                Rectangle {
                    id: allUsersChkBox
                    x: 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 13
                    height: 13
                    border.width: 1
                    border.color: allUsersChkMouse.containsMouse ? "#3c7fb1" : "#8e8f8f"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#f4f4f4" }
                        GradientStop { position: 1.0; color: "#dedede" }
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        color: "#ffffff"
                    }
                    Canvas {
                        anchors.fill: parent
                        visible: root.showAllUsers
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = "#1c5180"
                            ctx.lineWidth = 1.6
                            ctx.beginPath()
                            ctx.moveTo(2.5, 6.5)
                            ctx.lineTo(5.2, 9.5)
                            ctx.lineTo(10.5, 3.0)
                            ctx.stroke()
                        }
                    }
                }

                Text {
                    id: allUsersChkText
                    x: 19
                    anchors.verticalCenter: parent.verticalCenter
                    text: i18n("<u>S</u>how processes from all users")
                    textFormat: Text.StyledText
                    font.family: "Segoe UI"
                    font.pixelSize: 12
                    font.hintingPreference: Font.PreferFullHinting
                    color: "#000000"
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    id: allUsersChkMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.showAllUsers = !root.showAllUsers
                }
            }

            Item { Layout.fillWidth: true }

            Win7Button {
                Layout.preferredWidth: 80
                Layout.preferredHeight: 23
                mnemonicText: i18n("&End Process")
                text: i18n("End Process")
                enabled: root.visibleProcessCount > 0 && root.selectedRow >= 0
                onClicked: root.endSelectedProcess(false)
            }
        }
    }

    // Classic Win7 Process Right-Click Context Menu matching VM screenshot (crop_ctx_proc.png)
    Win7Menu {
        id: procContextMenu

        Win7MenuItem {
            text: i18n("Open File Location")
            onTriggered: root.openFileLocationForSelected()
        }
        Win7MenuSeparator { }
        Win7MenuItem {
            text: i18n("End Process")
            onTriggered: root.endSelectedProcess(false)
        }
        Win7MenuItem {
            text: i18n("End Process Tree")
            onTriggered: root.endSelectedProcess(true)
        }
        Win7MenuItem {
            text: i18n("Debug")
            enabled: false
        }
        Win7MenuItem {
            text: i18n("UAC Virtualization")
            checkable: true
            checked: false
            enabled: false
        }
        Win7MenuItem {
            text: i18n("Create Dump File")
            enabled: false
        }
        Win7MenuSeparator { }
        Win7Menu {
            title: i18n("Set Priority")

            Win7MenuItem {
                text: i18n("Realtime")
                checkable: true
                radio: true
                onTriggered: root.setSelectedPriority(-20)
            }
            Win7MenuItem {
                text: i18n("High")
                checkable: true
                radio: true
                onTriggered: root.setSelectedPriority(-10)
            }
            Win7MenuItem {
                text: i18n("Above Normal")
                checkable: true
                radio: true
                onTriggered: root.setSelectedPriority(-5)
            }
            Win7MenuItem {
                text: i18n("Normal")
                checked: true
                checkable: true
                radio: true
                onTriggered: root.setSelectedPriority(0)
            }
            Win7MenuItem {
                text: i18n("Below Normal")
                checkable: true
                radio: true
                onTriggered: root.setSelectedPriority(5)
            }
            Win7MenuItem {
                text: i18n("Low")
                checkable: true
                radio: true
                onTriggered: root.setSelectedPriority(19)
            }
            Win7MenuSeparator { }
            Win7MenuItem {
                text: i18n("Custom Priority / Scheduler...")
                onTriggered: root.openSelectedReniceDialog()
            }
        }
        Win7MenuItem {
            text: i18n("Set Affinity...")
            onTriggered: root.openSelectedAffinityDialog()
        }
        Win7MenuSeparator { }
        Win7MenuItem {
            text: i18n("Properties")
            onTriggered: root.openPropertiesDialog()
        }
        Win7MenuItem {
            text: i18n("Go to Service(s)")
            enabled: false
        }
    }

    // 1. Windowed Win7 Task Manager "Do you want to end 'process'?" TaskDialog (matching crop_dlg_taskdialog.png)
    Window {
        id: killConfirmWindow
        property int targetPid: 0
        property string targetName: ""
        property int signalToSend: Process.Signal.TerminateSignal

        title: i18n("Windows Task Manager")
        modality: Qt.WindowModal
        flags: Qt.Dialog | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowCloseButtonHint
        width: 366
        height: 170
        minimumWidth: 366
        maximumWidth: 366
        minimumHeight: 170
        maximumHeight: 170
        visible: false
        color: "#f0f0f0"

        function openDialog() {
            killConfirmWindow.show()
            killConfirmWindow.raise()
            killConfirmWindow.requestActivate()
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#ffffff"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: i18n("Do you want to end '%1'?", killConfirmWindow.targetName)
                        font.family: "Segoe UI"
                        font.pixelSize: 15
                        font.hintingPreference: Font.PreferFullHinting
                        color: "#003399"
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }

                    Text {
                        Layout.fillWidth: true
                        text: i18n("If an open program is associated with this process, it will close and you will lose any unsaved data. If you end a system process, it might result in system instability. Are you sure you want to continue?")
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        font.hintingPreference: Font.PreferFullHinting
                        color: "#000000"
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: "#dfdfdf"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                color: "#f0f0f0"

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Win7Button {
                        width: 86
                        height: 23
                        mnemonicText: i18n("&End Process")
                        text: i18n("End Process")
                        isDefault: true
                        hasFocus: true
                        onClicked: {
                            if (killConfirmWindow.targetPid > 0) {
                                processHelper.sendSignal([killConfirmWindow.targetPid], killConfirmWindow.signalToSend)
                            }
                            killConfirmWindow.close()
                        }
                    }

                    Win7Button {
                        width: 75
                        height: 23
                        text: i18n("Cancel")
                        onClicked: killConfirmWindow.close()
                    }
                }
            }
        }
    }

    // 2. Windowed Win7 "Select Process Page Columns" Dialog
    Window {
        id: selectColumnsWindow
        title: i18n("Select Process Page Columns")
        modality: Qt.WindowModal
        flags: Qt.Dialog | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowCloseButtonHint
        width: 340
        height: 340
        minimumWidth: 340
        maximumWidth: 340
        minimumHeight: 340
        maximumHeight: 340
        visible: false
        color: "#f0f0f0"

        property var pendingAttrs: []

        function openDialog() {
            pendingAttrs = root.activeColumnAttrs.slice()
            selectColumnsWindow.show()
            selectColumnsWindow.raise()
            selectColumnsWindow.requestActivate()
        }

        function isAttrChecked(attrName) {
            return pendingAttrs.indexOf(attrName) !== -1
        }

        function toggleAttr(attrName) {
            var copy = pendingAttrs.slice()
            var idx = copy.indexOf(attrName)
            if (idx === -1) {
                copy.push(attrName)
            } else if (copy.length > 1) {
                copy.splice(idx, 1)
            }
            pendingAttrs = copy
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: i18n("Select the columns that will appear on the Process page of the Task Manager.")
                wrapMode: Text.WordWrap
                font.family: "Segoe UI"
                font.pixelSize: 12
                font.hintingPreference: Font.PreferFullHinting
                color: "#000000"
                renderType: Text.NativeRendering
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#ffffff"
                border.width: 1
                border.color: "#828790"
                clip: true

                Flickable {
                    id: columnsFlick
                    anchors.fill: parent
                    anchors.margins: 1
                    contentWidth: width
                    contentHeight: columnsList.implicitHeight + 16
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: Win7ScrollBar { id: columnsScroll; policy: ScrollBar.AsNeeded }

                    Column {
                        id: columnsList
                        x: 8
                        y: 8
                        width: columnsFlick.width - 16 - (columnsScroll.visible ? 17 : 0)
                        spacing: 4

                        Repeater {
                            model: root.allColumnCatalog

                            Item {
                                required property var modelData
                                width: parent.width
                                height: 18

                                readonly property bool checkedState: selectColumnsWindow.pendingAttrs.indexOf(modelData.attr) !== -1

                                Rectangle {
                                    x: 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 13
                                    height: 13
                                    border.width: 1
                                    border.color: colChkMouse.containsMouse ? "#3c7fb1" : "#8e8f8f"
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "#f4f4f4" }
                                        GradientStop { position: 1.0; color: "#dedede" }
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        color: modelData.locked ? "#ebebeb" : "#ffffff"
                                    }
                                    Canvas {
                                        id: chkMarkCanvas
                                        anchors.fill: parent
                                        visible: parent.parent.checkedState
                                        onVisibleChanged: if (visible) requestPaint()
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.clearRect(0, 0, width, height)
                                            ctx.strokeStyle = modelData.locked ? "#6d6d6d" : "#1c5180"
                                            ctx.lineWidth = 1.6
                                            ctx.beginPath()
                                            ctx.moveTo(2.5, 6.5)
                                            ctx.lineTo(5.2, 9.5)
                                            ctx.lineTo(10.5, 3.0)
                                            ctx.stroke()
                                        }
                                    }
                                }

                                Text {
                                    x: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.checkLabel
                                    font.family: "Segoe UI"
                                    font.pixelSize: 12
                                    font.hintingPreference: Font.PreferFullHinting
                                    color: modelData.locked ? "#6d6d6d" : "#000000"
                                    renderType: Text.NativeRendering
                                }

                                MouseArea {
                                    id: colChkMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !modelData.locked
                                    onClicked: selectColumnsWindow.toggleAttr(modelData.attr)
                                }
                            }
                        }
                    }
                }
            }

            Row {
                Layout.alignment: Qt.AlignRight
                spacing: 8

                Win7Button {
                    width: 75
                    height: 23
                    text: i18n("OK")
                    isDefault: true
                    hasFocus: true
                    onClicked: {
                        // Preserve catalog order
                        var ordered = []
                        for (var i = 0; i < root.allColumnCatalog.length; ++i) {
                            var a = root.allColumnCatalog[i].attr
                            if (selectColumnsWindow.pendingAttrs.indexOf(a) !== -1) {
                                ordered.push(a)
                            }
                        }
                        var sortedAttr = root.columnDefs[root.sortColumn].attr
                        root.activeColumnAttrs = ordered
                        root.sortColumn = Math.max(0, ordered.indexOf(sortedAttr))
                        root.syncColumnWidths()
                        root.applySort()
                        selectColumnsWindow.close()
                    }
                }

                Win7Button {
                    width: 75
                    height: 23
                    text: i18n("Cancel")
                    onClicked: selectColumnsWindow.close()
                }
            }
        }
    }

    // 3. Windowed Win7 "Processor Affinity" Dialog
    Window {
        id: affinityWindow
        title: i18n("Processor Affinity")
        modality: Qt.WindowModal
        flags: Qt.Dialog | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowCloseButtonHint
        width: 252
        height: 268
        minimumWidth: 252
        maximumWidth: 252
        minimumHeight: 268
        maximumHeight: 268
        visible: false
        color: "#f0f0f0"

        property int targetPid: 0
        property string targetName: ""
        property var currentAffinity: []
        property int cpuCount: 8

        function openDialog() {
            if (!currentAffinity || currentAffinity.length === 0) {
                var all = []
                for (var c = 0; c < cpuCount; ++c) all.push(c)
                currentAffinity = all
            } else {
                var maxCore = cpuCount - 1
                for (var i = 0; i < currentAffinity.length; ++i) {
                    if (Number(currentAffinity[i]) > maxCore) maxCore = Number(currentAffinity[i])
                }
                cpuCount = Math.max(cpuCount, maxCore + 1)
            }
            affinityWindow.show()
            affinityWindow.raise()
            affinityWindow.requestActivate()
        }

        readonly property bool allChecked: currentAffinity.length >= cpuCount

        function toggleCpu(cpuIdx) {
            var copy = currentAffinity.slice()
            var pos = copy.indexOf(cpuIdx)
            if (pos === -1) {
                copy.push(cpuIdx)
                copy.sort(function(a, b) { return a - b })
            } else if (copy.length > 1) {
                copy.splice(pos, 1)
            }
            currentAffinity = copy
        }

        function toggleAll() {
            if (allChecked) {
                currentAffinity = [0]
            } else {
                var all = []
                for (var c = 0; c < cpuCount; ++c) all.push(c)
                currentAffinity = all
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: i18n("Which processors are allowed to run \"%1\"?", affinityWindow.targetName)
                wrapMode: Text.WordWrap
                font.family: "Segoe UI"
                font.pixelSize: 12
                font.hintingPreference: Font.PreferFullHinting
                color: "#000000"
                renderType: Text.NativeRendering
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#ffffff"
                border.width: 1
                border.color: "#828790"
                clip: true

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 6
                    contentHeight: affCol.implicitHeight
                    clip: true

                    Column {
                        id: affCol
                        width: parent.width
                        spacing: 4

                        // <All Processors> row
                        Item {
                            width: parent.width
                            height: 18

                            Rectangle {
                                x: 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: 13
                                height: 13
                                border.width: 1
                                border.color: "#8e8f8f"
                                color: "#ffffff"
                                Canvas {
                                    anchors.fill: parent
                                    visible: affinityWindow.allChecked
                                    onVisibleChanged: if (visible) requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        ctx.strokeStyle = "#1c5180"
                                        ctx.lineWidth = 1.6
                                        ctx.beginPath()
                                        ctx.moveTo(2.5, 6.5)
                                        ctx.lineTo(5.2, 9.5)
                                        ctx.lineTo(10.5, 3.0)
                                        ctx.stroke()
                                    }
                                }
                            }

                            Text {
                                x: 20
                                anchors.verticalCenter: parent.verticalCenter
                                text: i18n("<All Processors>")
                                font.family: "Segoe UI"
                                font.pixelSize: 12
                                font.hintingPreference: Font.PreferFullHinting
                                color: "#000000"
                                renderType: Text.NativeRendering
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: affinityWindow.toggleAll()
                            }
                        }

                        Repeater {
                            model: affinityWindow.cpuCount
                            Item {
                                required property int index
                                width: affCol.width
                                height: 18

                                readonly property bool cpuChecked: affinityWindow.currentAffinity.indexOf(index) !== -1

                                Rectangle {
                                    x: 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 13
                                    height: 13
                                    border.width: 1
                                    border.color: "#8e8f8f"
                                    color: "#ffffff"
                                    Canvas {
                                        anchors.fill: parent
                                        visible: parent.parent.cpuChecked
                                        onVisibleChanged: if (visible) requestPaint()
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.clearRect(0, 0, width, height)
                                            ctx.strokeStyle = "#1c5180"
                                            ctx.lineWidth = 1.6
                                            ctx.beginPath()
                                            ctx.moveTo(2.5, 6.5)
                                            ctx.lineTo(5.2, 9.5)
                                            ctx.lineTo(10.5, 3.0)
                                            ctx.stroke()
                                        }
                                    }
                                }

                                Text {
                                    x: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: i18n("CPU %1", index)
                                    font.family: "Segoe UI"
                                    font.pixelSize: 12
                                    font.hintingPreference: Font.PreferFullHinting
                                    color: "#000000"
                                    renderType: Text.NativeRendering
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: affinityWindow.toggleCpu(index)
                                }
                            }
                        }
                    }
                }
            }

            Row {
                Layout.alignment: Qt.AlignRight
                spacing: 8

                Win7Button {
                    width: 75
                    height: 23
                    text: i18n("OK")
                    isDefault: true
                    hasFocus: true
                    enabled: affinityWindow.currentAffinity.length > 0
                    onClicked: {
                        if (affinityWindow.targetPid > 0) {
                            processHelper.setAffinity([affinityWindow.targetPid], affinityWindow.currentAffinity)
                        }
                        affinityWindow.close()
                    }
                }

                Win7Button {
                    width: 75
                    height: 23
                    text: i18n("Cancel")
                    onClicked: affinityWindow.close()
                }
            }
        }
    }

    // 4. Windowed Win7 "Set Priority / Scheduler" Dialog
    Window {
        id: reniceWindow
        title: i18n("Windows Task Manager")
        modality: Qt.WindowModal
        flags: Qt.Dialog | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowCloseButtonHint
        width: 356
        height: 256
        minimumWidth: 356
        maximumWidth: 356
        minimumHeight: 256
        maximumHeight: 256
        visible: false
        color: "#f0f0f0"

        property int targetPid: 0
        property string targetName: ""
        property int niceValue: 0
        property int cpuMode: 0
        property int ioMode: 0

        function openDialog() {
            reniceWindow.show()
            reniceWindow.raise()
            reniceWindow.requestActivate()
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#ffffff"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: i18n("Do you want to change the priority class of '%1'?", reniceWindow.targetName)
                        font.family: "Segoe UI"
                        font.pixelSize: 15
                        font.hintingPreference: Font.PreferFullHinting
                        color: "#003399"
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }

                    Text {
                        Layout.fillWidth: true
                        text: i18n("Changing the priority class of certain processes could cause system instability.")
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        font.hintingPreference: Font.PreferFullHinting
                        color: "#000000"
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }

                    Win7GroupBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 92
                        title: i18n("Priority Class & Nice Level (%1)", reniceWindow.niceValue)

                        GridLayout {
                            anchors.fill: parent
                            columns: 3
                            rowSpacing: 4
                            columnSpacing: 6

                            Repeater {
                                model: [
                                    { label: i18n("Realtime (-20)"), val: -20 },
                                    { label: i18n("High (-10)"), val: -10 },
                                    { label: i18n("Above Normal (-5)"), val: -5 },
                                    { label: i18n("Normal (0)"), val: 0 },
                                    { label: i18n("Below Normal (5)"), val: 5 },
                                    { label: i18n("Low (19)"), val: 19 }
                                ]

                                Win7Button {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    height: 23
                                    text: modelData.label
                                    isDefault: reniceWindow.niceValue === modelData.val
                                    onClicked: reniceWindow.niceValue = modelData.val
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: "#dfdfdf"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                color: "#f0f0f0"

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Win7Button {
                        width: 98
                        height: 23
                        mnemonicText: i18n("&Change Priority")
                        text: i18n("Change Priority")
                        isDefault: true
                        hasFocus: true
                        onClicked: {
                            if (reniceWindow.targetPid > 0) {
                                processHelper.setPriority([reniceWindow.targetPid], reniceWindow.niceValue)
                            }
                            reniceWindow.close()
                        }
                    }

                    Win7Button {
                        width: 75
                        height: 23
                        text: i18n("Cancel")
                        onClicked: reniceWindow.close()
                    }
                }
            }
        }
    }

    // 5. Windowed Win7 "<processName> Properties" Dialog (General & Details tabs)
    Window {
        id: propertiesWindow
        property int propTabIndex: 0
        readonly property string procName: String(root.rowAttributeValue(root.selectedRow, "name", root.modelRevision) || "Process")
        readonly property string procPid: String(root.rowAttributeValue(root.selectedRow, "pid", root.modelRevision) || "0")
        readonly property string procUser: String(root.rowAttributeValue(root.selectedRow, "username", root.modelRevision) || "")
        readonly property string procUid: String(root.rowAttributeValue(root.selectedRow, "uid", root.modelRevision) || "0")
        readonly property string procCpu: root.formatCellText(root.selectedRow, "usage", root.modelRevision)
        readonly property string procMem: root.formatCellText(root.selectedRow, "memory", root.modelRevision)
        readonly property string procCmd: root.formatCellText(root.selectedRow, "command", root.modelRevision)

        title: i18n("%1 Properties", procName)
        modality: Qt.WindowModal
        flags: Qt.Dialog | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowCloseButtonHint
        width: 365
        height: 410
        minimumWidth: 365
        maximumWidth: 365
        minimumHeight: 410
        maximumHeight: 410
        visible: false
        color: "#f0f0f0"

        function openDialog() {
            propTabIndex = 0
            propertiesWindow.show()
            propertiesWindow.raise()
            propertiesWindow.requestActivate()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 11
            spacing: 0

            // Classic Win32 Tab Strip ("General" | "Details")
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 21
                z: 2

                Row {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 0

                    Repeater {
                        model: [i18n("General"), i18n("Details")]

                        Rectangle {
                            required property int index
                            required property string modelData
                            readonly property bool isTabActive: propertiesWindow.propTabIndex === index
                            width: 66
                            height: isTabActive ? 21 : 19
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: isTabActive ? -1 : 0
                            color: isTabActive ? "#ffffff" : "#f0f0f0"
                            border.width: 1
                            border.color: "#898c95"

                            Rectangle {
                                visible: parent.isTabActive
                                anchors.left: parent.left
                                anchors.leftMargin: 1
                                anchors.right: parent.right
                                anchors.rightMargin: 1
                                anchors.bottom: parent.bottom
                                height: 2
                                color: "#ffffff"
                            }

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                font.family: "Segoe UI"
                                font.pixelSize: 12
                                font.hintingPreference: Font.PreferFullHinting
                                color: "#000000"
                                renderType: Text.NativeRendering
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: propertiesWindow.propTabIndex = parent.index
                            }
                        }
                    }
                }
            }

            // Tab sheet body (#ffffff with 1px #898c95 border)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#ffffff"
                border.width: 1
                border.color: "#898c95"
                z: 1

                // General Tab
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10
                    visible: propertiesWindow.propTabIndex === 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // 32x32 Win7 executable window icon
                        Canvas {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.fillStyle = "#3b77bc"
                                ctx.fillRect(3, 5, 26, 22)
                                ctx.fillStyle = "#96c7f2"
                                ctx.fillRect(4, 6, 24, 4)
                                ctx.fillStyle = "#ffffff"
                                ctx.fillRect(4, 11, 24, 15)
                                ctx.fillStyle = "#d4d9df"
                                ctx.fillRect(7, 14, 18, 9)
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 23
                            color: "#ffffff"
                            border.width: 1
                            border.color: "#abadb3"
                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                verticalAlignment: Text.AlignVCenter
                                text: propertiesWindow.procName
                                font.family: "Segoe UI"
                                font.pixelSize: 12
                                font.hintingPreference: Font.PreferFullHinting
                                color: "#000000"
                                elide: Text.ElideRight
                                renderType: Text.NativeRendering
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#d5dfe5" }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 14
                        rowSpacing: 7

                        Text { text: i18n("Type of file:"); font.family: "Segoe UI"; font.pixelSize: 12; font.hintingPreference: Font.PreferFullHinting; color: "#000000" }
                        Text { text: i18n("Application / Process (PID %1)", propertiesWindow.procPid); font.family: "Segoe UI"; font.pixelSize: 12; font.hintingPreference: Font.PreferFullHinting; color: "#000000"; Layout.fillWidth: true; elide: Text.ElideRight }

                        Text { text: i18n("Description:"); font.family: "Segoe UI"; font.pixelSize: 12; font.hintingPreference: Font.PreferFullHinting; color: "#000000" }
                        Text { text: propertiesWindow.procName; font.family: "Segoe UI"; font.pixelSize: 12; font.hintingPreference: Font.PreferFullHinting; color: "#000000"; Layout.fillWidth: true; elide: Text.ElideRight }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#d5dfe5" }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 14
                        rowSpacing: 7

                        Text { text: i18n("Location:"); font.family: "Segoe UI"; font.pixelSize: 12; font.hintingPreference: Font.PreferFullHinting; color: "#000000" }
                        Text { text: propertiesWindow.procCmd; font.family: "Segoe UI"; font.pixelSize: 12; font.hintingPreference: Font.PreferFullHinting; color: "#000000"; Layout.fillWidth: true; elide: Text.ElideMiddle }

                        Text { text: i18n("Working Set:"); font.family: "Segoe UI"; font.pixelSize: 12; font.hintingPreference: Font.PreferFullHinting; color: "#000000" }
                        Text { text: propertiesWindow.procMem; font.family: "Segoe UI"; font.pixelSize: 12; font.hintingPreference: Font.PreferFullHinting; color: "#000000"; Layout.fillWidth: true }

                        Text { text: i18n("CPU Usage:"); font.family: "Segoe UI"; font.pixelSize: 12; font.hintingPreference: Font.PreferFullHinting; color: "#000000" }
                        Text { text: propertiesWindow.procCpu; font.family: "Segoe UI"; font.pixelSize: 12; font.hintingPreference: Font.PreferFullHinting; color: "#000000"; Layout.fillWidth: true }

                        Text { text: i18n("User Name:"); font.family: "Segoe UI"; font.pixelSize: 12; font.hintingPreference: Font.PreferFullHinting; color: "#000000" }
                        Text { text: propertiesWindow.procUser + " (UID " + propertiesWindow.procUid + ")"; font.family: "Segoe UI"; font.pixelSize: 12; font.hintingPreference: Font.PreferFullHinting; color: "#000000"; Layout.fillWidth: true }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#d5dfe5" }

                    Item { Layout.fillHeight: true }
                }

                // Details Tab
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6
                    visible: propertiesWindow.propTabIndex === 1

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#ffffff"
                        border.width: 1
                        border.color: "#828790"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 1

                            Rectangle {
                                width: parent.width
                                height: 22
                                color: "#f1f2f4"
                                Row {
                                    anchors.fill: parent
                                    Text { width: 130; height: 22; leftPadding: 6; verticalAlignment: Text.AlignVCenter; text: i18n("Property"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                                    Rectangle { width: 1; height: 22; color: "#d5d5d5" }
                                    Text { width: 180; height: 22; leftPadding: 6; verticalAlignment: Text.AlignVCenter; text: i18n("Value"); font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000" }
                                }
                            }

                            Repeater {
                                model: [
                                    { k: i18n("Image Name"), v: propertiesWindow.procName },
                                    { k: i18n("Process ID (PID)"), v: propertiesWindow.procPid },
                                    { k: i18n("User Name"), v: propertiesWindow.procUser },
                                    { k: i18n("User ID (UID)"), v: propertiesWindow.procUid },
                                    { k: i18n("CPU Usage"), v: propertiesWindow.procCpu },
                                    { k: i18n("Memory (Working Set)"), v: propertiesWindow.procMem },
                                    { k: i18n("Command Line"), v: propertiesWindow.procCmd }
                                ]
                                Row {
                                    required property var modelData
                                    width: parent.width
                                    height: 19
                                    Text { width: 130; height: 19; leftPadding: 6; verticalAlignment: Text.AlignVCenter; text: modelData.k; font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; elide: Text.ElideRight }
                                    Text { width: 185; height: 19; leftPadding: 6; verticalAlignment: Text.AlignVCenter; text: modelData.v; font.family: "Segoe UI"; font.pixelSize: 12; color: "#000000"; elide: Text.ElideRight }
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 10 }

            Row {
                Layout.alignment: Qt.AlignRight
                spacing: 8

                Win7Button {
                    width: 75
                    height: 23
                    text: i18n("OK")
                    isDefault: true
                    hasFocus: true
                    onClicked: propertiesWindow.close()
                }

                Win7Button {
                    width: 75
                    height: 23
                    text: i18n("Cancel")
                    onClicked: propertiesWindow.close()
                }

                Win7Button {
                    width: 75
                    height: 23
                    mnemonicText: i18n("&Apply")
                    text: i18n("Apply")
                    enabled: false
                }
            }
        }
    }
}
