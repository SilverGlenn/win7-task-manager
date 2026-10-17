/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami

Window {
    id: dialog

    title: i18nc("@title:window", "Create New Task")
    modality: Qt.WindowModal
    flags: Qt.Dialog | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowCloseButtonHint
    width: 398
    height: 173
    minimumWidth: 398
    maximumWidth: 398
    minimumHeight: 173
    maximumHeight: 173
    visible: false
    color: "#f0f0f0"

    signal commandSubmitted(string command)

    property var recentCommands: ["explorer", "konsole", "dolphin", "kate", "systemsettings"]
    property bool historyPopupOpen: false

    function open() {
        historyPopupOpen = false
        if (commandInput.text.trim().length === 0 && recentCommands.length > 0) {
            commandInput.text = recentCommands[0]
        }
        if (transientParent) {
            x = transientParent.x + Math.round((transientParent.width - width) / 2)
            y = transientParent.y + Math.round((transientParent.height - height) / 2)
        }
        dialog.show()
        dialog.raise()
        dialog.requestActivate()
        commandInput.forceActiveFocus()
        commandInput.selectAll()
    }

    function submitCurrentCommand() {
        var cmd = commandInput.text.trim()
        if (cmd.length === 0) return
        var idx = recentCommands.indexOf(cmd)
        var updated = recentCommands.slice()
        if (idx !== -1) updated.splice(idx, 1)
        updated.unshift(cmd)
        recentCommands = updated.slice(0, 10)
        dialog.commandSubmitted(cmd)
        dialog.close()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: dialog.close()

        // Upper white region (y: 0..101) with soft gradient transition into #f0f0f0 (matching petri_ref.jpg / crop_dlg_newtask.png)
        Rectangle {
            x: 0
            y: 0
            width: parent.width
            height: 111
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#ffffff" }
                GradientStop { position: 0.88; color: "#ffffff" }
                GradientStop { position: 1.0; color: "#f0f0f0" }
            }
        }

        // Authentic 32x32 Windows 7 Task Manager icon (/usr/share/icons/Windows 7 Aero/apps/32/utilities-system-monitor.png)
        Item {
            x: 12
            y: 23
            width: 32
            height: 32

            Image {
                id: win7TaskMgrIconImg
                anchors.fill: parent
                source: "file:///usr/share/icons/Windows 7 Aero/apps/32/utilities-system-monitor.png"
                smooth: true
                visible: status === Image.Ready
            }

            Kirigami.Icon {
                anchors.fill: parent
                source: "utilities-system-monitor"
                visible: !win7TaskMgrIconImg.visible
            }
        }

        // Top 2-line instruction text matching Windows 7 Create New Task dialog
        Text {
            x: 63
            y: 23
            text: i18n("Type the name of a program, folder, document, or Internet\nresource, and Windows will open it for you.")
            lineHeight: 1.08
            font.family: "Segoe UI"
            font.pixelSize: 12
            color: "#000000"
        }

        // "Open:" label
        Text {
            x: 12
            y: 73
            text: i18n("Open:")
            font.family: "Segoe UI"
            font.pixelSize: 12
            color: "#000000"
        }

        // Editable Win7 ComboBox for Open command
        Rectangle {
            id: comboBoxFrame
            x: 63
            y: 68
            width: 320
            height: 23
            color: "#ffffff"
            border.width: 1
            border.color: "#abadb3"

            // Subtle top inner bevel (#e3e9ef)
            Rectangle {
                x: 1
                y: 1
                width: parent.width - 2
                height: 1
                color: "#e3e9ef"
            }

            TextInput {
                id: commandInput
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.right: dropDownBtn.left
                anchors.rightMargin: 2
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                verticalAlignment: TextInput.AlignVCenter
                font.family: "Segoe UI"
                font.pixelSize: 12
                color: "#000000"
                selectionColor: "#3399ff"
                selectedTextColor: "#ffffff"
                selectByMouse: true
                clip: true
                onAccepted: dialog.submitCurrentCommand()
            }

            // Right-side ComboBox dropdown arrow button
            Rectangle {
                id: dropDownBtn
                anchors.right: parent.right
                anchors.rightMargin: 1
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                width: 17
                color: dropArea.containsMouse ? "#e5f1fb" : "transparent"

                Canvas {
                    width: 7
                    height: 4
                    anchors.centerIn: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.fillStyle = "#000000"
                        ctx.beginPath()
                        ctx.moveTo(0, 0)
                        ctx.lineTo(7, 0)
                        ctx.lineTo(3.5, 4)
                        ctx.closePath()
                        ctx.fill()
                    }
                }

                MouseArea {
                    id: dropArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: dialog.historyPopupOpen = !dialog.historyPopupOpen
                }
            }
        }

        // Dropdown history list when arrow is clicked
        Rectangle {
            visible: dialog.historyPopupOpen
            x: comboBoxFrame.x
            y: comboBoxFrame.y + comboBoxFrame.height
            width: comboBoxFrame.width
            height: Math.min(110, dialog.recentCommands.length * 20 + 2)
            color: "#ffffff"
            border.width: 1
            border.color: "#646464"
            z: 20

            Column {
                anchors.fill: parent
                anchors.margins: 1
                Repeater {
                    model: dialog.recentCommands
                    Rectangle {
                        required property string modelData
                        width: comboBoxFrame.width - 2
                        height: 20
                        color: histMouse.containsMouse ? "#3399ff" : "#ffffff"
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            verticalAlignment: Text.AlignVCenter
                            text: parent.modelData
                            font.family: "Segoe UI"
                            font.pixelSize: 12
                            color: histMouse.containsMouse ? "#ffffff" : "#000000"
                        }
                        MouseArea {
                            id: histMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                commandInput.text = parent.modelData
                                dialog.historyPopupOpen = false
                                commandInput.forceActiveFocus()
                            }
                        }
                    }
                }
            }
        }

        // Button placement measured from the Create New Task VM reference.
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 15
            y: 131
            spacing: 8

            Win7Button {
                width: 86
                height: 23
                text: i18n("OK")
                isDefault: true
                enabled: commandInput.text.trim().length > 0
                onClicked: dialog.submitCurrentCommand()
            }

            Win7Button {
                width: 86
                height: 23
                text: i18n("Cancel")
                onClicked: dialog.close()
            }

            Win7Button {
                width: 86
                height: 23
                text: i18n("Browse...")
                onClicked: fileDialog.open()
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: i18n("Browse")
        onAccepted: {
            var path = selectedFile.toString().replace("file://", "")
            if (path.length > 0) {
                commandInput.text = path
                commandInput.forceActiveFocus()
            }
        }
    }
}
