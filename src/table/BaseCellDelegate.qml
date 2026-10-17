/*
 * SPDX-FileCopyrightText: 2020 Arjen Hiemstra <ahiemstra@heimr.nl>
 *
 * SPDX-License-Identifier: LGPL-2.1-only OR LGPL-3.0-only OR LicenseRef-KDE-Accepted-LGPL
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml.Models

import org.kde.kirigami as Kirigami
import org.kde.ksysguard.table as Table

TreeViewDelegate
{
    id: root

    readonly property bool rowHovered: treeView.hoveredRow == row
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: selected ? Kirigami.Theme.Selection : Kirigami.Theme.View
    text: model.display

    // Important: Don't remove this until QTBUG-84858 is resolved properly.
    Accessible.role: Accessible.Cell

    rightPadding: Kirigami.Units.smallSpacing
    topPadding: Kirigami.Units.smallSpacing
    bottomPadding: Kirigami.Units.smallSpacing

    leftInset: 0
    bottomInset: 0
    rightInset: 0
    topInset: 0

    background: Rectangle {
        color: "#ffffff"

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            radius: 2
            visible: root.selected || root.rowHovered
            border.width: 1
            border.color: root.selected ? "#7da2ce" : "#b8d6fb"
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.selected ? "#dcebfc" : "#f2f7fe" }
                GradientStop { position: 1.0; color: root.selected ? "#c1dbfc" : "#e5f0fe" }
            }
        }
    }

    onHoveredChanged: {
        if (hovered) {
            treeView.hoveredRow = row
        } else if (treeView.hoveredRow == row) {
            treeView.hoveredRow = -1
        }
    }

    hoverEnabled: true
}
