# Logos Benchmark & Runtime Integration — Architectural Plan

> **Status:** architectural plan / research-first roadmap  
> **Scope:** historical Logos versions, common benchmark protocol, universal task/result representation, external integration and SDK strategy.  
> **Important:** this document is not an implementation checklist. It defines the direction and the order of investigation.

## Core rule: research before implementation

Before implementing **any** stage below, first inspect the current repository, relevant historical commits, existing CLI/stdin/stdout contracts, protocols, adapters, serializers, benchmark utilities and version-specific mechanisms.

The goal is to avoid:
- duplicating functionality that already exists;
- replacing working historical mechanisms with new abstractions only for architectural neatness;
- contaminating old versions by backporting modern capabilities;
- creating SDK/protocol layers before the real runtime contract is understood;
- changing benchmark conditions to fit a specific Logos version.

For each stage the workflow is:

```text
research existing implementation
        ↓
document what already exists
        ↓
identify the actual missing capability
        ↓
decide whether implementation is needed
        ↓
implement the minimum missing layer
        ↓
verify against historical and current versions
```

If an existing mechanism already solves the problem adequately, prefer adapting or documenting it instead of creating a replacement.

---

## 1. Freeze and classify historical versions

Primary comparison targets:

- **v7** — stable neuro-symbolic evolutionary line;
- **v8** — first-principle / reduced-hardcoding transition;
- **v9** — persistent executable knowledge, LSMA, dynamic ADF/operator evolution.

Versions below v7 should **not** be added to the main benchmark automatically.

Before including any pre-v7 version, research whether it contains a genuinely distinct architectural mechanism that later disappeared or materially explains the evolution of Logos. If not, keep it only as historical lineage.

Historical versions must be tested from pinned commits/tags wherever possible. Do not rewrite their internal reasoning logic merely to make them fit the benchmark.

---

## 2. Define a common external contract

The current CLI and stdin/stdout transport already exist. Do not replace them before auditing their capabilities.

The target is a stable external contract above the existing runtime.

Conceptually:

```text
Benchmark / SDK / external application
              ↓
          Logos IR
              ↓
       version adapter
              ↓
      native Logos runtime
              ↓
       version adapter
              ↓
       Logos Result IR
```

The benchmark must not depend on internal Lisp/Prolog/Python implementation details.

---

## 3. Logos IR (LIR)

Research the current input/output structures first. Reuse existing representations where possible.

The initial LIR should describe tasks and results, not redesign Logos itself.

Minimum task model:

```text
Task
├─ protocol/version
├─ task_id
├─ domain
├─ variables / inputs
├─ allowed primitives
├─ constants
├─ constraints / invariants
├─ dataset/reference input
├─ resource budget
└─ expected output type
```

Minimum result model:

```text
Result
├─ protocol/version
├─ task_id
├─ status
├─ candidate / AST / executable structure
├─ discovered primitives
├─ verification result
├─ execution/verification trace
├─ resource cost
└─ diagnostics
```

Preferred first transport: the existing long-lived CLI process over stdin/stdout.

Machine-readable output must remain separable from human logs. If the current CLI mixes them, research the least invasive way to reserve stdout for protocol messages and stderr for diagnostic output.

Do not design a binary protocol or C ABI until the textual/machine contract is stable.

---

## 4. Version adapters

Create the thinnest possible adapter for each benchmarked version.

```text
LIR task
  ↓
adapter-v7 → native v7 input/output
adapter-v8 → native v8 input/output
adapter-v9 → native v9 input/output
  ↓
normalized LIR result
```

Adapters may translate formats, operator names, paths and result schemas.

Adapters must **not**:
- add capabilities absent from that version;
- inject target formulas;
- add modern LSMA/ADF/meta-evolution behavior to older versions;
- modify the search algorithm to improve benchmark results.

---

## 5. Two benchmark modes

### Historical mode

Run each version using its native architecture from a pinned historical state.

Purpose: show the real evolution of Logos.

### Canonical mode

Provide equivalent task definitions, allowed primitives, datasets, budgets, seeds and evaluation rules through adapters.

Purpose: compare architectures under controlled conditions.

The common benchmark contract should remain the same even when a version supports only a subset of benchmark capabilities.

---

## 6. Benchmark tracks

Use capability-based tracks rather than a separate benchmark design for every Logos version.

Initial tracks:

1. **Recovery** — recover known mathematical/physical relationships.
2. **Verification** — reject invalid but superficially plausible candidates.
3. **Robustness** — noise, OOD ranges, singularities and adversarial cases.
4. **Composition** — build deeper solutions from simpler primitives.
5. **Transfer** — reuse valid structures across related tasks/domains.
6. **Language Growth** — discover a reusable executable primitive, verify it, persist it, and demonstrate measurable improvement on future tasks.

The **Language Growth** track is the central Logos-specific experiment.

A target experiment should compare:

```text
L0: fixed initial language
        ↓
solve simpler tasks
        ↓
discover + verify primitive X
        ↓
L1 = L0 + X
        ↓
fresh future task
```

Compare L0 versus L1 using the same compute/resource budget.

---

## 7. Ground truth and reproducibility

Prefer externally verifiable datasets, equations, published scientific relationships and established benchmark tasks.

Do not rely primarily on datasets generated from hidden formulas inside the Logos repository.

Every serious run should record at least:

- Logos version and commit SHA;
- adapter version;
- benchmark task version;
- seed / seed policy;
- machine/runtime information;
- allowed primitive set;
- resource limits;
- dataset hash/reference;
- final candidate;
- verifier result;
- execution cost;
- failure/timeout status.

The evaluator should remain outside the tested Logos version wherever practical.

---

## 8. Ablation study for the current architecture

After the base benchmark works, test the current Logos architecture with controlled feature removal.

Candidates:

- full Logos;
- without persistent memory;
- without ADF reuse;
- without meta-evolution;
- without formal censor;
- fixed operator language.

The goal is to measure what each architectural mechanism contributes rather than infer value from successful demos.

---

## 9. SDK and embedding strategy

Do not begin with separate native implementations for Python, C and Julia.

First stabilize LIR and the CLI process contract.

Initial integration:

```text
             Logos Runtime
                  │
          stdin/stdout + LIR
          ┌───────┼────────┐
       Python    Julia    other
        SDK       SDK     clients
```

The first Python/Julia SDKs may simply manage a persistent Logos process and expose typed task/result objects.

A stable **C ABI** should be considered only after:
- LIR semantics are stable;
- lifecycle requirements are understood;
- external applications demonstrate a real need for in-process embedding;
- process transport becomes a measurable limitation.

If a C ABI is introduced later, Python and Julia bindings should preferably build on the same stable runtime contract rather than duplicate Logos logic.

---

## 10. Implementation order

```text
0. repository + history audit
1. document current CLI/stdin/stdout behavior
2. define minimal LIR v0.1 from existing capabilities
3. build thin v7/v8/v9 adapters
4. create common benchmark harness
5. add a small set of externally verifiable tasks
6. run historical mode
7. run canonical mode
8. implement Language Growth benchmark
9. run ablations
10. stabilize protocol
11. add lightweight Python/Julia SDK wrappers
12. evaluate whether a native C ABI is actually necessary
```

At every numbered stage, repeat the research-first rule before writing new infrastructure.

---

## Success criterion

The project should not aim merely to show that multiple Logos versions can run the same test.

The stronger goal is to produce reproducible evidence for:

> Logos can transform verified solutions into reusable executable knowledge, and this knowledge can measurably change the efficiency or capability of later reasoning without storing that capability in neural weights.

The benchmark, adapters and SDK are supporting infrastructure for testing and exposing this claim. They should remain smaller and simpler than the engine they are intended to evaluate.
