/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import QtQuick.Templates as T

// Pixel-accurate Windows 7 (Aero) popup menu item.
//  - 22px tall rows, Segoe UI 9pt (12px) text starting 35px from the menu border
//  - optional "\t"-separated keyboard shortcut, right aligned 21px from the border
//  - 22x22 rounded check / radio box (#aecff7 border, #f4f6fa -> #edf2f7 fill)
//    with a navy (#0c12a1) check mark or bullet drawn in the gutter
//  - black submenu arrow 11px from the border
//  - rounded light-blue "hot" highlight, grey hot outline for disabled items
//  - disabled text in #6d6d6d (Win7 GrayText)
T.MenuItem {
    id: control

    // Draw a radio bullet instead of a check mark for mutually exclusive items
    // (e.g. Update Speed / CPU History submenus).
    property bool radio: false

    readonly property var textParts: String(text).split("\t")
    readonly property string labelText: textParts[0]
    readonly property string shortcutText: textParts.length > 1 ? textParts[1] : ""

    // Hide submenu entries whose Win7Menu has shown: false.
    visible: subMenu ? (subMenu.shown !== false) : true

    implicitWidth: visible
                   ? Math.ceil(leftPadding + labelMetrics.advanceWidth
                               + (shortcutText.length > 0 ? shortcutMetrics.advanceWidth : 0)
                               + rightPadding)
                   : 0
    implicitHeight: visible ? 22 : 0
    height: implicitHeight

    padding: 0
    leftPadding: 32
    rightPadding: 52
    spacing: 0

    font.family: "Segoe UI"
    font.pixelSize: 12

    TextMetrics {
        id: labelMetrics
        font: control.font
        text: control.labelText
    }
    TextMetrics {
        id: shortcutMetrics
        font: control.font
        text: control.shortcutText
    }

    readonly property color textColor: control.enabled ? "#000000" : "#6d6d6d"

    contentItem: Item {
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: control.labelText
            font: control.font
            color: control.textColor
            renderType: Text.NativeRendering
        }
    }

    // Shortcut text (e.g. "F5"), right aligned 18px from the item edge
    Text {
        visible: control.shortcutText.length > 0
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        text: control.shortcutText
        font: control.font
        color: control.textColor
        renderType: Text.NativeRendering
    }

    // 22x22 check / radio box in the gutter
    indicator: Item {
        x: 0
        y: 0
        width: 22
        height: 22
        visible: control.checkable && control.checked

        Rectangle {
            anchors.fill: parent
            radius: 3
            border.width: 1
            border.color: control.enabled ? "#aecff7" : "#d0d0d0"
            gradient: Gradient {
                GradientStop { position: 0.0; color: control.enabled ? "#f6f8fa" : "#f7f7f7" }
                GradientStop { position: 0.15; color: control.enabled ? "#f0f3f7" : "#f2f2f2" }
                GradientStop { position: 0.3; color: control.enabled ? "#edf2f7" : "#efefef" }
                GradientStop { position: 0.9; color: control.enabled ? "#edf2f7" : "#efefef" }
                GradientStop { position: 1.0; color: control.enabled ? "#f1f5fa" : "#f2f2f2" }
            }
        }

        Canvas {
            id: glyph
            anchors.fill: parent
            property bool isRadio: control.radio
            property bool isEnabled: control.enabled
            onIsRadioChanged: requestPaint()
            onIsEnabledChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var c = isEnabled ? "#0c12a1" : "#8d8d8d"
                if (isRadio) {
                    var g = ctx.createRadialGradient(10, 10, 0.5, 11, 11, 4)
                    g.addColorStop(0.0, isEnabled ? "#6f7cd8" : "#bdbdbd")
                    g.addColorStop(1.0, c)
                    ctx.fillStyle = g
                    ctx.beginPath()
                    ctx.arc(11, 11, 3.5, 0, Math.PI * 2)
                    ctx.fill()
                } else {
                    ctx.strokeStyle = c
                    ctx.lineWidth = 1.8
                    ctx.lineCap = "square"
                    ctx.lineJoin = "miter"
                    ctx.beginPath()
                    ctx.moveTo(7.5, 11.5)
                    ctx.lineTo(10, 14.5)
                    ctx.lineTo(15, 7.5)
                    ctx.stroke()
                }
            }
        }
    }

    // Black submenu arrow (4x7), 8px from the item edge
    arrow: Canvas {
        x: control.width - 12
        y: (control.height - 7) / 2
        width: 4
        height: 7
        visible: control.subMenu !== null
        property bool isEnabled: control.enabled
        onIsEnabledChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = isEnabled ? "#000000" : "#6d6d6d"
            ctx.beginPath()
            ctx.moveTo(0, 0)
            ctx.lineTo(4, 3.5)
            ctx.lineTo(0, 7)
            ctx.closePath()
            ctx.fill()
        }
    }

    // Rounded Aero "hot" highlight
    background: Item {
        implicitWidth: 120
        implicitHeight: 22

        Rectangle {
            anchors.fill: parent
            visible: control.highlighted
            radius: 3
            border.width: 1
            border.color: control.enabled ? "#aecff7" : "#d9d9d9"
            gradient: Gradient {
                GradientStop { position: 0.0; color: control.enabled ? "#f2f7fd" : "#f6f6f6" }
                GradientStop { position: 1.0; color: control.enabled ? "#dde9f8" : "#e9e9e9" }
            }

            // 1px inner white glow
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 2
                color: "transparent"
                border.width: 1
                border.color: "#80ffffff"
            }
        }
    }
}
