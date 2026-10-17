/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#pragma once

#include <QHash>
#include <QString>

struct Win7NetworkSocket {
    quint64 inode = 0;
    QString remoteIp;
    quint16 remotePort = 0;
    QString protocol;
    qint64 activityAgeMs = -1;
};

struct Win7NetworkProcessInfo {
    qint64 pid = 0;
    quint64 startTime = 0;
    QString name;
    int connections = 0;
    QString lastIp;
    quint16 remotePort = 0;
    QString protocol;
    qint64 lastActivityMs = 0;
};

struct Win7NetworkScan {
    QHash<qint64, Win7NetworkProcessInfo> processes;
    bool connectionsAvailable = false;
};

qint64 win7NetworkMonotonicMs();
QList<Win7NetworkSocket> win7ReadNetworkSockets(bool *available);
Win7NetworkProcessInfo win7ParseNetworkProcessStat(const QByteArray &stat);
Win7NetworkScan win7ScanNetworkProcesses(const QString &procRoot, const QList<Win7NetworkSocket> &sockets, bool connectionsAvailable);
Win7NetworkScan win7ScanNetworkProcesses();
