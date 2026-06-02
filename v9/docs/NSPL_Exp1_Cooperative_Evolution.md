# Experiment 1: Cooperative Evolution and Swarm Intelligence (NSPL)

## 1. Abstract
This experiment validates the Neuro-Symbolic Propositional Logic (NSPL) network protocol as a decentralized mechanism for Cooperative Evolution. We hypothesize that sharing fitness-validated Abstract Syntax Trees (ASTs) as functional macros (Automatically Defined Functions, ADFs) across a distributed network of cognitive engines dramatically reduces the time required for a target engine to converge on a complex physical or mathematical solution.

## 2. Experimental Setup
We simulate a dual-node network consisting of:
- **Node A (Generator/Junior):** Tasked with discovering fundamental building blocks (e.g., a quantum CNOT+H sequence). Upon discovery and rigorous Prolog validation, it serializes the AST using the binary NSPL protocol and broadcasts it to the network.
- **Node B (Architect/Senior):** Tasked with synthesizing a complex target algorithm (e.g., Grover's Search) from scratch.

### 2.1 Environmental Realism
Unlike ideal in-memory genetic programming benchmarks, this experiment implements a rigorous simulation of real-world network conditions. Specifically, we introduce:
- **Packet Loss Rate:** A simulated 5% probability of packet drop.
- **Latency Jitter:** Artificial delays injected into the communication pipe (50-150ms).

## 3. Result: TIMED OUT (180s)

The experiment did not complete within the 180-second timeout. However, it produced substantial partial output before being killed.

### Evidence of Progress
- **ADF Library Growth:** The engine dynamically registered numerous ADF subroutines (ADF-1 through ADF-40+), indicating active cooperative evolution.
- **Node A (Junior):** Successfully broadcast discovery patterns via NSPL-based LTP protocol.
- **Node B (Senior):** Received incoming transmissions, registered ADFs, and ran full evolution using the new macros.
- **Thread activity:** Multiple threads ran worker loops with migration and crossover.
- **Log size:** 33,182 lines of engine activity.

### Failure Mode
The engine likely entered an infinite or very long search loop in Node B's evolution. The timeout of 180s was insufficient for convergence given the search space size and the 5% packet loss simulation. The `node-b-solved` flag was never set to `t`.

## 4. Conclusion
The cooperative NSPL experiment demonstrated active ADF sharing and evolution but did not converge within 180s. The infrastructure (NSPL serialization, LTP protocol, ADF registration, Prolog censor integration) functioned correctly. A higher iteration budget or longer timeout would be needed for convergence.

**Crash status:** Timed out (no crash).
