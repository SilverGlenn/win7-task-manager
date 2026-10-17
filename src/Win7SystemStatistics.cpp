/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#include "Win7SystemStatistics.h"

#include <QDir>
#include <QFile>

#include <algorithm>
#include <optional>

namespace
{
std::optional<qulonglong> unsignedCount(const QByteArray &field)
{
    if (field.isEmpty() || !std::all_of(field.cbegin(), field.cend(), [](char c) {
            return c >= '0' && c <= '9';
        })) {
        return std::nullopt;
    }
    bool ok = false;
    const auto count = field.toULongLong(&ok);
    return ok ? std::optional<qulonglong>(count) : std::nullopt;
}

QByteArray readFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    // Procfs files often report size zero even though readAll() returns data.
    return file.readAll();
}

QVariant handlesFromFile(const QByteArray &data)
{
    const auto fields = data.simplified().split(' ');
    if (fields.size() != 3) {
        return {};
    }
    const auto allocated = unsignedCount(fields.at(0));
    const auto unused = unsignedCount(fields.at(1));
    const auto maximum = unsignedCount(fields.at(2));
    if (!allocated || !unused || !maximum || *unused > *allocated) {
        return {};
    }
    // Linux file handles are open file descriptions, not Windows object handles.
    return QVariant::fromValue(*allocated - *unused);
}

QVariant threadsFromFile(const QByteArray &data)
{
    const auto fields = data.simplified().split(' ');
    if (fields.size() != 5) {
        return {};
    }
    // The fourth loadavg field is runnable/total scheduling entities (threads).
    const auto counts = fields.at(3).split('/');
    if (counts.size() != 2 || !unsignedCount(counts.at(0))) {
        return {};
    }
    const auto total = unsignedCount(counts.at(1));
    return total ? QVariant::fromValue(*total) : QVariant{};
}
}

Win7SystemStatistics::Win7SystemStatistics(QObject *parent)
    : Win7SystemStatistics(QStringLiteral("/proc"), parent)
{
}

Win7SystemStatistics::Win7SystemStatistics(const QString &procRoot, QObject *parent)
    : QObject(parent)
    , m_procRoot(procRoot)
{
}

QVariant Win7SystemStatistics::handlesCount() const
{
    return m_handlesCount;
}

QVariant Win7SystemStatistics::threadsCount() const
{
    return m_threadsCount;
}

void Win7SystemStatistics::refresh()
{
    const QDir proc(m_procRoot);
    const auto handles = handlesFromFile(readFile(proc.filePath(QStringLiteral("sys/fs/file-nr"))));
    const auto threads = threadsFromFile(readFile(proc.filePath(QStringLiteral("loadavg"))));
    if (handles == m_handlesCount && threads == m_threadsCount) {
        return;
    }
    m_handlesCount = handles;
    m_threadsCount = threads;
    Q_EMIT countsChanged();
}
