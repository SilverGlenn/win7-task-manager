/*
 * SPDX-FileCopyrightText: 2019 Arjen Hiemstra <ahiemstra@heimr.nl>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtCore
import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import org.kde.kirigami as Kirigami
import org.kde.config as KConfig
import org.kde.coreaddons as KCoreAddons

import org.kde.systemmonitor
import org.kde.ksysguard.page as Page

ApplicationWindow {
    id: app

    // Default dimensions matching Windows 7 Task Manager client area in VM (397x421)
    width: 397
    height: 421
    minimumWidth: 380
    minimumHeight: 395
    visible: true

    title: i18n("Windows Task Manager")
    color: "#f0f0f0"

    property bool alwaysOnTop: false
    property bool minimizeOnUse: true
    property bool hideWhenMinimized: false
    property bool showKernelTimes: false
    property bool perCpuHistory: false
    // Windows 7 update speeds: High 0.5s, Normal 2s, Low 4s, Paused 0.
    property int updateInterval: 2000
    property string currentTabId: "applications"
    property string debugOpenMenu: ""
    readonly property var debugCaptureWindow: debugOpenMenu === "dlg_newtask" ? newTaskDialog
        : debugOpenMenu === "dlg_about" ? aboutDialog : processesTab.debugCaptureWindow
    onDebugOpenMenuChanged: menuBarRow.openMenuById(debugOpenMenu)

    flags: alwaysOnTop ? (Qt.Window | Qt.WindowStaysOnTopHint) : Qt.Window

    // Status bar live sensors
    Win7Sensor { updateController: refreshClock; id: statusCpuSensor; sensorId: "cpu/all/usage"; enabled: true }
    Win7Sensor { updateController: refreshClock; id: statusMemSensor; sensorId: "memory/physical/usedPercent"; enabled: true }

    readonly property int statusCpuPct: Math.round(Number(statusCpuSensor.value) || 0)
    readonly property int statusMemPct: Math.round(Number(statusMemSensor.value) || 0)
    readonly property int statusProcessCount: processesTab.totalProcessCount

    Win7UpdateClock {
        id: refreshClock
        updateInterval: app.updateInterval
        onRefreshed: app.refreshViews()
    }

    ToolsModel {
        id: toolsModel
    }

    Page.PagesModel {
        id: pagesModel
    }

    // Track any user-added custom pages from PagesModel beyond the 4 built-in pages
    property var customPages: []

    function rebuildTabs() {
        var extra = []
        var builtins = ["overview.page", "applications.page", "processes.page", "history.page", "old-overview.page", "old-history.page"]
        for (var i = 0; i < pagesModel.rowCount(); ++i) {
            var idx = pagesModel.index(i, 0)
            var fileName = String(pagesModel.data(idx, Page.PagesModel.FileNameRole) || "")
            var hidden = Boolean(pagesModel.data(idx, Page.PagesModel.HiddenRole))
            var title = String(pagesModel.data(idx, Page.PagesModel.TitleRole) || fileName)
            var controller = pagesModel.data(idx, Page.PagesModel.DataRole)
            if (!hidden && fileName.length > 0 && builtins.indexOf(fileName) === -1) {
                extra.push({
                    id: "page:" + fileName,
                    title: title,
                    fileName: fileName,
                    controller: controller
                })
            }
        }
        customPages = extra
    }

    readonly property var allTabs: {
        var base = [
            { id: "overview", title: i18n("Overview"), fileName: "overview.page" },
            { id: "applications", title: i18n("Applications"), fileName: "applications.page" },
            { id: "processes", title: i18n("Processes"), fileName: "processes.page" },
            { id: "performance", title: i18n("Performance"), fileName: "history.page" },
            { id: "networking", title: i18n("Networking"), fileName: "" }
        ]
        return base.concat(customPages)
    }

    function selectTabByPageIdOrName(pageId, pageName) {
        if (pageId) {
            if (pageId === "overview.page") { currentTabId = "overview"; return true }
            if (pageId === "applications.page") { currentTabId = "applications"; return true }
            if (pageId === "processes.page") { currentTabId = "processes"; return true }
            if (pageId === "history.page") { currentTabId = "performance"; return true }
            for (var i = 0; i < customPages.length; ++i) {
                if (customPages[i].fileName === pageId) {
                    currentTabId = customPages[i].id
                    return true
                }
            }
        }
        if (pageName) {
            var lower = pageName.toLowerCase()
            for (var j = 0; j < allTabs.length; ++j) {
                if (allTabs[j].title.toLowerCase() === lower || allTabs[j].id === lower) {
                    currentTabId = allTabs[j].id
                    return true
                }
            }
        }
        return false
    }

    Component.onCompleted: {
        rebuildTabs()
        if (!selectTabByPageIdOrName(CommandLineArguments.pageId, CommandLineArguments.pageName)) {
            var savedPage = Page.Configuration.startPage || Page.Configuration.lastVisitedPage
            if (!selectTabByPageIdOrName(savedPage, "")) {
                currentTabId = "overview"
            }
        }
    }

    onCurrentTabIdChanged: {
        for (var i = 0; i < allTabs.length; ++i) {
            if (allTabs[i].id === currentTabId && allTabs[i].fileName) {
                Page.Configuration.lastVisitedPage = allTabs[i].fileName
                break
            }
        }
    }

    function openNewTaskDialog() {
        toolsModel.setWindowIconByName(newTaskDialog, "system-run")
        newTaskDialog.open()
    }

    function openAboutDialog() {
        aboutDialog.open()
    }

    function refreshCurrentTab() {
        refreshClock.refreshNow()
    }

    function refreshViews() {
        overviewTab.refreshNow()
        applicationsTab.refreshNow()
        processesTab.refreshNow()
        performanceTab.refreshNow()
        networkingTab.refreshNow()
    }

    Shortcut {
        sequence: "F5"
        onActivated: app.refreshCurrentTab()
    }

    Shortcut {
        sequence: "F1"
        onActivated: app.openAboutDialog()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // 1. Classic Windows 7 Aero Menu Bar (19px tall, #fefeff -> #d4dbed -> #e1e6f6, bottom border #b6bccc)
        Rectangle {
            id: win7MenuBar
            Layout.fillWidth: true
            Layout.preferredHeight: 19
            Layout.minimumHeight: 19
            Layout.maximumHeight: 19
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#fefeff" }
                GradientStop { position: 0.22; color: "#f2f5fa" }
                GradientStop { position: 0.38; color: "#e5eaf5" }
                GradientStop { position: 0.42; color: "#d4dbed" }
                GradientStop { position: 0.94; color: "#e1e6f6" }
                GradientStop { position: 1.0; color: "#b6bccc" }
            }

            Row {
                id: menuBarRow
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                spacing: 1

                // Currently open top-level menu (Win32 menu bars switch menus on hover
                // while one is open).
                property var openMenu: null

                function openMenuFor(btn) {
                    var m = btn.modelData.menu
                    if (openMenu && openMenu !== m && openMenu.visible) {
                        openMenu.close()
                    }
                    // Keep the menu open when its own menu bar button is pressed so the
                    // click toggles it closed instead of immediately re-opening it.
                    m.closePolicy = Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                    m.popup(btn, -1, btn.height)
                    openMenu = m
                }

                function openMenuById(menuId) {
                    fileMenu.close()
                    optionsMenu.close()
                    viewMenu.close()
                    windowsMenu.close()
                    helpMenu.close()
                    openMenu = null
                    processesTab.closeContextMenu()
                    processesTab.resetHorizontalScroll()
                    overviewTab.resetHorizontalScroll()
                    networkingTab.resetHorizontalScroll()
                    if (newTaskDialog.visible) newTaskDialog.close()
                    if (aboutDialog.visible) aboutDialog.close()
                    if (!menuId) return
                    if (menuId === "network_processes_right") {
                        networkingTab.scrollToLastColumn()
                        return
                    }
                    if (menuId === "pause_updates") {
                        app.updateInterval = 0
                        return
                    }
                    if (menuId === "refresh_updates") {
                        app.refreshCurrentTab()
                        return
                    }
                    if (menuId === "normal_updates") {
                        app.updateInterval = 2000
                        return
                    }
                    if (menuId === "ctx_proc") {
                        processesTab.openContextMenuAt(120, 96)
                        return
                    }
                    if (menuId === "sort_mem") {
                        processesTab.sortByAttribute("memoryPercent", Qt.DescendingOrder)
                        return
                    }
                    if (menuId === "sort_cpu") {
                        processesTab.sortByAttribute("usage", Qt.DescendingOrder)
                        return
                    }
                    if (menuId === "sort_overview_cpu") {
                        overviewTab.sortByAttribute("usage", Qt.DescendingOrder)
                        return
                    }
                    if (menuId === "scroll_overview_right") {
                        overviewTab.scrollToLastColumn()
                        return
                    }
                    if (menuId === "scroll_proc_right") {
                        processesTab.scrollToLastColumn()
                        return
                    }
                    if (menuId === "dlg_about") {
                        aboutDialog.open()
                        return
                    }
                    if (menuId === "dlg_newtask") {
                        app.openNewTaskDialog()
                        return
                    }
                    if (menuId === "dlg_props") {
                        processesTab.openPropertiesDialog()
                        return
                    }
                    if (menuId === "dlg_cols") {
                        processesTab.openSelectColumnsDialog()
                        return
                    }
                    for (var i = 0; i < menuBarRepeater.count; ++i) {
                        var btn = menuBarRepeater.itemAt(i)
                        if (btn && btn.modelData.id === menuId && btn.visible) {
                            openMenuFor(btn)
                            return
                        }
                    }
                }

                Repeater {
                    id: menuBarRepeater
                    model: [
                        { id: "file", label: i18n("File"), onlyIfTab: "", menu: fileMenu },
                        { id: "options", label: i18n("Options"), onlyIfTab: "", menu: optionsMenu },
                        { id: "view", label: i18n("View"), onlyIfTab: "", menu: viewMenu },
                        { id: "windows", label: i18n("Windows"), onlyIfTab: "applications", menu: windowsMenu },
                        { id: "help", label: i18n("Help"), onlyIfTab: "", menu: helpMenu }
                    ]

                    Item {
                        id: menuBarBtn
                        required property var modelData
                        visible: !modelData.onlyIfTab || app.currentTabId === modelData.onlyIfTab
                        width: visible ? (menuBtnText.implicitWidth + 14) : 0
                        height: 18

                        property bool hovered: false
                        readonly property bool menuOpen: modelData.menu.visible

                        // Hot (hover) state: soft light-blue Aero highlight
                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 1
                            radius: 2
                            visible: menuBarBtn.hovered && !menuBarBtn.menuOpen && !(menuBarRow.openMenu && menuBarRow.openMenu.visible)
                            border.width: 1
                            border.color: "#a8b8ce"
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#f0f5fb" }
                                GradientStop { position: 1.0; color: "#dce6f4" }
                            }
                        }

                        // Pressed (menu open) state sampled from crop_menu_windows.png:
                        // dark #4b4d54 rim, inset top/left shading, #c7cdde -> #d5dae9 face
                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 1
                            radius: 2
                            visible: menuBarBtn.menuOpen
                            border.width: 1
                            border.color: "#4b4d54"
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#9fa0a2" }
                                GradientStop { position: 0.08; color: "#b6b8bb" }
                                GradientStop { position: 0.18; color: "#c8cad0" }
                                GradientStop { position: 0.3; color: "#c7cdde" }
                                GradientStop { position: 1.0; color: "#d5dae9" }
                            }
                            // Inset left shading
                            Rectangle {
                                x: 1
                                y: 2
                                width: 1
                                height: parent.height - 3
                                color: "#a3a8b3"
                            }
                            Rectangle {
                                x: 2
                                y: 2
                                width: 1
                                height: parent.height - 3
                                color: "#bbc1d0"
                            }
                        }

                        Text {
                            id: menuBtnText
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 1
                            text: menuBarBtn.modelData.label
                            textFormat: Text.StyledText
                            font.family: "Segoe UI"
                            font.pixelSize: 12
                            color: "#000000"
                            renderType: Text.NativeRendering
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: {
                                menuBarBtn.hovered = true
                                var row = menuBarBtn.parent
                                if (row.openMenu && row.openMenu.visible && row.openMenu !== menuBarBtn.modelData.menu) {
                                    row.openMenuFor(menuBarBtn)
                                }
                            }
                            onExited: menuBarBtn.hovered = false
                            onClicked: {
                                var m = menuBarBtn.modelData.menu
                                if (m.visible) {
                                    m.close()
                                } else {
                                    menuBarBtn.parent.openMenuFor(menuBarBtn)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. Classic Windows 7 Tab Control & Tab Pane area on #f0f0f0 background
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#f0f0f0"

            Item {
                id: tabControlArea
                anchors.fill: parent
                anchors.leftMargin: 5
                anchors.rightMargin: 6
                anchors.topMargin: 6
                anchors.bottomMargin: 2

                // Tab Pane (#ffffff interior with #898c95 1px border, starting at y=20)
                Rectangle {
                    id: tabPane
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 20
                    anchors.bottom: parent.bottom
                    color: "#ffffff"
                    border.width: 1
                    border.color: "#898c95"
                    z: 1

                    // Tab Views Stack
                    Win7OverviewTab {
                        updateController: refreshClock
                        id: overviewTab
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: app.currentTabId === "overview"
                        showKernelTimes: app.showKernelTimes
                        updateInterval: app.updateInterval
                        processCount: app.statusProcessCount
                        onSwitchToTabRequested: tabId => app.currentTabId = tabId
                        onInspectProcessRequested: (pid, name) => {
                            app.currentTabId = "processes"
                            processesTab.selectProcessByPid(pid, name)
                        }
                        onNewTaskRequested: app.openNewTaskDialog()
                    }

                    Win7ApplicationsTab {
                        updateController: refreshClock
                        id: applicationsTab
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: app.currentTabId === "applications"
                        onNewTaskRequested: app.openNewTaskDialog()
                        onSwitchToRequested: (pid, name) => {
                            if (app.minimizeOnUse) {
                                app.showMinimized()
                            }
                        }
                        onGoToProcessRequested: (pid, name) => {
                            app.currentTabId = "processes"
                            processesTab.selectProcessByPid(pid, name)
                        }
                    }

                    Win7ProcessesTab {
                        updateController: refreshClock
                        id: processesTab
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: app.currentTabId === "processes"
                    }

                    Win7PerformanceTab {
                        updateController: refreshClock
                        id: performanceTab
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: app.currentTabId === "performance"
                        showKernelTimes: app.showKernelTimes
                        perCpuHistory: app.perCpuHistory
                        updateInterval: app.updateInterval
                        processCount: app.statusProcessCount
                        onResourceMonitorClicked: {
                            app.currentTabId = "overview"
                        }
                    }

                    Win7NetworkingTab {
                        updateController: refreshClock
                        id: networkingTab
                        onInspectProcessRequested: pid => {
                            app.currentTabId = "processes"
                            processesTab.selectProcessByPid(pid, "")
                        }
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: app.currentTabId === "networking"
                        updateInterval: app.updateInterval
                    }

                    // Loader for any user-added custom .page files from PagesModel
                    Repeater {
                        model: app.customPages

                        Loader {
                            required property var modelData
                            anchors.fill: parent
                            anchors.margins: 6
                            active: app.currentTabId === modelData.id
                            visible: active
                            sourceComponent: Page.PageContents {
                                controller: modelData.controller
                            }
                        }
                    }
                }

                // Classic Win7 Tab Strip at top (z: 2 so active tab covers the top border of tabPane)
                Row {
                    id: tabStrip
                    anchors.left: parent.left
                    anchors.top: parent.top
                    height: 21
                    spacing: 0
                    z: 2

                    Repeater {
                        model: app.allTabs

                        Item {
                            id: tabButton
                            required property int index
                            required property var modelData

                            readonly property bool isCurrent: app.currentTabId === modelData.id
                            property bool isHovered: false

                            width: Math.ceil(tabLabel.implicitWidth) + 12
                            height: 21

                            Rectangle {
                                id: tabBox
                                radius: 0
                                antialiasing: false
                                x: 0
                                y: tabButton.isCurrent ? 0 : 2
                                width: parent.width
                                height: tabButton.isCurrent ? 21 : 19
                                color: tabButton.isCurrent ? "#ffffff" : "transparent"
                                border.width: 1
                                border.color: tabButton.isHovered && !tabButton.isCurrent ? "#3c7fb1" : "#898c95"

                                // Inactive tab gradient matching Win7 VM (#f2f2f2 -> #ebebeb -> #cfcfcf)
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    visible: !tabButton.isCurrent
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: tabButton.isHovered ? "#eaf6fd" : "#fcfcfc" }
                                        GradientStop { position: 0.12; color: tabButton.isHovered ? "#e3f3fc" : "#f2f2f2" }
                                        GradientStop { position: 0.55; color: tabButton.isHovered ? "#d9f0fc" : "#ebebeb" }
                                        GradientStop { position: 1.0; color: tabButton.isHovered ? "#bee6fd" : "#cfcfcf" }
                                    }
                                }

                                // Seamless white bridge at bottom of active tab so it merges into tabPane
                                Rectangle {
                                    visible: tabButton.isCurrent
                                    anchors.left: parent.left
                                    anchors.leftMargin: 1
                                    anchors.right: parent.right
                                    anchors.rightMargin: 1
                                    anchors.bottom: parent.bottom
                                    height: 2
                                    color: "#ffffff"
                                }

                                // Classic 1px dotted focus rectangle inside active tab matching VM screenshots
                                Canvas {
                                    anchors.fill: parent
                                    anchors.leftMargin: 2
                                    anchors.rightMargin: 2
                                    anchors.topMargin: 2
                                    anchors.bottomMargin: 3
                                    visible: tabButton.isCurrent
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        ctx.fillStyle = "#000000"
                                        for (var x = 0; x < width; x += 2) {
                                            ctx.fillRect(x, 0, 1, 1)
                                            ctx.fillRect(x, height - 1, 1, 1)
                                        }
                                        for (var y = 0; y < height; y += 2) {
                                            ctx.fillRect(0, y, 1, 1)
                                            ctx.fillRect(width - 1, y, 1, 1)
                                        }
                                    }
                                }

                                Text {
                                    id: tabLabel
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: tabButton.isCurrent ? -1 : 0
                                    text: tabButton.modelData.title
                                    font.family: "Segoe UI"
                                    font.pixelSize: 12
                                    color: "#000000"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: tabButton.isHovered = true
                                onExited: tabButton.isHovered = false
                                onClicked: app.currentTabId = tabButton.modelData.id
                            }
                        }
                    }
                }
            }
        }

        // 3. Classic Windows 7 3-Pane Status Bar (24px tall)
        Rectangle {
            id: statusBar
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            Layout.minimumHeight: 24
            Layout.maximumHeight: 24
            color: "#f0f0f0"

            // Top sunken divider (#919191 + #ffffff)
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 2
                height: 1
                color: "#919191"
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 3
                height: 1
                color: "#ffffff"
            }

            RowLayout {
                anchors.fill: parent
                anchors.topMargin: 4
                anchors.bottomMargin: 1
                spacing: 0

                // Pane 1: Processes: N
                Item {
                    Layout.preferredWidth: 104
                    Layout.minimumWidth: 95
                    Layout.fillHeight: true

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n("Processes: %1", app.statusProcessCount)
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        color: "#000000"
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 1
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: "#919191"
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: "#ffffff"
                    }
                }

                // Pane 2: CPU Usage: Y%
                Item {
                    Layout.preferredWidth: 132
                    Layout.minimumWidth: 105
                    Layout.fillHeight: true

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n("CPU Usage: %1%", app.statusCpuPct)
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        color: "#000000"
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 1
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: "#919191"
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: "#ffffff"
                    }
                }

                // Pane 3: Physical Memory: Z% + Win7 diagonal resize grip
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n("Physical Memory: %1%", app.statusMemPct)
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        color: "#000000"
                    }

                    // Classic Win7 3-by-3 diagonal status bar size grip dots at bottom-right
                    Canvas {
                        width: 12
                        height: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 1
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            var pts = [
                                [8, 8],
                                [5, 8], [8, 5],
                                [2, 8], [5, 5], [8, 2]
                            ]
                            for (var i = 0; i < pts.length; ++i) {
                                var px = pts[i][0]
                                var py = pts[i][1]
                                ctx.fillStyle = "#ffffff"
                                ctx.fillRect(px + 1, py + 1, 2, 2)
                                ctx.fillStyle = "#919191"
                                ctx.fillRect(px, py, 2, 2)
                            }
                        }
                    }
                }
            }
        }
    }

    // Classic Windows 7 Menus matching VM screenshots (crop_menu_*.png).
    // Rendered with the pixel-accurate Win7Menu / Win7MenuItem / Win7MenuSeparator
    // components; tab-specific entries are hidden (not just disabled) like Win7.
    readonly property bool perfLikeTab: currentTabId === "performance" || currentTabId === "overview"

    Win7Menu {
        id: fileMenu
        Win7MenuItem {
            text: i18n("New Task (Run...)")
            onTriggered: app.openNewTaskDialog()
        }
        Win7MenuSeparator { }
        Win7MenuItem {
            text: i18n("Exit Task Manager")
            onTriggered: Qt.quit()
        }
    }

    Win7Menu {
        id: optionsMenu
        Win7MenuItem {
            text: i18n("Always On Top")
            checkable: true
            checked: app.alwaysOnTop
            onTriggered: app.alwaysOnTop = checked
        }
        Win7MenuItem {
            text: i18n("Minimize On Use")
            checkable: true
            checked: app.minimizeOnUse
            onTriggered: app.minimizeOnUse = checked
        }
        Win7MenuItem {
            text: i18n("Hide When Minimized")
            checkable: true
            checked: app.hideWhenMinimized
            onTriggered: app.hideWhenMinimized = checked
        }
    }

    Win7Menu {
        id: viewMenu
        Win7MenuItem {
            text: i18n("Refresh Now") + "\t" + "F5"
            onTriggered: app.refreshCurrentTab()
        }
        Win7Menu {
            title: i18n("Update Speed")

            Win7MenuItem {
                text: i18n("High")
                checkable: true
                radio: true
                checked: app.updateInterval === 500
                onTriggered: app.updateInterval = 500
            }
            Win7MenuItem {
                text: i18n("Normal")
                checkable: true
                radio: true
                checked: app.updateInterval === 2000
                onTriggered: app.updateInterval = 2000
            }
            Win7MenuItem {
                text: i18n("Low")
                checkable: true
                radio: true
                checked: app.updateInterval === 4000
                onTriggered: app.updateInterval = 4000
            }
            Win7MenuItem {
                text: i18n("Paused")
                checkable: true
                radio: true
                checked: app.updateInterval === 0
                onTriggered: app.updateInterval = 0
            }
        }

        Win7MenuSeparator {
            visible: app.currentTabId === "applications" || app.currentTabId === "processes" || app.perfLikeTab || app.currentTabId === "networking"
        }

        // Contextual View items for Applications tab
        Win7MenuItem {
            visible: app.currentTabId === "applications"
            text: i18n("Large Icons")
            checkable: true
            radio: true
            checked: applicationsTab.viewStyle === 1
            onTriggered: applicationsTab.viewStyle = 1
        }
        Win7MenuItem {
            visible: app.currentTabId === "applications"
            text: i18n("Small Icons")
            checkable: true
            radio: true
            checked: applicationsTab.viewStyle === 2
            onTriggered: applicationsTab.viewStyle = 2
        }
        Win7MenuItem {
            visible: app.currentTabId === "applications"
            text: i18n("Details")
            checkable: true
            radio: true
            checked: applicationsTab.viewStyle === 0
            onTriggered: applicationsTab.viewStyle = 0
        }

        // Contextual View items for Processes tab (crop_menu_view_proc.png)
        Win7MenuItem {
            visible: app.currentTabId === "processes"
            text: i18n("Select Columns...")
            onTriggered: processesTab.openSelectColumnsDialog()
        }

        // Contextual View items for Performance / Overview tab (crop_menu_view_perf.png)
        Win7Menu {
            title: i18n("CPU History")
            shown: app.perfLikeTab

            Win7MenuItem {
                text: i18n("One Graph, All CPUs")
                checkable: true
                radio: true
                checked: !app.perCpuHistory
                onTriggered: app.perCpuHistory = false
            }
            Win7MenuItem {
                text: i18n("One Graph Per CPU")
                checkable: true
                radio: true
                checked: app.perCpuHistory
                onTriggered: app.perCpuHistory = true
            }
        }
        Win7MenuItem {
            visible: app.perfLikeTab
            text: i18n("Show Kernel Times")
            checkable: true
            checked: app.showKernelTimes
            onTriggered: app.showKernelTimes = checked
        }

        // Contextual View items for Networking tab
        Win7Menu {
            title: i18n("Network Adapter History")
            shown: app.currentTabId === "networking"

            Win7MenuItem {
                text: i18n("Bytes Sent")
                checkable: true
                radio: true
                checked: networkingTab.networkHistoryMode === 1
                onTriggered: networkingTab.networkHistoryMode = 1
            }
            Win7MenuItem {
                text: i18n("Bytes Received")
                checkable: true
                radio: true
                checked: networkingTab.networkHistoryMode === 2
                onTriggered: networkingTab.networkHistoryMode = 2
            }
            Win7MenuItem {
                text: i18n("Bytes Total")
                checkable: true
                radio: true
                checked: networkingTab.networkHistoryMode === 0
                onTriggered: networkingTab.networkHistoryMode = 0
            }
        }
    }

    // Classic Windows menu on Applications tab matching crop_menu_windows.png
    Win7Menu {
        id: windowsMenu
        Win7MenuItem {
            text: i18n("Tile Horizontally")
            enabled: applicationsTab.taskCount > 0
        }
        Win7MenuItem {
            text: i18n("Tile Vertically")
            enabled: applicationsTab.taskCount > 0
        }
        Win7MenuItem {
            text: i18n("Minimize")
            enabled: applicationsTab.taskCount > 0
            onTriggered: applicationsTab.switchToSelectedTask()
        }
        Win7MenuItem {
            text: i18n("Maximize")
            enabled: applicationsTab.taskCount > 0
            onTriggered: applicationsTab.switchToSelectedTask()
        }
        Win7MenuItem {
            text: i18n("Cascade")
            enabled: applicationsTab.taskCount > 0
        }
        Win7MenuItem {
            text: i18n("Bring To Front")
            enabled: applicationsTab.taskCount > 0
            onTriggered: applicationsTab.switchToSelectedTask()
        }
    }

    Win7Menu {
        id: helpMenu
        Win7MenuItem {
            text: i18n("Task Manager Help Topics") + "\t" + "F1"
            onTriggered: app.openAboutDialog()
        }
        Win7MenuSeparator { }
        Win7MenuItem {
            text: i18n("About Task Manager")
            onTriggered: app.openAboutDialog()
        }
    }

    Win7NewTaskDialog {
        id: newTaskDialog
        transientParent: app
        onCommandSubmitted: cmd => toolsModel.runCommand(cmd)
    }

    Win7AboutDialog {
        id: aboutDialog
        transientParent: app
    }

    KConfig.WindowStateSaver {
        configGroupName: "MainWindow"
    }

    onClosing: Page.PageManager.saveAll()
}
