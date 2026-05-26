# Logos Cognitive Engine (v8) - Refactoring Plan for True Emergence

This document outlines the strict technical roadmap and philosophical constraints for the upcoming refactoring phase of the Logos v8 engine. The primary objective is to eradicate all hardcoded heuristics, rigid lookup tables, and architectural "cheats" that bypass the necessity for emergent discovery.

The engine must earn its results strictly through fundamental logical and mathematical unification. We must strictly avoid the trap of passing benchmarks via wishful thinking and rigid sandboxes.

## 1. Strict Prohibitions

During the refactoring phase, the following practices are strictly prohibited:

*   **No Explicit Lookup Tables:** The engine may not rely on predefined lists of correct answers (e.g., hardcoded matrices for quantum gates like Hadamard, or symbolic replacement rules for calculus derivatives). All such structures must be discovered organically.
*   **No Dataset Schema Hardcoding:** The system must not inspect filenames (e.g., `gravity_data.csv`) to magically inject the correct physical variable names or infer data structure. The engine must read the raw CSV array and dynamically infer arity purely from its dimensions.
*   **No Artificial Domain Sandboxing:** We must eliminate functions (like `get-domain-config`) that artificially restrict the mathematical search space to only the operators needed to solve a specific test. The engine must search a generalized, unified mathematical space and determine which operators are relevant autonomously.
*   **No Discontinuous Penalties:** The Occam's Razor penalty function cannot be conditional on reaching an arbitrary error threshold. It must exert continuous, dynamic pressure against complexity across all error states.

## 2. Refactoring Directives

### Phase A: Eradicating Sandbox Constraints
- **Target:** `v8/engine/engine.lisp`
- **Action:** Refactor `get-domain-config` and the Lisp mutator. Combine all domains into a single, unified mathematical space (`*current-operators*`). The system must not be "told" it is doing thermodynamics or calculus; it must figure it out based on the constraints evaluated by the Prolog daemon.

### Phase B: Dynamic Dataset Ingestion
- **Target:** `v8/engine/regression.pl`
- **Action:** Delete the `dataset_vars` explicit rules. Implement logic that reads a CSV file, counts the columns dynamically, and assigns generic abstract variables (e.g., `v1, v2, ..., vn`). This ensures the engine operates without semantic bias.

### Phase C: Continuous Occam's Razor
- **Target:** `v8/engine/regression.pl` (specifically `regression_censor/2`)
- **Action:** Remove the hardcoded threshold (`TotalError < 0.1`). Implement a continuous penalty function: $Penalty = TotalError + (\lambda \times Size)$. Furthermore, $\lambda$ should ideally scale with the noise variance or information entropy of the dataset to prevent runaway overfitting.

### Phase D: Unitarity from Scratch
- **Target:** `v8/engine/root_axioms.pl`
- **Action:** Delete the `gate_matrix` hardcoded definitions. Update the Lisp mutator to generate multidimensional arrays of raw numbers. The Prolog censor will evaluate these arrays solely by checking the mathematical property $M \times M^T = I$. The engine must discover the gates itself through evolutionary pressure.

### Phase E: Deriving Continuous Mathematics
- **Target:** `v8/engine/root_axioms.pl`
- **Action:** Remove hardcoded calculus simplification rules (`deriv` and `int`). Implement the limit definition of a derivative as a base axiom. Force the engine to expand limits and perform algebraic reduction to genuinely derive derivatives organically.

## 3. Conclusion
By strictly adhering to these prohibitions and executing these refactoring phases, the Logos v8 engine will strip away its human-provided scaffolding. Only then can it demonstrate genuine First-Principle Ontological Bootstrapping.
