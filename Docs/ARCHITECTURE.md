# Architecture

## Layers

```
┌─────────────────────────────────────────────────────────┐
│  UI (SwiftUI + AppKit NSTableView)                      │
│  ScanSessionViewModel — main-actor state, filters, UX   │
├─────────────────────────────────────────────────────────┤
│  Actions / Export / Persistence                         │
│  DeviceActions · ResultExporter · FavoritesStore · Prefs│
├─────────────────────────────────────────────────────────┤
│  Discovery                                              │
│  ScanEngine — concurrency, cancellation, reconciliation │
├─────────────────────────────────────────────────────────┤
│  Protocol adapters (injectable)                         │
│  ReachabilityProbing · NeighborTable · HostnameResolver │
│  ServiceProbing · VendorLookup · InterfaceEnumerating   │
└─────────────────────────────────────────────────────────┘
```

## Scan lifecycle

1. Parse target expression → ordered unique `IPv4Address` list (cap warning above threshold).
2. Create `ScanGeneration` UUID; cancel prior task.
3. For each address, run bounded worker pool:
   - TCP probes (configured ports) with timeout.
   - Optional ICMP adapter (best-effort).
   - On any positive signal → mark online, record probe latency.
   - Reverse DNS + merge neighbor MAC + OUI vendor + open services.
4. Yield `HostRecord` updates only if generation still current.
5. Completion sets progress to finished; UI remains interactive.

## Result reconciliation

`HostRecord` is keyed by IPv4. Partial updates merge non-nil fields. Favorites overlay custom name/notes without inventing network facts.

## Dependency injection

Protocols in `OpenLANScannerCore` allow `SimulatedTransport` in tests. Production uses Network.framework `NWConnection`, `getifaddrs`, routing/ARP sysctl, and `Network` Bonjour browsers.

## Persistence

- Preferences: `UserDefaults` via `ScanPreferences`
- Favorites: Application Support JSON (`favorites.json`)
- No telemetry; no automatic OUI upload/download

## Subprocess policy

Shell parsing of network tables is avoided. Terminal launches for user-facing Ping/Traceroute/SSH pass argv-style commands via AppleScript/`open`. Wake-on-LAN uses a UDP socket directly.
