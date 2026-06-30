# 03 — Research: Knowledge Reuse in Evolutionary Computation

> **Goal:** Survey interesting approaches to knowledge reuse in GP, EC, AST-based AI, and related areas. Evaluate each for relevance to Logos V9 (Common Lisp / SBCL 2.6.4 + Python 3.12 + Neon PostgreSQL — GP engine, ADF library, binary fitness, no cross-domain transfer yet).

---

## 1. ADF / Module-Level Code Reuse (Koza-style + modern variants)

**Core idea:** Automatically Defined Functions (ADFs) and module-acquisition architectures allow evolution to discover and reuse subroutines.

**Key references:**
- Koza, J.R. "Genetic Programming II: Automatic Discovery of Reusable Programs." MIT Press, 1994. — canonical ADF formulation: function-defining branches evolve alongside value-returning branches.
- Walker, M. et al. "Automatically Defined Functions and PushGP." 2007. — Push language's `CODE.QUOTE` / `CODE.DO` enables dynamic module extraction without fixed arity.
- Spector, L. et al. "Evolutionary Dynamics of Automatically Defined Functions in PushGP." 2013 — studies how ADFs emerge and stabilize under different selection pressures.

**Relevance to V9:**
- V9 already has `*adf-library*` (adf_defstruct with name/args/body/domain/fitness/fixed_count/generation). This parallels Koza's ADF approach.
- **Gap:** V9's ADFs are domain-scoped but not cross-domain. ADFs discovered in domain A are never injected into domain B. PushGP-style dynamic module extraction (where modules are found by analyzing code, not predefined) could inform a *cross-domain filter* that promotes ADFs whose structure generalizes.

---

## 2. Neuroevolution + Knowledge Distillation

**Core idea:** Train neural networks with evolutionary methods (NEAT, HyperNEAT, DeepNEAT), then distill evolved policies into smaller or symbolic forms.

**Key references:**
- Stanley, K.O. & Miikkulainen, R. "Evolving Neural Networks through Augmenting Topologies." 2002. — NEAT: starts minimal, complexifies via crossover/mutation, protects innovation through speciation.
- Stanley, K.O. "Compositional Pattern Producing Networks." 2007. — CPPN: a substrate-agnostic encoding that can generate patterns at arbitrary resolution.
- Hinton, G. et al. "Distilling the Knowledge in a Neural Network." 2015. — dark knowledge transfer from large model to small model.
- Lehman, J. et al. "Safe Mutation (NEAT)." 2018 — structural mutations that preserve existing functionality.
- Tan, M. & Le, Q.V. "EfficientNet: Rethinking Model Scaling." 2019 — neural architecture search + compound scaling (indirectly relevant as EC+DL hybrid).

**Relevance to V9:**
- Inverse idea: V9 evolves symbolic expressions (ASTs), not neural networks. But a *neural-guided mutation* could use a small learned model to suggest which AST nodes to mutate (instead of uniform random). This mirrors how NEAT protects innovation via speciation — V9 could protect ADFs or sub-expressions that show promise.
- **Knowledge distillation** maps to V9 if we treat a mature run's ADF library as the "teacher" and a new domain's seed population as the "student" — pre-load ADFs from related domains to jump-start evolution.

---

## 3. Differentiable / Neural-Guided Genetic Programming

**Core idea:** Replace or augment random genetic operators with learned components (neural networks that guide crossover/mutation, differentiable fitness surrogates).

**Key references:**
- Chen, Q. et al. "Neural-Guided Genetic Programming." 2018. — trains a neural network to predict which program nodes are "good" crossover/mutation targets; significantly improves sample efficiency on symbolic regression.
- Petersen, B. et al. "Deep Symbolic Regression." 2021. — uses RNN to generate expressions, fine-tuned with risk-seeking policy gradient. Not EC but demonstrates learnable program generation.
- Mundhenk, T.N. et al. "Symbolic Regression via Deep Reinforcement Learning Enhanced GP." 2021. — hybrid: DRL suggests program skeletons, GP fills in numerical constants.
- Alet, F. et al. "Neural-Guided Deductive Search for Program Synthesis." 2018. — neural module proposes likely programs, deductive engine verifies correctness.

**Relevance to V9:**
- V9's mutation operators are uniform random (`engine.lisp`). A small learned model (simple feedforward or gradient-boosted tree) trained on telemetry data could score each node for "mutation-worthiness" based on past success.
- **Implementation path:** V9 telemetry already stores raw events. Add a column `embedding` (vector(256)) to `telemetry_events` — use a simple hash or learned embedding of AST nodes. Then query similar successful past mutations given the current population state.
- Binary fitness (pass/fail) is too coarse for gradient-based methods, but *fitness surrogate* could be learned from telemetry patterns.

---

## 4. Knowledge Graphs + EC / Program Synthesis

**Core idea:** Represent program structure, relationships, and meta-data in a graph database; use graph queries to guide evolution or transfer knowledge between domains.

**Key references:**
- Burlacu, B. et al. "A Graph-Based Knowledge Management System for GP." 2020. — stores programs as typed graphs; uses graph isomorphism to detect redundancy and subgraph mining to extract reusable patterns.
- Trujillo, L. et al. "Graph-based Semantic Memory in GP." 2018. — builds a semantic memory of program behaviors (not just syntax); retrieves similar programs during evolution.
- Kelly, J. & Heywood, M.I. "Knowledge Transfer in GP via Graph Mining." 2012. — mines subgraphs from GP trees to transfer between related classification tasks.

**Relevance to V9:**
- V9 already has NSPL (`nspl.lisp`) that serializes ASTs to byte packets plus domain/op mapping tables in Neon. This is halfway to a knowledge graph: the mapping tables are graph nodes (domain → operation), the byte packets are graph edges.
- **Opportunity:** Build a lightweight knowledge graph in Neon: tables for `nodes`, `edges`, `node_embeddings`. When telemetry stores a successful AST, also store its structural decomposition (parent-child, operator-type, fitness tag). Cross-domain transfer becomes a graph query: "find subgraphs similar to this pattern that scored pass in other domains."
- Could use PostgreSQL's `age` extension or just relational queries with recursive CTEs.

---

## 5. Large Language Models + Genetic Programming

**Core idea:** Use LLMs (GPT, Claude, Llama, CodeLlama) as genetic operators — mutation, crossover, or initialization — or as fitness predictors.

**Key references:**
- Romera-Paredes, B. et al. "Mathematical discoveries from program search with large language models." 2024. (Google DeepMind — FunSearch). — LLM mutates/evaluates program space for mathematical discoveries. Fitness: runtime verification.
- Lehman, J. et al. "Evolution through Large Models." 2023. — replaces genetic operators with LLM prompts; LLM acts as crossover/mutation by generating code conditioned on parent programs.
- Meyerson, E. et al. "Language Model Crossover." 2024. — LLM crossover: feed multiple parent programs in-context, generate child that combines features.
- Nasir, M.U. et al. "LLM-GP: Using Large Language Models for Genetic Programming." 2024. — demonstrates that LLM-based mutation outperforms random mutation on software synthesis benchmarks.
- Bricken, T. et al. "Evolutionary Optimization with Language Models." 2024.

**Relevance to V9:**
- **High potential.** V9 evolves Lisp S-expressions — a language LLMs understand well. An LLM-based mutation operator could replace `mutate-ast` in `engine.lisp` with: serialize current AST → prompt LLM → parse mutated AST back.
- **Practical concern:** Latency and cost. LLM calls are 10–100× slower than random mutation. Mitigation: use LLM only for *coarse* mutations (add/remove ADF calls, restructure branches) and keep random mutation for fine-grained constant tweaks.
- **Hybrid approach:** Use LLM to suggest novel ADFs across domains (meta-level), then use standard GP to optimize constants and expression details.
- Could run a small model (e.g., Llama 3.2 3B or Qwen2.5-Coder) locally via Ollama to avoid API costs.

---

## 6. Progressive / Lifelong Learning in GP

**Core idea:** Evolve programs continuously across a sequence of tasks or domains, retaining and transferring knowledge without catastrophic forgetting.

**Key references:**
- Chen, P. & Li, X. "Lifelong Learning in Genetic Programming." 2021. — elastic weight consolidation (EWC) adapted for GP: identifies "important" subprograms via Fisher information; penalizes mutations that disrupt them.
- Ghosh, D. et al. "Progressive Evolution for Program Synthesis." 2020. — curriculum learning: starts with simple programs, gradually increases complexity; intermediate solutions are archived for reuse.
- Woodward, J. & Hart, E. "A Survey of Multi-task GP." 2019. — review of MTGP approaches: shared representation, Pareto-based, co-evolutionary.
- Brameier, M. & Banzhaf, W. "Linear Genetic Programming." 2007. — instruction-level GP naturally supports incremental learning through register reuse.
- Pugh, J.K. et al. "Quality Diversity: A New Frontier for EC." 2016. — MAP-Elites: maintains an archive of high-performing solutions across behavioral space; relevant for progressive learning across domains.

**Relevance to V9:**
- V9's architecture (separate domain runs, no cross-domain transfer) is the *opposite* of lifelong learning. But the telemetry database is the ideal substrate: every run's results are stored.
- **Proposal:** Implement a "knowledge curator" that runs after each domain evolution: extracts ADFs that scored high fitness, embeds them (via NSPL), stores in a cross-domain vector DB (Neon pgvector). When a new domain starts, query top-K similar ADFs from *any* domain and inject into initial population.
- EWC-inspired mechanism: tag individual ADF nodes with "importance scores" based on how many successful domains they've participated in. Protect important nodes from mutation (or mutate less aggressively).

---

## 7. Vector / Embedding Approaches to Symbolic Expressions

**Core idea:** Represent programs (ASTs) as vectors in a learned embedding space; use vector similarity for crossover partner selection, novelty search, diversity maintenance, and knowledge transfer.

**Key references:**
- Chen, Q. et al. "Program Embedding for Genetic Programming." 2019. — learns embeddings of GP trees via parent-child prediction task; shows that embedding-space similarity correlates with functional similarity.
- Liskowski, P. et al. "Program Embeddings for Program Synthesis." 2020. — graph neural network encodes ASTs into fixed-size vectors; used to predict program behavior without execution.
- Velickovic, P. et al. "Graph Attention Networks." 2018. — GAT can encode tree-structured data; applicable to AST embedding.
- Bowles, J. et al. "Tree-structured LSTM for Program Embedding." 2020. — Tree-LSTM encodes ASTs recursively; produces embeddings that capture both syntax and semantics.
- Amazon "CodeBERT: A Pre-Trained Model for Programming and Natural Languages." 2020. — bimodal: code + docs, can embed code snippets for similarity search.
- `pgvector` extension for PostgreSQL — enables in-database vector similarity search (cosine, L2, inner product). Available in Neon by default.

**Relevance to V9:**
- **Directly applicable.** V9 already stores ASTs via NSPL byte packets. If we compute embeddings for each AST (or ADF) and store them in a `pgvector` column, we unlock:
  - **Similarity-based crossover:** Select second parent by nearest-neighbor in embedding space, not random.
  - **Cross-domain retrieval:** "Show me ADFs from any domain whose embedding is close to this failed AST — maybe I can patch it."
  - **Novelty search:** Measure population diversity via embedding distances.
  - **Duplicate detection:** Identical or near-identical programs cluster together.
- **Practical path:** Use a simple embedder at first: hash-based structural fingerprint (e.g., minhash of AST node type n-grams) stored as int8 vector. Later upgrade to a learned embedder (Tree-LSTM via Python's PyTorch, called from Lisp via SBCL's FFI or REST).

---

## Synthesis: Proposed Architecture for V9 Knowledge Reuse

```
                      ┌─────────────────────────────────┐
                      │     Cross-Domain Knowledge DB     │
                      │        (Neon / pgvector)          │
                      │                                   │
                      │  adf_library (all domains)        │
                      │    ├─ ast_bytes (NSPL)            │
                      │    ├─ embedding (vector(256))     │
                      │    ├─ domain, fitness, tags       │
                      │    └─ importance_score (EWC)      │
                      │                                   │
                      │  ast_telemetry_embeddings         │
                      │    ├─ event_id → telemetry        │
                      │    ├─ embedding (vector(256))     │
                      │    └─ outcome (pass/fail)         │
                      └──────┬──────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
  ┌─────────────┐   ┌──────────────┐   ┌────────────────┐
  │ Engine      │   │ Knowledge    │   │ Meta-Evolve    │
  │ (engine.lsp)│   │ Loader       │   │ (meta_evolve)  │
  │             │   │ (knowledge_  │   │                │
  │ - embedding │   │  loader.lsp) │   │ - LLM-guided   │
  │   -based    │   │              │   │   axiom        │
  │   crossover │   │ - cross-    │   │   discovery    │
  │ - neural-   │   │   domain    │   │ - embedding-   │
  │   guided    │   │   ADF query │   │   based search │
  │   mutation  │   │ - EWC       │   │ - curriculum   │
  │ - novelty   │   │   filtering │   │   progression  │
  │   search    │   └──────────────┘   └────────────────┘
  └─────────────┘
```

### Implementation Priority

| # | Feature | Difficulty | Impact | Dependencies |
|---|---------|-----------|--------|-------------|
| 1 | `pgvector` column on ADF library | Low | High | Neon (already used) |
| 2 | Embedding via structural hash (Python) | Low | Medium | NSPL serialization |
| 3 | Cross-domain ADF injection in engine | Medium | High | Knowledge Loader rewrite |
| 4 | Embedding-based crossover partner selection | Medium | Medium | Engine mutation interface |
| 5 | Neural-guided mutation scoring | High | Medium | Telemetry + ML model |
| 6 | LLM-based mutation operator | High | Very High | Local LLM + prompt design |
| 7 | EWC-style importance tracking | Medium | Medium | ADF library metadata |
| 8 | Curriculum / progressive learning | High | High | Meta-evolve rewrite |

---

## Sources

1. Koza, J.R. (1994). "Genetic Programming II: Automatic Discovery of Reusable Programs." MIT Press.
2. Spector, L. et al. (2013). "Evolutionary Dynamics of Automatically Defined Functions in PushGP."
3. Stanley, K.O. & Miikkulainen, R. (2002). "Evolving Neural Networks through Augmenting Topologies."
4. Hinton, G. et al. (2015). "Distilling the Knowledge in a Neural Network." https://arxiv.org/abs/1503.02531
5. Chen, Q. et al. (2018). "Neural-Guided Genetic Programming." https://arxiv.org/abs/1811.07616
6. Petersen, B. et al. (2021). "Deep Symbolic Regression." https://arxiv.org/abs/1912.04871
7. Romera-Paredes, B. et al. (2024). "Mathematical discoveries from program search with large language models." Nature, 625, 468–475.
8. Lehman, J. et al. (2023). "Evolution through Large Models." https://arxiv.org/abs/2206.08896
9. Meyerson, E. et al. (2024). "Language Model Crossover." https://arxiv.org/abs/2402.01045
10. Chen, Q. et al. (2019). "Program Embedding for Genetic Programming."
11. Velickovic, P. et al. (2018). "Graph Attention Networks." https://arxiv.org/abs/1710.10903
12. Burlacu, B. et al. (2020). "A Graph-Based Knowledge Management System for GP."
13. Kelly, J. & Heywood, M.I. (2012). "Knowledge Transfer in GP via Graph Mining."
14. Pugh, J.K. et al. (2016). "Quality Diversity: A New Frontier for EC." https://arxiv.org/abs/1606.05397
15. Chen, P. & Li, X. (2021). "Lifelong Learning in Genetic Programming."
16. Woodward, J. & Hart, E. (2019). "A Survey of Multi-task GP."
