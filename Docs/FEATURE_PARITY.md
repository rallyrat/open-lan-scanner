# Feature-parity matrix

Reference behavior inferred from the public Advanced IP Scanner website and help documentation. Open LAN Scanner is an independent implementation.

Legend: **Done** · **Partial** · **Unsupported** · **N/A (macOS)**

| Capability | Status | Notes |
|---|---|---|
| Enter IP range / scan / stop | Done | CIDR, single IP, `a-b` ranges; oversized ranges rejected before allocation |
| Suggest current subnet | Done | From selected interface; does not overwrite a manually edited target |
| Class-C helper | Done | `/24` snap from current start address |
| Live results table | Done | AppKit `NSTableView`; multi-select; selection/scroll preserved |
| Columns: status, IP, name, MAC, vendor, latency, services | Done | Custom name falls back to hostname; widths/order/sort persisted |
| Numeric IP / latency sort | Done | Header ascending/descending |
| Progress / elapsed / cancel | Done | Cancels in-flight transports; generation-token prevents stale updates |
| Favorites with custom names/notes | Done | Local JSON; validated/deduplicated imports |
| Text search filter | Done | |
| Online-only / favorites filters | Done | Distinct empty states when filters match nothing |
| Export CSV / JSON | Done | All, filtered, or selected rows |
| Import/export favorites | Done | JSON with actionable errors |
| MAC from local neighbors | Partial | Refreshed after probe; neighbor cache alone ≠ currently online |
| Vendor (OUI) | Partial | Bundled sample + in-app IEEE/compact CSV import; longest-prefix; LAA noted |
| Hostname (DNS) | Done | Async reverse DNS enrichment |
| Hostname (Bonjour/mDNS) | Partial | Optional browse; best-effort; often hostname-only |
| ICMP discovery | Partial | Best-effort unprivileged echo; failures ≠ offline |
| Shared folders browse | Done | Opens `smb://` in Finder |
| HTTP / HTTPS open | Done | Default browser |
| FTP open | Done | `ftp://` via browser/handler |
| SSH | Done | Opens Terminal (or configured app) with `ssh user@host` |
| Telnet | Partial | Opens Terminal with `telnet` if present |
| Ping / traceroute tools | Done | Opens Terminal with `/sbin/ping` or `traceroute` |
| VNC / Screen Sharing | Done | `vnc://` URL |
| RDP | Partial | Launches Microsoft Remote Desktop / `rdp://` if installed; else instructions |
| Wake-on-LAN | Done | Magic packet when MAC known; success/failure feedback |
| Scan history / compare | Done | Local snapshots; conservative matching; no cloud |
| Remote shutdown / abort | Unsupported | Windows-oriented; see Architecture notes |
| Radmin | Unsupported | Proprietary Windows remote control |
| NetBIOS name | Unsupported | No fragile Windows name-service dependency in v1 |
| Portable USB mode | N/A | macOS app bundle; ZIP distribution instead |
| Multi-language UI | Partial | English UI strings; not fully localized |
| High-accuracy multi-pass scan | Partial | Optional retry count in preferences |
| Scan rate / concurrency prefs | Done | Discovery vs enrichment concurrency |
| Resource/port selection | Done | Separate discovery-port and service-port toggles |
| Accessible keyboard actions | Partial | Native table navigation + menu shortcuts; Copy respects text editing |

## Honest limitations (product copy)

- A failed probe does **not** prove a host is offline (firewall, sleep, filtered ports).
- MAC addresses are typically available only for **directly connected** L2 neighbors.
- VPNs, client isolation, and randomized MACs reduce completeness.
- Latency shown is **TCP connect probe time**, not ICMP RTT, unless an ICMP sample succeeds.
- Ordinary scanning does not require administrator rights; some techniques remain unavailable without privileges.
