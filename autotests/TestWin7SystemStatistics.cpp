/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#include "../src/Win7SystemStatistics.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

namespace
{
bool writeFile(const QString &root, const QString &name, const QByteArray &data)
{
    const auto path = QDir(root).filePath(name);
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) {
        return false;
    }
    QFile file(path);
    return file.open(QIODevice::WriteOnly | QIODevice::Truncate) && file.write(data) == data.size();
}
}

class TestWin7SystemStatistics : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void handles_data()
    {
        QTest::addColumn<QByteArray>("input");
        QTest::addColumn<QVariant>("expected");
        QTest::newRow("in-use") << QByteArray("9345\t54\t9223372036854775807\n") << QVariant::fromValue(9291ULL);
        QTest::newRow("zero") << QByteArray("0 0 100000\n") << QVariant::fromValue(0ULL);
        QTest::newRow("64-bit") << QByteArray("1234567890123 123 9223372036854775807\n") << QVariant::fromValue(1234567890000ULL);
        QTest::newRow("whitespace") << QByteArray(" \t1234  0\t9999 \n") << QVariant::fromValue(1234ULL);
        QTest::newRow("empty") << QByteArray() << QVariant();
        QTest::newRow("missing-field") << QByteArray("1234 0") << QVariant();
        QTest::newRow("negative") << QByteArray("-1 0 9999") << QVariant();
        QTest::newRow("underflow") << QByteArray("2 3 9999") << QVariant();
        QTest::newRow("overflow") << QByteArray("18446744073709551616 0 9999") << QVariant();
        QTest::newRow("invalid-unused") << QByteArray("1234 unknown 9999") << QVariant();
        QTest::newRow("invalid-maximum") << QByteArray("1234 0 unknown") << QVariant();
    }

    void handles()
    {
        QFETCH(QByteArray, input);
        QFETCH(QVariant, expected);
        QTemporaryDir proc;
        QVERIFY(proc.isValid());
        QVERIFY(writeFile(proc.path(), QStringLiteral("sys/fs/file-nr"), input));
        Win7SystemStatistics statistics(proc.path());
        statistics.refresh();
        QCOMPARE(statistics.handlesCount(), expected);
        QVERIFY(!statistics.threadsCount().isValid());
    }

    void threads_data()
    {
        QTest::addColumn<QByteArray>("input");
        QTest::addColumn<QVariant>("expected");
        QTest::newRow("total-not-runnable-or-pid") << QByteArray("1.58 1.23 1.62 3/2337 9999\n") << QVariant::fromValue(2337ULL);
        QTest::newRow("whitespace") << QByteArray(" 0.00\t0.10 0.20  1/4000  123\n") << QVariant::fromValue(4000ULL);
        QTest::newRow("64-bit") << QByteArray("0.00 0.00 0.00 1/4294967297 123\n") << QVariant::fromValue(4294967297ULL);
        QTest::newRow("empty") << QByteArray() << QVariant();
        QTest::newRow("missing-field") << QByteArray("0.00 0.00 0.00") << QVariant();
        QTest::newRow("missing-total") << QByteArray("0.00 0.00 0.00 1/ 123") << QVariant();
        QTest::newRow("extra-separator") << QByteArray("0.00 0.00 0.00 1/2/3 123") << QVariant();
        QTest::newRow("negative") << QByteArray("0.00 0.00 0.00 1/-2 123") << QVariant();
        QTest::newRow("overflow") << QByteArray("0.00 0.00 0.00 1/18446744073709551616 123") << QVariant();
        QTest::newRow("invalid-runnable") << QByteArray("0.00 0.00 0.00 bad/1234 123") << QVariant();
    }

    void threads()
    {
        QFETCH(QByteArray, input);
        QFETCH(QVariant, expected);
        QTemporaryDir proc;
        QVERIFY(proc.isValid());
        QVERIFY(writeFile(proc.path(), QStringLiteral("loadavg"), input));
        Win7SystemStatistics statistics(proc.path());
        statistics.refresh();
        QCOMPARE(statistics.threadsCount(), expected);
        QVERIFY(!statistics.handlesCount().isValid());
    }

    void sampledValuesAndRecovery()
    {
        QTemporaryDir proc;
        QVERIFY(proc.isValid());
        Win7SystemStatistics statistics(proc.path());
        QSignalSpy changed(&statistics, &Win7SystemStatistics::countsChanged);
        statistics.refresh();
        QVERIFY(!statistics.handlesCount().isValid());
        QVERIFY(!statistics.threadsCount().isValid());
        QCOMPARE(changed.count(), 0);

        QVERIFY(writeFile(proc.path(), QStringLiteral("sys/fs/file-nr"), "800 10 9999\n"));
        QVERIFY(writeFile(proc.path(), QStringLiteral("loadavg"), "0.1 0.2 0.3 1/2000 123\n"));
        statistics.refresh();
        QCOMPARE(statistics.handlesCount().toULongLong(), 790ULL);
        QCOMPARE(statistics.threadsCount().toULongLong(), 2000ULL);
        QCOMPARE(changed.count(), 1);
        statistics.refresh();
        QCOMPARE(changed.count(), 1);

        QVERIFY(writeFile(proc.path(), QStringLiteral("sys/fs/file-nr"), "900 0 9999\n"));
        QVERIFY(writeFile(proc.path(), QStringLiteral("loadavg"), "0.1 0.2 0.3 4/2500 456\n"));
        QCoreApplication::processEvents(); // Backend changes cannot bypass the refresh clock.
        QCOMPARE(statistics.handlesCount().toULongLong(), 790ULL);
        QCOMPARE(statistics.threadsCount().toULongLong(), 2000ULL);
        statistics.refresh(); // Also represents F5 while the shared clock is paused.
        QCOMPARE(statistics.handlesCount().toULongLong(), 900ULL);
        QCOMPARE(statistics.threadsCount().toULongLong(), 2500ULL);
        QCOMPARE(changed.count(), 2);

        QVERIFY(QFile::remove(QDir(proc.path()).filePath(QStringLiteral("sys/fs/file-nr"))));
        statistics.refresh();
        QVERIFY(!statistics.handlesCount().isValid());
        QCOMPARE(statistics.threadsCount().toULongLong(), 2500ULL);

        QVERIFY(writeFile(proc.path(), QStringLiteral("sys/fs/file-nr"), "1000 0 9999\n"));
        QVERIFY(writeFile(proc.path(), QStringLiteral("loadavg"), "invalid\n"));
        statistics.refresh();
        QCOMPARE(statistics.handlesCount().toULongLong(), 1000ULL);
        QVERIFY(!statistics.threadsCount().isValid());
        QVERIFY(writeFile(proc.path(), QStringLiteral("loadavg"), "0.1 0.2 0.3 2/2600 789\n"));
        statistics.refresh();
        QCOMPARE(statistics.threadsCount().toULongLong(), 2600ULL);
    }
};

QTEST_GUILESS_MAIN(TestWin7SystemStatistics)
#include "TestWin7SystemStatistics.moc"
