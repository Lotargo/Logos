# APL Supplement — Experimental Accelerator

**Date:** 2026-07-01
**Status:** Deferred. For reference when pure-Lisp matrix ops hit performance ceiling.

---

## Premise

GNU APL is not part of LSMA core. The MVP uses SBCL nested vectors for all matrix operations. This document captures the APL integration path for future perf-critical scenarios.

## When to Consider

- ADF library exceeds 10 000 entries
- Operator co-occurrence matrix rebuild takes >100ms
- Cross-domain similarity search over 5000+ ASTs takes >500ms
- Frequent subtree mining over 10 000+ ASTs becomes bottleneck

## Architecture (if revived)

```
Lisp (SBCL)                GNU APL subprocess
    │                            │
    │─── write matrix dump ──────▶  (file: /tmp/apl_in.dat)
    │                            │  compute(ADF × FEATURES)
    │◀─── read result ───────────  (file: /tmp/apl_out.dat)
```

Same pattern as the Python bridge: `uiop:run-program` with file-based I/O.

## Risks

- GNU APL on Windows requires Cygwin/MSYS2
- Subprocess latency per matrix op (~50-200ms just for process start)
- Persistent APL process via pipe/PTY needed for production use
- Matrix format serialization/deserialization overhead
- Third platform dependency in a stack that's already Lisp + Python + Neon + Prolog

## Decision Record

**2026-07-01:** Deferred indefinitely. Pure-Lisp MVP first. If and only if profiling shows matrix ops as bottleneck, revisit this doc.
