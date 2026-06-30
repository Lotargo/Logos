# LSMA Graph Storage — PostgreSQL as Graph DB

**Date:** 2026-07-01
**Status:** Reference design. Optional migration from JSONB passport when subtree/lineage queries become bottleneck.

---

## 1. Rationale

PostgreSQL supports graph traversal via `WITH RECURSIVE` (recursive CTE) and indexed foreign keys. No extensions needed. This enables queries that are painful with flat JSONB:

- *"Find all ASTs sharing at least 3 subtrees with this one"*
- *"What operators are most common in successful ASTs in domain X?"*
- *"Walk lineage: what did the parent of the parent of ADF-42 look like?"*
- *"Which ADFs depend on operator Y at depth > 3?"*

---

## 2. Schema

### Core tables

```sql
-- ============================================================
-- Nodes: each atom, operator, or subtree-root in the AST forest
-- ============================================================
CREATE TABLE ast_nodes (
    id            BIGSERIAL PRIMARY KEY,
    ast_root_hash TEXT NOT NULL REFERENCES logos_knowledge(ast_hash),
    node_type     TEXT NOT NULL CHECK (node_type IN ('operator', 'variable', 'constant', 'subtree_root')),
    -- For operators: '+', 'sin', 'matrix', etc.
    -- For variables: canonical name (e.g., 'x', 'y')
    -- For constants: stringified value (e.g., '42', '0.5', 'true')
    -- For subtree_root: hash of the subtree (for sharing detection)
    node_value    TEXT NOT NULL,
    depth         INTEGER NOT NULL,         -- 0-based from root
    position      TEXT NOT NULL,             -- dot-path: '0', '0.1', '0.1.0'
    node_hash     TEXT NOT NULL,             -- canonical hash of THIS node + subtree

    created_at    TIMESTAMPTZ DEFAULT now()
);

-- Fast lookup by root + position
CREATE UNIQUE INDEX idx_ast_node_pos ON ast_nodes (ast_root_hash, position);
-- For subtree sharing queries
CREATE INDEX idx_ast_node_hash ON ast_nodes (node_hash);
-- For operator profiling
CREATE INDEX idx_ast_node_op ON ast_nodes (node_value) WHERE node_type = 'operator';

-- ============================================================
-- Edges: parent -> child relationships
-- ============================================================
CREATE TABLE ast_edges (
    id            BIGSERIAL PRIMARY KEY,
    ast_root_hash TEXT NOT NULL REFERENCES logos_knowledge(ast_hash),
    parent_pos    TEXT NOT NULL,             -- position of parent node ('' for root)
    child_pos     TEXT NOT NULL,             -- position of child node
    child_index   INTEGER NOT NULL,          -- ordinal: 0, 1, 2...
    parent_hash   TEXT NOT NULL,             -- node_hash of parent
    child_hash    TEXT NOT NULL,             -- node_hash of child

    FOREIGN KEY (ast_root_hash, parent_pos) REFERENCES ast_nodes (ast_root_hash, position),
    FOREIGN KEY (ast_root_hash, child_pos)  REFERENCES ast_nodes (ast_root_hash, position)
);

CREATE INDEX idx_ast_edges_parent ON ast_edges (ast_root_hash, parent_pos);
CREATE INDEX idx_ast_edges_child ON ast_edges (child_hash);

-- ============================================================
-- Lineage: AST ancestry (not tree structure, but evolutionary history)
-- ============================================================
CREATE TABLE ast_lineage (
    child_hash    TEXT NOT NULL REFERENCES logos_knowledge(ast_hash),
    parent_hash   TEXT NOT NULL REFERENCES logos_knowledge(ast_hash),
    relationship  TEXT NOT NULL CHECK (relationship IN (
                      'mutation', 'crossover', 'adf_expansion', 'meta_axiom'
                  )),
    generation    INTEGER NOT NULL,          -- 0 for root, 1 for children, etc.
    created_at    TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (child_hash, parent_hash)
);

CREATE INDEX idx_lineage_child ON ast_lineage (child_hash);
CREATE INDEX idx_lineage_parent ON ast_lineage (parent_hash);

-- ============================================================
-- ADF registry: which hash maps to which ADF symbol
-- ============================================================
CREATE TABLE ast_adf (
    adf_symbol    TEXT PRIMARY KEY,           -- 'ADF-42'
    ast_hash      TEXT NOT NULL UNIQUE REFERENCES logos_knowledge(ast_hash),
    promoted_at   TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- Operator co-occurrence (materialized)
-- For efficient lookup without full join
-- ============================================================
CREATE TABLE operator_cooc (
    op_a          TEXT NOT NULL,
    op_b          TEXT NOT NULL,
    count         INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (op_a, op_b)
);

-- ============================================================
-- Behavioural fingerprints (computed lazily, cached)
-- ============================================================
CREATE TABLE ast_behavior (
    ast_hash      TEXT PRIMARY KEY REFERENCES logos_knowledge(ast_hash),
    probe_vector  DOUBLE PRECISION[],         -- fixed-length array
    probe_domain  TEXT NOT NULL,
    computed_at   TIMESTAMPTZ DEFAULT now()
);
```

---

## 3. Key Query Patterns

### Subtree sharing: "Find ASTs with similar subtree composition"

```sql
WITH target_subtrees AS (
    SELECT node_hash FROM ast_nodes
    WHERE ast_root_hash = :target_hash AND node_type = 'subtree_root'
)
SELECT s.ast_root_hash, k.passport->>'adf_symbol' AS adf, COUNT(*) AS shared_subtrees
FROM ast_nodes s
JOIN target_subtrees t ON t.node_hash = s.node_hash
JOIN logos_knowledge k ON k.ast_hash = s.ast_root_hash
WHERE s.ast_root_hash != :target_hash
GROUP BY s.ast_root_hash, k.passport
HAVING COUNT(*) >= :min_shared
ORDER BY shared_subtrees DESC
LIMIT 10;
```

### Lineage walk: "How did ADF-42 evolve?"

```sql
WITH RECURSIVE ancestry AS (
    -- Start from target
    SELECT child_hash, parent_hash, relationship, generation
    FROM ast_lineage WHERE child_hash = (SELECT ast_hash FROM ast_adf WHERE adf_symbol = 'ADF-42')
    UNION ALL
    -- Walk up
    SELECT l.child_hash, l.parent_hash, l.relationship, l.generation
    FROM ast_lineage l
    JOIN ancestry a ON a.parent_hash = l.child_hash
)
SELECT * FROM ancestry ORDER BY generation DESC;
```

### Operator profiling by domain: "What operators work in :quantum?"

```sql
SELECT n.node_value AS operator, COUNT(*) AS frequency
FROM ast_nodes n
JOIN logos_knowledge k ON k.ast_hash = n.ast_root_hash
WHERE n.node_type = 'operator'
  AND k.passport @? '$.domains ? (@ == "quantum")'
  AND (k.passport ->> 'success_count')::int > 3
GROUP BY n.node_value
ORDER BY frequency DESC;
```

### Operator co-occurrence: "What operators pair well with 'sin'?"

```sql
SELECT op_b AS paired_with, count
FROM operator_cooc
WHERE op_a = 'sin' AND op_a != op_b
ORDER BY count DESC
LIMIT 5;
```

---

## 4. Migration Strategy

Not a migration — a **parallel representation**.

```
Phase 1 (MVP)     JSONB passport in logos_knowledge
Phase 2           ast_nodes + ast_edges — populated alongside passport
Phase 3           ast_lineage — when lineaged queries become useful
Phase 4           operator_cooc — materialized from ast_nodes periodically
Phase 5           ast_behavior — when behavioural fingerprints go online
```

Each phase is additive. Engine code never queries the graph tables directly — there is a Lisp function `graph-query` that can transparently fall back to JSONB parsing if the graph tables don't exist:

```lisp
(defun find-similar-asts (ast-hash &key (min-shared 3))
  ;; Try graph query first, fall back to in-memory AST comparison
  (or (ignore-errors (pg-graph-query ast-hash min-shared))
      (in-memory-ast-search ast-hash min-shared)))
```

---

## 5. When to Enable Phase 2

- Day 5-7 of LSMA implementation (frequent subtree mining)
- First real query: *"Find ASTs sharing subtrees with this candidate"*
- Trigger condition: `jsonb` extraction of subtree hashes starts being >10ms per query

Until then: `logos_knowledge.passport` JSONB is sufficient.
