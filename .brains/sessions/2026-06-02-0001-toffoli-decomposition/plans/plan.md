# Plan: Toffoli Decomposition via Cognitive Engine v7

## Goal
Use the Cognitive Engine v7's evolutionary synthesis to discover a quantum circuit that decomposes the Toffoli (CCNOT) gate using the gate set `{H, T, T†, S, S†, X, CNOT}` on 3 qubits (q1, q2, q3).

## Phase 1 — Bugs & Foundation (committed)

### 1. Mutation Arity Fix (engine.lisp)
- **Problem:** `mutate` used hardcoded `(member op '(h x_gate ...))` — missing `t`, `tdg`, `s`, `sdg` as 1-arg operators. Produced garbage ASTs like `(T Q1 Q2)`.
- **Fix:** `single-arg-operator-p` predicate + `compatible-arity-ops` filter.

### 2. Identity Fallback Removal (quantum.pl)
- **Problem:** `build_synthesis_unitary` had a catch-all returning identity for unmatched ASTs → fidelity 0.75 for *any* garbage circuit, creating a strong false local optimum.
- **Fix:** Removed catch-all. Unrecognized ASTs cause `synthesis_censor` to fail (penalty 1000).

### 3. Synthesis Domain Config (engine.lisp)
- **Problem:** `:synthesis` fell through to `:quantum` case with wrong constants `'(1 0)`.
- **Fix:** Explicit `:synthesis` clause with nil constants, explicit operators.

### 4. No Random Acceptance for Synthesis (engine.lisp)
- **Problem:** 15% random-accept constantly overwrote progress with garbage.
- **Fix:** `(and (not (eq domain :synthesis)) (< (random 100) 15))`.

### 5. Stagnation/Novelty Mode Fix (engine.lisp)
- **Problem:** Target→novelty→target reset `best-penalty` and overwrote `best-ast`.
- **Fix:** `saved-best-ast` / `saved-best-penalty` preserved across mode switches.

### 6. ADF Extraction Disabled for Synthesis (engine.lisp)
- **Problem:** Winner ASTs registered as ADF symbols → `(H ADF-1)` which gate parser couldn't expand.
- **Fix:** `(unless (eq domain :synthesis) ...)`.

### 7. Added T/TDG/S/SDG to Prolog Censor (quantum.pl)
- Clauses for `valid_quantum_structure`, `is_quantum_redundant`, `find_qubits`.
- Complex gate matrices (T=π/8, TDG, S=√i, SDG).
- `toffoli_target/1` — 8×8 CCNOT matrix.
- `synthesis_censor/2` with gate fidelity via complex matrix arithmetic.

### 8. Created Python Verifier + Bugfix
- `verify_toffoli.py` — independent fidelity check via numpy.
- Found `_parse_args` returning raw strings for nested sub-expressions → all multi-gate circuits evaluated as identity.
- **Fix:** recursive `parse_ast` call in `_parse_args`.

## Phase 2 — Anti-Identity & Search Improvements (uncommitted)

### 9. Anti-Identity Penalty via Trace (quantum.pl)
- **Problem:** Identity (all 3 H·H pairs) gives Fidelity=0.75 with Trace=8. Original state simulator couldn't distinguish identity (Tr=8) from CNOT (Tr=4) at same fidelity. Search got stuck producing identity circuits.
- **Fix:** Added `ctrace(UCandidate, c(Re,Im))` → `TraceMag = sqrt(Re²+Im²)`. If `TraceMag > 7.5` and `Fidelity < 0.8`, add `IdentityPenalty = 1000.0`.
- **Result:** Identity: Penalty ≈ 1258.5 (vs CNOT at same fidelity: 260.5). Search escapes identity plateau.

### 10. Synthesis-Specific Mutation (engine.lisp)
- `random-gate()` — generates random gate (never `seq`).
- `gate-insertion-mutation` — inserts random gate at leaf.
- `gate-deletion-mutation` — removes random leaf gate.
- `circuit-crossover` — swaps random subtrees between two circuits.
- `synthesis-mutate` — dispatcher: 25% insertion, 20% deletion, 55% standard mutate.
- Worker loop uses `synthesis-mutate` + `circuit-crossover` for `:synthesis` domain.

### 11. Stagnation Threshold Lowered (engine.lisp)
- **Changed:** 100 → 50 iterations before switching to novelty mode.

### 12. Iterations Increased (run_toffoli_decomp.lisp)
- **Changed:** 5000 → 50000 iterations per thread.

### 13. Missing Gate Handlers in eval_quantum (quantum.pl)
- Added `apply_phase_to_state` for T, TDG, S, SDG, Z gates.
- Added `apply_y_to_state` for Y gate.
- Added `eval_quantum` clauses for T, TDG, S, SDG, Y, Z.

## Phase 3 — Correct Reference & Full Run (completed)

### 14. 6-CNOT Decomposition Found (Qiskit CCXGate)
- **Source:** Extracted from `qiskit.circuit.library.standard_gates.x.py` CCXGate._define() ASCII diagram
- **Verified:** Python numpy — Fidelity=1.0, exact match, max diff=2.24e-16
- **Sequence (15 gates, 6 CNOT, T-count=7):**
  `H q3, CNOT(q1,q3), T† q3, CNOT(q2,q3), T q3, CNOT(q1,q3), T† q3, CNOT(q2,q3), T q3, T q2, CNOT(q1,q2), T† q2, CNOT(q1,q2), T q1, H q3`
- **Prover (`test_toffoli_full.pl`):** Penalty=0.500009 (vs 4-CNOT incorrect: 521.0, HHH: 915.6)

### 15. Full Experiment (50000×12 threads)
- **Metrics:** 600000 ASTs, 200.6s, 2990.86 AST/s (faster due to anti-identity filter reducing identity evaluations)
- **Best found:** `(SEQ (CNOT Q1 Q3) (SEQ (TDG Q2) (T Q2)))` = effectively CNOT(q1,q3)
- **Penalty:** 254.5 (Fidelity=0.75, TraceMag=4.0, no identity penalty)
- **Target:** 0.5 (6-CNOT Toffoli)
- **All 12 threads** converged to same local minimum — island model ineffective

## Current Result
- **Anti-identity working:** No identity convergence. Identity penalized to ~1258 vs CNOT at ~255.
- **6-CNOT reference verified:** Fidelity=1.0, correct decomposition confirmed.
- **Local minimum trap:** CNOT(q1,q3) at penalty 254.5 — search cannot reach 15-gate Toffoli (penalty 0.5) because every intermediate step is uphill (single-gate mutation adds λ·Δsize while fidelity stays ~0.75 until ~14/15 gates are correct).

## Fitness Landscape Analysis

| Circuit | Gates | Fidelity | TraceMag | IdentityPen | BasePenalty | λ | SizePenalty | Total |
|---------|-------|----------|----------|-------------|-------------|---|-------------|-------|
| Identity (H·H)³ | 6 | 0.750 | 8.0 | 1000 | 1250 | 0.5 | ~4 | ~1254 |
| HHH | 3 | 0.125 | 0.0 | 0 | 875 | 0.5 | ~4 | ~916 |
| CNOT(q1,q3) | 1 | 0.750 | 4.0 | 0 | 250 | 0.5 | 4.5 | 254.5 |
| **6-CNOT Toffoli (target)** | **15** | **1.000** | **6.0** | **0** | **0** | **0.01** | **0.5** | **0.5** |

The barrier: from 254.5 → 0.5 requires adding ~14 gates through point mutations. Each addition costs +0.5×Δgates in penalty without improving fidelity. The path is entirely uphill until ~90% of the target circuit is assembled.

## Proposed Solutions (Phase 4)

| Approach | Mechanism | Expected Benefit | Status |
|----------|-----------|------------------|--------|
| **A. λ-annealing** | Start λ=0.01 for all fidelity regimes, anneal up | Allows large circuits to form before size pressure | ❌ Tried — didn't help |
| **B. Staged curriculum** | First target any 3-qubit permutation, then refine to Toffoli | Reduces target complexity | ⏳ Next candidate |
| **C. Sub-circuit seeding** | Inject known sub-patterns (H·CNOT·T†·CNOT) as building blocks | Direct composition of known solution | ⏳ Next candidate |
| **D. Bulk novelty mutation** | On stagnation, add/swap/delete 3-5 gates at once, not 1 | Larger jumps in search space | ❌ Tried (3-5) — didn't help. Try 8-12? |
| **E. Multi-objective** | Pareto on (fidelity, size) instead of scalar penalty | No single local optimum | ⏳ Untried |
| **F. Simulated annealing** | Accept uphill moves with cooling schedule | Escape local minima | ⏳ Untried |

## Known Limitations
- **Local minimum trap:** CNOT-dominated circuits (penalty ~255) are unreachable from the 15-gate Toffoli (penalty 0.5) via single-gate mutations.
- All "textbook" T-count-7 variants (Maslov, AMM2013, Nielsen & Chuang) use 4 CNOTs and give Fidelity=0.5 (cyclic permutation, not Toffoli).
- Correct decomposition requires 6 CNOTs (Shende-Markov 2008 / Qiskit CCXGate).
- Anti-identity trace imposes ~2.8× slowdown vs no trace check (though throughput recovered to 2990 AST/s likely due to more circuits being filtered early).
- Non-adjacent CNOT expansion is correct (verified via numpy).
- Island model fails when all threads converge to the same local optimum — need diversity mechanisms.

## Phase 4 A+D Attempt (completed — did not overcome barrier)
- **A (λ-annealing):** dynamic lambda_synthesis/1 (quantum.pl), set_lambda/1 (daemon.pl), send-lambda (engine.lisp). λ = 0.01→0.5 логарифмически.
- **D (bulk mutation):** bulk-mutate, :bulk in synthesis-mutate, 3-5 ops at stagnation>15.
- **Result:** 600k ASTs, 206.8s, 2901.26 AST/s — **same local minimum** CNOT(q1,q3) penalty 254.5.
- **Conclusion:** λ-annealing + bulk (3-5 ops) недостаточны для преодоления fitness landscape barrier.

## Next Actions
- [ ] **Выполнить веб-поиск** по техникам эволюционного синтеза квантовых схем (GP, curriculum learning, hierarchical decomposition, differential evolution, RL-based)
- [ ] Выбрать следующий Phase 4 подход на основе research
- [ ] Verify against 6-CNOT reference (Penalty < 1.0)

## Files Changed (Phase 1, committed)
- `v7/engine/engine.lisp` — mutation, domain config, novelty mode, ADF, random acceptance
- `v7/engine/quantum.pl` — valid structure, redundancy, find_qubits clauses; complex matrix arithmetic; synthesis_censor; gate matrices
- `v7/experiments/verify_toffoli.py` — independent fidelity verifier

## Files Changed (Phase 2, uncommitted)
- `v7/engine/engine.lisp` — synthesis mutate/insert/delete/crossover, stagnation threshold 50
- `v7/engine/quantum.pl` — anti-identity via trace, eval_quantum handlers for T/TDG/S/SDG/Y/Z
- `v7/engine/test_debug.pl` — extended with trace/fidelity/penalty tests
- `v7/experiments/run_toffoli_decomp.lisp` — iterations 5000→50000
- `v7/experiments/find_correct_toffoli.py` — numpy verification of multiple decomposition variants
- `v7/experiments/test_gate_order.py` — gate ordering and CNOT expansion tests
- `v7/experiments/test_toffoli_numpy.py` — detailed numpy Toffoli fidelity analysis

## Files Changed (Phase 3, uncommitted)
- `v7/engine/test_toffoli_full.pl` — replaced 4-CNOT reference with 6-CNOT (verified Fidelity=1.0)
- `v7/experiments/find_correct_toffoli.py` — added Qiskit_6CNOT variant
- `v7/experiments/verify_6cnot_toffoli.py` — numpy verification (Fidelity=1.0 confirmed)
- `v7/experiments/toffoli_results.log` — 50000-iteration run results (local min at penalty 254.5)
