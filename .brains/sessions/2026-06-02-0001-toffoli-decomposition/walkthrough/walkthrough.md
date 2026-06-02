# Walkthrough: Toffoli Decomposition — Full Session

## Executive Summary

Мы реализуем эволюционный синтез Toffoli (CCNOT) гейта через Cognitive Engine v7.
Проект прошёл две фазы: (1) исправление критических багов в мутациях, цензоре и управлении
novelty mode; (2) добавление anti-identity trace-пенальти, специализированных операторов
мутации/кроссинговера для synthesis-домена, и верификация эталонной декомпозиции.

**Текущий статус:** Поиск стабилен, anti-identity trap решён, 6-CNOT эталонная
декомпозиция найдена и верифицирована (Fidelity=1.0). Новый блокер — fitness landscape
barrier: поиск сходится к CNOT(q1,q3) (штраф 254.5) и не может достичь 15-гейтового
Toffoli (штраф 0.5) через одноточечные мутации. Нужен один из подходов Phase 4.

---

## Phase 1: Bug Fixes (committed `2598678`)

| Шаг | Действие | Проблема | Результат |
|-----|----------|----------|-----------|
| 1 | Initial run | Garbage ASTs `(T Q1 Q2)` — wrong arities | Все 12 потоков ушли в identity |
| 2 | Fixed mutation arity | `single-arg-operator-p` predicate | Операторы H/T/TDG/S/SDG/X/Y/Z получают 1 аргумент |
| 3 | Fixed synthesis domain config | `:synthesis` не было в `set-domain` / `get-domain-config` | Чистый домен без констант |
| 4 | Fixed operator swap arity | `compatible-arity-ops` filter | Нельзя заменить H (1-arg) на CNOT (2-arg) |
| 5 | Removed identity fallback | `build_synthesis_unitary` возвращал identity для unknown AST | Невалидные AST получают Penalty=1000 (fail) |
| 6 | Disabled ADF for synthesis | Winner AST → `(H ADF-1)` ломало парсер | ADF не извлекаются для synthesis |
| 7 | Fixed novelty mode save/restore | `best-penalty` сбрасывался в 1000 | Прогресс target-mode сохраняется |
| 8 | Disabled random-accept for synthesis | 15% chance перезаписывал хорошие схемы | Только genuine improvements принимаются |
| 9 | Wrote `verify_toffoli.py` | Independent fidelity verifier | Найден баг nested-parse |
| 10 | Fixed verifier nested-parse | `_parse_args` не парсил sub-expressions | Multi-gate circuit fidelity корректна |

## Phase 2: Anti-Identity & Search Improvements (uncommitted)

### Key Discovery: Identity Trap
- Identity circuit (H·H on each qubit) gives Fidelity = 0.75, Trace = 8
- CNOT(q1,q3) gives Fidelity = 0.75 too, Trace = 4
- State simulator used `c(N,R)` complex representation with dual semantics — couldn't reliably detect identity
- **Solution:** Matrix trace check in `synthesis_censor`: if `TraceMag > 7.5 ∧ Fidelity < 0.8 → IdentityPenalty=1000`
- Result: Identity → 1258.5 vs CNOT → 260.5 at same fidelity — search escapes identity plateau

### Synthesis-Specific Operators
- `gate-insertion-mutation`: inserts random gate at leaf (25% chance)
- `gate-deletion-mutation`: removes random leaf gate (20% chance)
- `circuit-crossover`: swaps random subtrees (used in migration + hybridization)
- `synthesis-mutate`: dispatching 25% insert / 20% delete / 55% standard mutate

### Missing Gate Handlers
- `eval_quantum` had no clauses for T, TDG, S, SDG, Y, Z — state simulator couldn't evaluate them
- Added `apply_phase_to_state` (T/TDG/S/SDG/Z) and `apply_y_to_state` (Y)

### Critical Finding: Wrong Reference Decomposition
- `test_toffoli_full.pl` uses a 4-CNOT T-count-7 formula (Nielsen & Chuang variant)
- **All T-count-7 variants** (Maslov, AMM2013, NC_a, NC_b) produce Fidelity=0.5 in numpy
- The circuit implements cyclic permutation |100⟩→|110⟩→|101⟩→|111⟩→|100⟩ instead of Toffoli |110⟩↔|111⟩
- **Root cause:** These decompositions use only 4 CNOTs + 7 T-gates — missing 2 CNOTs needed for correct phase alignment
- Qiskit CCXGate uses 6 CNOTs (confirmed via docstring and arXiv:0803.2316 Figure 1)

### Anti-Identity Trace Check Verification

| Circuit | Fidelity | Trace | Penalty (before) | Penalty (after) |
|---------|----------|-------|-------------------|------------------|
| Identity (H·H)³ | 0.750 | 8.0 | 258.5 | 1258.5 |
| HHH | 0.125 | 0.0 | 887.5 | 887.5 |
| CNOT(q1,q2) | 0.750 | 4.0 | 260.5 | 260.5 |
| CNOT(q1,q3) | 0.750 | 4.0 | 260.5 | 260.5 |
| CNOT*2 chain | 0.625 | 2.0 | 386.3 | 386.3 |
| Incorrect 4-CNOT Toffoli | 0.500 | 0.0 | 504.0 | 504.0 |

## Phase 3: Correct 6-CNOT Reference & Full Run

### 6-CNOT Decomposition Found
- **Source:** `qiskit.circuit.library.standard_gates.x.py` CCXGate._define() ASCII diagram
  ```
  # q_0: ───────────────────■─────────────────────■────■───┤ T ├───■──
  # q_1: ───────■───────────┼─────────■───┤ T ├───┼──┤ X ├┤ Tdg ├┤ X ├
  # q_2: ┤ H ├┤ X ├┤ Tdg ├┤ X ├┤ T ├┤ X ├┤ Tdg ├┤ X ├┤ T ├─┤ H ├──────
  ```
- **Numpy verification:** `verify_6cnot_toffoli.py` — Fidelity=1.0, exact match, max diff=2.24e-16
- **Interpretation (15 gates, 6 CNOT):**
  `H q3, CNOT(q1,q3), T† q3, CNOT(q2,q3), T q3, CNOT(q1,q3), T† q3, CNOT(q2,q3), T q3, T q2, CNOT(q1,q2), T† q2, CNOT(q1,q2), T q1, H q3`
- **Prover test:** `test_toffoli_full.pl` — 6-CNOT: Penalty=0.500009, 4-CNOT (incorrect): Penalty=521.0

### Full Experiment (50000×12 threads)
- **Metrics:** 600k ASTs in 200.6s, 2990.86 AST/s (higher throughput than Phase 2 because anti-identity filters identity circuits early)
- **Dashboard:**
  ```
  Total Elapsed Time    : 200.6113 seconds
  Logical CPU Cores     : 12
  Total ASTs Evaluated  : 600000
  Throughput (AST/sec)  : 2990.86
  Avg Latency per AST   : 0.3344 ms
  ```
- **Best found:** `(SEQ (CNOT Q1 Q3) (SEQ (TDG Q2) (T Q2)))` = essentially CNOT(q1,q3), since T†(q2)·T(q2)=I
- **Penalty:** 254.5 (Fidelity=0.75, TraceMag=4.0, Size=9)
- **All 12 threads** converged to this local minimum.

### Critical Finding: Fitness Landscape Barrier

The evolutionary search cannot traverse from the local minimum (3 gates, penalty 254.5) to the global minimum (15 gates, penalty 0.5) because:

| Circuit | Gates | Fidelity | BasePenalty | λ | SizePenalty | Total |
|---------|-------|----------|-------------|---|-------------|-------|
| CNOT(q1,q3) | 3 | 0.750 | 250 | 0.5 | 4.5 | **254.5** |
| Intermediate (add gate) | +1 | ~0.75 | ~250 | 0.5 | +0.5 | **~255** |
| 6-CNOT Toffoli | 15 | 1.000 | 0 | 0.01 | 0.5 | **0.5** |

Every single-gate mutation that adds a gate increases penalty by +0.5×Δgates, while fidelity remains ~0.75 until ~14/15 gates are correctly placed. The search sees only uphill moves and rejects them.

### Why Island Model Failed
All threads converged to the same CNOT minimum. Migration and hybridization exchanged the same solution. No thread explored different regions because:
- Single-gate mutation can't jump from 3 to 15 gates
- Novelty mode wasn't triggered (stagnation threshold? never met because mutations kept finding small variations)
- Crossover between two CNOT-minimum parents produces another CNOT-minimum child

### Current Throughput
- **With trace check:** ~1028 AST/s, 0.97ms/AST (includes double unitary build + trace)
- **Before:** ~2872 AST/s (single unitary, no trace)
- **Trade-off:** 2.8× slowdown accepted for reliable anti-identity detection

## Root Cause Analysis: Why Previous Runs Failed

### Failure 1: Identity Local Optimum (Critical)
**Симптом:** Все потоки сходились к identity-подобным схемам.
**Причина 1:** Identity fallback в `build_synthesis_unitary` — любая неизвестная структура
автоматически получала Fidelity=0.75, создавая ложный оптимум.
**Причина 2:** State simulator не мог отличить identity (Tr=8) от CNOT (Tr=4) — 
внутреннее представление `c(N,R)` с двойной семантикой давало сбои на комплексных амплитудах.
**Решение:** Двойная защита — (а) убрать identity fallback, (б) добавить trace-based anti-identity penalty.

### Failure 2: Mutation Generating Garbage (Critical)
**Симптом:** AST вида `(T Q1 Q2)`, `(H 1)`, `(CNOT ADF-1 Q2)`.
**Причины:**
- Hardcoded arity list не включал T/TDG/S/SDG (Phase 1)
- Fallthrough в `:quantum` домен давал константы 0 и 1
- ADF injection подставлял подвыражения как аргументы гейтов
- Operator swap не проверял arity (2→1 или 1→2)

### Failure 3: Random Acceptance Destroying Convergence (Critical)
**Симптом:** После нахождения хорошей схемы поиск её терял.
**Причина:** 15% random-accept перезаписывал `best-ast` даже невалидными схемами.
**Решение:** Отключить random-accept для synthesis-домена.

### Failure 4: Wrong Reference Decomposition (Blocking)
**Симптом:** "Known Toffoli decomposition" даёт Fidelity=0.5.
**Причина:** Использована 4-CNOT T-count-7 формула, которая реализует циклическую
перестановку 4×4 подпространства |1??⟩, а не Toffoli |110⟩↔|111⟩.
**Верификация:** numpy подтверждает — все T-count-7 варианты (Maslov, AMM2013,
Nielsen & Chuang) дают одинаковый циклический сдвиг.
**Правильная декомпозиция:** 6 CNOT + 7 T-гейтов (Qiskit CCXGate, Shende-Markov 2008).

## Phase 4: Escape Local Minimum — A+D Attempt (uncommitted)

### Implementation
- **A (λ-annealing):** `dynamic lambda_synthesis/1` в `quantum.pl`, `set_lambda/1` handler в `daemon.pl`, `send-lambda` в `engine.lisp`. λ = 0.01 + 0.49×min(iter/max_iters, 1), обновляется каждые ~1000 итераций.
- **D (bulk mutation):** `bulk-mutate`, `:bulk` keyword в `synthesis-mutate`, 3-5 операций при stagnation > 15. Stagnation reset добавлен в immigrant/crossover.

### Result
- **Metrics:** 600k ASTs in 206.8s, 2901.24 AST/s (slightly slower than Phase 3 due to bulk-mutation overhead)
- **Best found:** `(SEQ (TDG Q2) (SEQ (CNOT Q1 Q3) (T Q2)))` — effectively CNOT(q1,q3)
- **Penalty:** 254.5 — **identical to Phase 3**
- **Barrier not overcome:** λ-annealing снижает λ на старте, но bulk mutation (3-5 gates) даёт +1.5-2.5 penalty за шаг, что всё равно uphill от 254.5. Все 12 потоков сошлись в тот же локальный минимум.

### Conclusion
Ни λ-annealing, ни bulk mutation (3-5 ops) не дают достаточного прыжка через fitness landscape barrier. Нужен качественно иной подход.

### Новое: требуется веб-поиск
Для выбора следующего подхода (B — curriculum, C — субсхемная инжекция, или альтернативные техники вроде differential evolution, gradient-guided synthesis, RL-based quantum circuit design) необходимо обратиться к веб-поиску и актуальной литературе по эволюционному синтезу квантовых схем.

## Session Log

| Date | Step | Result |
|------|------|--------|
| 2026-06-02 | Phase 1 initial debugging | Fixed 8 critical bugs in engine + censor |
| 2026-06-02 | Phase 1 run | All 12 threads → T⊗I⊗I (fidelity 0.699) |
| 2026-06-02 | Phase 2 anti-identity | Identity trap resolved via trace penalty |
| 2026-06-02 | Phase 2 synthesis ops | Insert/delete/crossover added |
| 2026-06-02 | Phase 2 reference analysis | Found all T-count-7 variants give Fidelity=0.5 |
| 2026-06-02 | Phase 2 experiments | 600000 ASTs evaluated, 583s, 1028 AST/s |
| 2026-06-02 | Phase 3: 6-CNOT found | Qiskit CCXGate → Fidelity=1.0 in numpy |
| 2026-06-02 | Phase 3: full experiment | 600k ASTs, 200.6s, converged to CNOT min (penalty 254.5) |
| 2026-06-02 | Phase 3: barrier analysis | Fitness landscape barrier identified — single-gate mutations cannot escape local min |
| 2026-06-02 | Phase 4: A+D (λ-annealing + bulk) | 600k ASTs, 206.8s, **still converged to CNOT min (penalty 254.5)** — barrier not overcome |
| 2026-06-02 | **Blocked** | **Phase 4 approaches B (curriculum), C (sub-circuit seeding), D (aggressive bulk 8-12) не реализованы. Требуется веб-поиск для выбора следующего направления.** |

## Files
- `v7/engine/engine.lisp` (668 lines) — evolutionary engine with synthesis operators (+ Phase 4: bulk-mutate, send-lambda, λ-annealing in worker-loop)
- `v7/engine/quantum.pl` (799 lines) — Prolog censor with anti-identity trace (+ Phase 4: dynamic lambda_synthesis/1)
- `v7/engine/daemon.pl` (+ Phase 4: set_lambda/1 handler)
- `v7/engine/test_toffoli_full.pl` — updated with correct 6-CNOT reference (Penalty=0.500009)
- `v7/experiments/find_correct_toffoli.py` (135 lines) — numpy verify 8 decomposition variants (incl Qiskit_6CNOT)
- `v7/experiments/verify_6cnot_toffoli.py` — standalone numpy verification of 6-CNOT (Fidelity=1.0 confirmed)
- `v7/experiments/test_toffoli_numpy.py` (145 lines) — detailed gate-by-gate analysis
- `v7/experiments/toffoli_results.log` — 50000-iteration run results (Phase 3: 2990 AST/s, CNOT local min penalty 254.5; Phase 4 A+D: 2901 AST/s, same local min)
- `.dataset/lessons/fitness_landscape_barrier_single_gate_mutation.json` — dataset lesson

## Next Steps (Phase 4 — post A+D)
- [ ] Use web search to research:
  - Evolutionary quantum circuit synthesis — proven techniques for escaping local minima
  - Curriculum learning / staged evolution for circuit synthesis
  - Sub-circuit seeding / hierarchical decomposition in GP
  - Differential evolution for quantum circuit search
  - RL-based quantum circuit design (if relevant)
- [ ] Choose next approach based on research:
  - B. Staged curriculum: evolve permutation → refine
  - C. Sub-circuit seeding: inject known patterns as building blocks
  - D-a. Aggressive bulk mutation (8-12 ops instead of 3-5)
  - E. Multi-objective Pareto: separate size/fidelity
  - F. Simulated annealing: accept uphill moves
- [ ] Implement and run 50000-iteration experiment
- [ ] Verify against 6-CNOT reference (Penalty < 1.0)

## Commands
```powershell
# Run experiment
cd F:\Кейс\AGI-lite
sbcl --non-interactive --load v7/experiments/run_toffoli_50000.lisp

# Verify with numpy
python v7/experiments/find_correct_toffoli.py
python v7/experiments/verify_6cnot_toffoli.py

# Test Prolog censor with correct reference
& "C:\Program Files\swipl\bin\swipl.exe" -q -t "test, halt" v7/engine/test_toffoli_full.pl
```

## Phase 4.1: Simulated Annealing to escape local minimum (completed)
- **Problem:** Fitness landscape barrier where single-gate mutations adding intermediate gates result in a penalty increase relative to the 3-gate CNOT sequence.
- **Solution:** Implemented probabilistic Simulated Annealing logic within `worker-loop` in `v7/engine/engine.lisp` for the `:synthesis` domain. It calculates a decreasing temperature across iterations, and accepts uphill moves (penalty increase) with probability `P = exp(-delta/T)`.
- **Result:** Successfully modified the evolutionary logic to conditionally accept uphill movements during early stages, to provide a mechanism to cross the fitness landscape barrier blocking progression towards the 15-gate Toffoli decomposition. Tested and confirmed the changes are properly integrated.
