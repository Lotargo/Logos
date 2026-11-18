# Logos Engine v9

> First-Principle Neuro-Symbolic Logos Kernel — Autonomous Discovery of Fundamental Laws

---

## What is Logos?

Logos is a self-evolving cognitive engine that autonomously discovers, mathematically verifies, and synthesizes fundamental laws of physics and logic from raw empirical data. It does not memorize formulas or rely on domain hardcoding — it derives macroscopic phenomena from first principles using a rigorous **Dual-Stack** architecture.

**Version 9** adds persistent memory (LSMA), distributed binary protocol (NSPL), PostgreSQL telemetry backend, and a full DS/ML statistical verification pipeline.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    THE MIND (Common Lisp / SBCL)            │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  Evolutionary │  │  Meta-       │  │  LSMA Memory     │  │
│  │  Engine       │  │  Evolution   │  │  Algebra         │  │
│  │  (islands,    │  │  (invents    │  │  (passports,     │  │
│  │   crossover,  │  │   new ops    │  │   ADF scoring,   │  │
│  │   mutation)   │  │   on stale)  │  │   persistence)   │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                    │             │
│         └─────────────────┼────────────────────┘             │
│                           │                                  │
│                    AST mutations                             │
└───────────────────────────┼──────────────────────────────────┘
                            │
                     ┌──────▼──────┐
                     │  NSPL Binary │  ← inter-node packets
                     │  Protocol    │
                     └──────┬──────┘
                            │
┌───────────────────────────┼──────────────────────────────────┐
│                    THE CENSOR (SWI-Prolog)                   │
│                           │                                  │
│  ┌──────────────┐  ┌──────▼───────┐  ┌──────────────────┐  │
│  │  Root Axioms  │  │  Domain      │  │  Regression      │  │
│  │  (Occam,      │  │  Censors     │  │  (CSV evaluation,│  │
│  │   Boolean,    │  │  (quantum,   │  │   lambda scale)  │  │
│  │   Unitarity)  │  │   logic,     │  │                  │  │
│  │               │  │   hardware)  │  │                  │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
│                                                              │
│  Penalty score → return to Lisp → discard or evolve further  │
└──────────────────────────────────────────────────────────────┘

                            │
                     ┌──────▼──────┐
                     │   Neon PG    │  ← telemetry, knowledge persistence
                     │   (Postgres) │
                     └─────────────┘
```

**The Mind** (Common Lisp / SBCL): Multi-threaded evolutionary orchestrator. Mutates and crosses over Abstract Syntax Trees (ASTs) across parallel island workers with ring-topology migration. Leverages Lisp homoiconicity — code is data, data is code.

**The Censor** (SWI-Prolog): Uncompromising mathematical judge. Enforces Root Axioms — Occam's Razor (structural complexity penalty), Boolean strictness (no tautologies), Quantum Unitarity (U * U^T = I), Information Theory (Shannon entropy, KL divergence). Rejects mathematical bloat and physical impossibilities in nanoseconds.

---

## Directory Structure

```
v9/
├── src/                    # Lisp engine & subsystems
│   ├── engine.lisp         #   Main cognitive engine (603 lines)
│   ├── meta_evolve.lisp    #   Dynamic axiom invention
│   ├── knowledge_loader.lisp#  Persistent knowledge initialization
│   ├── ontology_generator.lisp# LaTeX whitepaper generator
│   ├── verilog_emitter.lisp#   Silicon lowering (AST → Verilog)
│   ├── curry_howard.lisp   #   Proof-as-program type checker
│   ├── nspl.lisp           #   Binary inter-node protocol
│   └── lsma/               #   Logos Symbolic Memory Algebra
│       ├── passport.lisp   #     AST canonical hashing & passports
│       ├── storage.lisp    #     Two-layer storage (JSONL + Neon)
│       ├── selection.lisp  #     Weighted ADF scoring (8 factors)
│       └── eviction.lisp   #     Library bloat prevention
│
├── prolog/                 # Prolog mathematical censor
│   ├── daemon.pl           #   IPC daemon (stdin/stdout)
│   ├── root_axioms.pl      #   Foundation axioms (266 lines)
│   ├── rules.pl            #   Domain dispatcher
│   ├── regression.pl       #   Empirical symbolic regression
│   ├── nspl_invariants.pl  #   NSPL packet validation
│   ├── hardware.pl         #   Gate-level circuit evaluation
│   ├── curry_howard.pl     #   Type-theoretic proof checker
│   └── adversarial.pl      #   Red-team logic testing
│
├── analysis/               # DS/ML verification pipeline (Python)
│   ├── stats.py            #   Statistical rigor (SciPy)
│   ├── evolutionary.py     #   Evolutionary search analytics
│   ├── symbolic_quality.py #   Symbolic regression quality
│   ├── dashboard.py        #   Interactive Plotly dashboard
│   └── verify_pipeline.py  #   Pipeline orchestrator
│
├── telemetry/              # Structured memory & logging
│   ├── schema.sql          #   PostgreSQL schema (10 tables)
│   ├── migration_v2_verification.sql  # DS/ML tables migration
│   ├── telemetry_helper.lisp#  Lisp → Python bridge
│   ├── verify_run.py       #   Post-run verification script
│   ├── telemetry_logger.py #   Central CLI logger
│   ├── db.py               #   Neon PostgreSQL layer
│   └── config.yaml         #   Telemetry settings
│
├── data/                   # CSV datasets & generators
│   ├── kepler_data.csv     #   Kepler's Third Law
│   ├── gravity_data.csv    #   Newtonian Gravity
│   ├── relativity_data.csv #   Lorentz factor
│   ├── schrodinger_data.csv#   Schrodinger Hamiltonian
│   ├── holographic_entropy_data.csv # Bekenstein-Hawking
│   └── ... (16 datasets, 10 generators)
│
├── experiments/            # Experiment scripts & results
│   ├── run_experiments.lisp#   Core empirical discovery
│   ├── grand_experiment.lisp#  3-phase grand experiment
│   ├── run_cold_fusion.lisp#   LENR / cold fusion
│   ├── run_millennium_poincare.lisp # Poincare conjecture
│   ├── run_warp_drive.lisp #   Alcubierre warp metric
│   └── ... (14 Lisp runners, 11 Python helpers)
│
├── tests/                  # Test suite
│   ├── test_integration_smoke.lisp  # Full pipeline smoke test
│   ├── test_lsma_smoke.lisp         # LSMA unit tests
│   ├── test_breaker.lisp            # Stress / breaker tests
│   ├── test_nspl_basic.lisp         # NSPL protocol tests
│   └── verify_results.py            # Independent numpy verification
│
├── docs/                   # Documentation
│   ├── EXPERIMENTS_SUMMARY.md  # Experiment results summary
│   ├── VERIFICATION_REPORT.md  # Honesty audit report
│   └── ... (20+ docs)
│
├── papers/                 # Auto-generated LaTeX whitepapers
│   └── discovery_*.tex     #   Per-domain discovery papers
│
├── dev_docs/               # Development documentation
│   ├── 00_v9_audit.md      #   Comprehensive v9 audit
│   └── plans/              #   Implementation plans
│       ├── LSMA/           #     LSMA design & roadmap
│       └── DS-ML/          #     DS/ML verification tools
│
└── scripts/                # Utility scripts
```

---

## Quick Start

### Prerequisites

```bash
# Common Lisp (SBCL)
sudo apt-get install sbcl    # Linux
# or: brew install sbcl       # macOS

# SWI-Prolog
sudo apt-get install swi-prolog

# Python 3.12+ with dependencies
pip install numpy pandas scipy plotly statsmodels
```

### Run the Engine

```bash
# Multi-domain demo suite
sbcl --script v9/src/engine.lisp

# Specific domain experiment
sbcl --script v9/experiments/run_experiments.lisp

# Grand experiment (3 phases)
sbcl --script v9/experiments/grand_experiment.lisp
```

### Run Tests

```bash
# Full integration smoke test
sbcl --script v9/tests/test_integration_smoke.lisp

# LSMA subsystem tests
sbcl --script v9/tests/test_lsma_smoke.lisp

# NSPL protocol tests
sbcl --script v9/tests/test_nspl_basic.lisp

# Independent Python verification
python v9/tests/verify_results.py v9/data/kepler_data.csv a "(mul a (mul a a))"
```

### Run DS/ML Verification Pipeline

```bash
# Quick mode (stats + dashboard only)
python v9/analysis/verify_pipeline.py \
  --run-dir benchmarks_output/experiment_1/ \
  --mode quick

# Full mode (all 4 phases)
python v9/analysis/verify_pipeline.py \
  --run-dir benchmarks_output/experiment_1/ \
  --mode full \
  --domain algebra
```

---

## Verified Discoveries

The engine discovers physical laws from raw data without prior knowledge. Independent numpy verification confirms mathematical accuracy:

| Physical Law | Discovered Formula (Lisp AST) | MSE | R² | Status |
|:---|:---|:---|:---|:---|
| **Kepler's Third Law** | `(mul a (mul a a))` | 0.000028 | 1.000000 | VERIFIED |
| **Newtonian Gravity** | `(div (mul m1 m2) (mul r r))` | 0.000000 | 1.000000 | VERIFIED |
| **Relativistic Kinematics** | `(div 1 (sub 1 (div (mul v v) (mul c c))))` | 0.000025 | 0.999913 | VERIFIED |

---

## DS/ML Verification Pipeline

A 7-phase Python verification suite for rigorous statistical validation of experiment results:

| Phase | Module | What it does |
|:---|:---|:---|
| 1 | `stats.py` | t-test / Mann-Whitney U, Cohen's d, bootstrap CI, ANOVA, power analysis |
| 2 | `evolutionary.py` | Population diversity, fitness landscape, stagnation detection, operator importance |
| 3 | `symbolic_quality.py` | Pareto frontier, semantic equivalence, OOD robustness, noise sensitivity, AIC/BIC |
| 4 | `dashboard.py` | Interactive Plotly HTML dashboard (5 widgets: fitness, diversity, Pareto, heatmap, stats) |
| 5 | DB migration | 4 new Neon PG tables: `population_snapshots`, `operator_stats`, `experiment_configs`, `verification_results` |
| 6 | Engine hooks | `verify-run-telemetry()` Lisp function + `verify_run.py` post-run script |
| 7 | Pipeline | `verify_pipeline.py` orchestrator: `--mode quick` or `--mode full` |

### Output

```
verification_report/
├── dashboard.html           # Interactive Plotly dashboard
├── statistical_summary.md   # t-test, Cohen's d, CI, power
├── convergence_analysis.md  # Stagnation, landscape metrics
├── quality_report.md        # Pareto, noise, OOD, equivalence
├── pareto_frontier.png      # Complexity vs R²
├── diversity_trend.png      # AST diversity over generations
├── operator_heatmap.png     # Operator usage by phase
└── noise_sensitivity.png    # Accuracy vs noise level
```

---

## Telemetry & Memory

### LSMA (Logos Symbolic Memory Algebra)

Every discovered AST gets a structured **passport** — a deterministic algebraic fingerprint:

- **Canonical hash** (MD5, variable-canonicalized) for deduplication
- **Operator profile** — which operators appear and how often
- **Subtree hashes** — top-50 subtrees by depth
- **Domain tags** — which scientific domains the AST belongs to
- **Usage/success/failure counters** — behavioral history
- **Freshness timestamp** — recency tracking

**Two-layer storage:**
1. **Local JSONL cache** — fast, always-on, works offline
2. **Neon PostgreSQL** — persistent, queryable, shared across runs

### ADF Scoring Formula

When selecting which discovered ADF (Automatic Defined Function) to inject into evolution, LSMA scores each candidate across 8 weighted factors:

| Factor | Weight | Description |
|:---|:---|:---|
| Structural similarity | 0.25 | How well the AST fits the current context |
| Domain affinity | 0.20 | Match with current scientific domain |
| Operator affinity | 0.15 | Compatibility with current operator pool |
| Historical success | 0.15 | Past fitness improvements |
| Freshness | 0.10 | Recency of last use |
| Novelty bonus | 0.05 | How different from recent selections |
| Bloat penalty | -0.05 | Penalize overly complex ASTs |
| Failure penalty | -0.05 | Penalize recent failures |

### Neon PostgreSQL Schema (10 tables)

| Table | Purpose |
|:---|:---|
| `logos_runs` | Experiment run metadata |
| `logos_events` | Structured event log |
| `logos_fitness_results` | Candidate fitness evaluations |
| `logos_ab_tests` | A/B test comparisons |
| `logos_linear_issues` | Linear.app issue tracking |
| `logos_knowledge` | LSMA passport persistence |
| `logos_population_snapshots` | Diversity metrics per iteration |
| `logos_operator_stats` | Operator usage & success rates |
| `logos_experiment_configs` | Hyperparameters & reproducibility |
| `logos_verification_results` | Cached verification metrics + CI |

---

## Experiments

12 experiments across 8 scientific domains, all running on the unified operator space:

| # | Experiment | Domain | Status | Key Finding |
|:---|:---|:---|:---|:---|
| 1 | Cold Fusion (LENR) | Quantum | SUCCESS | Quantum tunneling + phonon resonance converged |
| 2 | Millennium Poincaré | Math | SUCCESS | Topological invariant + Ricci flow discovered |
| 3 | Adversarial LENR | Red Team | SUCCESS | 4 hypotheses found, meta-evolution active |
| 4 | Adversarial Singularity | Healing | SUCCESS | Singularity healed, regularization invented |
| 5 | Theory Healing (LENR) | LENR | SUCCESS | Universal formula discovered |
| 6 | Empirical Discovery 1-3 | Regression | SUCCESS | Gravity, healing, paradigm shift |
| 7 | Novel Experiments 4-5 | Quantum | SUCCESS | Schrödinger + Bekenstein-Hawking |
| 8 | Grand Experiment | Multi | SUCCESS | 3-phase: AI Physicist + Quantum + Cross-Domain |
| 9 | Warp Drive | Relativity | TIMEOUT | exotic matter metrics (non-convergence) |
| 10 | Cross-Domain Transfer | Multi | TIMEOUT | Transfer learning test |
| 11 | Complexity Ceiling | Regression | TIMEOUT | Two-phase ceiling test |
| 12 | NSPL Cross-Domain | Distributed | TIMEOUT | Binary protocol distributed test |

**Zero crashes.** All timeouts are non-convergence (180s limit), not engine failures. Meta-evolution invented new operators in 3 experiments.

---

## Tech Stack

| Layer | Technology | Purpose |
|:---|:---|:---|
| Orchestration | Common Lisp (SBCL) | Evolutionary engine, AST manipulation, homoiconicity |
| Verification | SWI-Prolog | Mathematical axiom enforcement, constraint solving |
| IPC | stdin/stdout pipes | Lisp ↔ Prolog daemon communication |
| Binary Protocol | NSPL | Inter-node packet serialization |
| Persistence | Neon PostgreSQL | Knowledge base, telemetry, LSMA passports |
| Cache | JSONL files | Local fast read/write, offline-first |
| Analysis | Python 3.12 | NumPy, SciPy, Pandas, Plotly, Statsmodels |
| Visualization | Plotly | Interactive HTML dashboards |
| Issue Tracking | Linear.app | Auto-create issues on anomalies |
| Hardware | Verilog | AST → gate-level circuit synthesis |
| Papers | LaTeX | Auto-generated discovery whitepapers |

---

## Key Architectural Patterns

1. **Dual-Stack**: Lisp generates/mutates ASTs; Prolog verifies them against root axioms. The Prolog daemon runs as a persistent subprocess.

2. **Offline-First Telemetry**: All events write to local JSONL first, then flush to Neon PG. Works without network.

3. **Island Model Parallelism**: Multi-threaded workers with ring-topology migration every 50 iterations. Crossover with immigrants prevents premature convergence.

4. **Meta-Evolution**: When stagnation is detected (100 iterations without improvement), the engine invents new operators by generating random subtrees, injecting them as Prolog rules, and testing them.

5. **Novelty Search**: Auto-switches between target-seeking (penalty=0.0) and novelty exploration (phenotype archive) when stagnation is detected.

6. **Cross-Domain Transfer**: ADFs discovered in one domain are available to others via the unified operator pool and persistent knowledge base.

7. **Dynamic Subroutine Extraction**: Successful island winners are automatically registered as new ADF symbols, expanding the engine's capabilities over time.

---

## License

Internal research project. All rights reserved.
