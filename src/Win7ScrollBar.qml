/* SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL */
import QtQuick
import QtQuick.Templates as T

T.ScrollBar {
    id: control
    implicitWidth: vertical ? 17 : 100
    implicitHeight: vertical ? 100 : 17
    leftPadding: vertical ? 1 : 17
    rightPadding: vertical ? 1 : 17
    topPadding: vertical ? 17 : 1
    bottomPadding: vertical ? 17 : 1
    minimumSize: Math.min(1, 17 / Math.max(17, vertical ? availableHeight : availableWidth))
    visible: policy === T.ScrollBar.AlwaysOn || (policy === T.ScrollBar.AsNeeded && size < 1)
    hoverEnabled: true

    background: Rectangle {
        color: "#f0f0f0"
        border.color: "#e2e2e2"
        gradient: Gradient {
            orientation: control.vertical ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: 0; color: "#f0f0f0" }
            GradientStop { position: 1; color: "#e9e9e9" }
        }
    }

    contentItem: Rectangle {
        radius: 2
        border.width: 1
        border.color: control.pressed ? "#3c7fb1" : thumbHover.hovered ? "#7d9fb1" : "#979797"
        gradient: Gradient {
            orientation: control.vertical ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: 0; color: control.pressed ? "#c4e5f6" : thumbHover.hovered ? "#eaf6fd" : "#f2f2f2" }
            GradientStop { position: 0.49; color: control.pressed ? "#98d1ef" : thumbHover.hovered ? "#d9f0fc" : "#e9e9e9" }
            GradientStop { position: 0.5; color: control.pressed ? "#87c6e9" : thumbHover.hovered ? "#bee6fd" : "#d8d8d8" }
            GradientStop { position: 1; color: control.pressed ? "#6db6dd" : thumbHover.hovered ? "#a7d9f5" : "#cfcfcf" }
        }
        HoverHandler { id: thumbHover }
        Canvas {
            anchors.centerIn: parent
            width: 8
            height: 8
            visible: parent.width >= 12 && parent.height >= 12
            property bool vertical: control.vertical
            onVerticalChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                for (var i = 0; i < 3; ++i) {
                    ctx.fillStyle = "#8c8c8c"
                    if (vertical) ctx.fillRect(1, 1 + i * 2, 6, 1)
                    else ctx.fillRect(1 + i * 2, 1, 1, 6)
                    ctx.fillStyle = "#ffffff"
                    if (vertical) ctx.fillRect(1, 2 + i * 2, 6, 1)
                    else ctx.fillRect(2 + i * 2, 1, 1, 6)
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 1
            color: "transparent"
            border.color: "#80ffffff"
        }
    }

    Repeater {
        model: 2
        Item {
            id: arrowButton
            parent: control
            z: 1
            required property int index
            x: control.vertical ? 0 : index * (control.width - 17)
            y: control.vertical ? index * (control.height - 17) : 0
            width: 17
            height: 17
            function step() { index === 0 ? control.decrease() : control.increase() }
            Rectangle {
                anchors.fill: parent
                radius: 2
                border.color: arrowMouse.pressed ? "#3c7fb1" : arrowMouse.containsMouse ? "#7d9fb1" : "#979797"
                gradient: Gradient {
                    GradientStop { position: 0; color: arrowMouse.pressed ? "#c4e5f6" : arrowMouse.containsMouse ? "#eaf6fd" : "#f2f2f2" }
                    GradientStop { position: 0.49; color: arrowMouse.pressed ? "#98d1ef" : arrowMouse.containsMouse ? "#d9f0fc" : "#e9e9e9" }
                    GradientStop { position: 0.5; color: arrowMouse.pressed ? "#87c6e9" : arrowMouse.containsMouse ? "#bee6fd" : "#d8d8d8" }
                    GradientStop { position: 1; color: arrowMouse.pressed ? "#6db6dd" : arrowMouse.containsMouse ? "#a7d9f5" : "#cfcfcf" }
                }
            }
            Canvas {
                anchors.centerIn: parent
                width: 7
                height: 7
                property bool vertical: control.vertical
                onVerticalChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.translate(3.5, 3.5)
                    if (!vertical) ctx.rotate(arrowButton.index === 0 ? -Math.PI / 2 : Math.PI / 2)
                    else if (arrowButton.index === 1) ctx.rotate(Math.PI)
                    ctx.fillStyle = "#333333"
                    ctx.beginPath()
                    ctx.moveTo(-3, 1.5)
                    ctx.lineTo(0, -1.5)
                    ctx.lineTo(3, 1.5)
                    ctx.closePath()
                    ctx.fill()
                }
            }
            MouseArea {
                id: arrowMouse
                anchors.fill: parent
                hoverEnabled: true
                onPressed: arrowButton.step()
                onPressAndHold: repeatTimer.start()
                onReleased: repeatTimer.stop()
                onCanceled: repeatTimer.stop()
            }
            Timer {
                id: repeatTimer
                interval: 80
                repeat: true
                onTriggered: if (arrowMouse.containsMouse) arrowButton.step()
            }
        }
    }
}
