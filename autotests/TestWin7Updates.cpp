/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#include "../src/Win7SnapshotModel.h"

#include <QAbstractItemModelTester>
#include <QPersistentModelIndex>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSignalSpy>
#include <QStandardItemModel>
#include <QTest>

class TestWin7Updates : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void frozenValuesAndMembership()
    {
        QStandardItemModel source;
        source.setItemRoleNames({{Qt::UserRole, "pid"}, {Qt::UserRole + 1, "value"}});
        source.setColumnCount(1);
        source.setHeaderData(0, Qt::Horizontal, "usage", Qt::UserRole);
        auto *first = new QStandardItem;
        first->setData(101, Qt::UserRole);
        first->setData(12.5, Qt::UserRole + 1);
        source.appendRow(first);

        Win7SnapshotModel snapshot;
        QAbstractItemModelTester tester(&snapshot, QAbstractItemModelTester::FailureReportingMode::QtTest);
        snapshot.setSourceModel(&source);
        snapshot.refresh();
        QCOMPARE(snapshot.headerData(0, Qt::Horizontal, Qt::UserRole).toString(), "usage");
        QCOMPARE(snapshot.roleNames(), source.roleNames());
        const QPersistentModelIndex kept(snapshot.index(0, 0));

        first->setData(75.0, Qt::UserRole + 1);
        auto *second = new QStandardItem;
        second->setData(202, Qt::UserRole);
        source.insertRow(0, second);
        QCoreApplication::processEvents();
        QCOMPARE(snapshot.rowCount(), 1);
        QCOMPARE(snapshot.data(kept, Qt::UserRole + 1).toDouble(), 12.5);

        snapshot.refresh();
        QCOMPARE(snapshot.rowCount(), 2);
        QVERIFY(kept.isValid());
        QCOMPARE(kept.row(), 1);
        QCOMPARE(snapshot.data(kept, Qt::UserRole).toInt(), 101);
        QCOMPARE(snapshot.data(kept, Qt::UserRole + 1).toDouble(), 75.0);

        source.removeRow(0);
        QCOMPARE(snapshot.rowCount(), 2);
        snapshot.refresh();
        QCOMPARE(snapshot.rowCount(), 1);
        QCOMPARE(kept.row(), 0);
        QCOMPARE(snapshot.data(kept, Qt::UserRole).toInt(), 101);

        source.removeRow(0);
        snapshot.refresh();
        QCOMPARE(snapshot.rowCount(), 0);
        source.appendRow(new QStandardItem("later process"));
        QCoreApplication::processEvents();
        QCOMPARE(snapshot.rowCount(), 0); // Emptying the view must not re-enable startup sampling.
        snapshot.refresh();
        QCOMPARE(snapshot.rowCount(), 1);
    }

    void pausedDuringStartup()
    {
        QStandardItemModel source;
        Win7SnapshotModel snapshot;
        snapshot.setProperty("initialUpdatesEnabled", false);
        snapshot.setSourceModel(&source);
        source.appendRow(new QStandardItem("new process"));
        QCoreApplication::processEvents();
        QCOMPARE(snapshot.rowCount(), 0);
        snapshot.refresh(); // Refresh Now is allowed while automatic updates are paused.
        QCOMPARE(snapshot.rowCount(), 1);
        QCOMPARE(snapshot.data(snapshot.index(0, 0)).toString(), "new process");
    }

    void updateSpeeds_data()
    {
        QTest::addColumn<int>("milliseconds");
        QTest::newRow("High") << 500;
        QTest::newRow("Normal") << 2000;
        QTest::newRow("Low") << 4000;
    }

    void updateSpeeds()
    {
        QFETCH(int, milliseconds);
        QQmlEngine engine;
        QQmlComponent component(&engine, QUrl::fromLocalFile(QFINDTESTDATA("../src/Win7UpdateClock.qml")));
        QScopedPointer<QObject> clock(component.create());
        QVERIFY2(clock, qPrintable(component.errorString()));
        QCOMPARE(clock->property("updateInterval").toInt(), 2000);
        QSignalSpy sampled(clock.data(), SIGNAL(sampleRequested()));
        QSignalSpy refreshed(clock.data(), SIGNAL(refreshed()));
        clock->setProperty("updateInterval", milliseconds);
        QTest::qWait(milliseconds - 150);
        QCOMPARE(refreshed.count(), 0);
        QTRY_COMPARE_WITH_TIMEOUT(refreshed.count(), 1, 500);
        QCOMPARE(sampled.count(), refreshed.count());

        clock->setProperty("updateInterval", 0);
        QTest::qWait(600);
        QCOMPARE(refreshed.count(), 1);
        QVERIFY(QMetaObject::invokeMethod(clock.data(), "refreshNow"));
        QCOMPARE(refreshed.count(), 2);
        QCOMPARE(sampled.count(), 2);
        QVERIFY(!clock->property("running").toBool());

        clock->setProperty("updateInterval", 500);
        QTRY_COMPARE_WITH_TIMEOUT(refreshed.count(), 3, 1000);
    }
};

QTEST_MAIN(TestWin7Updates)
#include "TestWin7Updates.moc"
