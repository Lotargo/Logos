# Escaping Local Minima in Evolutionary Quantum Circuit Synthesis via Simulated Annealing: A Negative Result

**Abstract.** We present a controlled experiment evaluating whether Simulated Annealing (SA) can overcome the fitness landscape barrier in evolutionary synthesis of the 3-qubit Toffoli (CCNOT) gate using the v7 Neuro-Symbolic Cognitive Engine. Despite the integration of an exponential SA cooling schedule ($T_0 = 10.0$, $T_f = 0.05$) within the engine's Lisp DNA-mutator, the search collapsed to the same trivial 3-gate local minimum previously observed with purely greedy selection: $\texttt{(SEQ (H q1) (SEQ (H q1) (CNOT q2 q3)))}$ (effective unitary: $I_2 \otimes \text{CNOT}$, gate fidelity $F = 0.75$, penalty $\approx 250$). We demonstrate that the SA temperature scale is insufficient to bridge the $\Delta \approx 250$ penalty gap between the observed local minimum and the known optimal 15-gate decomposition (penalty $\approx 0$), yielding an acceptance probability $P_{\text{accept}} = \exp(-250 / 10) \approx 1.4 \times 10^{-11}$ even at the initial temperature. This negative result establishes a lower bound on the required SA temperature scale for this class of synthesis problems and motivates alternative landscape-bridging strategies.

## 1. Introduction

Quantum circuit synthesis via evolutionary algorithms (EA) aims to find sequence decompositions of unitary operators over a discrete basis gate set. The engine uses a combined Lisp/Prolog architecture where Common Lisp evolves Abstract Syntax Trees (ASTs), and Prolog evaluates them via symbolic matrix computation, computing gate fidelity against a target unitary [1].

The Toffoli (CCNOT) gate — a 3-qubit gate that flips the target qubit $q_3$ iff both control qubits $q_1$ and $q_2$ are in state $|1\rangle$ — requires a minimum of 15 elementary gates over the Clifford+T basis $\{H, T, T^\dagger, S, S^\dagger, X, \text{CNOT}\}$ [2]. Previous attempts with pure greedy selection (strictly rejecting any uphill penalty move) stagnated at the identity-like circuit $\texttt{(CNOT q2 q3)}$, which attains a gate fidelity of $F = 0.75$ with respect to the Toffoli target.

The fitness (penalty) function for synthesis is:

$$P(U) = 1000 \times (1 - \text{Fidelity}(U, U_{\text{CCNOT}})) + P_{\text{identity}} + \lambda \times \text{Size}$$

where $P_{\text{identity}} = 1000$ if $\text{Tr}(U) > 7.5 \land \text{Fidelity} < 0.8$ (anti-identity trap penalty), and $\lambda$ is annealed from $0.01$ to $0.50$ over the run to gradually favor smaller circuits.

## 2. Simulated Annealing Implementation

To overcome the fitness landscape barrier, we introduced an exponential Simulated Annealing schedule in the worker loop (`engine.lisp:444-451`). Instead of strictly rejecting any mutation with $\Delta P = P_{\text{new}} - P_{\text{old}} > 0$, the engine permits acceptance with probability:

$$P_{\text{accept}} = \exp\left(-\frac{\Delta P}{T}\right)$$

The temperature $T$ decays exponentially over $N$ iterations:

$$T_i = T_0 \times \left(\frac{T_f}{T_0}\right)^{i/N}$$

with $T_0 = 10.0$ and $T_f = 0.05$. Crucially, while uphill jumps update the `current-ast` (the position of the random walk), the absolute global `best-ast` and `best-penalty` trackers are strictly preserved against regression. This design ensures the SA explores high-penalty configurations without losing the best-discovered solution.

## 3. Experimental Configuration

- **Target:** Toffoli Gate (CCNOT), 8×8 complex unitary matrix
- **Basis:** $\{H, T, T^\dagger, S, S^\dagger, X, \text{CNOT}\}$
- **Starting AST:** $\texttt{(SEQ (H q1) (SEQ (H q2) (H q3)))}$
- **Iterations:** 50,000 (12,500 per island thread)
- **Threads:** 4
- **Population Topology:** 4-node ring Island Model (migration every 50 iterations, FIFO buffer of 5)
- **Lambda Annealing:** $\lambda = 0.01 + 0.49 \times \min(i/N, 1.0)$, updated every $N/50$ iterations
- **Novelty Search Mode:** Auto (switches to novelty targets after 50 iterations of stagnation; restores best target solution after 5 novelty discoveries)
- **Fitness Function:** $P = 1000(1-F) + P_{\text{identity}} + \lambda \cdot \text{Size}$, where $F$ is the absolute gate fidelity $F = |\text{Tr}(U_{\text{CCNOT}}^\dagger U_{\text{candidate}})| / 8$

## 4. Results

### 4.1 Performance Metrics

| Metric | Value |
|--------|-------|
| Total Elapsed Time | 207.4280 s |
| Logical CPU Cores | 4 |
| Total ASTs Evaluated | 200,000 |
| Throughput | 964.19 AST/s |
| Avg Latency per AST | 1.0371 ms |

The system evaluated 200,000 ASTs across 4 threads, yielding an average throughput of 964.19 evaluations per second and an average latency of 1.04 ms per evaluation. This latency is dominated by the Prolog symbolic matrix construction, Kronecker expansion to 8×8 complex matrices, and complex matrix multiplication required for fidelity computation.

### 4.2 Discovered Solution

All four threads converged to the same trivial AST:

```
(SEQ (H Q1) (SEQ (H Q1) (CNOT Q2 Q3)))
```

This circuit simplifies to $H \cdot H \otimes \text{CNOT} = I_2 \otimes \text{CNOT}$ on 3 qubits — a CNOT gate acting on qubits $q_2$ (control) and $q_3$ (target), with $q_1$ completely decoupled. This is the same local minimum previously observed with purely greedy selection.

### 4.3 Fidelity Analysis

The gate fidelity of $I_2 \otimes \text{CNOT}$ with respect to the Toffoli target is:

$$F = \frac{|\text{Tr}(U_{\text{CCNOT}}^\dagger \cdot (I_2 \otimes \text{CNOT}))|}{8} = \frac{6}{8} = 0.75$$

Each of the 8 computational basis states contributes to the trace as shown in Table 1.

**Table 1: Trace contribution per basis state**

| State $|q_1 q_2 q_3\rangle$ | CCNOT output | CNOT output | $\text{Tr}$ contrib. |
|---|---|---|---|
| $|000\rangle$ | $|000\rangle$ | $|000\rangle$ | 1 |
| $|001\rangle$ | $|001\rangle$ | $|001\rangle$ | 1 |
| $|010\rangle$ | $|010\rangle$ | $|011\rangle$ | 0 |
| $|011\rangle$ | $|011\rangle$ | $|010\rangle$ | 0 |
| $|100\rangle$ | $|100\rangle$ | $|100\rangle$ | 1 |
| $|101\rangle$ | $|101\rangle$ | $|101\rangle$ | 1 |
| $|110\rangle$ | $|111\rangle$ | $|111\rangle$ | 1 |
| $|111\rangle$ | $|110\rangle$ | $|110\rangle$ | 1 |

The four states that differ ($|010\rangle$, $|011\rangle$) are precisely those where the CNOT erroneously flips $q_3$ when only $q_2$ (but not $q_1$) is $|1\rangle$.

### 4.4 Penalty Analysis

The matrix trace of $I_2 \otimes \text{CNOT}$ is $\text{Tr}(I_2) \times \text{Tr}(\text{CNOT}_4) = 2 \times 2 = 4$. Since $4 < 7.5$, the anti-identity penalty is **not** triggered. The penalty of the discovered circuit is thus:

$$P = 1000 \times (1 - 0.75) + 0 + \lambda \times 9 \approx 250$$

where $\text{Size} = 9$ (3 seq + 2 H + 1 CNOT + 3 qubit references).

The known optimal 15-gate Toffoli decomposition [2] achieves $F = 1.0$, yielding $P \approx 15 \times 0.005 = 0.075$ (near zero). The penalty gap between the local trap and the global optimum is therefore $\Delta P \approx 250$.

### 4.5 SA Parameter Analysis

The SA acceptance probability for a jump of magnitude $\Delta P$ is $P_{\text{accept}} = \exp(-\Delta P / T)$. For the gap $\Delta P \approx 250$:

- At $T_0 = 10.0$: $P_{\text{accept}} = \exp(-25) \approx 1.39 \times 10^{-11}$
- At $T_{25000} \approx 0.707$: $P_{\text{accept}} = \exp(-353.6) \approx 10^{-154}$
- At $T_{50000} = 0.05$: $P_{\text{accept}} = \exp(-5000) \approx 0$

Figure 1 illustrates the acceptance probability as a function of $\Delta P$ and temperature:

```
P_accept(ΔP, T)
  T=10.0:  exp(-250/10)  = 1.4e-11  (essentially zero)
  T=100:   exp(-250/100) = 0.082    (barely plausible)
  T=250:   exp(-250/250) = 0.368    (reasonable exploration)
```

**The SA temperature scale is the root cause of failure.** With $T_0 = 10.0$, the algorithm is fundamentally incapable of accepting jumps of $\Delta P > 30$ with any meaningful probability. Yet the landscape requires traversing a penalty barrier of $\Delta P \approx 250$ to escape the local minimum. The SA schedule is entirely ineffective for this problem.

Furthermore, single-gate mutations (insertion, deletion, or replacement) produce penalty changes on the order of $\Delta P \approx \lambda \approx 0.01\text{--}0.50$ from size alone, plus fidelity changes of $O(10\text{--}100)$ from structural changes. The SA temperature is high enough to accept the former (minor size changes) but catastrophically too low to accept the latter (fidelity landscape transitions).

### 4.6 Comparison with Quick Test

A separate 1,000-iteration run (same SA parameters) produced a different, non-trivial circuit:

```
(SEQ (T Q1)
  (SEQ (SEQ (SEQ (SDG Q2) (H Q3))
            (SEQ (T Q3) (S Q2)))
       (SEQ (H Q3) (T Q2))))
```

This 7-gate circuit explores significantly more of the search space but still does not implement Toffoli. The divergence between the short and long runs suggests that SA's early exploration can temporarily escape the local trap, but as the temperature cools and $\lambda$ anneals upward, the greedy descent phase pulls the search back to the nearest (trivial) local minimum. The longer the run, the more time the greedy phase has to regress.

## 5. Root Cause Analysis

The failure of SA in this experiment is attributable to three interacting factors:

### 5.1 Mismatched Temperature Scale
The initial temperature $T_0 = 10.0$ was chosen arbitrarily, not derived from the typical penalty scale of the problem. The penalty function has a natural scale of $O(100\text{--}1000)$ (the fidelity term $1000(1-F)$ dominates). For SA to be effective, the initial temperature must be on the order of the typical penalty barrier height, i.e., $T_0 \sim 250\text{--}500$ for this problem. The chosen $T_0 = 10.0$ is too cold by a factor of 25--50.

### 5.2 Competing Lambda Annealing
The $\lambda$ parameter, which multiplies the circuit size penalty, is annealed from $0.01$ to $0.50$ over the run. This means the size penalty grows 50-fold as the search progresses, increasingly favoring shorter circuits over faithful ones. Late in the run, the algorithm faces a strong pressure to delete gates, which actively counteracts the exploration that SA might enable. The combined effect is a search that briefly explores early (when $\lambda$ is small and $T$ is high) but is increasingly constrained to trivial solutions (when $\lambda$ is large and $T$ is cold).

### 5.3 Single-Gate Mutation Horizon
The mutation operators (single-gate insertion, deletion, replacement) produce small, local changes. The penalty landscape between the 3-gate trivial circuit and the 15-gate optimal solution consists of a long plateau of intermediate penalty values. Each individual mutation changes the penalty by $O(\lambda)$ from size changes. To progress from 3 gates to 15 gates, the algorithm must accept 12 consecutive disadvantageous mutations (each increasing size), then hope the fidelity improvements compensate. The SA temperature is too low to accept even a single size-increasing mutation once $\lambda > 0.1$, and the probability of accepting 12 in sequence is effectively zero.

## 6. Corrective Recommendations

### 6.1 Temperature Rescaling
Set $T_0$ based on the characteristic penalty scale of the problem. For the Toffoli synthesis, $T_0 = \max(1000(1-F_{\text{trap}}), 100) = 250$ is a natural starting point. A common heuristic is to set $T_0$ such that the initial acceptance rate for random moves is $\approx 0.8$, which requires sampling the penalty distribution of random mutations.

### 6.2 Decouple Lambda from SA Schedule
The $\lambda$-annealing for Occam's Razor should operate independently from the SA temperature schedule, or be disabled during the exploration phase. When $\lambda$ grows large, it effectively creates a potential well around small circuits from which no temperature can escape.

### 6.3 Mutations with Larger Step Sizes
Introduce a "bulk swap" operator that replaces a contiguous subsequence of gates with a random alternative of varying length, allowing jumps across the fidelity landscape that multiple single-gate mutations cannot achieve. (The existing `bulk-mutate` function applies 3--5 random insertions/deletions, which may still be too local.)

### 6.4 Adaptive Temperature
Replace the fixed exponential schedule with an adaptive schedule that maintains a target acceptance ratio (e.g., the modified Lam schedule or adaptive simulated annealing), which automatically adjusts $T$ to the landscape's scale.

## 7. Conclusion

This experiment provides a rigorous negative result: the implemented Simulated Annealing schedule ($T_0 = 10.0$, $T_f = 0.05$) is **insufficient** to escape the local minimum at $P \approx 250$ in Toffoli gate synthesis. The SA acceptance probability for the required $\Delta P \approx 250$ jump is $P_{\text{accept}} \approx 10^{-11}$ even at maximum temperature — effectively no different from greedy selection. The algorithm evaluated 200,000 ASTs over 207.4 seconds (throughput 964.19 AST/s) but produced the same trivial 3-gate circuit as greedy baselines.

The root cause is a fundamental scale mismatch between the SA temperature and the problem's penalty landscape. Correcting this requires setting $T_0 \sim 250$ or adopting adaptive temperature control, decoupling the $\lambda$ size penalty from the SA schedule, and implementing cross-barrier mutation operators. The results establish an empirical lower bound for SA parameters in quantum circuit synthesis and highlight the importance of landscape-aware temperature selection when combining SA with compound fitness functions.

## References

[1] v7 Cognitive Engine architecture: `v7/engine/engine.lisp` (SA logic at lines 444--451); Prolog synthesis censor at `v7/engine/quantum.pl` (lines 770--801, `synthesis_censor/2`).

[2] Minimum Toffoli decomposition (15 gates over Clifford+T): Amy, M., Maslov, D., Mosca, M., & Roetteler, M. (2013). A meet-in-the-middle algorithm for fast synthesis of depth-optimal quantum circuits. *IEEE Transactions on Computer-Aided Design of Integrated Circuits and Systems*, 32(6), 818--830.
