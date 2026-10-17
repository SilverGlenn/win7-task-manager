/*
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#include "Win7NetworkConnections.h"

#include <QDir>
#include <QFile>
#include <QSet>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstring>

#ifdef Q_OS_LINUX
#include <arpa/inet.h>
#include <linux/inet_diag.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/sock_diag.h>
#include <linux/tcp.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

qint64 win7NetworkMonotonicMs()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

QList<Win7NetworkSocket> win7ReadNetworkSockets(bool *available)
{
    QList<Win7NetworkSocket> result;
    *available = false;
#ifdef Q_OS_LINUX
    const int fd = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC, NETLINK_SOCK_DIAG);
    if (fd < 0) {
        return result;
    }
    const timeval timeout{0, 200000};
    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) < 0) {
        close(fd);
        return result;
    }
    sockaddr_nl address{};
    address.nl_family = AF_NETLINK;
    if (bind(fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) < 0) {
        close(fd);
        return result;
    }
    quint32 sequence = 0;
    int completeDumps = 0;
    for (int family : {AF_INET, AF_INET6}) {
        for (int protocol : {IPPROTO_TCP, IPPROTO_UDP}) {
            struct Request {
                nlmsghdr header;
                inet_diag_req_v2 request;
            } request{};
            request.header.nlmsg_len = NLMSG_LENGTH(sizeof(request.request));
            request.header.nlmsg_type = SOCK_DIAG_BY_FAMILY;
            request.header.nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
            request.header.nlmsg_seq = ++sequence;
            request.request.sdiag_family = family;
            request.request.sdiag_protocol = protocol;
            request.request.idiag_states = ~0U;
            request.request.idiag_ext = protocol == IPPROTO_TCP ? 1 << (INET_DIAG_INFO - 1) : 0;
            sockaddr_nl kernel{};
            kernel.nl_family = AF_NETLINK;
            if (sendto(fd, &request, request.header.nlmsg_len, 0, reinterpret_cast<sockaddr *>(&kernel), sizeof(kernel)) < 0) {
                continue;
            }
            bool complete = false;
            while (!complete) {
                alignas(nlmsghdr) std::array<char, 65536> buffer;
                sockaddr_nl sender{};
                socklen_t senderSize = sizeof(sender);
                const auto received = recvfrom(fd, buffer.data(), buffer.size(), 0, reinterpret_cast<sockaddr *>(&sender), &senderSize);
                if (received <= 0) {
                    break;
                }
                if (sender.nl_pid != 0) {
                    continue;
                }
                int remaining = received;
                for (auto *header = reinterpret_cast<nlmsghdr *>(buffer.data()); NLMSG_OK(header, remaining); header = NLMSG_NEXT(header, remaining)) {
                    if (header->nlmsg_seq != sequence) {
                        continue;
                    }
                    if (header->nlmsg_type == NLMSG_DONE) {
                        if (!(header->nlmsg_flags & NLM_F_DUMP_INTR)) {
                            ++completeDumps;
                        }
                        complete = true;
                        break;
                    }
                    if (header->nlmsg_type == NLMSG_ERROR) {
                        complete = true;
                        break;
                    }
                    if (header->nlmsg_len < NLMSG_LENGTH(sizeof(inet_diag_msg))) {
                        continue;
                    }
                    const auto *message = reinterpret_cast<const inet_diag_msg *>(NLMSG_DATA(header));
                    if (!message->idiag_inode || !message->id.idiag_dport) {
                        continue; // Listening, unconnected, or ownerless sockets.
                    }
                    std::array<char, INET6_ADDRSTRLEN> ip{};
                    if (!inet_ntop(family, message->id.idiag_dst, ip.data(), ip.size())) {
                        continue;
                    }
                    Win7NetworkSocket peer;
                    peer.inode = message->idiag_inode;
                    peer.remoteIp = QString::fromLatin1(ip.data());
                    peer.remotePort = ntohs(message->id.idiag_dport);
                    peer.protocol = protocol == IPPROTO_TCP ? QStringLiteral("TCP") : QStringLiteral("UDP");
                    int attributesSize = header->nlmsg_len - NLMSG_LENGTH(sizeof(inet_diag_msg));
                    auto *attribute = reinterpret_cast<const rtattr *>(reinterpret_cast<const char *>(message) + NLMSG_ALIGN(sizeof(inet_diag_msg)));
                    for (; RTA_OK(attribute, attributesSize); attribute = RTA_NEXT(attribute, attributesSize)) {
                        if (protocol == IPPROTO_TCP && attribute->rta_type == INET_DIAG_INFO
                            && RTA_PAYLOAD(attribute) >= offsetof(tcp_info, tcpi_last_data_recv) + sizeof(quint32)) {
                            tcp_info info{};
                            std::memcpy(&info, RTA_DATA(attribute), std::min<size_t>(RTA_PAYLOAD(attribute), sizeof(info)));
                            peer.activityAgeMs = std::min(info.tcpi_last_data_sent, info.tcpi_last_data_recv);
                        }
                    }
                    result.append(peer);
                }
            }
        }
    }
    *available = completeDumps == 4;
    close(fd);
#endif
    return result;
}

Win7NetworkProcessInfo win7ParseNetworkProcessStat(const QByteArray &stat)
{
    Win7NetworkProcessInfo process;
    const auto left = stat.indexOf('(');
    const auto right = stat.lastIndexOf(')');
    if (left < 1 || right <= left) {
        return process;
    }
    bool validPid = false;
    process.pid = stat.left(left).trimmed().toLongLong(&validPid);
    const auto fields = stat.mid(right + 1).simplified().split(' ');
    bool validStart = false;
    if (fields.size() > 19) {
        process.startTime = fields.at(19).toULongLong(&validStart); // stat field 22
    }
    if (!validPid || process.pid <= 0 || !validStart || !process.startTime) {
        return {};
    }
    process.name = QString::fromUtf8(stat.mid(left + 1, right - left - 1));
    return process;
}

Win7NetworkScan win7ScanNetworkProcesses(const QString &procRoot, const QList<Win7NetworkSocket> &sockets, bool connectionsAvailable)
{
    Win7NetworkScan scan;
    scan.connectionsAvailable = connectionsAvailable;
    QHash<quint64, Win7NetworkSocket> byInode;
    for (const auto &peer : sockets) {
        byInode.insert(peer.inode, peer);
    }
    const qint64 now = win7NetworkMonotonicMs();
    const QDir proc(procRoot);
    for (const auto &directory : proc.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        bool numeric = false;
        const auto pid = directory.toLongLong(&numeric);
        if (!numeric || pid <= 0) {
            continue;
        }
        QFile stat(proc.filePath(directory + QStringLiteral("/stat")));
        if (!stat.open(QIODevice::ReadOnly)) {
            continue;
        }
        auto process = win7ParseNetworkProcessStat(stat.readAll());
        if (process.pid != pid) {
            continue;
        }
        QSet<quint64> seen;
        QList<Win7NetworkSocket> udpPeers;
        const QDir descriptors(proc.filePath(directory + QStringLiteral("/fd")));
        for (const auto &descriptor : descriptors.entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System)) {
#ifdef Q_OS_LINUX
            std::array<char, 128> target{};
            const auto length = readlink(QFile::encodeName(descriptors.filePath(descriptor)).constData(), target.data(), target.size());
            if (length <= 0) {
                continue;
            }
            const QByteArray link(target.data(), length);
            if (!link.startsWith("socket:[") || !link.endsWith(']')) {
                continue;
            }
            bool valid = false;
            const auto inode = link.mid(8, link.size() - 9).toULongLong(&valid);
            if (!valid || seen.contains(inode) || !byInode.contains(inode)) {
                continue;
            }
            seen.insert(inode);
            const auto peer = byInode.value(inode);
            ++process.connections;
            const qint64 activity = peer.activityAgeMs >= 0 ? now - peer.activityAgeMs : 0;
            if (activity > process.lastActivityMs) {
                process.lastActivityMs = activity;
                process.lastIp = peer.remoteIp;
                process.remotePort = peer.remotePort;
                process.protocol = peer.protocol;
            }
            if (peer.protocol == QLatin1String("UDP")) {
                udpPeers.append(peer);
            }
#endif
        }
        // A single connected UDP peer is identifiable, but has no activity age.
        // Never guess which of several UDP destinations was contacted last.
        if (process.lastIp.isEmpty() && udpPeers.size() == 1) {
            process.lastIp = udpPeers.first().remoteIp;
            process.remotePort = udpPeers.first().remotePort;
            process.protocol = QStringLiteral("UDP");
        }
        scan.processes.insert(pid, process);
    }
    return scan;
}

Win7NetworkScan win7ScanNetworkProcesses()
{
    bool available = false;
    const auto sockets = win7ReadNetworkSockets(&available);
    return win7ScanNetworkProcesses(QStringLiteral("/proc"), sockets, available);
}
