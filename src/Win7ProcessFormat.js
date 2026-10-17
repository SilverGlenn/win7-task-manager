/* SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL */
.pragma library

function percentage(value, maximum) {
    if (value === null || value === undefined || !isFinite(Number(value))
            || !isFinite(Number(maximum)) || Number(maximum) <= 0) {
        return "—"
    }
    return Math.max(0, Math.min(100, Number(value) * 100 / Number(maximum))).toFixed(1) + "%"
}
