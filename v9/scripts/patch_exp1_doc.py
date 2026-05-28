import re
import os

filepath = "v9/docs/NSPL_Exp1_Cooperative_Evolution.md"

with open(filepath, "r") as f:
    content = f.read()

# 1 & 5. Fix Abstract claims (Complexity and Fitness)
content = re.sub(
    r"By broadcasting validated subroutines.*?down to near-polynomial time by preventing redundant localized random walks\.",
    "By broadcasting phenotypically proven subroutines (ASTs that have achieved local fitness maxima), nodes acting as 'junior researchers' can autonomously supply foundational mathematical building blocks to 'senior architects' struggling with complex search spaces. This effectively reduces the depth of the target search tree, creating a massive constant-factor speedup in exponential search times.",
    content,
    flags=re.DOTALL
)

# 5. Fix Theoretical Framework Complexity Claims
content = re.sub(
    r"bypassing the exponential depth bottleneck\.",
    "drastically shifting the exponential constant by flattening the effective search depth ($d' = d - |a_{sub}| + 1$).",
    content
)

# 4. Fix Zero-copy myth
content = re.sub(
    r"The binary deserialization.*?confirming the zero-copy philosophy\.",
    "While the network transmission operates in a highly compressed binary state, saving immense bandwidth, an architectural bottleneck remains at the verification layer: transferring the deserialized AST from SBCL to SWI-Prolog (`nspl_invariants.pl`) currently requires string serialization via standard I/O pipes. Future iterations must implement a true C-FFI bridge between Lisp and Prolog to achieve true zero-copy processing.",
    content,
    flags=re.DOTALL
)

# 2 & 3. Add new sections to architectural implications addressing Arity and Bloat
new_architecture_text = r"""### 5.1 Dynamic Vocabulary Expansion & Arity Extraction
A critical challenge in accepting foreign macros is parameterization. When Node B receives `(SEQ H Q1 CNOT Q2 Q1)`, the specific variables `Q1` and `Q2` are useless outside Node A's original context. Before injection into $V$, the Logos `meta_evolve` subsystem performs Automatic Variable Extraction. It identifies unique un-bound variables, abstracts them, and assigns an arity to the new ADF:
$$ \lambda(a, b). \text{SEQ}(H(a), \text{CNOT}(b, a)) $$
This allows Node B to dynamically instantiate the macro with its own local variables (e.g., applying the entanglement sequence to `Q5` and `Q6`).

### 5.2 Mitigating Vocabulary Bloat (Pruning)
Naively expanding the vocabulary $V_{new} = V_{old} \cup \{ ADF_{incoming} \}$ introduces the risk of vocabulary bloat. As $|V|$ grows, the probability of selecting the correct operator diminishes. To counter this, Node B implements an Exponential Decay protocol. Every injected ADF is assigned an initial utility score. If the ADF does not participate in an AST that successfully lowers the global penalty within $N$ iterations, its utility decays. Once utility reaches zero, the ADF is purged from $V$, ensuring the search space remains highly optimized and free of network spam.

### 5.3 Island Model Crossover"""

content = re.sub(
    r"### 5\.1 Dynamic Vocabulary Expansion.*?### 5\.2 Island Model Crossover",
    new_architecture_text.replace('\\', '\\\\'),
    content,
    flags=re.DOTALL
)

# 5. Fix Statistical validation conclusion
content = re.sub(
    r"This \$12\\times\$ speedup clearly demonstrates the non-linear returns",
    r"While this $12\\times$ speedup on a depth-7 tree represents a substantial constant-factor optimization (shifting the search from $\\mathcal{O}(|V|^7)$ to effectively $\\mathcal{O}(|V|^2)$ for the receiving node), it does not strictly alter the asymptotic complexity class of GP. However, it clearly demonstrates the practical non-linear returns",
    content
)

with open(filepath, "w") as f:
    f.write(content)

print("Exp1 Documentation patched successfully.")
