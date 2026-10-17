/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.systemmonitor
import org.kde.ksysguard.formatter as Formatter

ColumnLayout {
    id: root

    required property var updateController
    property int selectedPid: 0
    property var columnWidths: [90, 46, 62, 64, 62, 90, 90, 82, 150, 58, 65]
    readonly property var columns: [
        {key: "name", title: i18n("Image Name"), numeric: false},
        {key: "pid", title: i18n("PID"), numeric: true},
        {key: "sendRate", title: i18n("Send"), numeric: true, rate: true},
        {key: "receiveRate", title: i18n("Receive"), numeric: true, rate: true},
        {key: "totalRate", title: i18n("Total"), numeric: true, rate: true},
        {key: "sentBytes", title: i18n("Sent"), numeric: true, bytes: true},
        {key: "receivedBytes", title: i18n("Received"), numeric: true, bytes: true},
        {key: "connections", title: i18n("Connections"), numeric: true},
        {key: "lastIp", title: i18n("Last IP"), numeric: false},
        {key: "remotePort", title: i18n("Port"), numeric: true},
        {key: "protocol", title: i18n("Protocol"), numeric: false}
    ]
    readonly property real tableWidth: Math.max(networkList.width, columnWidths.reduce((sum, width) => sum + width, 0))
    readonly property var selectedProcess: {
        var revision = networkModel.revision
        return networkModel.processForPid(selectedPid)
    }
    signal inspectProcessRequested(int pid, string name)
    spacing: 5

    function startMonitoring() { networkModel.monitoring = true }
    function refreshNow() { if (networkModel.monitoring) networkModel.refresh() }
    function resetHorizontalScroll() { networkList.contentX = 0 }
    function scrollToLastColumn() { networkList.contentX = Math.max(0, tableWidth - networkList.width) }

    function cellText(process, column) {
        var value = process[column.key]
        if (value === undefined || value === null || value === "" || (column.key === "remotePort" && value === 0)) return "—"
        if (column.rate) return Formatter.Formatter.formatValueShowNull(value, Formatter.Units.UnitByteRate)
        if (column.bytes) return Formatter.Formatter.formatValueShowNull(value, Formatter.Units.UnitByte)
        return String(value)
    }

    Win7NetworkProcessModel { id: networkModel }

    Connections {
        target: networkModel
        function onRefreshed() {
            if (!networkModel.processForPid(root.selectedPid).pid) {
                var first = networkModel.rowCount() ? networkModel.data(networkModel.index(0, 0), Win7NetworkProcessModel.ProcessRole) : null
                root.selectedPid = first ? first.pid : 0
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: networkModel.statusText || i18n("TCP/UDP · Totals since monitoring started")
        font.family: "Segoe UI"
        font.pixelSize: 12
        color: "#000000"
        elide: Text.ElideRight
    }

    Rectangle {
        id: viewport
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 60
        color: "#ffffff"
        border.color: "#828790"
        border.width: 1
        clip: true

        Item {
            id: headerClip
            x: 1
            y: 1
            width: networkList.width
            height: 22
            clip: true
            Rectangle {
                x: -networkList.contentX
                width: root.tableWidth
                height: 22
                gradient: Gradient {
                    GradientStop { position: 0; color: "#ffffff" }
                    GradientStop { position: 0.45; color: "#f7f8fa" }
                    GradientStop { position: 0.94; color: "#f1f2f4" }
                    GradientStop { position: 1; color: "#d5d5d5" }
                }
                Row {
                    Repeater {
                        model: root.columns
                        Rectangle {
                            id: columnHeader
                            required property int index
                            required property var modelData
                            width: root.columnWidths[index]
                            height: 22
                            color: networkModel.sortColumn === index ? "#e1f1f9" : "transparent"
                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 5
                                anchors.rightMargin: 5
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: columnHeader.modelData.numeric ? Text.AlignRight : Text.AlignLeft
                                text: columnHeader.modelData.title
                                elide: Text.ElideRight
                                font.family: "Segoe UI"
                                font.pixelSize: 12
                                color: "#000000"
                            }
                            Canvas {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 1
                                width: 7
                                height: 4
                                visible: networkModel.sortColumn === columnHeader.index
                                property int order: networkModel.sortOrder
                                onOrderChanged: requestPaint()
                                onVisibleChanged: if (visible) requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.fillStyle = "#3c596c"
                                    ctx.beginPath()
                                    if (order === Qt.AscendingOrder) {
                                        ctx.moveTo(3.5, 0); ctx.lineTo(7, 4); ctx.lineTo(0, 4)
                                    } else {
                                        ctx.moveTo(0, 0); ctx.lineTo(7, 0); ctx.lineTo(3.5, 4)
                                    }
                                    ctx.closePath(); ctx.fill()
                                }
                            }
                            Rectangle { anchors.right: parent.right; width: 1; height: 21; color: "#d5d5d5" }
                            MouseArea {
                                anchors.fill: parent
                                anchors.rightMargin: 4
                                hoverEnabled: true
                                onClicked: {
                                    var order = networkModel.sortColumn === columnHeader.index
                                        ? (networkModel.sortOrder === Qt.AscendingOrder ? Qt.DescendingOrder : Qt.AscendingOrder)
                                        : (columnHeader.modelData.numeric ? Qt.DescendingOrder : Qt.AscendingOrder)
                                    networkModel.sort(columnHeader.index, order)
                                }
                                ToolTip.visible: containsMouse
                                ToolTip.delay: 600
                                ToolTip.text: columnHeader.modelData.key === "lastIp"
                                    ? i18n("Latest observed TCP peer, or an identifiable connected UDP peer. Short-lived and unconnected UDP traffic may have no address.")
                                    : columnHeader.modelData.rate ? i18n("Bytes per second")
                                    : columnHeader.modelData.bytes ? i18n("Bytes observed since monitoring started")
                                    : columnHeader.modelData.key === "connections" ? i18n("Current connected TCP and UDP sockets visible to your user") : columnHeader.modelData.title
                            }
                            MouseArea {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 6
                                cursorShape: Qt.SplitHCursor
                                property real startX: 0
                                property int startWidth: 0
                                onPressed: mouse => {
                                    startX = mapToItem(viewport, mouse.x, 0).x
                                    startWidth = columnHeader.width
                                }
                                onPositionChanged: mouse => {
                                    if (!pressed) return
                                    var widths = root.columnWidths.slice()
                                    widths[columnHeader.index] = Math.max(42, Math.round(startWidth + mapToItem(viewport, mouse.x, 0).x - startX))
                                    root.columnWidths = widths
                                }
                            }
                        }
                    }
                }
            }
        }

        ListView {
            id: networkList
            x: 1
            y: 23
            width: viewport.width - 2 - (verticalBar.visible ? 17 : 0)
            height: viewport.height - 24 - (horizontalBar.visible ? 17 : 0)
            contentWidth: root.tableWidth
            model: networkModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalAndVerticalFlick
            ScrollBar.vertical: Win7ScrollBar {
                id: verticalBar
                parent: viewport
                x: parent.width - width - 1
                y: 23
                width: 17
                height: networkList.height
                policy: ScrollBar.AsNeeded
                stepSize: 18 / Math.max(18, networkList.contentHeight)
            }
            ScrollBar.horizontal: Win7ScrollBar {
                id: horizontalBar
                parent: viewport
                x: 1
                y: parent.height - height - 1
                height: 17
                width: networkList.width
                policy: ScrollBar.AsNeeded
                stepSize: 24 / Math.max(24, root.tableWidth)
            }
            delegate: Rectangle {
                id: processRow
                required property var process
                width: root.tableWidth
                height: 18
                color: "#ffffff"
                Rectangle {
                    anchors.fill: parent
                    visible: root.selectedPid === processRow.process.pid
                    border.color: "#7da2ce"
                    radius: 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#dcebfc" }
                        GradientStop { position: 1; color: "#c1dbfc" }
                    }
                }
                Row {
                    Repeater {
                        model: root.columns
                        Text {
                            required property int index
                            required property var modelData
                            width: root.columnWidths[index]
                            height: 18
                            leftPadding: 5
                            rightPadding: 5
                            text: root.cellText(processRow.process, modelData)
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: modelData.numeric ? Text.AlignRight : Text.AlignLeft
                            elide: Text.ElideRight
                            font.family: "Segoe UI"
                            font.pixelSize: 12
                            color: "#000000"
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.selectedPid = processRow.process.pid
                    onDoubleClicked: root.inspectProcessRequested(processRow.process.pid, processRow.process.name)
                }
            }
        }

        Text {
            anchors.centerIn: networkList
            width: networkList.width - 20
            visible: networkList.count === 0
            text: i18n("Waiting for network processes…")
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.family: "Segoe UI"
            font.pixelSize: 12
            color: "#666666"
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: root.selectedProcess.pid ? i18n("Last IP: %1", root.selectedProcess.lastIp || "—") : i18n("Select a process to inspect its remote IP")
            elide: Text.ElideRight
            font.family: "Segoe UI"
            font.pixelSize: 12
            color: "#000000"
        }
        Win7Button {
            text: i18n("Go to Process")
            enabled: !!root.selectedProcess.pid
            onClicked: root.inspectProcessRequested(root.selectedProcess.pid, root.selectedProcess.name)
        }
    }
}
