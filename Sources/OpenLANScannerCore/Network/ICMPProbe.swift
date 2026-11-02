import Darwin
import Foundation

public protocol ICMPProbing: Sendable {
    func echo(host: IPv4Address, timeoutMs: Int) async -> ProbeOutcome
}

/// Best-effort ICMP echo using an unprivileged datagram socket when the OS allows it.
/// Failures are soft: callers must not treat them as proof the host is offline.
public struct SystemICMPProbe: ICMPProbing {
    public init() {}

    public func echo(host: IPv4Address, timeoutMs: Int) async -> ProbeOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = Self.pingOnce(host: host, timeoutMs: timeoutMs)
                continuation.resume(returning: result)
            }
        }
    }

    private static func pingOnce(host: IPv4Address, timeoutMs: Int) -> ProbeOutcome {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else {
            return ProbeOutcome(kind: .error, detail: "ICMP socket unavailable")
        }
        defer { close(fd) }

        var timeout = timeval(
            tv_sec: timeoutMs / 1000,
            tv_usec: suseconds_t((timeoutMs % 1000) * 1000)
        )
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = in_addr_t(host.rawValue.bigEndian)

        let ident = UInt16(getpid() & 0xFFFF)
        let seq: UInt16 = 1
        let packet = ICMPPacketCodec.buildEchoRequest(identifier: ident, sequence: seq)

        let started = Date()
        let sent: Int = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                sendto(fd, packet, packet.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent > 0 else {
            return ProbeOutcome(kind: .error, detail: "ICMP send failed")
        }

        // Drain a few replies until timeout; ignore unrelated ICMP noise.
        let deadline = Date().addingTimeInterval(Double(max(timeoutMs, 1)) / 1000.0)
        while Date() < deadline {
            var reply = [UInt8](repeating: 0, count: 128)
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received: Int = withUnsafeMutablePointer(to: &from) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    recvfrom(fd, &reply, reply.count, 0, sockPtr, &fromLen)
                }
            }
            if received <= 0 { break }
            let slice = Array(reply.prefix(received))
            if ICMPPacketCodec.isMatchingEchoReply(
                slice,
                expectedIdentifier: ident,
                expectedSequence: seq
            ) {
                let ms = Date().timeIntervalSince(started) * 1000
                return ProbeOutcome(kind: .open, latencyMs: ms, detail: "icmp")
            }
        }
        return ProbeOutcome(kind: .timeout, detail: "icmp")
    }
}

public struct NoOpICMPProbe: ICMPProbing {
    public init() {}
    public func echo(host: IPv4Address, timeoutMs: Int) async -> ProbeOutcome {
        _ = host; _ = timeoutMs
        return ProbeOutcome(kind: .timeout, detail: "icmp-disabled")
    }
}

public struct SimulatedICMPProbe: ICMPProbing, @unchecked Sendable {
    public var responsive: Set<IPv4Address>
    public init(responsive: Set<IPv4Address> = []) {
        self.responsive = responsive
    }

    public func echo(host: IPv4Address, timeoutMs: Int) async -> ProbeOutcome {
        _ = timeoutMs
        if responsive.contains(host) {
            return ProbeOutcome(kind: .open, latencyMs: 3, detail: "icmp")
        }
        return ProbeOutcome(kind: .timeout, detail: "icmp")
    }
}
