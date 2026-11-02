# Open LAN Scanner — Design

## Audience and tasks

Network-savvy Mac users who need a fast, honest LAN inventory: pick an interface, set a range, scan, act on hosts. Primary task is **scan → find → open/copy/wake**.

## Visual direction

**Precision instrument** — dense, calm utility chrome. No dashboard cards, charts, or onboarding carousels. Hierarchy comes from the toolbar + results table + optional inspector.

Native macOS materials and controls; SF Symbols only. System typography (SF Pro) for OS alignment and Dynamic Type.

## Color tokens

| Token | Light | Dark |
|---|---|---|
| background | `#F4F5F7` | `#1C1D1F` |
| surface | `#FFFFFF` | `#2A2B2E` |
| text | `#1A1C1E` | `#F3F4F6` |
| mutedText | `#5C6370` | `#A0A6B0` |
| border | `#D5D8DE` | `#3E4248` |
| accent | `#0F6B63` | `#3DBEAF` |
| onAccent | `#FFFFFF` | `#062E2A` |
| focus | `#0F6B63` | `#3DBEAF` |
| success | `#1B7F4A` | `#3DDC97` |
| warning | `#A15C00` | `#F0B429` |
| error | `#B42318` | `#F97066` |
| offline | `#8B919A` | `#6B7280` |

Status colors are adaptive semantic tokens (not a fixed green). Responding = success + symbol; no response = muted/offline + symbol. Must remain readable on alternating and selected rows.

## Type scale (SwiftUI / AppKit table)

| Role | Size | Weight |
|---|---|---|
| caption | 11–12 | regular |
| secondary / table (default) | 13 | regular |
| table (compact) | 12 | regular |
| toolbar | 13 | medium |
| title | 15 | semibold |

Monospaced digits for IP, MAC, and latency/response columns.

## Layout tokens (`OLSTheme`)

Implemented in `Theme.swift` and reused by toolbar, inspector, footer, and sheets:

| Token | Value | Use |
|---|---|---|
| `contentInset` | 16 pt | Outer pane / sheet padding |
| `controlGap` | 8 pt | Tight control spacing |
| `relatedGap` | 12 pt | Related content blocks |
| `toolbarGroupGap` | 16 pt | Distinct toolbar groups |
| `inspectorSectionGap` | 20 pt | Inspector sections |
| `tableRowHeight` | 28 pt | Default density |
| `tableRowHeightCompact` | 22 pt | Compact preference |
| `tableFontSize` | 13 / 12 | Default / compact |
| Inspector width | 300–360 pt (ideal 320) | Trailing split |
| Window min | 920×560 | After adaptable toolbar |
| Window default | 1120×700 | First launch |

Primary column defaults (Name/IP/Status/Services/Response) sum to roughly 626 pt so they remain practical beside the inspector at the default window width. Persisted column widths are clamped (≤260 pt) so `lastColumnOnly` fill widths are not written back into preferences. The Response column shows compact “N ms” text; method detail remains in the tooltip and inspector.

Do not sprinkle padding indiscriminately — apply tokens at pane and group boundaries.

## Icons

SF Symbols: `wifi`, `play.fill`, `stop.fill`, `star`, `magnifyingglass`, `network`, `sidebar.trailing`, `line.3.horizontal.decrease.circle`, `checkmark.circle.fill`, `questionmark.circle`. One family, consistent hierarchical rendering.

## Motion

160ms control feedback; interruptible. Progress is a determinate bar — not decorative. Honor Reduce Motion.

## Layout

```
┌─ Toolbar: [iface · range options · target · Scan/Stop] · Filters · search · inspector ─┐
├─ Results table (flexible) ┬─ Inspector (optional, scrollable) ──────────────────────────┤
├─ Status (left) · progress · counts · elapsed · History (right) ─────────────────────────┤
```

- **Toolbar:** Interface → target → Scan is the primary group. Range helpers live in a labeled menu. Filters are a menu with an active indicator. Narrow windows collapse secondary actions into an overflow menu (`ViewThatFits`).
- **Inspector:** Display name + IP header; Details / Favorite / Actions; primary actions suggested from observed services; More Actions for the rest; evidence in a disclosure.
- **Table:** Default columns Name, IP, Status, Services, Response. MAC/Vendor optional via Preferences. Compact density optional.
- **Preferences:** Tabs — General, Discovery, Services, Data, Advanced (⌘,).
- **History:** Earlier/Later pickers; Compare enabled only for two distinct scans; device rows, not comma lists.

Empty state: short instruction + recovery. Errors: clear cause + recovery. Timeouts never claimed as proof a host left the network.

## Language

Use readable labels (“TCP connection”, “Open TCP port”, “Responded”, “No response”, “Unavailable”). Keep raw evidence kinds behind expandable details.
