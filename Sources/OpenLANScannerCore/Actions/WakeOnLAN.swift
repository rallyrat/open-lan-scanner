import Foundation
import Network

public enum WakeOnLANError: Error, LocalizedError, Sendable {
    case invalidMAC(String)
    case sendFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMAC(let value):
            return "Invalid MAC address: \(value)"
        case .sendFailed(let reason):
            return "Wake-on-LAN send failed: \(reason)"
        }
    }
}

public enum WakeOnLAN {
    public static func normalizeMAC(_ mac: String) throws -> [UInt8] {
        let hex = mac.uppercased().filter { $0.isHexDigit }
        guard hex.count == 12 else { throw WakeOnLANError.invalidMAC(mac) }
        var bytes: [UInt8] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else {
                throw WakeOnLANError.invalidMAC(mac)
            }
            bytes.append(byte)
            idx = next
        }
        return bytes
    }

    public static func magicPacket(mac: String) throws -> Data {
        let macBytes = try normalizeMAC(mac)
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        return packet
    }

    /// Sends a WoL magic packet to the IPv4 broadcast address on UDP/9 (and UDP/7).
    public static func send(mac: String, broadcast: IPv4Address = IPv4Address(rawValue: 0xFFFF_FFFF)) async throws {
        let packet = try magicPacket(mac: mac)
        try await sendUDP(packet: packet, host: broadcast, port: 9)
        try await sendUDP(packet: packet, host: broadcast, port: 7)
    }

    private static func sendUDP(packet: Data, host: IPv4Address, port: UInt16) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host.dotted),
                port: NWEndpoint.Port(rawValue: port)!
            )
            let connection = NWConnection(to: endpoint, using: .udp)
            let lock = NSLock()
            var resumed = false

            func finish(_ result: Result<Void, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(with: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(
                        content: packet,
                        completion: .contentProcessed { error in
                            if let error {
                                finish(.failure(WakeOnLANError.sendFailed(error.localizedDescription)))
                            } else {
                                finish(.success(()))
                            }
                        }
                    )
                case .failed(let error):
                    finish(.failure(WakeOnLANError.sendFailed(error.localizedDescription)))
                case .cancelled:
                    finish(.failure(WakeOnLANError.sendFailed("cancelled")))
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                finish(.failure(WakeOnLANError.sendFailed("timeout")))
            }
        }
    }
}
