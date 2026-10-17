/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#pragma once

#include <QAbstractTableModel>
#include <QPointer>
#include <qqmlregistration.h>

// Keep backend changes out of the view until the shared update clock samples it.
class Win7SnapshotModel : public QAbstractTableModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QAbstractItemModel *sourceModel READ sourceModel WRITE setSourceModel NOTIFY sourceModelChanged)
    Q_PROPERTY(int keyRole MEMBER m_keyRole)
    Q_PROPERTY(bool initialUpdatesEnabled MEMBER m_initialUpdatesEnabled)

public:
    explicit Win7SnapshotModel(QObject *parent = nullptr);
    QAbstractItemModel *sourceModel() const;
    void setSourceModel(QAbstractItemModel *source);
    int rowCount(const QModelIndex &parent = {}) const override;
    int columnCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QVariant headerData(int section, Qt::Orientation orientation, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
    Q_INVOKABLE void refresh();
    Q_SIGNAL void sourceModelChanged();

private:
    using Cell = QHash<int, QVariant>;
    struct Row {
        QVariant key;
        QList<Cell> cells;
    };
    void scheduleInitialRefresh();

    QPointer<QAbstractItemModel> m_source;
    QList<QMetaObject::Connection> m_connections;
    QHash<int, QByteArray> m_roles;
    QList<Cell> m_headers;
    QList<Row> m_rows;
    int m_keyRole = Qt::UserRole;
    bool m_initialUpdatesEnabled = true;
    bool m_initialized = false;
    bool m_initialRefreshPending = false;
};
