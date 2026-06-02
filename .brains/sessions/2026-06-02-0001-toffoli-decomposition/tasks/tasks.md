# Tasks — Toffoli Decomposition

## [x] Fix mutation arity — add t, tdg, s, sdg as 1-arg operators (engine.lisp)
## [x] Fix synthesis domain config — no constants, explicit operators (engine.lisp)
## [x] Fix operator-swapping mutation — respect arity via compatible-arity-ops (engine.lisp)
## [x] Remove identity fallback in build_synthesis_unitary (quantum.pl)
## [x] Add T/TDG/S/SDG to Prolog censor — valid_structure, redundancy, find_qubits, gate matrices (quantum.pl)
## [x] Implement synthesis_censor with complex matrix arithmetic (quantum.pl)
## [x] Disable ADF extraction for synthesis domain (engine.lisp)
## [x] Save/restore target best across novelty mode switches (engine.lisp)
## [x] Disable 15% random acceptance for synthesis domain (engine.lisp)
## [x] Write Python verifier (verify_toffoli.py)
## [x] Fix verifier nested-parse bug

## [ ] Increase iterations per thread from 5000 to 50000+
## [ ] Add gate-insertion and gate-deletion mutation operators
## [ ] Add circuit-aware crossover (swap gate subsequences between two circuits)
## [ ] Implement adaptive lambda scheduling (high λ early for small circuits, low λ later for precision)
## [ ] Add CNOT-based entanglement patterns to starting population
## [ ] Support non-adjacent CNOT qubit expansion in Prolog censor OR compile CNOT to adjacent qubits
## [ ] Add T-count minimization as secondary objective when fidelity > 0.99

## Stretch / Later
## [ ] Run with 100K+ iterations and 24+ threads
## [ ] Add reward shaping — bonus for circuits that move off the identity diagonal
## [ ] Implement iterative deepening — start with max_size=5, increase as search progresses
## [ ] Test on other targets: Fredkin (CSWAP), Deutsch, QFT2
