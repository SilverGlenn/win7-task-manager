/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick

Timer {
    property int updateInterval: 2000
    signal sampleRequested()
    signal refreshed()

    interval: Math.max(500, updateInterval)
    running: updateInterval > 0
    repeat: true
    onTriggered: refreshNow()

    function refreshNow() {
        sampleRequested()
        refreshed()
    }
}
