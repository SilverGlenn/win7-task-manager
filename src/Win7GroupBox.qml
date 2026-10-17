/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick

Item {
    id: root

    property string title: ""
    default property alias content: contentArea.data

    property int topPadding: 15
    property int leftPadding: 9
    property int rightPadding: 9
    property int bottomPadding: 8

    // Classic Win7 GroupBox border (#d5dfe5, 1px, 3px radius, top at y=7)
    Rectangle {
        id: borderRect
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 7
        anchors.bottom: parent.bottom
        color: "transparent"
        border.width: 1
        border.color: "#d5dfe5"
        radius: 3
    }

    // Title label cutting the top border at x=7..9
    Rectangle {
        visible: root.title.length > 0
        x: 7
        y: 0
        width: titleText.implicitWidth + 4
        height: titleText.implicitHeight
        color: "#ffffff"

        Text {
            id: titleText
            x: 2
            y: 0
            text: root.title
            font.family: "Segoe UI"
            font.pixelSize: 12
            color: "#000000"
        }
    }

    Item {
        id: contentArea
        anchors.fill: parent
        anchors.topMargin: root.topPadding
        anchors.leftMargin: root.leftPadding
        anchors.rightMargin: root.rightPadding
        anchors.bottomMargin: root.bottomPadding
    }
}
