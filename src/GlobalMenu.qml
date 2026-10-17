/*
 * SPDX-FileCopyrightText: 2021 Felipe Kinoshita <kinofhek@gmail.com>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import Qt.labs.platform as Labs

Labs.MenuBar {
    Labs.Menu {
        title: i18nc("@menu", "File")

        Labs.MenuItem {
            text: i18nc("@menu-action", "New Task (Run...)")
            onTriggered: app.openNewTaskDialog()
        }

        Labs.MenuSeparator { }

        Labs.MenuItem {
            text: i18nc("@menu-action", "Exit Task Manager")
            shortcut: StandardKey.Quit
            onTriggered: Qt.quit()
        }
    }

    Labs.Menu {
        title: i18nc("@menu", "Options")

        Labs.MenuItem {
            text: i18nc("@menu-action", "Always On Top")
            checkable: true
            checked: app.alwaysOnTop
            onTriggered: app.alwaysOnTop = !app.alwaysOnTop
        }

        Labs.MenuItem {
            text: i18nc("@menu-action", "Minimize On Use")
            checkable: true
            checked: app.minimizeOnUse
            onTriggered: app.minimizeOnUse = !app.minimizeOnUse
        }

        Labs.MenuItem {
            text: i18nc("@menu-action", "Hide When Minimized")
            checkable: true
            checked: app.hideWhenMinimized
            onTriggered: app.hideWhenMinimized = !app.hideWhenMinimized
        }
    }

    Labs.Menu {
        title: i18nc("@menu", "View")

        Labs.MenuItem {
            text: i18nc("@menu-action", "Refresh Now")
            shortcut: "F5"
            onTriggered: app.refreshCurrentTab()
        }
    }

    Labs.Menu {
        title: i18nc("@menu", "Help")

        Labs.MenuItem {
            text: i18nc("@menu-action", "About Task Manager")
            onTriggered: app.openAboutDialog()
        }
    }
}
