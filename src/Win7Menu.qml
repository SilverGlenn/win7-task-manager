/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import QtQuick.Templates as T
import QtQuick.Window

// Pixel-accurate Windows 7 (Aero) popup menu, measured from the VM reference
// screenshots (crop_menu_*.png / crop_ctx_*.png):
//   x=0      1px #979797 outer border
//   x=1..2   2px #f5f5f5 inner frame
//   x=3..28  #f1f1f1 icon/check gutter
//   x=29     1px #e2e3e3 gutter divider
//   x=30     1px #ffffff gutter highlight
//   rest     #f0f0f0 menu face
// plus a ~4px soft drop shadow on the right and bottom edges.
T.Menu {
    id: control

    // When false the submenu entry for this menu is hidden in its parent menu
    // (Win7 Task Manager only shows tab-specific submenus on their own tab).
    property bool shown: true

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    // Render inside the main window so the drop shadow can extend beyond the
    // menu bounds and so offscreen screenshot capture includes open menus.
    popupType: T.Popup.Item

    margins: 0
    padding: 3
    // Submenus overlap their parent menu by 3px like Win7.
    overlap: 3

    font.family: "Segoe UI"
    font.pixelSize: 12

    delegate: Win7MenuItem { }

    contentItem: ListView {
        implicitHeight: contentHeight
        implicitWidth: {
            // ListView does not report an implicit width; use the widest item.
            var w = 0
            for (var i = 0; i < control.count; ++i) {
                var it = control.itemAt(i)
                if (it && it.visible) {
                    w = Math.max(w, it.implicitWidth)
                }
            }
            return w
        }
        model: control.contentModel
        interactive: Window.window
                     ? contentHeight + control.topPadding + control.bottomPadding > control.height
                     : false
        clip: true
        currentIndex: control.currentIndex
        boundsBehavior: Flickable.StopAtBounds
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 90 }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 60 }
    }

    background: Item {
        implicitWidth: 120
        implicitHeight: 8

        // Soft drop shadow (right + bottom), alpha sampled from the VM:
        // #8e8e8e, #ababab, #d4d4d4, #f1f1f1 over white.
        Repeater {
            model: [0.44, 0.33, 0.17, 0.05]
            Item {
                required property int index
                required property real modelData
                anchors.fill: parent
                Rectangle {
                    x: parent.width + parent.index
                    y: 4 + parent.index
                    width: 1
                    height: parent.height - 4
                    color: "#000000"
                    opacity: parent.modelData
                }
                Rectangle {
                    x: 4 + parent.index
                    y: parent.height + parent.index
                    width: parent.width - 4
                    height: 1
                    color: "#000000"
                    opacity: parent.modelData
                }
            }
        }

        // Menu face + 1px outer border
        Rectangle {
            anchors.fill: parent
            color: "#f0f0f0"
            border.width: 1
            border.color: "#979797"
        }

        // 2px light inner frame
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            color: "transparent"
            border.width: 2
            border.color: "#f5f5f5"
        }

        // Icon / check gutter
        Rectangle {
            x: 3
            y: 3
            width: 26
            height: parent.height - 6
            color: "#f1f1f1"
        }
        Rectangle {
            x: 29
            y: 3
            width: 1
            height: parent.height - 6
            color: "#e2e3e3"
        }
        Rectangle {
            x: 30
            y: 3
            width: 1
            height: parent.height - 6
            color: "#ffffff"
        }
    }
}
