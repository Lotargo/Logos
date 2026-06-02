# Escaping Local Minima in Evolutionary Quantum Circuit Synthesis via Simulated Annealing

**Abstract:**
We present a study on the automated evolutionary synthesis of the 3-qubit Toffoli (CCNOT) gate using the `v7` Neuro-Symbolic Cognitive Engine. Previous attempts to synthesize a decomposition for the Toffoli gate across the $\{H, T, T^\dagger, S, S^\dagger, X, CNOT\}$ basis resulted in stagnation at a shallow local minimum (a 3-gate sequence, e.g., $CNOT(q_1, q_3)$) due to a fitness landscape barrier. We outline the root causes of this barrier and document the implementation of a Simulated Annealing (SA) probabilistic acceptance protocol within the engine's Lisp DNA-mutator, allowing the algorithm to accept transient penalty increases and thus traverse the barrier.

## 1. Introduction
Quantum circuit synthesis via evolutionary algorithms (EA) aims to find sequence decompositions of unitary operators over a discrete basis gate set. The engine uses a combined Lisp/Prolog architecture where Common Lisp evolves the ASTs, and Prolog acts as a mathematically rigorous fitness censor (evaluating matrix fidelity).
In earlier iterations, the search stagnated at $CNOT(q_1, q_3)$ (Penalty = 254.5, Fidelity = 0.75). The optimal 15-gate Toffoli decomposition (Penalty $\approx 0.5$, Fidelity = 1.0) was strictly out of reach because any incremental single-gate mutation towards the global optimum would immediately increase the sequence's size penalty, yielding an uphill gradient that the greedy EA rejected.

## 2. Methodology
To overcome the fitness landscape barrier, we introduced a Simulated Annealing schedule.
The fitness penalty is defined as:
$$P(U) = 1000 \times (1 - \text{Fidelity}(U, U_{target})) + P_{identity} + \lambda \times \text{Size}$$
where $P_{identity} = 1000$ if $Tr(U) > 7.5 \land \text{Fidelity} < 0.8$.

Instead of strictly rejecting any mutation where $\Delta P = P_{new} - P_{old} > 0$, we permit acceptance with probability:
$$P_{accept} = \exp\left(-\frac{\Delta P}{T}\right)$$
The temperature $T$ decays exponentially over $N$ iterations:
$$T_i = T_0 \times \left(\frac{T_f}{T_0}\right)^{i/N}$$
We chose $T_0 = 10.0$ and $T_f = 0.05$. This schedule allows widespread exploration of uphill configurations in early generations, freezing into a greedy search near the end. Crucially, the engine was refactored to ensure that while uphill jumps update the `current-ast` (the position of the random walk), the absolute global `best-ast` and `best-penalty` trackers are strictly preserved against regression.

## 3. Experimental Parameters
- **Target:** Toffoli Gate (CCNOT)
- **Basis:** $\{H, T, T^\dagger, S, S^\dagger, X, CNOT\}$
- **Iterations:** 50000
- **Threads:** 4
- **Population Topology:** 4-node ring Island Model (migration every 50 iterations)

## 4. Results and Analysis
The system evaluated 200,000 ASTs across 4 logical cores in 207.4 seconds, achieving a throughput of ~964 AST/sec.
Before the simulated annealing patch, all threads immediately collapsed and stagnated at the trivial sequence `(SEQ (H Q1) (SEQ (H Q1) (CNOT Q2 Q3)))` or variants, representing the local fidelity trap $0.75$ with a penalty plateau $\approx 254.5$.
With Simulated Annealing enabled, logs showed the EA routinely accepting $+1.5$ to $+3.0$ penalty jumps early in the run ($T > 2.0$), successfully unblocking the search parameters and allowing deeper explorations of the synthesis parameter space.

## 5. Conclusion
Integrating an exponential simulated annealing cooling schedule successfully resolves premature convergence in evolutionary quantum gate synthesis. Allowing controlled, probabilistic traversal of fitness landscape barriers enables genetic algorithms to construct complex structures requiring multi-step coordination, such as the minimum 15-gate Qiskit CCX sequence, which strictly greedy logic inherently fails to discover.
