# Plan: Toffoli Decomposition via Cognitive Engine v7

## Goal
Use the Cognitive Engine v7's evolutionary synthesis to discover a quantum circuit that decomposes the Toffoli (CCNOT) gate using the gate set {H, T, T†, S, S†, X, CNOT} on 3 qubits (q1, q2, q3).

## What We Changed

### 1. Mutation Arity Fix (engine.lisp)
- **Problem:** `mutate` created sub-expressions with operator arity hardcoded as `(member op '(h x_gate ...))` — missing `t`, `tdg`, `s`, `sdg` as 1-arg operators. This produced garbage ASTs like `(T Q1 Q2)` (arity 2) or left them unmutated.
- **Fix:** Introduced `single-arg-operator-p` predicate and `compatible-arity-ops` filter. All operator-swapping respects arity. Growth uses `(single-arg-operator-p op)` to determine arity.

### 2. Identity Fallback Removal (quantum.pl)
- **Problem:** `build_synthesis_unitary` had a catch-all clause returning identity for any AST whose gate/pattern didn't match. This gave fidelity 0.75 to *any* unrecognizable circuit, creating a strong local optimum.
- **Fix:** Removed the catch-all. Unrecognized ASTs now cause `synthesis_censor` to fail (penalty 1000).

### 3. Synthesis Domain Config (engine.lisp)
- **Problem:** `:synthesis` domain inherited constants `'(1 0)` from the `:quantum` domain case-fallthrough, producing garbage ASTs like `(H 1)`.
- **Fix:** Added explicit `:synthesis` clause in `set-domain` and `get-domain-config` with `*current-constants* = nil` and explicit gate operators.

### 4. No Random Acceptance for Synthesis (engine.lisp)
- **Problem:** A 15% random-accept clause (`(< (random 100) 15)`) constantly overwrote legitimate progress with garbage circuits, explaining why previous runs always found identity.
- **Fix:** Added `(and (not (eq domain :synthesis)) (< (random 100) 15))` — random acceptance disabled for synthesis.

### 5. Stagnation/Novelty Mode Fix (engine.lisp)
- **Problem:** When switching from target → novelty → back to target, `best-penalty` was reset to 1000 and `best-ast` was overwritten by novelty discoveries. This discarded any progress made in target mode.
- **Fix:** Added `saved-best-ast` and `saved-best-penalty`. Saved before entering novelty mode, restored on return to target.

### 6. ADF Extraction Disabled for Synthesis (engine.lisp)
- **Problem:** After each island generation, winner ASTs were registered as dynamic subroutines (ADF symbols). These ADF symbols appeared in gate arguments as `(H ADF-1)`, which `build_synthesis_unitary` couldn't expand (needs atom qubits).
- **Fix:** Wrapped ADF extraction in `(unless (eq domain :synthesis) ...)`.

### 7. Added T/TDG/S/SDG to Prolog Censor (quantum.pl)
- Added `valid_quantum_structure`, `is_quantum_redundant`, and `find_qubits` clauses for `t/1`, `tdg/1`, `s/1`, `sdg/1`.
- Added complex gate matrices for T, TDG, S, SDG.
- Added `toffoli_target/1` — 8×8 CCNOT matrix.
- Implemented `synthesis_censor/2` computing gate fidelity via complex matrix arithmetic in Prolog.

### 8. Created Python Verifier (verify_toffoli.py)
- Independent fidelity check using numpy — reads ASTs from experiment log, builds 8×8 unitaries, computes |Tr(U^dag_target @ U)| / 8.
- Found bug: `_parse_args` returned nested sub-expressions as raw strings → all multi-gate circuits evaluated as identity.
- **Fix:** Recursive `parse_ast` call in `_parse_args`.
- After fix, `(SEQ (TDG Q3) (SEQ (TDG Q2) (SEQ (T Q1) (SEQ (T Q2) (T Q3)))))` correctly identified as T⊗I⊗I with fidelity ≈ 0.699.

## Current Result
- **Best fidelity found:** 0.699 (T gate on q1, with T/T† pairs on q2,q3 cancelling to identity)
- **Identity baseline:** 0.750
- **Target:** 1.000
- **Status:** All 12 threads converged on the same two circuits (local optimum). Search is stable but cannot escape this optimum.

## Known Limitations
- Only 5000 iterations per thread — insufficient for a 3-qubit synthesis problem
- No crossover — only mutation (single-node swap and atom changes)
- No gate insertion/deletion operators — search can't add gates to a circuit, only change existing ones
- The fitness landscape is dominated by T gates near identity (~0.69 fidelity); the H-CNOT pattern needed for Toffoli requires specific multi-gate sequences with low probability of random discovery

## Files Changed
- `v7/engine/engine.lisp` — mutation, domain config, novelty mode, ADF, random acceptance
- `v7/engine/quantum.pl` — valid structure, redundancy, find_qubits clauses; complex matrix arithmetic; synthesis_censor; gate matrices
- `v7/experiments/verify_toffoli.py` — independent fidelity verifier (fix commit)
- `v7/experiments/run_toffoli_decomp.lisp` — experiment entry point
- `v7/experiments/run_and_verify.ps1` — wrapper script
