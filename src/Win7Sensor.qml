/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick
import org.kde.ksysguard.sensors as Sensors

QtObject {
    id: root

    required property var updateController
    property string sensorId
    property bool enabled: true
    property var value
    property bool initialized: false

    function sample() {
        if (source.value !== undefined && source.value !== null) {
            value = source.value
            initialized = true
        }
    }

    property Sensors.Sensor source: Sensors.Sensor {
        sensorId: root.sensorId
        enabled: root.enabled
        onValueChanged: {
            if (!root.initialized && root.updateController && root.updateController.updateInterval > 0) {
                root.sample()
            }
        }
    }

    property Connections clockConnection: Connections {
        target: root.updateController
        function onSampleRequested() { root.sample() }
    }
}
