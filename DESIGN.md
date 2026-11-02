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

Status colors are distinct from the brand accent. Online = success; offline/unknown = muted/offline.

## Type scale (SwiftUI)

| Role | Size | Weight |
|---|---|---|
| caption | 11–12 | regular |
| secondary | 13 | regular |
| body | 13–14 | regular (table uses 13) |
| toolbar | 13 | medium |
| title | 15 | semibold |

Monospaced digits for IP, MAC, and latency columns.

## Spacing & shape

4 / 8 / 12 / 16 / 24. Toolbar padding 8–12. Inspector width ~280. Corner radius 6 for compact controls; panels use system split styling. 1pt borders only where separators already exist.

## Icons

SF Symbols: `wifi`, `lanyardcard`, `play.fill`, `stop.fill`, `star`, `star.fill`, `magnifyingglass`, `network`, `cable.connector`. One family, consistent hierarchical rendering.

## Motion

160ms control feedback; interruptible. Progress is indeterminate/determinate bar — not decorative. Honor Reduce Motion.

## Layout

```
┌─ Toolbar: iface | range | Scan/Stop | search | filters ─┐
├─ Results table (flexible) ┬─ Inspector (optional) ──────┤
├─ Status: progress · count · elapsed · warnings ─────────┤
```

Empty state: short instruction + suggested subnet. Error state: clear cause (invalid range, permission denied) + recovery hint.
