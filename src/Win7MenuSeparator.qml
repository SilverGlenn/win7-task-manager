/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import QtQuick.Templates as T

// Windows 7 popup menu separator: 8px tall, an etched #e0e0e0 / #ffffff line
// pair starting right after the icon gutter (x=28 inside the menu padding).
T.MenuSeparator {
    id: control

    implicitWidth: 60
    implicitHeight: visible ? 8 : 0
    height: implicitHeight
    padding: 0

    contentItem: Item {
        Rectangle {
            x: 28
            y: 4
            width: parent.width - 28
            height: 1
            color: "#e0e0e0"
        }
        Rectangle {
            x: 28
            y: 5
            width: parent.width - 28
            height: 1
            color: "#ffffff"
        }
    }
}
