import Foundation

public protocol HostnameResolving: Sendable {
    func reverseDNS(for ip: IPv4Address) async -> String?
}

public struct SystemHostnameResolver: HostnameResolving {
    public init() {}

    public func reverseDNS(for ip: IPv4Address) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
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

public struct StaticHostnameResolver: HostnameResolving {
    public var mapping: [IPv4Address: String]

    public init(mapping: [IPv4Address: String] = [:]) {
        self.mapping = mapping
    }

    public func reverseDNS(for ip: IPv4Address) async -> String? {
        mapping[ip]
    }
}
