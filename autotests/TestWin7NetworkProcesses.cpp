/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#include "../src/Win7NetworkProcessModel.h"

#include <QAbstractItemModelTester>
#include <QDir>
#include <QFile>
#include <QPersistentModelIndex>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTest>

#ifdef Q_OS_LINUX
#include <unistd.h>
#endif

namespace
{
QByteArray processStat(qint64 pid, const QByteArray &name, quint64 start)
{
    QByteArray stat = QByteArray::number(pid) + " (" + name + ") S";
    for (int field = 4; field < 22; ++field) {
        stat += " 0";
    }
    return stat + ' ' + QByteArray::number(start) + '\n';
}

Win7NetworkScan sampleScan()
{
    Win7NetworkScan scan;
    scan.connectionsAvailable = true;
    scan.processes.insert(101, {101, 1000, QStringLiteral("browser"), 2, QStringLiteral("203.0.113.10"), 443, QStringLiteral("TCP"), win7NetworkMonotonicMs() - 200});
    scan.processes.insert(202, {202, 2000, QStringLiteral("downloader"), 1, QStringLiteral("2001:db8::20"), 80, QStringLiteral("TCP"), win7NetworkMonotonicMs() - 100});
    return scan;
}
}

class TestWin7NetworkProcesses : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void sampledRatesAndExactTotals()
    {
        Win7NetworkProcessModel model;
        QAbstractItemModelTester tester(&model, QAbstractItemModelTester::FailureReportingMode::QtTest);
        auto scan = sampleScan();
        model.setConnectionSnapshot(scan);
        model.recordTrafficLine("12:00:00|PID|101|IN|2000|OUT|500\n");
        model.recordTrafficLine("12:00:00|PID|202|IN|100|OUT|400\n");
        QCOMPARE(model.rowCount(), 0);
        model.refresh();
        QCOMPARE(model.rowCount(), 2);
        QCOMPARE(model.data(model.index(0, 0)).toString(), "browser");
        QCOMPARE(model.processForPid(101).value("totalRate").toULongLong(), 2500ULL);
        QCOMPARE(model.processForPid(101).value("sentBytes").toULongLong(), 500ULL);
        QCOMPARE(model.processForPid(101).value("lastIp").toString(), "203.0.113.10");
        const QPersistentModelIndex browser(model.index(0, 0));
        model.refresh(); // High-speed display refresh must not double-count a helper interval.
        QCOMPARE(model.processForPid(101).value("sentBytes").toULongLong(), 500ULL);

        model.recordTrafficLine("12:00:01|PID|202|IN|600|OUT|900\n");
        model.sort(2, Qt::DescendingOrder); // Sorting Paused rows must not pull newer traffic.
        QCOMPARE(model.processForPid(202).value("sentBytes").toULongLong(), 400ULL);
        QCOMPARE(model.data(model.index(0, 0)).toString(), "browser");
        model.refresh();
        QCOMPARE(model.data(model.index(0, 0)).toString(), "downloader");
        QCOMPARE(model.processForPid(101).value("sendRate").toULongLong(), 0ULL);
        QCOMPARE(model.processForPid(202).value("sendRate").toULongLong(), 900ULL);
        QCOMPARE(model.processForPid(202).value("sentBytes").toULongLong(), 1300ULL);
        QCOMPARE(browser.row(), 1);
        QCOMPARE(model.data(browser).toString(), "browser");

        model.recordTrafficLine("12:00:02\n");
        model.refresh();
        QCOMPARE(model.processForPid(202).value("totalRate").toULongLong(), 0ULL);
        QCOMPARE(model.processForPid(202).value("sentBytes").toULongLong(), 1300ULL);
        scan.processes[101].connections = 0;
        scan.processes[101].lastIp.clear();
        model.setConnectionSnapshot(scan);
        model.refresh();
        QCOMPARE(model.processForPid(101).value("lastIp").toString(), "203.0.113.10");

        scan.processes.remove(101);
        model.setConnectionSnapshot(scan);
        QCOMPARE(model.rowCount(), 2);
        model.refresh();
        QCOMPARE(model.rowCount(), 1);
        QVERIFY(!browser.isValid());
        scan.processes[202].startTime = 9999;
        model.setConnectionSnapshot(scan);
        model.recordTrafficLine("12:00:03|PID|202|IN|10|OUT|20\n");
        model.refresh();
        QCOMPARE(model.processForPid(202).value("sentBytes").toULongLong(), 20ULL);
        QCOMPARE(model.processForPid(202).value("receivedBytes").toULongLong(), 10ULL);

        model.recordTrafficLine("12:00:04|PID|303|IN|50|OUT|75\n");
        model.refresh(); // A report may precede the background scan's new PID.
        QVERIFY(model.processForPid(303).isEmpty());
        Win7NetworkProcessInfo newProcess;
        newProcess.pid = 303;
        newProcess.startTime = 3000;
        newProcess.name = QStringLiteral("new-process");
        newProcess.connections = 1;
        scan.processes.insert(303, newProcess);
        model.setConnectionSnapshot(scan);
        model.refresh();
        QCOMPARE(model.processForPid(303).value("sentBytes").toULongLong(), 75ULL);
        QCOMPARE(model.processForPid(303).value("receivedBytes").toULongLong(), 50ULL);
    }

    void unavailableAndMalformedTraffic()
    {
        Win7NetworkProcessModel model;
        auto scan = sampleScan();
        scan.connectionsAvailable = false;
        model.setConnectionSnapshot(scan);
        for (const auto &line : {"invalid", "12:00:00|PID|-1|IN|30|OUT|40", "12:00:00|PID|101|IN|18446744073709551616|OUT|40",
                                 "12:00:00|PID|101|OUT|30|IN|40"}) {
            model.recordTrafficLine(line);
        }
        model.refresh();
        QVERIFY(!model.processForPid(101).value("sendRate").isValid());
        QVERIFY(!model.processForPid(101).value("sentBytes").isValid());
        QVERIFY(!model.processForPid(101).value("connections").isValid());
        model.recordTrafficLine("23:59:59|PID|101|IN|4294967297|OUT|1234567890123");
        model.refresh();
        QCOMPARE(model.processForPid(101).value("receivedBytes").toULongLong(), 4294967297ULL);
        QCOMPARE(model.processForPid(101).value("sentBytes").toULongLong(), 1234567890123ULL);
        model.recordTrafficLine("00:00:00");
        model.refresh();
        QVERIFY(model.processForPid(101).value("sendRate").isValid());
        QCOMPARE(model.processForPid(101).value("sendRate").toULongLong(), 0ULL);
    }

    void processIdentityAndPeerAttribution()
    {
#ifdef Q_OS_LINUX
        const auto stat = processStat(101, "name with ) and ( spaces", 123456789ULL);
        const auto parsed = win7ParseNetworkProcessStat(stat);
        QCOMPARE(parsed.name, "name with ) and ( spaces");
        QCOMPARE(parsed.startTime, 123456789ULL);
        QVERIFY(!win7ParseNetworkProcessStat("101 (bad) S 1").pid);
        QTemporaryDir proc;
        QVERIFY(proc.isValid());
        QVERIFY(QDir().mkpath(proc.path() + "/101/fd"));
        QFile file(proc.path() + "/101/stat");
        QVERIFY(file.open(QIODevice::WriteOnly));
        QCOMPARE(file.write(stat), stat.size());
        file.close();
        QVERIFY(symlink("socket:[10]", QFile::encodeName(proc.path() + "/101/fd/3").constData()) == 0);
        QVERIFY(symlink("socket:[20]", QFile::encodeName(proc.path() + "/101/fd/4").constData()) == 0);
        QVERIFY(symlink("socket:[20]", QFile::encodeName(proc.path() + "/101/fd/5").constData()) == 0);
        QList<Win7NetworkSocket> sockets{{10, "203.0.113.10", 80, "TCP", 1000}, {20, "2001:db8::20", 443, "TCP", 10}};
        auto scan = win7ScanNetworkProcesses(proc.path(), sockets, true);
        QCOMPARE(scan.processes.value(101).connections, 2); // dup() does not create a second connection.
        QCOMPARE(scan.processes.value(101).lastIp, "2001:db8::20");
        QCOMPARE(scan.processes.value(101).remotePort, 443);
        sockets[0].protocol = "UDP";
        sockets[0].activityAgeMs = -1;
        sockets[1].protocol = "UDP";
        sockets[1].activityAgeMs = -1;
        scan = win7ScanNetworkProcesses(proc.path(), sockets, true);
        QVERIFY(scan.processes.value(101).lastIp.isEmpty()); // Do not invent a last UDP destination.
        sockets.removeLast();
        scan = win7ScanNetworkProcesses(proc.path(), sockets, true);
        QCOMPARE(scan.processes.value(101).lastIp, "203.0.113.10");
#endif
    }

    void liveLoopback_data()
    {
        QTest::addColumn<bool>("ipv6");
        QTest::newRow("IPv4") << false;
        QTest::newRow("IPv6") << true;
    }

    void liveLoopback()
    {
#ifdef Q_OS_LINUX
        QFETCH(bool, ipv6);
        QTcpServer server;
        const auto host = ipv6 ? QHostAddress::LocalHostIPv6 : QHostAddress::LocalHost;
        if (!server.listen(host, 0)) {
            QSKIP("Loopback networking is unavailable in this environment");
        }
        QTcpSocket client;
        client.connectToHost(host, server.serverPort());
        QVERIFY(client.waitForConnected(1000));
        QVERIFY(server.waitForNewConnection(1000));
        const QScopedPointer<QTcpSocket> accepted(server.nextPendingConnection());
        bool available = false;
        const auto sockets = win7ReadNetworkSockets(&available);
        if (sockets.isEmpty() && !available) {
            QSKIP("Kernel socket diagnostics are unavailable in this environment");
        }
        bool found = false;
        for (const auto &socket : sockets) {
            if (socket.remotePort == server.serverPort() && socket.remoteIp == QHostAddress(host).toString()) {
                found = true;
                QVERIFY(socket.activityAgeMs >= 0);
                const auto scan = win7ScanNetworkProcesses(QStringLiteral("/proc"), sockets, available);
                QVERIFY(scan.processes.contains(QCoreApplication::applicationPid()));
                QVERIFY(scan.processes.value(QCoreApplication::applicationPid()).connections >= 2);
                break;
            }
        }
        QVERIFY(found);
#endif
    }
};

QTEST_MAIN(TestWin7NetworkProcesses)
#include "TestWin7NetworkProcesses.moc"
