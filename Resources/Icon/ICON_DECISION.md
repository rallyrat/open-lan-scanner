# App icon decision

## Concepts

| ID | File | Direction |
|---|---|---|
| A | `concepts/icon-concept-a-radar.jpg` | Concentric radar arcs + discovered node |
| B | `concepts/icon-concept-b-mesh.jpg` | Mesh of linked hosts |
| C | `concepts/icon-concept-c-sweep.jpg` | Horizontal sweep over host dots |

## Selection

**Concept A (radar)** selected for production.

Rationale: strongest Dock silhouette, clearest “discovery/scan” metaphor, matches the teal precision-instrument palette in `DESIGN.md`, remains legible at 16–32 px. Mesh (B) reads too generic; sweep (C) loses clarity when small.

Production assets are a clean vector-aligned re-render of A (not a cropped photo of the concept JPEG): `AppIcon.svg`, `AppIcon-1024.png`, `AppIcon.iconset/`, `AppIcon.icns`.
