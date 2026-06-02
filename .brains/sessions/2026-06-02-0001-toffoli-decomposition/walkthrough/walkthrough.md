# Walkthrough: Toffoli Decomposition Session

## Summary
We debugged the Cognitive Engine v7's evolutionary synthesis for Toffoli gate decomposition. The search algorithm had multiple bugs that prevented any meaningful convergence: mutation didn't respect operator arity, identity fallback created a false local optimum, random acceptance constantly overwrote progress, ADF injection broke gate parsing, and novelty mode discarded target-mode progress. All fixes applied. Current search converges stably but reaches only 0.699 fidelity (local optimum: T⊗I⊗I).

## Session Log

| Step | Action | Result |
|------|--------|--------|
| 1 | Initial run | Garbage ASTs like `(T Q1 Q2)` — wrong arities |
| 2 | Fixed mutation arity | Operators now use correct arity |
| 3 | Wrote `verify_toffoli.py` | Independent fidelity checker with numpy |
| 4 | Found identity fallback bug | `build_synthesis_unitary` returned identity for unknown ASTs |
| 5 | Removed identity fallback | Unrecognized ASTs now get penalty 1000 |
| 6 | Fixed operator swap arity | Can't replace H with CNOT (arity mismatch) |
| 7 | Disabled ADF for synthesis | ADF symbols no longer injected into gate args |
| 8 | Found novelty mode bug | `best-penalty` reset to 1000, `best-ast` overwritten |
| 9 | Fixed stagnation save/restore | Target best preserved across novelty switches |
| 10 | Found random-accept bug | 15% chance constantly overwrote good circuits |
| 11 | Disabled random-accept for synthesis | Only genuine improvements accepted |
| 12 | Final run | All 12 threads converged on same circuit (T⊗I⊗I, fidelity 0.699) |
| 13 | Found verifier bug | `_parse_args` didn't parse sub-expressions recursively |
| 14 | Fixed verifier | Now correctly computes fidelity for multi-gate circuits |

## Files
- `v7/engine/engine.lisp` (605 lines) — evolutionary engine
- `v7/engine/quantum.pl` (730 lines) — Prolog censor with complex matrices
- `v7/experiments/verify_toffoli.py` (321 lines) — independent Python verifier
- `v7/experiments/toffoli_results.log` — last experiment output

## Command to Re-run
```powershell
cd F:\Кейс\AGI-lite
& "C:\Program Files\Steel Bank Common Lisp\1.12.2\sbcl.exe" --script v7/experiments/run_toffoli_decomp.lisp
python v7/experiments/verify_toffoli.py v7/experiments/toffoli_results.log
```

Or use the wrapper:
```powershell
.\v7\experiments\run_and_verify.ps1
```

## Next Session Focus
1. Increase iterations (50000+)
2. Add gate-insertion/removal mutation
3. Add crossover between circuits
4. More aggressive search operators (adaptive mutation rate)
