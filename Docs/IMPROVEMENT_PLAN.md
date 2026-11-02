# Improvement plan (local, unpushed)

Verified against `3e6ffc6` at start; Priority 1–5 items below are implemented locally (not pushed).

## Order of work

1. **Safe parsing** — count before allocate; overflow-safe; tests for /0 and oversized ranges ✅  
2. **Discovery correctness** — probe outcomes, discovery vs service ports, refuse≠timeout, progressive enrichment, cancel, unbounded event delivery ✅  
3. **Interface-aware scanning** — pass interface into scan/transport; UI feedback ✅  
4. **Daily UX** — sort, multi-select, empty states, export scopes, action feedback ✅  
5. **Vendor + persistence** — IEEE CSV, longest prefix, LAA, import, validated prefs/favorites ✅  
6. **Distribution** — restore `.github/workflows` with signing/notarization/checksum order fixed ✅  
7. **Scan history** — bounded local snapshots + conservative compare ✅  

No push/release in this task.
