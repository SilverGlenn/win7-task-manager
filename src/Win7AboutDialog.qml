/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import org.kde.coreaddons as KCoreAddons

Window {
    id: dialog

    title: i18nc("@title:window", "About Windows Task Manager")
    modality: Qt.WindowModal
    flags: Qt.Dialog | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowCloseButtonHint
    width: 459
    height: 374
    minimumWidth: 459
    maximumWidth: 459
    minimumHeight: 374
    maximumHeight: 374
    visible: false
    color: "#f0f0f0"

    function open() {
        if (transientParent) {
            x = transientParent.x + Math.round((transientParent.width - width) / 2)
            y = transientParent.y + Math.round((transientParent.height - height) / 2)
        }
        dialog.show()
        dialog.raise()
        dialog.requestActivate()
        okButton.forceActiveFocus()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: dialog.close()
        Keys.onReturnPressed: dialog.close()
        Keys.onEnterPressed: dialog.close()

        // 1. Top Windows 7 Ultimate banner (matching crop_dlg_about.png)
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 9
            spacing: 8

            // Authentic 4-quadrant waving Windows 7 flag icon
            Image {
                id: windowsLogo
                width: 42
                height: 42
                source: "file:///usr/share/icons/Windows 7 Aero/places/48/distributor-logo.png"
                fillMode: Image.PreserveAspectFit
                smooth: true
                visible: status === Image.Ready
                anchors.verticalCenter: parent.verticalCenter
            }
            Canvas {
                visible: !windowsLogo.visible
                width: 42
                height: 38
                anchors.verticalCenter: parent.verticalCenter
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    // Top-left (Red-Orange)
                    var g1 = ctx.createLinearGradient(4, 3, 20, 17)
                    g1.addColorStop(0, "#e8381c")
                    g1.addColorStop(1, "#f78d1e")
                    ctx.fillStyle = g1
                    ctx.beginPath()
                    ctx.moveTo(6, 5)
                    ctx.quadraticCurveTo(13, 2, 20, 5)
                    ctx.lineTo(17, 17)
                    ctx.quadraticCurveTo(10, 14, 3, 17)
                    ctx.closePath()
                    ctx.fill()

                    // Top-right (Green)
                    var g2 = ctx.createLinearGradient(22, 5, 38, 19)
                    g2.addColorStop(0, "#6db33f")
                    g2.addColorStop(1, "#a7d744")
                    ctx.fillStyle = g2
                    ctx.beginPath()
                    ctx.moveTo(23, 6)
                    ctx.quadraticCurveTo(30, 9, 37, 6)
                    ctx.lineTo(34, 18)
                    ctx.quadraticCurveTo(27, 21, 20, 18)
                    ctx.closePath()
                    ctx.fill()

                    // Bottom-left (Blue)
                    var g3 = ctx.createLinearGradient(2, 20, 18, 34)
                    g3.addColorStop(0, "#1d70b8")
                    g3.addColorStop(1, "#5bc0eb")
                    ctx.fillStyle = g3
                    ctx.beginPath()
                    ctx.moveTo(3, 20)
                    ctx.quadraticCurveTo(10, 17, 17, 20)
                    ctx.lineTo(14, 32)
                    ctx.quadraticCurveTo(7, 29, 0, 32)
                    ctx.closePath()
                    ctx.fill()

                    // Bottom-right (Yellow-Gold)
                    var g4 = ctx.createLinearGradient(19, 21, 35, 35)
                    g4.addColorStop(0, "#f9c80e")
                    g4.addColorStop(1, "#f48c06")
                    ctx.fillStyle = g4
                    ctx.beginPath()
                    ctx.moveTo(20, 21)
                    ctx.quadraticCurveTo(27, 24, 34, 21)
                    ctx.lineTo(31, 33)
                    ctx.quadraticCurveTo(24, 36, 17, 33)
                    ctx.closePath()
                    ctx.fill()
                }
            }

            Row {
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: "Windows"
                    font.family: "Segoe UI"
                    font.pixelSize: 38
                    font.weight: Font.Light
                    font.styleName: "Light"
                    font.hintingPreference: Font.PreferFullHinting
                    color: "#000000"
                    renderType: Text.NativeRendering
                }

                Text {
                    text: "®"
                    font.family: "Segoe UI"
                    font.pixelSize: 10
                    font.hintingPreference: Font.PreferFullHinting
                    color: "#000000"
                    anchors.top: parent.top
                    anchors.topMargin: 6
                    renderType: Text.NativeRendering
                }

                Text {
                    text: "7"
                    font.family: "Segoe UI"
                    font.pixelSize: 40
                    font.weight: Font.Light
                    font.styleName: "Light"
                    font.hintingPreference: Font.PreferFullHinting
                    color: "#000000"
                    renderType: Text.NativeRendering
                }

                Item { width: 5; height: 1 }

                Text {
                    text: "Ultimate"
                    font.family: "Segoe UI"
                    font.pixelSize: 26
                    font.weight: Font.Light
                    font.styleName: "Light"
                    font.hintingPreference: Font.PreferFullHinting
                    color: "#000000"
                    anchors.baseline: parent.children[0].baseline
                    renderType: Text.NativeRendering
                }
            }
        }

        // 2. Etched horizontal separator at y: 82 (matching crop_dlg_about.png)
        Rectangle {
            x: 14
            y: 82
            width: parent.width - 28
            height: 1
            color: "#a0a0a0"
        }
        Rectangle {
            x: 14
            y: 83
            width: parent.width - 28
            height: 1
            color: "#ffffff"
        }

        // 3. Left 32x32 Task Manager icon at x: 12, y: 101
        Image {
            x: 12
            y: 101
            width: 32
            height: 32
            source: "file:///usr/share/icons/Windows 7 Aero/apps/32/utilities-system-monitor.png"
            smooth: true
        }

        // 4. Version & copyright text block at x: 52, y: 99
        Column {
            x: 52
            y: 99
            width: parent.width - x - 16
            spacing: 0

            Text {
                text: i18n("Microsoft Windows")
                font.family: "Segoe UI"
                font.pixelSize: 12
                font.hintingPreference: Font.PreferFullHinting
                color: "#000000"
                renderType: Text.NativeRendering
            }

            Text {
                text: i18n("Version 6.1 (Build 7601: Service Pack 1) — KDE Plasma %1", KCoreAddons.AboutData.version)
                font.family: "Segoe UI"
                font.pixelSize: 12
                font.hintingPreference: Font.PreferFullHinting
                color: "#000000"
                renderType: Text.NativeRendering
            }

            Text {
                text: i18n("Copyright © 2009 Microsoft Corporation.  All rights reserved.")
                font.family: "Segoe UI"
                font.pixelSize: 12
                font.hintingPreference: Font.PreferFullHinting
                color: "#000000"
                renderType: Text.NativeRendering
            }

            Text {
                width: parent.width
                text: i18n("The Windows 7 Ultimate operating system and its user interface are protected by trademark and other pending or existing intellectual property rights in the United States and other countries.")
                wrapMode: Text.WordWrap
                font.family: "Segoe UI"
                font.pixelSize: 12
                font.hintingPreference: Font.PreferFullHinting
                color: "#000000"
                renderType: Text.NativeRendering
            }
        }

        // 5. License block at x: 52, y: 245
        Column {
            x: 52
            y: 245
            width: 334
            spacing: 4

            Text {
                width: parent.width
                text: i18n("This product is licensed under the <a href=\"https://www.kde.org\">Microsoft Software License Terms</a> to:")
                textFormat: Text.StyledText
                linkColor: "#0066cc"
                wrapMode: Text.WordWrap
                font.family: "Segoe UI"
                font.pixelSize: 12
                font.hintingPreference: Font.PreferFullHinting
                color: "#000000"
                renderType: Text.NativeRendering
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            Text {
                x: 16
                text: "siru"
                font.family: "Segoe UI"
                font.pixelSize: 12
                font.hintingPreference: Font.PreferFullHinting
                color: "#000000"
                renderType: Text.NativeRendering
            }
        }

        // 6. Bottom-right OK button (75x23, default + focus dotted rect, matching crop_dlg_about.png)
        Win7Button {
            id: okButton
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            width: 75
            height: 23
            text: i18n("OK")
            isDefault: true
            hasFocus: true
            onClicked: dialog.close()
        }
    }
}
