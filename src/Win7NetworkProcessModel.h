/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#pragma once

#include "Win7NetworkConnections.h"

#include <QAbstractListModel>
#include <QFutureWatcher>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>
#include <qqmlregistration.h>

class Win7NetworkProcessModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool monitoring READ monitoring WRITE setMonitoring NOTIFY monitoringChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY refreshed)
    Q_PROPERTY(int revision READ revision NOTIFY refreshed)
    Q_PROPERTY(int sortColumn READ sortColumn NOTIFY refreshed)
    Q_PROPERTY(Qt::SortOrder sortOrder READ sortOrder NOTIFY refreshed)

public:
    enum Roles { ProcessRole = Qt::UserRole + 1 };
    Q_ENUM(Roles)
    explicit Win7NetworkProcessModel(QObject *parent = nullptr);
    ~Win7NetworkProcessModel() override;
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
    bool monitoring() const;
    void setMonitoring(bool monitoring);
    QString statusText() const;
    int revision() const;
    int sortColumn() const;
    Qt::SortOrder sortOrder() const;
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void sort(int column, Qt::SortOrder order) override;
    Q_INVOKABLE QVariantMap processForPid(qint64 pid) const;

    // Data ingestion is deliberately separate from publishing rows. A helper
    // report or completed background scan must never bypass Paused.
    void recordTrafficLine(const QByteArray &line);
    void setConnectionSnapshot(const Win7NetworkScan &scan);
    Q_SIGNAL void monitoringChanged();
    Q_SIGNAL void refreshed();

private:
    struct Traffic {
        quint64 startTime = 0;
        bool observed = false;
        qulonglong received = 0;
        qulonglong sent = 0;
        qulonglong receiveRate = 0;
        qulonglong sendRate = 0;
        qint64 lastTrafficMs = 0;
        qint64 lastActivityMs = 0;
        QString lastIp;
        quint16 remotePort = 0;
        QString protocol;
    };
    void startScan();
    void publish(QList<QVariantMap> rows);
    void orderRows(QList<QVariantMap> &rows) const;

    QProcess m_helper;
    QTimer m_scanTimer;
    QFutureWatcher<Win7NetworkScan> m_scanWatcher;
    Win7NetworkScan m_scan;
    QHash<qint64, Traffic> m_traffic;
    QList<QVariantMap> m_rows;
    QString m_timestamp;
    QString m_statusText;
    qint64 m_lastReportMs = 0;
    qint64 m_monitoringSinceMs = 0;
    bool m_monitoring = false;
    bool m_scanPending = false;
    bool m_helperFailed = false;
    int m_revision = 0;
    int m_sortColumn = 4;
    Qt::SortOrder m_sortOrder = Qt::DescendingOrder;
};
