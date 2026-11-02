# Follow-ups (not done in local cleanup)

Low-priority architectural items deferred so cleanup stayed small and low-risk:

1. **Cache `filteredHosts` for a single view pass** — `ContentView` evaluates the computed property multiple times per body refresh. A generation-stamped cache could reduce repeated filter/sort work during rapid scan updates without changing filter semantics.
2. **Diff-based AppKit table updates** — Prefer insert/remove/move row APIs when host identity sets change modestly, instead of `reloadData()` on identity churn.
3. **Shared BUILD_PATH collisions** — Document or auto-suffix `BUILD_PATH` when `OLS_ISOLATE_BUILD=1` for parallel local jobs beyond the existing env override.
4. **Re-package after ad-hoc app rebuilds** — `dist/OpenLANScanner.app` can drift newer than ZIP/DMG when only `build-app.sh` runs; a package freshness check could warn before sharing archives.
