# AGI-lite Research Engine

> Experimental neuro-symbolic and evolutionary synthesis research project.

**Repository:** `Lotargo/AGI-lite`  
**Status:** research prototype family  
**Primary stable line:** `v7`  
**Experimental line:** `v9`

AGI-lite is a family of experimental engines for structured hypothesis search, program/formula synthesis, and neuro-symbolic verification. The project explores how candidate structures can be generated, mutated, evaluated, repaired, and audited using a combination of symbolic representations, formal validators, evolutionary search, and numerical backends.

This repository should be read as a research lab, not as a claim of finished AGI. The name **AGI-lite** is a project label for a small-scale experimental system that investigates pieces of machine reasoning: AST search, formal censors, penalty functions, program synthesis, symbolic regression, integrity auditing, and reproducible verification.

---

## Project map

```text
AGI-lite/
├── v7/    # Stable neuro-symbolic evolutionary engine line
├── v8/    # Intermediate audit / vulnerability exploration line
├── v9/    # Experimental first-principle Logos-oriented line
└── docs/  # Reports, audits, figures, and supporting material
```

### v7

`v7` is the most portfolio-ready and operationally stable line. It is built around a native triple-stack approach:

```text
Common Lisp generator / AST mutator
        ↓
SWI-Prolog mathematical censor
        ↓
Sonata numerical backend for regression-style scoring
```

v7 is best understood as a **domain-specified neuro-symbolic evolutionary synthesis engine**. It can use domain operators, axioms, constraints, and task-specific evaluators as part of the problem specification.

### v9

`v9` is the more experimental line. Its goal is to reduce hardcoded scaffolding and move closer to first-principle emergence. This increases scientific interest but also increases instability, search cost, and the need for stronger verification.

---

## Core idea

AGI-lite uses a search-and-evaluate loop:

```text
candidate AST / formula / program
        ↓
mutation / crossover / repair
        ↓
formal or numerical evaluator
        ↓
penalty / fitness / verdict
        ↓
selection and next generation
```

The important part is not simply generating candidates. The important part is that every candidate must be evaluated, logged, and classified.

---

## What the project is

AGI-lite is:

- an experimental neuro-symbolic research engine;
- an AST-level evolutionary search system;
- a testbed for formal censors and penalty functions;
- a platform for comparing domain-specified search against more open-ended first-principle search;
- a research artifact for studying failures, shortcuts, overfitting, and integrity limits.

AGI-lite is not:

- a production AGI system;
- a replacement for formal proof assistants;
- a fully validated scientific discovery engine;
- a claim that all generated results are discoveries by default;
- a benchmark result unless the exact run, seed, evaluator, manifest, and verification artifacts are preserved.

---

## Verification and analytics stack

The next development layer is a reproducible verification and ML/DS pipeline. The goal is to turn AGI-lite runs into structured experimental data rather than isolated terminal logs.

Recommended stack:

| Layer | Tooling | Purpose |
|---|---|---|
| Execution harness | SBCL / project scripts | Run v7/v9 experiments with fixed configs and seeds |
| Formal validation | SWI-Prolog censors, domain checkers | Validate candidate ASTs and reject invalid structures |
| Numerical validation | Sonata backend, Python reference checks | Compare regression/fitness outputs against independent reference paths |
| Metrics storage | ClickHouse | Store append-only run, candidate, metric, and evaluator events |
| Local analysis | Python + Polars/Pandas | Analyze convergence, bloat, penalties, failures, and evaluator behavior |
| Reports | Markdown + CSV/JSONL | Produce reproducible experiment summaries |
| Artifact repository | `Lotargo/verification-lab-1` | Store result bundles, manifests, exported datasets, and audit reports |

### Minimum ClickHouse event model

A first version can be event-based instead of over-normalized:

```text
ts
run_id
project = agi-lite
version = v7 | v9
commit_sha
domain
experiment
seed
iteration
candidate_id
event_type
ast_size
ast_depth
penalty
fitness
verdict = accept | reject | timeout | error | converged
error_type
evaluator = prolog | sonata | python_reference | internal
integrity_mode = normal | trusted | benchmark | experimental
config_json
payload_json
```

### Recommended event types

```text
run_started
candidate_generated
candidate_mutated
candidate_evaluated
candidate_rejected
candidate_accepted
best_candidate_updated
prolog_timeout
backend_error
integrity_warning
convergence_detected
run_finished
artifact_exported
```

### Verification bundle format

Every serious experiment should export a bundle that can later be stored in `verification-lab-1`:

```text
verification-lab-1/
└── agi-lite/
    └── <version>/
        └── <experiment_id>/
            ├── MANIFEST.json
            ├── config.json
            ├── results.csv
            ├── events.jsonl
            ├── best_candidate.lisp
            ├── audit.md
            └── hashes.txt
```

A run should be considered reportable only if it includes:

- code commit SHA;
- run configuration;
- seed or seed policy;
- evaluator version;
- domain configuration;
- candidate/result artifacts;
- final verdict;
- failure cases, if any;
- manifest with hashes.

---

## Suggested verification phases

### Phase 1: v7 stable benchmark mode

Goal: make v7 reproducible and auditable.

Recommended checks:

- fixed seeds;
- disabled or explicitly documented shortcuts;
- domain config exported with every run;
- candidate-level event logging;
- best candidate export;
- penalty and verdict history;
- timeout and error classification;
- ClickHouse ingestion;
- final bundle export to `verification-lab-1`.

### Phase 2: evaluator cross-checks

Goal: detect evaluator bugs and shortcut paths.

Recommended checks:

- compare Prolog verdicts against small Python reference checks where possible;
- compare Sonata numerical penalties against a slower reference implementation;
- log evaluator disagreement as a first-class event;
- keep rejected candidates for failure analysis.

### Phase 3: v9 first-principle audit mode

Goal: test whether v9 improvements survive without hidden scaffolding.

Recommended checks:

- no monkey-patching during benchmark runs;
- no preloaded target solutions;
- no undocumented zero-penalty paths;
- strict timeout handling;
- explicit domain assumptions;
- separation between discovery runs and demonstration runs.

---

## What should go to ClickHouse

ClickHouse should store structured experimental telemetry:

- run metadata;
- per-candidate metrics;
- penalties and fitness curves;
- AST size/depth over time;
- evaluator verdicts;
- timeout/error events;
- convergence events;
- backend selection;
- integrity warnings;
- artifact export status.

ClickHouse is not the artifact archive. Large files, reports, manifests, and exported result bundles should go to `verification-lab-1`. ClickHouse stores the queryable event stream; `verification-lab-1` stores reproducibility evidence.

---

## Integrity policy

AGI-lite results should be classified before publication or portfolio use:

| Class | Meaning |
|---|---|
| Demonstration | Shows that a mechanism runs, but does not prove discovery |
| Domain-specified result | Uses explicit operators, axioms, templates, or constraints as part of the task specification |
| Benchmark result | Reproducible run with fixed config, seed policy, manifest, and independent verification |
| Candidate discovery | Interesting result that passed internal checks but still needs external validation |
| Invalid / contaminated | Result affected by hidden templates, shortcut penalties, evaluator bugs, or undocumented assumptions |

This distinction is important: AGI-lite is strongest when it reports not only successes, but also failures, contaminated runs, overfitting, and evaluator weaknesses.

---

## Relationship to `verification-lab-1`

`Lotargo/verification-lab-1` is the intended place for public or semi-public verification outputs:

```text
AGI-lite repository      = engine source, experiments, internal reports
verification-lab-1      = exported evidence, manifests, result tables, reproducibility bundles
ClickHouse              = local analytical database for querying run/event history
```

The clean workflow is:

```text
run experiment
    ↓
write events to ClickHouse
    ↓
export CSV/JSONL + manifest
    ↓
store final bundle in verification-lab-1
    ↓
write audit summary / portfolio-safe result
```

---

## Portfolio positioning

A cautious public description:

> AGI-lite is a neuro-symbolic evolutionary synthesis research project. It explores AST-level candidate generation, formal and numerical evaluators, integrity auditing, and reproducible verification workflows for structured hypothesis search.

A stronger but still honest description:

> AGI-lite is a small-scale algorithmic discovery lab: it combines symbolic program mutation, formal censors, numerical scoring, and verification artifacts to study how machines can generate, test, and refine structured candidates.

---

## Current priority

The immediate priority is not to add more claims. The priority is to make experiments measurable:

1. define run/candidate/event schemas;
2. write ClickHouse ingestion;
3. export reproducibility bundles;
4. store final artifacts in `verification-lab-1`;
5. separate demonstration runs from benchmark-grade runs.

---

## License / visibility

This repository is currently private. Public release policy is not defined yet.
