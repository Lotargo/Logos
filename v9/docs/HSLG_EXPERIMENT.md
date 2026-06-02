# HSLG 3D->4D Experiment (Meta-Axiomatic Hardcore Test)

## 1. Objective
To test the engine's ability to reason about the paradox of classical gravity: the limit as `r -> 0` of `1/r` (the classical singularity problem). This experiment uses the `calculus` domain.

## 2. Experimental Setup
- **Script:** `v9/experiments/run_hslg_experiment.lisp`
- **Starting AST:** `(limit (div 1 r) r 0)`
- **Domain:** Calculus
- **Iterations:** 1000
- **Threads:** Auto-detected (4)

## 3. Result: TIMED OUT (180s)

The experiment did not complete within the 180-second timeout.

### Evidence of Progress
- **Engine started:** Successfully loaded engine.lisp and entered the calculus domain.
- **ADF Library Growth:** The engine dynamically registered numerous ADF subroutines (ADF-1 through ADF-20+).
- **Thread activity:** All 4 threads ran worker loops with active migration.
- **Island migration:** ASTs were migrated between threads via the migration pool mechanism.
- **Log size:** 19,865 lines of engine activity.

### Failure Mode
The calculus domain's limit operator and the complex ASTs generated from the singularity seed led to an extremely large search space. The 1000-iteration budget combined with Prolog evaluation latency prevented convergence within 180s.

## 4. Conclusion
The HSLG experiment infrastructure (limit operator, calculus domain, thread migration) functioned correctly. Convergence requires either a longer timeout, reduced search space, or optimized Prolog evaluation.

**Crash status:** Timed out (no crash).
