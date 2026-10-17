/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.ksysguard.process as Process
import org.kde.ksysguard.table as Table

Item {
    id: root

    // 0 = Details, 1 = Large Icons, 2 = Small Icons
    property int viewStyle: 0
    property int selectedRow: 0
    property int sortColumn: 0
    property int sortOrder: Qt.AscendingOrder
    property real taskColWidth: 255
    property real statusColWidth: 92
    property int modelRevision: 0

    signal newTaskRequested()
    signal switchToRequested(int pid, string name)
    signal goToProcessRequested(int pid, string name)

    function applyTaskSort() {
        appSortModel.sort(0, root.sortOrder)
        fallbackFilterModel.sort(0, root.sortOrder)
        root.modelRevision++
    }

    function refreshNow() {
        fallbackFilterModel.invalidate()
        appSortModel.invalidate()
        root.applyTaskSort()
    }

    function endSelectedTask() {
        var pids = currentSelectedPids()
        if (pids.length > 0) {
            killConfirmDialog.targetPids = pids
            killConfirmDialog.targetName = currentSelectedName()
            killConfirmDialog.openDialog()
        }
    }

    function switchToSelectedTask() {
        var pids = currentSelectedPids()
        if (pids.length > 0) {
            root.switchToRequested(pids[0], currentSelectedName())
        }
    }

    function currentSelectedPids() {
        var pid = fallbackFilterModel.attributeValue(root.selectedRow, "pid")
        if (!useAppModel) {
            return pid ? [Number(pid)] : []
        }
        if (root.selectedRow < 0 || root.selectedRow >= appSortModel.rowCount() || appSortModel.columnCount() <= 0) return []
        var idx = appSortModel.index(root.selectedRow, 0)
        if (!idx.valid) return []
        var srcIdx = appSortModel.mapToSource(idx)
        if (!srcIdx.valid) return []
        return appModel.data(srcIdx, Process.ProcessDataModel.PIDs) || []
    }

    function currentSelectedName() {
        if (useAppModel) {
            if (root.selectedRow < 0 || root.selectedRow >= appSortModel.rowCount() || appSortModel.columnCount() <= 0) return ""
            var idx = appSortModel.index(root.selectedRow, 0)
            if (!idx.valid) return ""
            return String(appSortModel.data(idx, Process.ProcessDataModel.Value) || "")
        } else {
            return String(fallbackFilterModel.attributeValue(root.selectedRow, "name") || "")
        }
    }

    // Primary backend: ApplicationDataModel
    Process.ApplicationDataModel {
        id: appModel
        enabled: root.visible
        enabledAttributes: ["appName", "iconName", "menuId"]
    }

    KItemModels.KSortFilterProxyModel {
        id: appSortModel
        sourceModel: appModel
        sortRole: Process.ProcessDataModel.Value
        sortCaseSensitivity: Qt.CaseInsensitive
        sortColumn: 0
        sortOrder: root.sortOrder
        filterRowCallback: function(row, parent) {
            if (appModel.columnCount(parent) <= 0) return false
            var idx = appModel.index(row, 0, parent)
            if (!idx.valid) return false
            var appName = String(appModel.data(idx, Process.ProcessDataModel.Value) || "").trim()
            if (appName.length === 0) return false
            if (appModel.columnCount(parent) > 2) {
                var menuIdx = appModel.index(row, 2, parent)
                var menuId = menuIdx.valid ? String(appModel.data(menuIdx, Process.ProcessDataModel.Value) || "") : ""
                if (menuId === "session.slice" || menuId === "background.slice" || menuId === "services") return false
            }
            return true
        }
    }

    Timer {
        id: appFilterTimer
        interval: 600
        repeat: false
        onTriggered: {
            appSortModel.invalidateFilter()
            root.appModelRowCount = appSortModel.rowCount()
            root.applyTaskSort()
        }
    }

    property int appModelRowCount: 0
    Connections {
        target: appSortModel
        function onRowsInserted() {
            root.appModelRowCount = appSortModel.rowCount()
            root.modelRevision++
            appFilterTimer.restart()
        }
        function onRowsRemoved() {
            root.appModelRowCount = appSortModel.rowCount()
            root.modelRevision++
        }
        function onModelReset() {
            root.appModelRowCount = appSortModel.rowCount()
            root.modelRevision++
            appFilterTimer.restart()
        }
        function onLayoutChanged() {
            root.appModelRowCount = appSortModel.rowCount()
            root.modelRevision++
        }
        function onDataChanged() {
            if (root.appModelRowCount !== appSortModel.rowCount()) {
                root.appModelRowCount = appSortModel.rowCount()
            }
            root.modelRevision++
        }
    }

    // Fallback backend when systemd application cgroups are not active: user processes from ProcessDataModel
    Process.ProcessDataModel {
        id: fallbackProcessModel
        enabled: root.visible && !root.useAppModel
        flatList: true
        enabledAttributes: ["name", "pid", "command", "username", "usage", "memory", "uid"]
    }

    Table.ProcessSortFilterModel {
        id: fallbackFilterModel
        sourceModel: fallbackProcessModel
        viewMode: Table.ProcessSortFilterModel.ViewOwn
        hiddenAttributes: ["uid"]
    }

    Connections {
        target: fallbackFilterModel
        property bool initialSorted: false
        function onColumnMappingChanged() {
            if (fallbackFilterModel.columnCount() > 0) {
                fallbackFilterModel.sort(0, root.sortOrder)
                root.modelRevision++
            }
        }
        function onRowsInserted() {
            root.modelRevision++
            if (!initialSorted && fallbackFilterModel.rowCount() > 0 && fallbackFilterModel.columnCount() > 0) {
                initialSorted = true
                fallbackFilterModel.sort(0, root.sortOrder)
            }
        }
        function onRowsRemoved() { root.modelRevision++ }
        function onLayoutChanged() { root.modelRevision++ }
        function onSorted() { root.modelRevision++ }
    }

    readonly property bool useAppModel: appModel.available && root.appModelRowCount > 0
    readonly property int taskCount: taskListView.count

    Process.ProcessController {
        id: processHelper
        window: root.Window.window
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 17
        anchors.rightMargin: 14
        anchors.topMargin: 17
        anchors.bottomMargin: 15
        spacing: 8

        // Classic Win7 ListView container (#828790 border)
        Rectangle {
            id: listContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#ffffff"
            border.width: 1
            border.color: "#828790"
            clip: true

            // Right-click in empty area -> "New Task (Run...)" just like Win7 Task Manager
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: mouse => {
                    listContainer.forceActiveFocus()
                    if (mouse.button === Qt.RightButton) {
                        emptyAreaMenu.popup()
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                // Classic Win7 25px Column Header Bar (Task | Status)
                Rectangle {
                    id: headerBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 25
                    visible: root.viewStyle === 0
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#ffffff" }
                        GradientStop { position: 0.42; color: "#f7f8fa" }
                        GradientStop { position: 0.92; color: "#f1f2f4" }
                        GradientStop { position: 0.96; color: "#d5d5d5" }
                        GradientStop { position: 1.0; color: "#fbfbfb" }
                    }

                    Row {
                        anchors.fill: parent

                        // Column 0: Task
                        Item {
                            id: taskColHeader
                            width: root.taskColWidth
                            height: parent.height

                            Rectangle {
                                anchors.fill: parent
                                visible: root.sortColumn === 0
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#ffffff" }
                                    GradientStop { position: 0.08; color: "#f2f9fc" }
                                    GradientStop { position: 0.45; color: "#e1f1f9" }
                                    GradientStop { position: 0.92; color: "#d8ecf6" }
                                    GradientStop { position: 0.96; color: "#96d9f9" }
                                    GradientStop { position: 1.0; color: "#ffffff" }
                                }
                            }

                            // Sort arrow at top center of sorted column
                            Canvas {
                                id: taskSortArrow
                                width: 7
                                height: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 3
                                visible: root.sortColumn === 0
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
                                Connections {
                                    target: root
                                    function onSortOrderChanged() { taskSortArrow.requestPaint() }
                                    function onSortColumnChanged() { taskSortArrow.requestPaint() }
                                }
                            }

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                anchors.rightMargin: 6
                                verticalAlignment: Text.AlignVCenter
                                text: i18n("Task")
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
                                color: root.sortColumn === 0 ? "#96d9f9" : "#d5d5d5"
                            }

                            MouseArea {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.right: taskColResizer.left
                                onClicked: {
                                    if (root.sortColumn === 0) {
                                        root.sortOrder = root.sortOrder === Qt.AscendingOrder ? Qt.DescendingOrder : Qt.AscendingOrder
                                    } else {
                                        root.sortColumn = 0
                                        root.sortOrder = Qt.AscendingOrder
                                    }
                                    root.applyTaskSort()
                                }
                            }

                            MouseArea {
                                id: taskColResizer
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 6
                                cursorShape: Qt.SplitHCursor
                                preventStealing: true
                                property real startX: 0
                                property real startW: 0
                                onPressed: mouse => {
                                    startX = mapToItem(headerBar, mouse.x, 0).x
                                    startW = root.taskColWidth
                                }
                                onPositionChanged: mouse => {
                                    if (pressed) {
                                        var curX = mapToItem(headerBar, mouse.x, 0).x
                                        root.taskColWidth = Math.max(80, Math.min(headerBar.width - 60, Math.round(startW + (curX - startX))))
                                    }
                                }
                            }
                        }

                        // Column 1: Status
                        Item {
                            id: statusColHeader
                            width: root.statusColWidth
                            height: parent.height

                            Rectangle {
                                anchors.fill: parent
                                visible: root.sortColumn === 1
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
                                id: statusSortArrow
                                width: 7
                                height: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 3
                                visible: root.sortColumn === 1
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
                                Connections {
                                    target: root
                                    function onSortOrderChanged() { statusSortArrow.requestPaint() }
                                    function onSortColumnChanged() { statusSortArrow.requestPaint() }
                                }
                            }

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                anchors.rightMargin: 6
                                verticalAlignment: Text.AlignVCenter
                                text: i18n("Status")
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
                                color: root.sortColumn === 1 ? "#96d9f9" : "#e5e5e5"
                            }

                            MouseArea {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.right: statusColResizer.left
                                onClicked: {
                                    if (root.sortColumn === 1) {
                                        root.sortOrder = root.sortOrder === Qt.AscendingOrder ? Qt.DescendingOrder : Qt.AscendingOrder
                                    } else {
                                        root.sortColumn = 1
                                        root.sortOrder = Qt.AscendingOrder
                                    }
                                    root.applyTaskSort()
                                }
                            }

                            MouseArea {
                                id: statusColResizer
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 6
                                cursorShape: Qt.SplitHCursor
                                preventStealing: true
                                property real startX: 0
                                property real startW: 0
                                onPressed: mouse => {
                                    startX = mapToItem(headerBar, mouse.x, 0).x
                                    startW = root.statusColWidth
                                }
                                onPositionChanged: mouse => {
                                    if (pressed) {
                                        var curX = mapToItem(headerBar, mouse.x, 0).x
                                        root.statusColWidth = Math.max(48, Math.round(startW + (curX - startX)))
                                    }
                                }
                            }
                        }
                    }
                }

                // Task ListView
                ListView {
                    id: taskListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.vertical: Win7ScrollBar {
                        policy: ScrollBar.AsNeeded
                        stepSize: 18 / Math.max(18, taskListView.contentHeight)
                    }
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.useAppModel ? appSortModel : fallbackFilterModel

                    // Subtle vertical column grid line matching Win7 Applications tab (#ebf4fe)
                    Rectangle {
                        visible: root.viewStyle === 0
                        x: taskColHeader.width - 1
                        y: 0
                        width: 1
                        height: parent.height
                        color: "#ebf4fe"
                        z: 0
                    }
                    Rectangle {
                        visible: root.viewStyle === 0
                        x: taskColHeader.width + statusColHeader.width - 1
                        y: 0
                        width: 1
                        height: parent.height
                        color: "#ebf4fe"
                        z: 0
                    }

                    delegate: Item {
                        id: rowDelegate
                        required property int index
                        required property var model

                        width: taskListView.width
                        height: taskTitle.length > 0 ? (root.viewStyle === 1 ? 26 : 18) : 0
                        visible: taskTitle.length > 0

                        readonly property bool isSelected: root.selectedRow === index
                        property bool isHovered: false

                        readonly property string taskTitle: {
                            var _rev = root.modelRevision
                            if (root.useAppModel) {
                                if (appSortModel.columnCount() <= 0 || index < 0 || index >= appSortModel.rowCount()) return ""
                                var idx = appSortModel.index(index, 0)
                                return idx.valid ? String(appSortModel.data(idx, Process.ProcessDataModel.Value) || "") : ""
                            } else {
                                return String(fallbackFilterModel.attributeValue(index, "name") || "")
                            }
                        }

                        readonly property string taskIcon: {
                            var _rev = root.modelRevision
                            if (root.useAppModel) {
                                if (appSortModel.columnCount() <= 0 || appModel.columnCount() <= 1 || index < 0 || index >= appSortModel.rowCount()) return "application-x-executable"
                                var idx = appSortModel.index(index, 0)
                                if (!idx.valid) return "application-x-executable"
                                var sIdx = appSortModel.mapToSource(idx)
                                if (!sIdx.valid) return "application-x-executable"
                                var iconIdx = appModel.index(sIdx.row, 1)
                                return iconIdx.valid ? String(appModel.data(iconIdx, Process.ProcessDataModel.Value) || "application-x-executable") : "application-x-executable"
                            } else {
                                return taskTitle.split(" ")[0].toLowerCase()
                            }
                        }

                        // Win7 row selection / hover pill
                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 1
                            anchors.rightMargin: 2
                            radius: 2
                            visible: rowDelegate.isSelected || rowDelegate.isHovered
                            border.width: 1
                            border.color: rowDelegate.isSelected ? "#7da2ce" : "#b8d6fb"
                            gradient: Gradient {
                                GradientStop {
                                    position: 0.0
                                    color: rowDelegate.isSelected ? "#dcebfc" : "#f2f7fe"
                                }
                                GradientStop {
                                    position: 1.0
                                    color: rowDelegate.isSelected ? "#c1dbfc" : "#e5f0fe"
                                }
                            }
                        }

                        Row {
                            anchors.fill: parent

                            // Task column: Icon + Name
                            Item {
                                width: root.viewStyle === 0 ? taskColHeader.width : parent.width
                                height: parent.height

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 3
                                    anchors.rightMargin: 4
                                    spacing: 4

                                    Item {
                                        Layout.preferredWidth: root.viewStyle === 1 ? 20 : 16
                                        Layout.preferredHeight: root.viewStyle === 1 ? 20 : 16
                                        Layout.alignment: Qt.AlignVCenter

                                        // Classic Win7 16x16 executable window icon under theme icon
                                        Canvas {
                                            anchors.fill: parent
                                            visible: true
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                ctx.fillStyle = "#2b579a"
                                                ctx.fillRect(1, 2, width - 2, height - 3)
                                                ctx.fillStyle = "#6cb4f4"
                                                ctx.fillRect(2, 3, width - 4, 3)
                                                ctx.fillStyle = "#ffffff"
                                                ctx.fillRect(2, 6, width - 4, height - 8)
                                                ctx.fillStyle = "#d4e7f7"
                                                ctx.fillRect(3, 7, width - 6, height - 10)
                                            }
                                        }

                                        Kirigami.Icon {
                                            id: taskIconItem
                                            anchors.fill: parent
                                            source: rowDelegate.taskIcon
                                            fallback: "application-x-executable"
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: rowDelegate.taskTitle
                                        elide: Text.ElideRight
                                        font.family: "Segoe UI"
                                        font.pixelSize: 12
                                        color: "#000000"
                                    }
                                }
                            }

                            // Status column: "Running"
                            Item {
                                visible: root.viewStyle === 0
                                width: statusColHeader.width
                                height: parent.height

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 7
                                    anchors.rightMargin: 4
                                    verticalAlignment: Text.AlignVCenter
                                    text: i18n("Running")
                                    elide: Text.ElideRight
                                    font.family: "Segoe UI"
                                    font.pixelSize: 12
                                    color: "#000000"
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onEntered: rowDelegate.isHovered = true
                            onExited: rowDelegate.isHovered = false
                            onPressed: mouse => {
                                root.selectedRow = rowDelegate.index
                                if (mouse.button === Qt.RightButton) {
                                    taskContextMenu.popup()
                                }
                            }
                            onDoubleClicked: root.switchToSelectedTask()
                        }
                    }
                }
            }
        }

        // Bottom-right Win7 buttons: End Task | Switch To | New Task...
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Item { Layout.fillWidth: true }

            Win7Button {
                Layout.preferredWidth: 75
                Layout.preferredHeight: 23
                mnemonicText: i18n("&End Task")
                text: i18n("End Task")
                enabled: root.taskCount > 0 && root.selectedRow >= 0
                onClicked: root.endSelectedTask()
            }

            Win7Button {
                Layout.preferredWidth: 75
                Layout.preferredHeight: 23
                mnemonicText: i18n("&Switch To")
                text: i18n("Switch To")
                isDefault: true
                enabled: root.taskCount > 0 && root.selectedRow >= 0
                onClicked: root.switchToSelectedTask()
            }

            Win7Button {
                Layout.preferredWidth: 75
                Layout.preferredHeight: 23
                mnemonicText: i18n("&New Task...")
                text: i18n("New Task...")
                onClicked: root.newTaskRequested()
            }
        }
    }

    // Empty-area right-click menu matching Win7 VM screenshot (crop_ctx_app.png)
    Win7Menu {
        id: emptyAreaMenu
        Win7MenuItem {
            text: i18n("New Task (Run...)")
            onTriggered: root.newTaskRequested()
        }
    }

    // Task item right-click context menu matching Win7 Task Manager
    Win7Menu {
        id: taskContextMenu

        Win7MenuItem {
            text: i18n("Switch To")
            font.bold: true
            onTriggered: root.switchToSelectedTask()
        }
        Win7MenuItem {
            text: i18n("Bring To Front")
            onTriggered: root.switchToSelectedTask()
        }
        Win7MenuSeparator { }
        Win7MenuItem {
            text: i18n("Minimize")
            onTriggered: root.switchToSelectedTask()
        }
        Win7MenuItem {
            text: i18n("Maximize")
            onTriggered: root.switchToSelectedTask()
        }
        Win7MenuItem {
            text: i18n("Tile Horizontally")
            enabled: false
        }
        Win7MenuItem {
            text: i18n("Tile Vertically")
            enabled: false
        }
        Win7MenuItem {
            text: i18n("Cascade")
            enabled: false
        }
        Win7MenuSeparator { }
        Win7MenuItem {
            text: i18n("End Task")
            onTriggered: root.endSelectedTask()
        }
        Win7MenuItem {
            text: i18n("Go To Process")
            onTriggered: {
                var pids = root.currentSelectedPids()
                if (pids.length > 0) {
                    root.goToProcessRequested(pids[0], root.currentSelectedName())
                }
            }
        }
    }

    // Win7 Task Manager End Task / End Process confirmation dialog (Windowed TaskDialog)
    Window {
        id: killConfirmDialog
        property var targetPids: []
        property string targetName: ""

        title: i18n("Windows Task Manager")
        modality: Qt.WindowModal
        transientParent: root.Window.window
        flags: Qt.Dialog | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint
        width: 366
        height: 158
        minimumWidth: 366
        maximumWidth: 366
        minimumHeight: 158
        maximumHeight: 158
        color: "#f0f0f0"
        visible: false

        function openDialog() {
            if (transientParent) {
                x = transientParent.x + Math.round((transientParent.width - width) / 2)
                y = transientParent.y + Math.round((transientParent.height - height) / 2)
            }
            show()
            raise()
            requestActivate()
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
                    anchors.margins: 11
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: i18n("Do you want to end '%1'?", killConfirmDialog.targetName)
                        font.family: "Segoe UI"
                        font.pixelSize: 16
                        color: "#003399"
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: i18n("If an open program is associated with this process, it will close and you will lose any unsaved data. If you end a system process, it might result in system instability. Are you sure you want to continue?")
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        color: "#000000"
                        wrapMode: Text.WordWrap
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

                RowLayout {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Win7Button {
                        Layout.preferredWidth: 78
                        Layout.preferredHeight: 23
                        mnemonicText: i18n("&End Process")
                        text: i18n("End Process")
                        isDefault: true
                        onClicked: {
                            if (killConfirmDialog.targetPids.length > 0) {
                                processHelper.sendSignal(killConfirmDialog.targetPids, Process.Signal.TerminateSignal)
                            }
                            killConfirmDialog.close()
                        }
                    }

                    Win7Button {
                        Layout.preferredWidth: 68
                        Layout.preferredHeight: 23
                        text: i18n("Cancel")
                        onClicked: killConfirmDialog.close()
                    }
                }
            }
        }
    }
}
