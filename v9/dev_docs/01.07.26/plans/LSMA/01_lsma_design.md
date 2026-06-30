# LSMA — Logos Symbolic Memory Algebra

**Date:** 2026-07-01
**Status:** Selected design (result of brainstorming 3-agent synthesis)

---

## 1. Core Principle

Logos does **not** connect to external intelligence. No LLM, no ML, no borrowed embeddings.
It grows its own memory from the traces of its own evolution.

```
No LLM mutation / crossover / ADF generation
No neural surrogate fitness predictor
No pgvector as ML-semantic layer
No TreeLSTM / GNN / diffusion
```

## 2. Stack Allocation

| Component | Role |
|-----------|------|
| Common Lisp (SBCL) | Evolutionary engine, AST/ADF manipulation, **matrix memory algebra** |
| PostgreSQL (Neon) + JSONL | Long-term fact storage |
| Prolog (via censor) | Formal verification, judge |
| ADF / AST | Internal "genes" of Logos |
| GNU APL *(experimental)* | *Optional accelerator — see supplement doc* |

```
       DB stores.
       Lisp computes (matrix ops in SBCL nested vectors).
       Lisp evolves.
       Prolog verifies.
```

Matrix operations live in Lisp using SBCL's native arrays and vector operations (`make-array`, `map`, `reduce`, vectorized loops). No external dependency for the MVP. GNU APL can be added later as an experimental accelerator if matrix sizes exceed practical Lisp performance — see `05_apl_supplement.md`.

## 3. AST Passport — Knowledge Representation

Every AST/ADF gets a structured "passport" instead of a raw S-expression:

| Field | Type | Description |
|-------|------|-------------|
| `ast_hash` | text (SHA256) | Canonical hash — same structure = same hash, independent of variable names |
| `subtree_hashes` | text[] | Hashes of all subtrees (for reuse mining). **Capped** at top-N subtrees per AST |
| `operator_profile` | jsonb | Operator frequencies in this AST |
| `depth_profile` | int[] | Depth at each node position |
| `domains` | text[] | Domains where this AST was successful |
| `usage_count` | int | Times selected for evolution |
| `success_count` | int | Times produced valid/improved offspring |
| `failure_count` | int | Times produced invalid/worse offspring |
| `lineage` | text[] | Parent AST hashes (ancestry chain, bounded depth) |
| `behavior_trace` | jsonb | Output on probe inputs across domains (computed lazily) |
| `fitness_scores` | float[] | Rolling window of last N fitness values |
| `freshness` | timestamptz | Last usage timestamp |

**Design constraints:**
- `subtree_hashes` — cap at 50 deepest/most frequent subtrees per AST to prevent bloat
- `behavior_trace` — computed on-demand for ADF candidates, not eagerly for every AST
- `lineage` — bounded at 5 generations back; older parents are summarized as count, not hash
- `fitness_scores` — rolling window of 20 entries max; beyond that aggregated as `mean + std`

## 4. ADF Selection Formula

```
ADF_SCORE =
    w_sim  * structural_similarity   -- how structurally similar to current target
  + w_beam * behavior_similarity     -- how similarly this AST behaves on probes
  + w_dom  * domain_affinity          -- how relevant to current domain
  + w_op   * operator_affinity        -- operator co-occurrence with current context
  + w_hist * historical_success       -- track record (success/(success+failure))
  + w_frsh * freshness                -- recency bonus
  + w_nov  * novelty_bonus           -- penalty for overused ADFs
  - w_bloat* bloat_penalty           -- depth/size penalty
  - w_fail * failure_penalty          -- recent failure penalty
```

All weights are scalar constants. Pure statistics. No ML.

## 5. Matrix Memory Algebra (Lisp-native)

Matrix operations run on SBCL nested vectors, not on APL:

```
ADF × FEATURES         — N×M matrix:   2D array of doubles
ADF × DOMAIN           — N×D matrix:   2D array of floats
OPERATOR × OPERATOR    — O×O matrix:   2D integer (co-occurrence counts)
ADF × BEHAVIOR_TRACE   — N×P matrix:   lazy — computed on demand
DOMAIN × OPERATOR      — D×O matrix:   2D float (domain-operator affinity)
AST × SUBTREE_HASH     — sparse:       hash-table of (node . count)
```

Implementation in Lisp:
```lisp
(defparameter *adf-feature-matrix* (make-array '(0 0) :element-type 'double-float))
(defparameter *op-cooc-matrix* (make-array (list *operator-count* *operator-count*)
                                            :element-type 'integer :initial-element 0))
```

Results computed and returned to the engine:
- Top-K useful ADFs for current domain
- Similar ASTs by behavior (not structure)
- Operator suggestions for mutation
- Cross-domain transfer candidates
- Eviction candidates

## 6. Behavioural Fingerprints — Strategy

Most powerful and most expensive feature. Strategy:

1. **Probe set** — small fixed set of input vectors (e.g., 5-10 per domain), stored in config
2. **Lazy computation** — fingerprint computed only when ADF becomes a candidate for selection, not at insert time
3. **Cache** — computed fingerprints cached in `*behavior-cache*` hash table, invalidated on ADF mutation
4. **Comparison** — cosine similarity between output vectors on the probe set

This avoids O(N×P) eval on every cycle. In practice: O(K×P) where K=top-20 ADF candidates.

## 7. Implementation Order (MVP)

```
 1. Canonical AST hash             Day 1   hash normalization, variable canonicalization
 2. Structured AST extraction       Day 1   operators/subtrees/depth → jsonb
 3. JSONL/Neon storage              Day 2   passport schema, migration
 4. ADF_SCORE formula               Day 2   weighted selection in Lisp
 5. Weighted ADF selection          Day 2   replace random ADF pick
 6. Operator co-occurrence matrix   Day 3   pure Lisp matrix
 7. Cross-domain ADF transfer       Day 3   top-K from other domains
 8. Behavioral fingerprints         Day 4   lazy, cached, probe-based
 9. Lineage tracking                Day 4   bounded parent chain
10. Forgetting / eviction           Day 5   freshness + failure threshold
11. Frequent subtree mining         Day 5+  hash-table pattern detection
```

## 8. Storage Design

### PostgreSQL JSONB (logos_knowledge)

```sql
CREATE TABLE logos_knowledge (
    ast_hash      TEXT PRIMARY KEY,
    ast           JSONB NOT NULL,
    passport      JSONB NOT NULL,
    adf_symbol    TEXT,
    created_at    TIMESTAMPTZ DEFAULT now(),
    updated_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_knowledge_ops ON logos_knowledge USING GIN ((passport -> 'operator_profile'));
CREATE INDEX idx_knowledge_domains ON logos_knowledge USING GIN ((passport -> 'domains'));
```

### Local cache

```
*adf-library*          — alist: (sym . ast)  — active ADFs in memory
*adf-passports*        — hash-table: ast_hash → passport plist
*adf-feature-matrix*   — 2D array: N × M double-float
*op-cooc-matrix*       — 2D array: O × O integer
*behavior-cache*       — hash-table: ast_hash → behavior-vector (lazy)
```

## 9. Comparison to Rejected Alternatives

| Alternative | Why Rejected |
|-------------|--------------|
| LLM mutation | External dependency, Logos loses autonomy |
| Neural surrogate | Overkill for <10K ADF, slow training |
| pgvector embeddings | External to symbolic system, fragile |
| APL as DB | Wrong tool — APL computes, doesn't persist |
| RAG from chunks | Text chunks don't map to AST structure |
| Pure SQL everything | Matrix ops in SQL are painful and slow |
| No knowledge at all | Current state — loses insight between runs |

## 10. Design Constraints

- Zero external ML/LLM calls
- All similarity = deterministic algebra, not learned
- SBCL native vectors for all matrix ops — no BLAS/LAPACK dependency in MVP
- GNU APL deferred to `05_apl_supplement.md` as experimental accelerator
- Behavioural fingerprint = lazy + cached + bounded probe set
- Passport fields bounded to prevent bloat (subtree cap, lineage depth, rolling window)
- All roads lead back to Neon for persistence
