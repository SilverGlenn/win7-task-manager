/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick

Item {
    id: root

    // Latest primary sample in [0, 100]
    property real currentValue: 0
    // Latest secondary/kernel sample in [0, 100]
    property real secondaryValue: 0
    // Optional third series in [0, 100]
    property real tertiaryValue: 0

    property bool showSecondary: false
    property bool showTertiary: false

    property color primaryColor: "#00ff00"
    property color secondaryColor: "#ff0000"
    property color tertiaryColor: "#0080ff"
    property int primaryLineWidth: 1
    property int secondaryLineWidth: 1
    property int tertiaryLineWidth: 1

    property color gridColor: "#008040"
    property int gridSpacing: 12
    property int maxSamples: Math.max(200, Math.ceil(width / 2) + 1)
    property int updateInterval: 2000
    property bool running: true

    property var primaryHistory: []
    property var secondaryHistory: []
    property var tertiaryHistory: []
    property int gridScrollOffset: 0
    property bool seededWithLiveValue: false

    implicitWidth: 230
    implicitHeight: 64

    function seedIfNeeded() {
        if (!seededWithLiveValue && (root.currentValue > 0 || root.tertiaryValue > 0)) {
            seededWithLiveValue = true
            var p = Math.max(0, Math.min(100, isNaN(root.currentValue) ? 0 : root.currentValue))
            var s = Math.max(0, Math.min(100, isNaN(root.secondaryValue) ? 0 : root.secondaryValue))
            var t = Math.max(0, Math.min(100, isNaN(root.tertiaryValue) ? 0 : root.tertiaryValue))
            var pArr = []
            var sArr = []
            var tArr = []
            var sampleCount = Math.max(2, Math.ceil((root.width - 4) / 2) + 1)
            for (var i = 0; i < sampleCount; ++i) {
                pArr.push(p)
                sArr.push(s)
                tArr.push(t)
            }
            primaryHistory = pArr
            secondaryHistory = sArr
            tertiaryHistory = tArr
            graphCanvas.requestPaint()
        }
    }

    onCurrentValueChanged: seedIfNeeded()
    onTertiaryValueChanged: seedIfNeeded()

    function pushSample() {
        var p = Math.max(0, Math.min(100, isNaN(root.currentValue) ? 0 : root.currentValue))
        var s = Math.max(0, Math.min(100, isNaN(root.secondaryValue) ? 0 : root.secondaryValue))
        var t = Math.max(0, Math.min(100, isNaN(root.tertiaryValue) ? 0 : root.tertiaryValue))

        primaryHistory.push(p)
        secondaryHistory.push(s)
        tertiaryHistory.push(t)

        if (primaryHistory.length > maxSamples) {
            primaryHistory.shift()
            secondaryHistory.shift()
            tertiaryHistory.shift()
        }

        gridScrollOffset = (gridScrollOffset + 2) % gridSpacing
        graphCanvas.requestPaint()
    }

    function clearHistory() {
        primaryHistory = []
        secondaryHistory = []
        tertiaryHistory = []
        gridScrollOffset = 0
        graphCanvas.requestPaint()
    }

    Timer {
        id: sampleTimer
        interval: Math.max(250, root.updateInterval)
        running: root.running && root.updateInterval > 0 && root.visible
        repeat: true
        onTriggered: root.pushSample()
    }

    Component.onCompleted: {
        var sampleCount = Math.max(2, Math.ceil((root.width - 4) / 2) + 1)
        for (var i = 0; i < sampleCount; ++i) {
            primaryHistory.push(Math.max(0, Math.min(100, isNaN(root.currentValue) ? 0 : root.currentValue)))
            secondaryHistory.push(Math.max(0, Math.min(100, isNaN(root.secondaryValue) ? 0 : root.secondaryValue)))
            tertiaryHistory.push(Math.max(0, Math.min(100, isNaN(root.tertiaryValue) ? 0 : root.tertiaryValue)))
        }
        graphCanvas.requestPaint()
    }

    onShowSecondaryChanged: graphCanvas.requestPaint()
    onShowTertiaryChanged: graphCanvas.requestPaint()
    onWidthChanged: graphCanvas.requestPaint()
    onHeightChanged: graphCanvas.requestPaint()

    Canvas {
        id: graphCanvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            var w = Math.floor(width)
            var h = Math.floor(height)
            ctx.clearRect(0, 0, w, h)

            // 1. Sunken 2px 3D bevel matching Win7 Task Manager
            ctx.fillStyle = "#a0a0a0"
            ctx.fillRect(0, 0, w - 1, 1)
            ctx.fillRect(0, 0, 1, h - 1)

            ctx.fillStyle = "#696969"
            ctx.fillRect(1, 1, w - 3, 1)
            ctx.fillRect(1, 1, 1, h - 3)

            ctx.fillStyle = "#ffffff"
            ctx.fillRect(0, h - 1, w, 1)
            ctx.fillRect(w - 1, 0, 1, h)

            ctx.fillStyle = "#e3e3e3"
            ctx.fillRect(1, h - 2, w - 2, 1)
            ctx.fillRect(w - 2, 1, 1, h - 2)

            // 2. Black interior
            var ix = 2
            var iy = 2
            var iw = w - 4
            var ih = h - 4
            ctx.fillStyle = "#000000"
            ctx.fillRect(ix, iy, iw, ih)

            ctx.save()
            ctx.beginPath()
            ctx.rect(ix, iy, iw, ih)
            ctx.clip()

            // 3. Classic #008040 12px gridlines (scrolling left with gridScrollOffset)
            ctx.fillStyle = root.gridColor
            var step = root.gridSpacing
            for (var gy = iy + step - 1; gy < iy + ih; gy += step) {
                ctx.fillRect(ix, gy, iw, 1)
            }
            var startX = ix + step - 1 - root.gridScrollOffset
            if (startX < ix) {
                startX += step
            }
            for (var gx = startX; gx < ix + iw; gx += step) {
                ctx.fillRect(gx, iy, 1, ih)
            }

            function drawSeries(arr, strokeColor, lineWidthVal) {
                if (!arr || arr.length === 0) return
                ctx.strokeStyle = strokeColor
                ctx.lineWidth = lineWidthVal
                ctx.beginPath()

                var stepX = 2
                var pixelOffset = lineWidthVal % 2 === 1 ? 0.5 : 0
                var count = arr.length
                for (var i = 0; i < count; ++i) {
                    var idxFromRight = count - 1 - i
                    var px = (ix + iw - 1) - idxFromRight * stepX
                    if (px < ix - stepX) continue
                    var val = Math.max(0, Math.min(100, arr[i]))
                    var py = iy + ih - 1 - Math.round((val / 100.0) * (ih - 2))
                    if (i === 0 || px - stepX < ix - stepX) {
                        ctx.moveTo(px + pixelOffset, py + pixelOffset)
                    } else {
                        ctx.lineTo(px + pixelOffset, py + pixelOffset)
                    }
                }
                ctx.stroke()
            }

            if (root.showTertiary) {
                drawSeries(root.tertiaryHistory, root.tertiaryColor, root.tertiaryLineWidth)
            }
            if (root.showSecondary) {
                drawSeries(root.secondaryHistory, root.secondaryColor, root.secondaryLineWidth)
            }
            drawSeries(root.primaryHistory, root.primaryColor, root.primaryLineWidth)

            ctx.restore()
        }
    }
}
