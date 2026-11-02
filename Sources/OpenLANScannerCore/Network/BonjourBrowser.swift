import Foundation
import Network
import os

public struct BonjourHit: Sendable, Equatable {
    public var ip: IPv4Address
    public var hostname: String?
    public var serviceType: String

    public init(ip: IPv4Address, hostname: String?, serviceType: String) {
        self.ip = ip
        self.hostname = hostname
        self.serviceType = serviceType
    }
}

public protocol BonjourBrowsing: Sendable {
    func browse(timeoutMs: Int) async -> [BonjourHit]
}

public struct SystemBonjourBrowser: BonjourBrowsing {
    public var serviceTypes: [String]

    public init(serviceTypes: [String] = [
        "_ssh._tcp",
        "_http._tcp",
        "_https._tcp",
        "_smb._tcp",
        "_afpovertcp._tcp",
        "_rfb._tcp"
    ]) {
        self.serviceTypes = serviceTypes
    }

    public func browse(timeoutMs: Int) async -> [BonjourHit] {
        await withTaskGroup(of: [BonjourHit].self) { group in
            for type in serviceTypes {
                group.addTask { await Self.browseOne(type: type, timeoutMs: timeoutMs) }
            }
            var all: [BonjourHit] = []
            for await chunk in group {
                all.append(contentsOf: chunk)
            }
            var seen = Set<String>()
            return all.filter { hit in
                seen.insert("\(hit.ip.dotted)|\(hit.serviceType)").inserted
            }
        }
    }

    private static func browseOne(type: String, timeoutMs: Int) async -> [BonjourHit] {
        await withCheckedContinuation { continuation in
            let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: nil)
            let browser = NWBrowser(for: descriptor, using: .tcp)
            let lock = OSAllocatedUnfairLock(initialState: [BonjourHit]())
            let finished = OSAllocatedUnfairLock(initialState: false)

            let finish: @Sendable () -> Void = {
                let should = finished.withLock { done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }
                guard should else { return }
                browser.cancel()
                continuation.resume(returning: lock.withLock { $0 })
            }

            browser.stateUpdateHandler = { state in
                if case .failed = state { finish() }
            }
            browser.browseResultsChangedHandler = { results, _ in
                var hits: [BonjourHit] = []
                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint {
                        // Metadata may include peer endpoint interfaces; resolve when hostPort is present.
                        for interface in result.interfaces {
                            _ = interface
                        }
                        // Without resolved addresses, record hostname-only hits by skipping IP.
                        // Prefer resolved NWConnection endpoints when available in metadata.
                        if let ip = Self.ipv4(from: result) {
                            hits.append(BonjourHit(ip: ip, hostname: name, serviceType: type))
                        }
                    } else if let ip = Self.ipv4(from: result) {
                        hits.append(BonjourHit(ip: ip, hostname: nil, serviceType: type))
                    }
                }
                let batch = hits
                if !batch.isEmpty {
                    lock.withLock { $0.append(contentsOf: batch) }
                }
            }
            browser.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
                finish()
            }
        }
    }

    private static func ipv4(from result: NWBrowser.Result) -> IPv4Address? {
        if case .hostPort(let host, _) = result.endpoint {
            return ipv4(fromHost: host)
        }
        return nil
    }

    private static func ipv4(fromHost host: NWEndpoint.Host) -> IPv4Address? {
        switch host {
        case .ipv4(let address):
            return IPv4Address(string: address.debugDescription)
        case .name(let name, _):
            // Ignore unresolved names here.
            _ = name
            return nil
        default:
            return nil
        }
    }
}

public struct NoOpBonjourBrowser: BonjourBrowsing {
    public init() {}
    public func browse(timeoutMs: Int) async -> [BonjourHit] {
        _ = timeoutMs
        return []
    }
}

public struct SimulatedBonjourBrowser: BonjourBrowsing {
    public var hits: [BonjourHit]
    public init(hits: [BonjourHit] = []) { self.hits = hits }
    public func browse(timeoutMs: Int) async -> [BonjourHit] {
        _ = timeoutMs
        return hits
    }
}
