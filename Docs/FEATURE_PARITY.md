# Feature-parity matrix

Reference behavior inferred from the public Advanced IP Scanner website and help documentation. Open LAN Scanner is an independent implementation.

Legend: **Done** · **Partial** · **Unsupported** · **N/A (macOS)**

| Capability | Status | Notes |
|---|---|---|
| Enter IP range / scan / stop | Done | CIDR, single IP, `a-b` ranges |
| Suggest current subnet | Done | From selected interface IPv4 + mask |
| Class-C helper | Done | `/24` snap from current start address |
| Live results table | Done | AppKit `NSTableView` hosted in SwiftUI |
| Columns: status, IP, hostname, MAC, vendor, latency, services | Done | Unavailable fields shown as em dash |
| Numeric IP sort | Done | |
| Progress / elapsed / cancel | Done | Generation-token prevents stale updates |
| Favorites with custom names/notes | Done | Local JSON store |
| Text search filter | Done | |
| Online-only / favorites filters | Done | |
| Export CSV | Done | RFC-style escaping |
| Export JSON | Done | |
| Import/export favorites | Done | JSON |
| MAC from local neighbors | Partial | ARP/neighbor table when present; not for routed/VPN-only hosts |
| Vendor (OUI) | Partial | Bundled sample + optional full IEEE download |
| Hostname (DNS) | Done | Reverse DNS |
| Hostname (Bonjour/mDNS) | Partial | Browse common service types; best-effort |
| Shared folders browse | Done | Opens `smb://` in Finder |
| HTTP / HTTPS open | Done | Default browser |
| FTP open | Done | `ftp://` via browser/handler |
| SSH | Done | Opens Terminal (or configured app) with `ssh user@host` |
| Telnet | Partial | Opens Terminal with `telnet` if present |
| Ping / traceroute tools | Done | Opens Terminal with `/sbin/ping` or `traceroute` |
| VNC / Screen Sharing | Done | `vnc://` URL |
| RDP | Partial | Launches Microsoft Remote Desktop / `rdp://` if installed; else instructions |
| Wake-on-LAN | Done | Magic packet when MAC known |
| Remote shutdown / abort | Unsupported | Windows-oriented; see Architecture notes |
| Radmin | Unsupported | Proprietary Windows remote control |
| NetBIOS name | Unsupported | No fragile Windows name-service dependency in v1 |
| Portable USB mode | N/A | macOS app bundle; ZIP distribution instead |
| Multi-language UI | Partial | English first; String Catalog ready |
| High-accuracy multi-pass scan | Partial | Optional retry count in preferences |
| Scan rate / concurrency prefs | Done | |
| Resource/port selection | Done | Configurable service probe set |

## Honest limitations (product copy)

- A failed probe does **not** prove a host is offline (firewall, sleep, filtered ports).
- MAC addresses are typically available only for **directly connected** L2 neighbors.
- VPNs, client isolation, and randomized MACs reduce completeness.
- Latency shown is **TCP connect probe time**, not ICMP RTT, unless an ICMP sample succeeds.
- Ordinary scanning does not require administrator rights; some techniques remain unavailable without privileges.
