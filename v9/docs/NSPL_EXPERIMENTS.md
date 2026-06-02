# NSPL Swarm Intelligence Experiments: Honest Yet Unstable Report

## 1. Objective
To document the behavior of the Neural Symbolic Protocol Layer (NSPL) after eliminating scripted illusions, hardcoded mapping dictionaries, and prescribed operator sandboxes.

## 2. Experimental Setup
- **Exp 1 (Coop)**: Node B receives AST, registers it as ADF macro, launches `worker-loop`.
- **Exp 2 (GAN)**: Generator mutates hypothesis dynamically; no hardcoded "healed" fallback.
- **Exp 3 (Cross-Domain)**: Hardcoded `sublis` dictionary removed; `mask-domain` replaces foreign operators with placeholders; `worker-loop` evolves replacements.

## 3. Hard Data from Logs

### Exp 1 — Coop (v9/experiments/coop.log)
| Metric | Value |
|--------|-------|
| TIMEOUT restarts | **138** |
| Converged ASTs | 15 |
| Ultimate hybrids produced | Yes (6 per domain) |
| Crashes | 0 |
| Domains completed | Arithmetic, Calculus, Quantum, Multidim, Paradox, Relativity |
| Notable | ~90% of `censor` queries timed out; engine kept restarting Prolog |

### Exp 2 — GAN / Adversarial LENR (v9/experiments/gan.log)
| Metric | Value |
|--------|-------|
| TIMEOUT restarts | **99** |
| Converged ASTs | 14 |
| Ultimate hybrids produced | Yes (3 in A, 2 in C, 3 in Q) |
| Crashes | **1 (fatal)** — unhandled timeout in `META-MUTATE-AXIOM` with penalty=1000.0 |
| Final state | Process quit during Paradox test |
| Penalty 1000 occurrences | 1 (in backtrace) |

### Exp 3 — Cross-Domain (v9/experiments/cross.log)
| Metric | Value |
|--------|-------|
| TIMEOUT restarts | **171** |
| Converged ASTs | 18 |
| Ultimate hybrids produced | Yes (6 per domain) |
| Crashes | 0 |
| Domains completed | Arithmetic, Calculus, Quantum, Multidim, Paradox, Relativity, Thermo |
| Notable | Most domains succeeded despite extreme timeout count |

## 4. Analysis

**Timeout saturation**: In all three experiments, the first ~10 attempts per domain are TIMEOUTs on `censor(target, ...)`. The engine brute-forces through by restarting the Prolog daemon repeatedly. Both cooperating experiments (Coop, Cross) survive this; the adversarial experiment (GAN) eventually hits an unhandled timeout.

**Penalty 1000**: The GAN crash backtrace explicitly shows `META-MUTATE-AXIOM` receiving penalty `1000.0` — the maximum penalty, assigned when the evolved expression is structurally invalid for CLP(R) evaluation. This is honest: without hardcoded whitelists, nonsensical ASTs receive the maximum penalty instead of being silently passed.

**Cross-domain learning works (slowly)**: Exp 3 does evolve structural equivalents for `unknown_op` placeholders, confirming the concept is valid. However, without a dictionary, it finds valid math that is bad physics first ("Negative Transfers"), requiring many more iterations.

## 5. Conclusion
The NSPL experiments now demonstrate genuine distributed cognitive search — but at extreme computational cost. Coop and Cross survive with 138–171 timeouts per run; GAN crashes outright. The engine is honest but brittle: when it works, the results are unscripted; when it fails, it produces penalty 1000 or a fatal thread crash. Stability improvements to the Prolog evaluation bridge are prerequisite to any production use.
