/*
 * SPDX-FileCopyrightText: 2020 Arjen Hiemstra <ahiemstra@heimr.nl>
 *
 * SPDX-License-Identifier: LGPL-2.1-only OR LGPL-3.0-only OR LicenseRef-KDE-Accepted-LGPL
 */

#include "ProcessSortFilterModel.h"

#include <cmath>
#include <ranges>

#include <QDebug>

#include <processcore/process_data_model.h>

using namespace KSysGuard;

ProcessSortFilterModel::ProcessSortFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setSortRole(ProcessDataModel::Value);
    setSortCaseSensitivity(Qt::CaseInsensitive);
    setSortLocaleAware(false);

    setFilterRole(ProcessDataModel::Value);
    setFilterCaseSensitivity(Qt::CaseInsensitive);
    setRecursiveFilteringEnabled(true);
    setAutoAcceptChildRows(true);
}

void ProcessSortFilterModel::setSourceModel(QAbstractItemModel *newSourceModel)
{
    auto oldSourceModel = sourceModel();

    if (newSourceModel == oldSourceModel) {
        return;
    }

    if (oldSourceModel) {
        oldSourceModel->disconnect(this);
    }

    QSortFilterProxyModel::setSourceModel(newSourceModel);
    if (newSourceModel) {
        connect(newSourceModel, &QAbstractItemModel::modelReset, this, &ProcessSortFilterModel::findColumns);
        connect(newSourceModel, &QAbstractItemModel::columnsInserted, this, &ProcessSortFilterModel::findColumns);
        connect(newSourceModel, &QAbstractItemModel::columnsRemoved, this, &ProcessSortFilterModel::findColumns);
        connect(newSourceModel, &QAbstractItemModel::columnsMoved, this, &ProcessSortFilterModel::findColumns);
        findColumns();
    }
}

bool ProcessSortFilterModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    // not handled a reset yet, we'll invalidate at the end of modelReset anyway
    if (m_uidColumn == -1 && m_pidColumn == -1 && m_nameColumn == -1) {
        return false;
    }

    auto source = sourceModel();
    if (!source || sourceRow < 0 || sourceRow >= source->rowCount(sourceParent)) {
        return false;
    }
    const int srcColCount = source->columnCount(sourceParent);

    bool result = true;

    if (m_viewMode != ViewAll && m_uidColumn >= 0 && m_uidColumn < srcColCount) {
        const QModelIndex uidIdx = source->index(sourceRow, m_uidColumn, sourceParent);
        if (uidIdx.isValid()) {
            auto uid = source->data(uidIdx, ProcessDataModel::Value).toUInt();

            switch (m_viewMode) {
            case ViewOwn:
                result = m_currentUser.userId().nativeId() == uid;
                break;
            case ViewUser:
                result = uid >= 1000 && uid < 65534;
                break;
            case ViewSystem:
                result = uid < 1000 || uid >= 65534;
                break;
            default:
                break;
            }
        }
    }

    if (!m_filterPids.isEmpty() && m_pidColumn >= 0 && m_pidColumn < srcColCount) {
        const QModelIndex pidIdx = source->index(sourceRow, m_pidColumn, sourceParent);
        if (pidIdx.isValid()) {
            auto pid = source->data(pidIdx, ProcessDataModel::Value);
            result = m_filterPids.contains(pid);
        }
    }

    if (!result) {
        return false;
    }

    if (m_splitFilterStrings.empty()) {
        return true;
    }

    for (int sourceColumn : {m_nameColumn, m_commandColumn}) {
        if (sourceColumn < 0 || sourceColumn >= srcColCount || !filterAcceptsColumn(sourceColumn, sourceParent)) {
            continue;
        }
        const QModelIndex colIdx = source->index(sourceRow, sourceColumn, sourceParent);
        if (!colIdx.isValid()) {
            continue;
        }
        const auto columnData = source->data(colIdx, filterRole()).toString();
        for (auto string : m_splitFilterStrings) {
            if (columnData.contains(string, Qt::CaseInsensitive)) {
                return true;
            }
        }
    }

    return false;
}

bool ProcessSortFilterModel::filterAcceptsColumn(int sourceColumn, const QModelIndex &sourceParent) const
{
    Q_UNUSED(sourceParent)
    auto *source = sourceModel();
    if (!source || sourceColumn < 0 || sourceColumn >= source->columnCount()) {
        return false;
    }

    auto attribute = source->headerData(sourceColumn, Qt::Horizontal, ProcessDataModel::Attribute).toString();
    if (m_hiddenAttributes.contains(attribute)) {
        return false;
    }

    return true;
}

QString ProcessSortFilterModel::filterString() const
{
    return m_filterString;
}

void ProcessSortFilterModel::setFilterString(const QString &newFilterString)
{
    if (newFilterString == m_filterString) {
        return;
    }
    beginFilterChange();
    m_filterString = newFilterString;
    constexpr auto isNotEmpty = [](QStringView string) {
        return !string.isEmpty();
    };
    auto range =
        m_filterString.tokenize(u',', Qt::SkipEmptyParts) | std::views::transform(&QStringView::trimmed) | std::views::filter(isNotEmpty) | std::views::common;
    m_splitFilterStrings = std::vector<QStringView>(range.begin(), range.end());
    endFilterChange(QSortFilterProxyModel::Direction::Rows);
    Q_EMIT filterStringChanged();
}

ProcessSortFilterModel::ViewMode ProcessSortFilterModel::viewMode() const
{
    return m_viewMode;
}

void ProcessSortFilterModel::setViewMode(ViewMode newViewMode)
{
    if (newViewMode == m_viewMode) {
        return;
    }
    beginFilterChange();
    m_viewMode = newViewMode;
    endFilterChange(QSortFilterProxyModel::Direction::Rows);
    Q_EMIT viewModeChanged();
}

QStringList ProcessSortFilterModel::hiddenAttributes() const
{
    return m_hiddenAttributes;
}

void ProcessSortFilterModel::setHiddenAttributes(const QStringList &newHiddenAttributes)
{
    if (newHiddenAttributes == m_hiddenAttributes) {
        return;
    }
    beginFilterChange();
    m_hiddenAttributes = newHiddenAttributes;
    endFilterChange(QSortFilterProxyModel::Direction::Both);
    Q_EMIT hiddenAttributesChanged();
}

QVariantList ProcessSortFilterModel::filterPids() const
{
    return m_filterPids;
}

void ProcessSortFilterModel::setFilterPids(const QVariantList &newFilterPids)
{
    if (newFilterPids == m_filterPids) {
        return;
    }
    beginFilterChange();
    m_filterPids = newFilterPids;
    endFilterChange(QSortFilterProxyModel::Direction::Rows);
    Q_EMIT filterPidsChanged();
}

bool ProcessSortFilterModel::lessThan(const QModelIndex &source_left, const QModelIndex &source_right) const
{
    const auto *src = sourceModel();
    if (!src || !source_left.isValid() || !source_right.isValid()) {
        return source_left.row() < source_right.row();
    }

    const int srcColCount = src->columnCount();
    const int col = source_left.column();

    auto safeStringAt = [src, srcColCount, this](int row, int column, const QModelIndex &parent) -> QString {
        if (column < 0 || column >= srcColCount) {
            return QString();
        }
        const QModelIndex idx = src->index(row, column, parent);
        return idx.isValid() ? src->data(idx, sortRole()).toString() : QString();
    };

    auto safeLongLongAt = [src, srcColCount, this](int row, int column, const QModelIndex &parent) -> qlonglong {
        if (column < 0 || column >= srcColCount) {
            return 0;
        }
        const QModelIndex idx = src->index(row, column, parent);
        return idx.isValid() ? src->data(idx, sortRole()).toLongLong() : 0;
    };

    QVariant leftData = src->data(source_left, sortRole());
    QVariant rightData = src->data(source_right, sortRole());

    const QString attr = src->headerData(col, Qt::Horizontal, ProcessDataModel::Attribute).toString();
    const bool isStringColumn = (attr == QStringLiteral("name") || attr == QStringLiteral("username")
                                 || attr == QStringLiteral("command") || attr == QStringLiteral("status")
                                 || attr == QStringLiteral("cgroup") || attr == QStringLiteral("tty"));

    if (!isStringColumn) {
        double numL = leftData.toDouble();
        double numR = rightData.toDouble();
        if (std::isnan(numL)) {
            numL = 0.0;
        }
        if (std::isnan(numR)) {
            numR = 0.0;
        }
        if (numL != numR) {
            return numL < numR;
        }
        const QString nameL = safeStringAt(source_left.row(), m_nameColumn, source_left.parent());
        const QString nameR = safeStringAt(source_right.row(), m_nameColumn, source_right.parent());
        const int nameCmp = QString::compare(nameL, nameR, Qt::CaseInsensitive);
        if (nameCmp != 0) {
            return nameCmp < 0;
        }
    } else {
        QString strL = leftData.toString();
        QString strR = rightData.toString();
        if (col == m_commandColumn && m_nameColumn >= 0) {
            if (strL.isEmpty()) {
                strL = safeStringAt(source_left.row(), m_nameColumn, source_left.parent());
            }
            if (strR.isEmpty()) {
                strR = safeStringAt(source_right.row(), m_nameColumn, source_right.parent());
            }
        }
        const int strCmp = QString::compare(strL, strR, Qt::CaseInsensitive);
        if (strCmp != 0) {
            return strCmp < 0;
        }
    }

    const qlonglong pidL = safeLongLongAt(source_left.row(), m_pidColumn, source_left.parent());
    const qlonglong pidR = safeLongLongAt(source_right.row(), m_pidColumn, source_right.parent());
    if (pidL != pidR) {
        return pidL < pidR;
    }
    return source_left.row() < source_right.row();
}

void ProcessSortFilterModel::sort(int column, Qt::SortOrder order)
{
    const bool sameSort = (column == sortColumn() && order == sortOrder());
    QSortFilterProxyModel::sort(column, order);
    if (sameSort && column >= 0) {
        invalidate();
    }
    Q_EMIT sorted();
}

QVariant ProcessSortFilterModel::attributeValue(int row, const QString &attribute) const
{
    const auto *src = sourceModel();
    if (!src || row < 0 || row >= rowCount() || columnCount() <= 0) {
        return QVariant();
    }
    const int srcCol = m_sourceColumns.value(attribute, -1);
    if (srcCol < 0 || srcCol >= src->columnCount()) {
        return QVariant();
    }
    const QModelIndex proxyIdx = index(row, 0);
    if (!proxyIdx.isValid()) {
        return QVariant();
    }
    const QModelIndex srcIdx = mapToSource(proxyIdx);
    if (!srcIdx.isValid()) {
        return QVariant();
    }
    const QModelIndex cellIdx = src->index(srcIdx.row(), srcCol, srcIdx.parent());
    if (!cellIdx.isValid()) {
        return QVariant();
    }
    return src->data(cellIdx, ProcessDataModel::Value);
}

double ProcessSortFilterModel::attributeMaximum(int row, const QString &attribute) const
{
    const auto *src = sourceModel();
    if (!src || row < 0 || row >= rowCount() || columnCount() <= 0) {
        return 100.0;
    }
    const int srcCol = m_sourceColumns.value(attribute, -1);
    if (srcCol < 0 || srcCol >= src->columnCount()) {
        return 100.0;
    }
    const QModelIndex proxyIdx = index(row, 0);
    if (!proxyIdx.isValid()) {
        return 100.0;
    }
    const QModelIndex srcIdx = mapToSource(proxyIdx);
    if (!srcIdx.isValid()) {
        return 100.0;
    }
    const QModelIndex cellIdx = src->index(srcIdx.row(), srcCol, srcIdx.parent());
    if (!cellIdx.isValid()) {
        return 100.0;
    }
    const double maxVal = src->data(cellIdx, ProcessDataModel::Maximum).toDouble();
    return maxVal > 0.0 ? maxVal : 100.0;
}

QVariantMap ProcessSortFilterModel::columnMapping() const
{
    return m_columnMapping;
}

void ProcessSortFilterModel::findColumns()
{
    beginFilterChange();

    m_uidColumn = -1;
    m_pidColumn = -1;
    m_nameColumn = -1;
    m_commandColumn = -1;
    m_sourceColumns.clear();

    auto source = sourceModel();

    m_columnMapping.clear();

    if (source) {
        for (auto column = 0; column < source->columnCount(); ++column) {
            auto attribute = source->headerData(column, Qt::Horizontal, ProcessDataModel::Attribute).toString();
            m_sourceColumns.insert(attribute, column);

            if (attribute == QStringLiteral("uid")) {
                m_uidColumn = column;
            } else if (attribute == QStringLiteral("pid")) {
                m_pidColumn = column;
            } else if (attribute == QStringLiteral("name")) {
                m_nameColumn = column;
            } else if (attribute == QStringLiteral("command")) {
                m_commandColumn = column;
            }
        }
    }

    endFilterChange(QSortFilterProxyModel::Direction::Both);

    // This is done after the above to ensure that we get proper sorted column indices.
    for (auto column = 0; column < columnCount(); ++column) {
        auto attribute = headerData(column, Qt::Horizontal, ProcessDataModel::Attribute).toString();
        m_columnMapping.insert(attribute, column);
    }
    Q_EMIT columnMappingChanged();
}

#include "moc_ProcessSortFilterModel.cpp"
