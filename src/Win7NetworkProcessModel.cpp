/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#include "Win7NetworkProcessModel.h"

#include <QDir>
#include <QLibraryInfo>
#include <QStandardPaths>
#include <QTime>
#include <QtConcurrentRun>

#include <algorithm>
#include <limits>
#include <optional>
#include <utility>

namespace
{
const QStringList columns = {QStringLiteral("name"), QStringLiteral("pid"), QStringLiteral("sendRate"), QStringLiteral("receiveRate"),
                             QStringLiteral("totalRate"), QStringLiteral("sentBytes"), QStringLiteral("receivedBytes"),
                             QStringLiteral("connections"), QStringLiteral("lastIp"), QStringLiteral("remotePort"), QStringLiteral("protocol")};

std::optional<qulonglong> number(const QByteArray &value)
{
    if (value.isEmpty() || !std::all_of(value.cbegin(), value.cend(), [](char c) { return c >= '0' && c <= '9'; })) {
        return {};
    }
    bool valid = false;
    const auto result = value.toULongLong(&valid);
    return valid ? std::optional<qulonglong>(result) : std::nullopt;
}

qulonglong addBytes(qulonglong a, qulonglong b)
{
    return b > std::numeric_limits<qulonglong>::max() - a ? std::numeric_limits<qulonglong>::max() : a + b;
}

bool sameProcess(const QVariantMap &a, const QVariantMap &b)
{
    return a.value(QStringLiteral("pid")) == b.value(QStringLiteral("pid")) && a.value(QStringLiteral("startTime")) == b.value(QStringLiteral("startTime"));
}
}

Win7NetworkProcessModel::Win7NetworkProcessModel(QObject *parent)
    : QAbstractListModel(parent)
{
    const QStringList paths = {QDir(QLibraryInfo::path(QLibraryInfo::LibrariesPath)).filePath(QStringLiteral("libexec/ksysguard")),
                               QStringLiteral("/usr/libexec/ksysguard"), QStringLiteral("/usr/lib/ksysguard"),
                               QStringLiteral("/usr/lib/libexec/ksysguard"), QStringLiteral("/usr/lib64/libexec/ksysguard")};
    auto helper = QStandardPaths::findExecutable(QStringLiteral("ksgrd_network_helper"), paths);
    if (helper.isEmpty()) {
        helper = QStandardPaths::findExecutable(QStringLiteral("ksgrd_network_helper"));
    }
    m_helper.setProgram(helper);
    connect(&m_helper, &QProcess::readyReadStandardOutput, this, [this] {
        while (m_helper.canReadLine()) {
            recordTrafficLine(m_helper.readLine());
        }
    });
    connect(&m_helper, &QProcess::readyReadStandardError, this, [this] { m_helper.readAllStandardError(); });
    connect(&m_helper, &QProcess::errorOccurred, this, [this] { m_helperFailed = true; });
    connect(&m_helper, &QProcess::finished, this, [this] { m_helperFailed = true; });
    m_scanTimer.setInterval(1000);
    connect(&m_scanTimer, &QTimer::timeout, this, &Win7NetworkProcessModel::startScan);
    connect(&m_scanWatcher, &QFutureWatcher<Win7NetworkScan>::finished, this, [this] {
        setConnectionSnapshot(m_scanWatcher.result());
        m_scanPending = false;
    });
}

Win7NetworkProcessModel::~Win7NetworkProcessModel()
{
    disconnect(&m_helper, nullptr, this, nullptr);
    if (m_helper.state() != QProcess::NotRunning) {
        m_helper.terminate();
        if (!m_helper.waitForFinished(1000)) {
            m_helper.kill();
            m_helper.waitForFinished(1000);
        }
    }
}

int Win7NetworkProcessModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant Win7NetworkProcessModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size()) {
        return {};
    }
    return role == ProcessRole ? QVariant(m_rows.at(index.row())) : role == Qt::DisplayRole ? m_rows.at(index.row()).value(QStringLiteral("name")) : QVariant{};
}

QHash<int, QByteArray> Win7NetworkProcessModel::roleNames() const
{
    return {{ProcessRole, "process"}};
}

bool Win7NetworkProcessModel::monitoring() const { return m_monitoring; }
QString Win7NetworkProcessModel::statusText() const { return m_statusText; }
int Win7NetworkProcessModel::revision() const { return m_revision; }
int Win7NetworkProcessModel::sortColumn() const { return m_sortColumn; }
Qt::SortOrder Win7NetworkProcessModel::sortOrder() const { return m_sortOrder; }

void Win7NetworkProcessModel::setMonitoring(bool monitoring)
{
    if (monitoring == m_monitoring) {
        return;
    }
    m_monitoring = monitoring;
    if (monitoring) {
        m_monitoringSinceMs = win7NetworkMonotonicMs();
        m_helperFailed = m_helper.program().isEmpty();
        if (!m_helperFailed) {
            m_helper.start();
        }
        startScan();
        m_scanTimer.start();
    } else {
        m_scanTimer.stop();
        m_helper.terminate();
        m_lastReportMs = 0;
    }
    Q_EMIT monitoringChanged();
}

void Win7NetworkProcessModel::startScan()
{
    if (!m_scanPending) {
        m_scanPending = true;
        m_scanWatcher.setFuture(QtConcurrent::run([] { return win7ScanNetworkProcesses(); }));
    }
}

void Win7NetworkProcessModel::setConnectionSnapshot(const Win7NetworkScan &scan)
{
    m_scan = scan;
}

void Win7NetworkProcessModel::recordTrafficLine(const QByteArray &line)
{
    const auto parts = line.trimmed().split('|');
    if ((parts.size() != 1 && parts.size() != 7) || !QTime::fromString(QString::fromLatin1(parts.first()), QStringLiteral("HH:mm:ss")).isValid()) {
        return;
    }
    std::optional<qulonglong> pid;
    std::optional<qulonglong> received;
    std::optional<qulonglong> sent;
    if (parts.size() == 7) {
        pid = number(parts.at(2));
        received = number(parts.at(4));
        sent = number(parts.at(6));
        if (parts.at(1) != "PID" || parts.at(3) != "IN" || parts.at(5) != "OUT" || !pid || !*pid
            || *pid > std::numeric_limits<int>::max() || !received || !sent) {
            return;
        }
    }
    const auto timestamp = QString::fromLatin1(parts.first());
    if (timestamp != m_timestamp) {
        m_timestamp = timestamp;
        for (auto &traffic : m_traffic) {
            traffic.receiveRate = 0;
            traffic.sendRate = 0;
        }
    }
    m_lastReportMs = win7NetworkMonotonicMs();
    m_helperFailed = false;
    if (!pid) {
        return;
    }
    auto &traffic = m_traffic[*pid];
    const auto start = m_scan.processes.value(*pid).startTime;
    if (start && traffic.startTime && start != traffic.startTime) {
        traffic = {};
    }
    if (start) {
        traffic.startTime = start;
    }
    traffic.observed = true;
    traffic.received = addBytes(traffic.received, *received);
    traffic.sent = addBytes(traffic.sent, *sent);
    traffic.receiveRate = addBytes(traffic.receiveRate, *received);
    traffic.sendRate = addBytes(traffic.sendRate, *sent);
    if (*received || *sent) {
        traffic.lastTrafficMs = m_lastReportMs;
    }
}

void Win7NetworkProcessModel::refresh()
{
    const qint64 now = win7NetworkMonotonicMs();
    const bool trafficAvailable = !m_helperFailed && m_lastReportMs && now - m_lastReportMs < 3500;
    if (trafficAvailable) {
        m_statusText = tr("TCP/UDP · Totals since monitoring started");
    } else if (m_helperFailed || (m_monitoring && (m_helper.state() == QProcess::NotRunning || now - m_monitoringSinceMs > 3500))) {
        m_statusText = tr("Traffic unavailable; readable connections are still shown.");
    } else {
        m_statusText = tr("Collecting per-process network activity…");
    }
    if (!m_scan.connectionsAvailable && !m_scan.processes.isEmpty()) {
        m_statusText = trafficAvailable ? tr("Connection details unavailable; traffic totals continue.") : tr("Traffic and connection details are unavailable.");
    }
    QList<QVariantMap> rows;
    for (const auto &process : std::as_const(m_scan.processes)) {
        auto &traffic = m_traffic[process.pid];
        if (traffic.startTime && traffic.startTime != process.startTime) {
            traffic = {};
        }
        traffic.startTime = process.startTime;
        traffic.observed = traffic.observed || trafficAvailable;
        if (!process.lastIp.isEmpty() && (traffic.lastIp.isEmpty() || process.lastActivityMs > traffic.lastActivityMs
                                        || (!process.lastActivityMs && traffic.lastTrafficMs > traffic.lastActivityMs))) {
            traffic.lastIp = process.lastIp;
            traffic.remotePort = process.remotePort;
            traffic.protocol = process.protocol;
            traffic.lastActivityMs = process.lastActivityMs ? process.lastActivityMs : traffic.lastTrafficMs;
        }
        if (!process.connections && (!traffic.lastTrafficMs || now - traffic.lastTrafficMs > 10000)) {
            continue;
        }
        const bool recentRates = trafficAvailable && now - m_lastReportMs < 2000;
        const qulonglong sendRate = recentRates ? traffic.sendRate : 0;
        const qulonglong receiveRate = recentRates ? traffic.receiveRate : 0;
        QVariantMap row{{QStringLiteral("name"), process.name}, {QStringLiteral("pid"), process.pid},
                        {QStringLiteral("startTime"), process.startTime},
                        {QStringLiteral("sendRate"), trafficAvailable ? QVariant::fromValue(sendRate) : QVariant{}},
                        {QStringLiteral("receiveRate"), trafficAvailable ? QVariant::fromValue(receiveRate) : QVariant{}},
                        {QStringLiteral("totalRate"), trafficAvailable ? QVariant::fromValue(addBytes(sendRate, receiveRate)) : QVariant{}},
                        {QStringLiteral("sentBytes"), traffic.observed ? QVariant::fromValue(traffic.sent) : QVariant{}},
                        {QStringLiteral("receivedBytes"), traffic.observed ? QVariant::fromValue(traffic.received) : QVariant{}},
                        {QStringLiteral("connections"), m_scan.connectionsAvailable ? QVariant(process.connections) : QVariant{}},
                        {QStringLiteral("lastIp"), traffic.lastIp}, {QStringLiteral("remotePort"), traffic.remotePort},
                        {QStringLiteral("protocol"), traffic.protocol}};
        rows.append(row);
    }
    for (auto it = m_traffic.begin(); it != m_traffic.end();) {
        // A traffic report can arrive before a newly started process appears
        // in the asynchronous scan. Keep it briefly so its first bytes survive.
        if (!m_scan.processes.contains(it.key()) && now - it->lastTrafficMs > 10000) {
            it = m_traffic.erase(it);
        } else {
            ++it;
        }
    }
    orderRows(rows);
    publish(rows);
}

void Win7NetworkProcessModel::orderRows(QList<QVariantMap> &rows) const
{
    const auto key = columns.at(m_sortColumn);
    std::sort(rows.begin(), rows.end(), [this, &key](const auto &a, const auto &b) {
        const auto left = a.value(key);
        const auto right = b.value(key);
        if (left.isValid() != right.isValid()) {
            return left.isValid();
        }
        int comparison = 0;
        if (m_sortColumn == 0 || m_sortColumn == 8 || m_sortColumn == 10) {
            comparison = QString::compare(left.toString(), right.toString(), Qt::CaseInsensitive);
        } else {
            comparison = left.toULongLong() < right.toULongLong() ? -1 : left.toULongLong() > right.toULongLong() ? 1 : 0;
        }
        return comparison ? (m_sortOrder == Qt::AscendingOrder ? comparison < 0 : comparison > 0)
                          : a.value(QStringLiteral("pid")).toLongLong() < b.value(QStringLiteral("pid")).toLongLong();
    });
}

void Win7NetworkProcessModel::publish(QList<QVariantMap> rows)
{
    for (int row = 0; row < rows.size(); ++row) {
        int existing = row;
        while (existing < m_rows.size() && !sameProcess(m_rows.at(existing), rows.at(row))) {
            ++existing;
        }
        if (existing == m_rows.size()) {
            beginInsertRows({}, row, row);
            m_rows.insert(row, rows.at(row));
            endInsertRows();
        } else {
            if (existing != row) {
                beginMoveRows({}, existing, existing, {}, row);
                m_rows.move(existing, row);
                endMoveRows();
            }
            m_rows[row] = rows.at(row);
        }
    }
    if (m_rows.size() > rows.size()) {
        beginRemoveRows({}, rows.size(), m_rows.size() - 1);
        m_rows.erase(m_rows.begin() + rows.size(), m_rows.end());
        endRemoveRows();
    }
    if (!m_rows.isEmpty()) {
        Q_EMIT dataChanged(index(0, 0), index(m_rows.size() - 1, 0));
    }
    ++m_revision;
    Q_EMIT refreshed();
}

void Win7NetworkProcessModel::sort(int column, Qt::SortOrder order)
{
    if (column < 0 || column >= columns.size()) {
        return;
    }
    m_sortColumn = column;
    m_sortOrder = order;
    auto rows = m_rows; // Sorting while paused must use the displayed snapshot.
    orderRows(rows);
    publish(rows);
}

QVariantMap Win7NetworkProcessModel::processForPid(qint64 pid) const
{
    for (const auto &row : m_rows) {
        if (row.value(QStringLiteral("pid")).toLongLong() == pid) {
            return row;
        }
    }
    return {};
}
