# Tasks — Toffoli Decomposition

## Phase 1: Bug Fixes (committed)
- [x] Fix mutation arity — add t, tdg, s, sdg as 1-arg operators (engine.lisp)
- [x] Fix synthesis domain config — no constants, explicit operators (engine.lisp)
- [x] Fix operator-swapping mutation — respect arity via compatible-arity-ops (engine.lisp)
- [x] Remove identity fallback in build_synthesis_unitary (quantum.pl)
- [x] Add T/TDG/S/SDG to Prolog censor — valid_structure, redundancy, find_qubits, gate matrices (quantum.pl)
- [x] Implement synthesis_censor with complex matrix arithmetic (quantum.pl)
- [x] Disable ADF extraction for synthesis domain (engine.lisp)
- [x] Save/restore target best across novelty mode switches (engine.lisp)
- [x] Disable 15% random acceptance for synthesis domain (engine.lisp)
- [x] Write Python verifier (verify_toffoli.py)
- [x] Fix verifier nested-parse bug

## Phase 2: Anti-Identity & Search (uncommitted)
- [x] Replace state-simulator identity check with matrix trace check (quantum.pl)
- [x] Add anti-identity penalty: TraceMag>7.5 + Fidelity<0.8 → +1000 (quantum.pl)
- [x] Add gate-insertion-mutation (engine.lisp)
- [x] Add gate-deletion-mutation (engine.lisp)
- [x] Add circuit-crossover (engine.lisp)
- [x] Add synthesis-mutate dispatcher (engine.lisp)
- [x] Add eval_quantum handlers for T, TDG, S, SDG, Y, Z (quantum.pl)
- [x] Lower stagnation threshold 100→50 (engine.lisp)
- [x] Increase iterations 5000→50000 (run_toffoli_decomp.lisp)
- [x] Write find_correct_toffoli.py — numpy verify multiple decomposition variants
- [x] Write test_gate_order.py — verify gate ordering and CNOT expansion
- [x] Write test_toffoli_numpy.py — detailed Toffoli fidelity analysis

## Phase 3: Correct Reference & Full Run (completed)
- [x] Extract exact 6-CNOT decomposition from Qiskit CCXGate source (from GitHub qiskit/x.py ASCII diagram)
- [x] Verify extracted sequence in numpy (Fidelity=1.0, exact match, max diff=2.24e-16)
- [x] Update test_toffoli_full.pl with correct 6-CNOT decomposition (Penalty=0.500009)
- [x] Add Qiskit_6CNOT variant to find_correct_toffoli.py
- [x] Run full 50000-iteration experiment (600k ASTs, 200.6s, 2990 AST/s)
- [x] Analyze results — all threads converged to CNOT(q1,q3) (local min, penalty 254.5)

## Phase 4: Escape Local Minimum — A+D попытка (выполнена, не сработало)
- [x] Implement λ-annealing: dynamic lambda_synthesis/1 (quantum.pl), set_lambda/1 (daemon.pl), send-lambda (engine.lisp)
- [x] Implement bulk mutation: bulk-mutate, :bulk keyword in synthesis-mutate, 3-5 ops at stagnation>15
- [x] Run 50000-iteration experiment with A+D — **600k ASTs, 206.8s, still converged to CNOT(q1,q3) penalty 254.5**
- [ ] Ни λ-annealing, ни bulk (3-5 ops) не преодолели barrier

## Phase 4 — следующий подход (требуется веб-поиск)

### Root Cause
Fitness landscape barrier: 15-gate Toffoli (penalty 0.5) unreachable from 3-gate CNOT (penalty 254.5) via incremental mutations. λ-annealing + bulk (3-5 ops) не помогли.

### Research (required before next implementation)
- [ ] Perform web search on evolutionary quantum circuit synthesis techniques
- [ ] Search literature: curriculum learning for GP, hierarchical circuit synthesis, differential evolution quantum
- [ ] Document findings and recommended approach

### Candidate Approaches (pick one after research)
- [ ] **B. Staged curriculum** — First evolve any non-trivial permutation (loose target), then refine to Toffoli
- [ ] **C. Sub-circuit seeding** — Inject known sub-patterns (H·CNOT·T†·CNOT) as building blocks in starting population
- [ ] **D-a. Aggressive bulk** — 8-12 ops at once instead of 3-5 (larger jump)
- [ ] **E. Multi-objective Pareto** — Separate fidelity from size in selection (Pareto front, not scalar penalty)
- [ ] **F. Simulated annealing** — Accept uphill moves with cooling schedule

### Verification
- [ ] Run 50000-iteration experiment with chosen approach
- [ ] Verify best circuit matches 6-CNOT reference (Penalty < 1.0)
- [ ] Run `test_toffoli_full.pl` to confirm

## Stretch / Later
- [ ] Test on other targets: Fredkin (CSWAP), Deutsch, QFT2
- [ ] Run with 100K+ iterations and 24+ threads
- [ ] Adaptive mutation rate based on diversity metrics
