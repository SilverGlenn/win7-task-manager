/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#pragma once

#include <QObject>
#include <QVariant>
#include <qqmlregistration.h>

// These readings are latched by the same refresh cycle as the other Win7 views.
class Win7SystemStatistics : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariant handlesCount READ handlesCount NOTIFY countsChanged)
    Q_PROPERTY(QVariant threadsCount READ threadsCount NOTIFY countsChanged)

public:
    explicit Win7SystemStatistics(QObject *parent = nullptr);
    explicit Win7SystemStatistics(const QString &procRoot, QObject *parent = nullptr);

    QVariant handlesCount() const;
    QVariant threadsCount() const;
    Q_INVOKABLE void refresh();
    Q_SIGNAL void countsChanged();

private:
    QString m_procRoot;
    QVariant m_handlesCount;
    QVariant m_threadsCount;
};
