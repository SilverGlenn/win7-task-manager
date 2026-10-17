/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#include "Win7SnapshotModel.h"

#include <QTimer>
#include <utility>

Win7SnapshotModel::Win7SnapshotModel(QObject *parent)
    : QAbstractTableModel(parent)
{
}

QAbstractItemModel *Win7SnapshotModel::sourceModel() const
{
    return m_source;
}

void Win7SnapshotModel::setSourceModel(QAbstractItemModel *source)
{
    if (m_source == source) {
        return;
    }
    for (const auto &connection : std::as_const(m_connections)) {
        disconnect(connection);
    }
    m_connections.clear();
    beginResetModel();
    m_source = source;
    m_rows.clear();
    m_headers.clear();
    m_roles = source ? source->roleNames() : QHash<int, QByteArray>{};
    m_initialized = false;
    endResetModel();
    if (source) {
        m_connections = {
            connect(source, &QAbstractItemModel::modelReset, this, &Win7SnapshotModel::scheduleInitialRefresh),
            connect(source, &QAbstractItemModel::rowsInserted, this, &Win7SnapshotModel::scheduleInitialRefresh),
            connect(source, &QAbstractItemModel::columnsInserted, this, &Win7SnapshotModel::scheduleInitialRefresh),
            connect(source, &QAbstractItemModel::dataChanged, this, &Win7SnapshotModel::scheduleInitialRefresh),
            connect(source, &QAbstractItemModel::headerDataChanged, this, &Win7SnapshotModel::scheduleInitialRefresh),
        };
        scheduleInitialRefresh();
    }
    Q_EMIT sourceModelChanged();
}

int Win7SnapshotModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

int Win7SnapshotModel::columnCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_headers.size();
}

QVariant Win7SnapshotModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid)) {
        return {};
    }
    return m_rows.at(index.row()).cells.at(index.column()).value(role);
}

QVariant Win7SnapshotModel::headerData(int section, Qt::Orientation orientation, int role) const
{
    if (orientation == Qt::Horizontal && section >= 0 && section < m_headers.size()) {
        return m_headers.at(section).value(role);
    }
    return {};
}

QHash<int, QByteArray> Win7SnapshotModel::roleNames() const
{
    return m_roles;
}

void Win7SnapshotModel::scheduleInitialRefresh()
{
    if (m_initialized || m_initialRefreshPending || !m_initialUpdatesEnabled) {
        return;
    }
    m_initialRefreshPending = true;
    QTimer::singleShot(0, this, [this] {
        m_initialRefreshPending = false;
        if (!m_initialized && m_initialUpdatesEnabled) {
            refresh();
        }
    });
}

void Win7SnapshotModel::refresh()
{
    if (!m_source) {
        return;
    }
    const auto roles = m_source->roleNames();
    auto roleIds = roles.keys();
    for (const auto role : {Qt::DisplayRole, Qt::DecorationRole, Qt::ToolTipRole}) {
        if (!roleIds.contains(role)) {
            roleIds.append(role);
        }
    }
    QList<Cell> headers;
    QList<Row> rows;
    const int columns = m_source->columnCount();
    for (int column = 0; column < columns; ++column) {
        Cell header;
        for (int role : std::as_const(roleIds)) {
            header.insert(role, m_source->headerData(column, Qt::Horizontal, role));
        }
        headers.append(header);
    }
    for (int row = 0; row < m_source->rowCount(); ++row) {
        Row sample;
        sample.key = m_source->data(m_source->index(row, 0), m_keyRole);
        if (!sample.key.isValid()) {
            sample.key = row;
        }
        for (int column = 0; column < columns; ++column) {
            Cell cell;
            const auto index = m_source->index(row, column);
            for (int role : std::as_const(roleIds)) {
                cell.insert(role, m_source->data(index, role));
            }
            sample.cells.append(cell);
        }
        rows.append(sample);
    }
    m_initialized = m_initialized || (columns > 0 && !rows.isEmpty());
    if (headers != m_headers || roles != m_roles) {
        beginResetModel();
        m_roles = roles;
        m_headers = headers;
        m_rows = rows;
        endResetModel();
        return;
    }
    // Preserve persistent indexes and the viewport while processes appear, exit,
    // or change source order. Values and membership remain frozen between ticks.
    for (int row = 0; row < rows.size(); ++row) {
        int existing = row;
        while (existing < m_rows.size() && m_rows.at(existing).key != rows.at(row).key) {
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
    if (!m_rows.isEmpty() && columns > 0) {
        Q_EMIT dataChanged(index(0, 0), index(m_rows.size() - 1, columns - 1));
    }
}
