# V9 Implementation and Refactoring Plan

Based on the exploration of the `v9` codebase, execution of the breaker tests, and analysis of the vulnerability reports, the following issues have been identified. We will work on these systematically.

## 1. Fix Lisp Load Order and Underspecified Variables (Critical Stability)
**Issue:** `v9/src/engine.lisp` loads extension modules (`meta_evolve.lisp`, `ontology_generator.lisp`, etc.) at the very top of the file, before defining core variables (`*unified-operators*`, `*current-variables*`) and core functions (`lisp-to-prolog`, `mutate`). This causes undefined variable and function warnings/errors during compilation and execution, leading to potential instability in the meta-evolution loop.
**Action:** Move the `(load ...)` statements to the bottom of `v9/src/engine.lisp`, ensuring all core parameters and functions are defined before the extensions are loaded. Initialize `*current-dataset*` and `*regression-vars*` appropriately before they are accessed in domain setup functions.

## 2. Fix Directory Path Errors in Python Data Generators (Bug Fix)
**Issue:** Python data generation scripts (e.g., `v9/data/generate_extreme_noise_data.py`, `generate_gravity_data.py`, `generate_relativity.py`, `generate_kepler.py`) are attempting to write their output CSV files to a hardcoded `v9/engine/...` directory instead of the correct `v9/data/...` directory. This causes `FileNotFoundError` exceptions during test setup.
**Action:** Update the target paths in all generation scripts to correctly point to `v9/data/...`.

## 3. Eradicate Domain Sandboxing (First-Principle Violation)
**Issue:** The `get-domain-config` function in `engine.lisp` artificially restricts the evolutionary search space by handing the engine exactly the operators and constants it needs for specific domains (e.g., giving only `carnot` and `t_hot` for thermodynamics). This violates the core philosophy of autonomous ontological bootstrapping.
**Action:** Unify the search space. The `*current-operators*`, `*current-variables*`, and `*current-constants*` must be global and contain all fundamental mathematical operations. The engine must discover relevant operators naturally without domain-specific subset hints.

## 4. Abolish Hardcoded Calculus and Quantum Matrices (First-Principle Violation)
**Issue:** `v9/prolog/root_axioms.pl` explicitly defines `gate_matrix` for quantum gates and uses pre-calculated calculus rules (e.g., `simplify(deriv(sin(A), Var), ...)`). This makes the system an expert system rather than an AI discovering physics from scratch.
**Action:**
- Delete the predefined `gate_matrix` facts. Mutate raw multi-dimensional numeric arrays in Lisp and evaluate them strictly for unitarity in Prolog, allowing gates to emerge naturally.
- Remove hardcoded `deriv` and `int` simplification rules. Force the engine to derive continuous mathematics via fundamental limit evaluations ($f'(x) = \lim_{h \to 0} \frac{f(x+h) - f(x)}{h}$).

## 5. Address the Occam's Razor & Overfitting Vulnerabilities
**Issue:** While some dynamic variable parsing has been introduced to `regression.pl` (e.g., dynamic `Lambda` and `get_vars`), the meta-evolution and regression domains still struggle with extreme noise datasets, leading to bloated ASTs that chase noise spikes rather than extracting generalized physical signals.
**Action:** Ensure that the continuous complexity penalty `Penalty = TotalError + (Size * Lambda)` is strictly enforced and verified across all adversarial cases. Implement semantic crossover and dimensional analysis heuristics in Lisp to prevent blind topological bloat.
