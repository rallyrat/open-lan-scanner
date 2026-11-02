# Open LAN Scanner — Implementation Plan

Working name: **Open LAN Scanner**  
Independent open-source macOS LAN scanner. Not affiliated with Advanced IP Scanner or Famatech.

## Assumptions (documented)

| Decision | Choice | Rationale |
|---|---|---|
| Min macOS | **14.0** | SwiftUI maturity, Observation, Network framework; Local Network privacy applies when running on 15+ |
| Architecture | SPM library + SwiftUI/AppKit app executable packaged as `.app` | Testable core; reproducible CLI builds |
| Sandbox | **Disabled** | Neighbor/ARP table and unprivileged ICMP-adjacent probing need broader network/system access; documented in `Docs/DISTRIBUTION.md` |
| Discovery primary | Bounded **TCP connect** probes | Works without root; devices that ignore ICMP still appear when a probed port is open |
| ICMP | Optional best-effort via isolated adapter | Not required for usability; failures never imply offline |
| OUI data | Bundled compact sample + optional IEEE MA-L download | IEEE does not assert copyright on the public listing; update is explicit |
| Remote shutdown | **Not implemented** as Windows SMB/RPC shutdown | Documented limitation; macOS has no safe generic equivalent without credentials/protocols we will not fake |
| Radmin | **Unsupported** | Windows-only proprietary; no macOS client integration |
| Branding | Original name, icons, copy | MIT; no Famatech marks |

## Build increments

1. **Core parsing & models** — IPv4/CIDR/range, numeric sort, device records  
2. **Transports** — Interface enum, TCP probe, neighbor table, reverse DNS, Bonjour enrichment  
3. **Scan engine** — Bounded parallelism, cancellation, generation tokens, live merge  
4. **Persistence & export** — Preferences, favorites, CSV/JSON  
5. **Actions** — SMB, HTTP(S), SSH, VNC, RDP, WoL, copy  
6. **UI** — Toolbar, results table, detail, filters, menus  
7. **Packaging** — `.app` script, ZIP, CI, docs  

## Validation gates

- `swift test` (deterministic simulated transports)  
- `Scripts/build-app.sh` → runnable `.app`  
- Manual scan on local subnet when environment allows  
