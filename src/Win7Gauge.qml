/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import QtQuick

Item {
    id: root

    // Value in [0, 100]
    property real value: 0
    // Optional kernel percentage in [0, 100] (shown in red at the bottom when showKernelTimes is true)
    property real kernelValue: 0
    property bool showKernelTimes: false
    property string displayText: Math.round(value) + " %"

    implicitWidth: 72
    implicitHeight: 64

    onValueChanged: gaugeCanvas.requestPaint()
    onKernelValueChanged: gaugeCanvas.requestPaint()
    onShowKernelTimesChanged: gaugeCanvas.requestPaint()
    onDisplayTextChanged: gaugeCanvas.requestPaint()
    onWidthChanged: gaugeCanvas.requestPaint()
    onHeightChanged: gaugeCanvas.requestPaint()

    Canvas {
        id: gaugeCanvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            var w = Math.floor(width)
            var h = Math.floor(height)
            ctx.clearRect(0, 0, w, h)

            // 1. Sunken 2px 3D bevel exactly matching Win7 VM:
            // Outer top/left: #a0a0a0
            ctx.fillStyle = "#a0a0a0"
            ctx.fillRect(0, 0, w - 1, 1)
            ctx.fillRect(0, 0, 1, h - 1)

            // Inner top/left: #696969
            ctx.fillStyle = "#696969"
            ctx.fillRect(1, 1, w - 3, 1)
            ctx.fillRect(1, 1, 1, h - 3)

            // Outer bottom/right: #ffffff
            ctx.fillStyle = "#ffffff"
            ctx.fillRect(0, h - 1, w, 1)
            ctx.fillRect(w - 1, 0, 1, h)

            // Inner bottom/right: #e3e3e3
            ctx.fillStyle = "#e3e3e3"
            ctx.fillRect(1, h - 2, w - 2, 1)
            ctx.fillRect(w - 2, 1, 1, h - 2)

            // 2. Black interior (#000000)
            var ix = 2
            var iy = 2
            var iw = w - 4
            var ih = h - 4
            ctx.fillStyle = "#000000"
            ctx.fillRect(ix, iy, iw, ih)

            // 3. Dual LED bar columns centered horizontally:
            // In VM: total bar width = 33px (left col 16px, 1px gap, right col 16px)
            var barTotalW = 33
            var colW = 16
            var bx = ix + Math.floor((iw - barTotalW) / 2)
            var topPad = iy + 5
            var textAreaH = 18
            var availBarH = Math.max(12, ih - 5 - textAreaH)
            var numSegments = Math.max(4, Math.floor(availBarH / 3))
            var clampedVal = Math.max(0, Math.min(100, root.value))
            var clampedKernel = root.showKernelTimes ? Math.max(0, Math.min(clampedVal, root.kernelValue)) : 0

            var litSegments = Math.round((clampedVal / 100.0) * numSegments)
            if (clampedVal > 0 && litSegments === 0) {
                litSegments = 1
            }
            var kernelSegments = Math.round((clampedKernel / 100.0) * numSegments)

            for (var s = 0; s < numSegments; ++s) {
                // s = 0 is top segment, s = numSegments - 1 is bottom segment
                var segFromBottom = numSegments - 1 - s
                var sy = topPad + s * 3

                if (segFromBottom < litSegments) {
                    // Lit segment: solid #ff0000 (kernel) or #00ff00 (normal)
                    ctx.fillStyle = (root.showKernelTimes && segFromBottom < kernelSegments) ? "#ff0000" : "#00ff00"
                    ctx.fillRect(bx, sy, colW, 2)
                    ctx.fillRect(bx + colW + 1, sy, colW, 2)
                } else {
                    // Unlit segment: exact Win7 checkerboard dither (#008000 and #000000)
                    ctx.fillStyle = "#008000"
                    for (var dy = 0; dy < 2; ++dy) {
                        for (var dx = 0; dx < colW; ++dx) {
                            if ((dx + dy) % 2 === 0) {
                                ctx.fillRect(bx + dx, sy + dy, 1, 1)
                                ctx.fillRect(bx + colW + 1 + dx, sy + dy, 1, 1)
                            }
                        }
                    }
                }
            }

            // 4. Bottom readout text in #00ff00
            ctx.fillStyle = "#00ff00"
            ctx.font = "11px 'Segoe UI', sans-serif"
            ctx.textAlign = "center"
            ctx.textBaseline = "bottom"
            ctx.fillText(root.displayText, ix + Math.floor(iw / 2), iy + ih - 3)
        }
    }
}
