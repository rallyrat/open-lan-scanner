import Foundation
import os

public protocol HostnameResolving: Sendable {
    func reverseDNS(for ip: IPv4Address) async -> String?
}

public struct SystemHostnameResolver: HostnameResolving {
    public var timeoutMs: Int
    /// Hard cap on concurrent blocking `getnameinfo` calls (thread/work items).
    public static let maxConcurrentLookups = 8
    private static let gate = DispatchSemaphore(value: maxConcurrentLookups)
    private static let inflight = OSAllocatedUnfairLock(initialState: 0)

    public init(timeoutMs: Int = 2_000) {
        self.timeoutMs = max(50, timeoutMs)
    }

    public static func currentInflightLookups() -> Int {
        inflight.withLock { $0 }
    }

    public func reverseDNS(for ip: IPv4Address) async -> String? {
        await withTimeout(milliseconds: timeoutMs) {
            await Self.lookup(ip)
        } ?? nil
    }

    private static func lookup(_ ip: IPv4Address) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                gate.wait()
                inflight.withLock { $0 += 1 }
                defer {
                    inflight.withLock { $0 = max(0, $0 - 1) }
                    gate.signal()
                }

                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_addr.s_addr = in_addr_t(ip.rawValue.bigEndian)

                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        getnameinfo(
                            sockPtr,
                            socklen_t(MemoryLayout<sockaddr_in>.size),
                            &hostBuffer,
                            socklen_t(hostBuffer.count),
                            nil,
                            0,
                            NI_NAMEREQD
                        )
                    }
                }

                if result == 0 {
                    let name = String(cString: hostBuffer)
                    continuation.resume(returning: name.isEmpty ? nil : name)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// Returns `nil` when the operation does not finish within `milliseconds`.
/// Note: cooperative cancellation cannot abort a blocked libc lookup already running;
/// `SystemHostnameResolver` therefore also caps concurrent blocking lookups.
public func withTimeout<T: Sendable>(
    milliseconds: Int,
    operation: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(max(1, milliseconds)) * 1_000_000)
            return nil
        }
        for await value in group {
            group.cancelAll()
            if let value { return value }
        }
        return nil
    }
}

public struct StaticHostnameResolver: HostnameResolving {
    public var mapping: [IPv4Address: String]

    public init(mapping: [IPv4Address: String] = [:]) {
        self.mapping = mapping
    }

    public func reverseDNS(for ip: IPv4Address) async -> String? {
        mapping[ip]
    }
}
