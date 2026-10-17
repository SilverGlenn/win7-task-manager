/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

AbstractButton {
    id: control

    property bool isDefault: false
    property bool hasFocus: false
    property bool showShield: false
    property string mnemonicText: text

    readonly property bool defaultFrame: enabled && (isDefault || activeFocus || hasFocus)
    readonly property bool defaultRing: defaultFrame && !down

    implicitWidth: Math.max(75, contentRow.implicitWidth + 16)
    implicitHeight: 23

    // Do not inherit the host Qt Quick style's padding or background insets.
    leftPadding: 8
    rightPadding: 8
    topPadding: 3
    bottomPadding: 3
    leftInset: 0
    rightInset: 0
    topInset: 0
    bottomInset: 0

    font.family: "Segoe UI"
    font.pixelSize: 12
    font.styleName: "Regular"
    font.hintingPreference: Font.PreferFullHinting

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    function formatMnemonic(str) {
        if (!str) return ""
        const idx = str.indexOf("&")
        if (idx === -1 || idx === str.length - 1) {
            return str
        }
        const before = str.substring(0, idx)
        const ch = str.substring(idx + 1, idx + 2)
        const after = str.substring(idx + 2)
        return before + "<u>" + ch + "</u>" + after
    }

    background: Rectangle {
        // Three-pixel Aero corners and the one-pixel outer outline.
        radius: 3
        antialiasing: true
        color: {
            if (!control.enabled) return "#adb2b5"
            if (control.down) return "#2c628b"
            if (control.hovered || control.defaultFrame) return "#3c7fb1"
            return "#707070"
        }

        // The inner rim is shaded, rather than a solid white/cyan rectangle.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 2
            antialiasing: true
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: {
                        if (!control.enabled) return "#f4f4f4"
                        if (control.down) return "#9dbdd6"
                        if (control.defaultRing) return "#2fd4ff"
                        if (control.hovered) return "#fafdfe"
                        return "#fcfcfc"
                    }
                }
                GradientStop {
                    position: 1
                    color: {
                        if (!control.enabled) return "#f4f4f4"
                        if (control.down) return "#9dbdd6"
                        if (control.defaultRing) return "#24cffc"
                        if (control.hovered) return "#e8f5fc"
                        return "#f3f3f3"
                    }
                }
            }
        }

        // Default buttons have a second, softer blue line inside the cyan rim.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 1
            antialiasing: true
            visible: control.defaultRing
            gradient: Gradient {
                GradientStop { position: 0; color: "#93e7fd" }
                GradientStop { position: 1; color: "#71d6f7" }
            }
        }

        // A single rounded face keeps the glossy halfway transition aligned
        // while preserving all of the border pixels, including the corners.
        Rectangle {
            anchors.fill: parent
            anchors.margins: control.defaultRing ? 3 : 2
            radius: 1
            antialiasing: true
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: {
                        if (!control.enabled) return "#f4f4f4"
                        if (control.down) return "#e5f4fc"
                        if (control.hovered) return "#eaf6fd"
                        if (control.defaultRing) return "#ebf6fc"
                        return "#f2f2f2"
                    }
                }
                GradientStop {
                    position: 0.49
                    color: {
                        if (!control.enabled) return "#f4f4f4"
                        if (control.down) return "#c4e5f6"
                        if (control.hovered) return "#d9f0fc"
                        if (control.defaultRing) return "#e5f3fc"
                        return "#ebebeb"
                    }
                }
                GradientStop {
                    position: 0.5
                    color: {
                        if (!control.enabled) return "#f4f4f4"
                        if (control.down) return "#98d1ef"
                        if (control.hovered) return "#bee6fd"
                        if (control.defaultRing) return "#cae9fa"
                        return "#dddddd"
                    }
                }
                GradientStop {
                    position: 1
                    color: {
                        if (!control.enabled) return "#f4f4f4"
                        if (control.down) return "#6db6dd"
                        if (control.hovered) return "#a7d9f5"
                        if (control.defaultRing) return "#b6def4"
                        return "#cfcfcf"
                    }
                }
            }
        }

        // Classic Win7 dotted focus rectangle
        Canvas {
            anchors.fill: parent
            anchors.margins: 4
            visible: control.enabled && (control.visualFocus || control.hasFocus)
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onVisibleChanged: requestPaint()
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
    }

    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight

        Row {
            id: contentRow
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: control.down ? 1 : 0
            anchors.verticalCenterOffset: control.down ? 1 : 0
            spacing: 4

            // Authentic 16x16 Windows 7 UAC Shield icon (/usr/share/icons/Windows 7 Aero/status/16/gtk-dialog-authentication.png)
            Image {
                id: uacShieldImg
                width: 16
                height: 16
                visible: control.showShield && status === Image.Ready
                source: "file:///usr/share/icons/Windows 7 Aero/status/16/gtk-dialog-authentication.png"
                smooth: false
                anchors.verticalCenter: parent.verticalCenter
            }

            Kirigami.Icon {
                width: 16
                height: 16
                visible: control.showShield && !uacShieldImg.visible
                source: "gtk-dialog-authentication"
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: control.formatMnemonic(control.mnemonicText)
                textFormat: Text.StyledText
                font: control.font
                renderType: Text.NativeRendering
                color: control.enabled ? "#000000" : "#838383"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
