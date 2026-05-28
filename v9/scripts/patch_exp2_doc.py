import re
import os

filepath = "v9/docs/NSPL_Exp2_Adversarial_Physics.md"

with open(filepath, "r") as f:
    content = f.read()

# 1. Update Limits to Floating-Point Exception
content = re.sub(
    r"Upon receiving \$x_\{adv\}\$, Node A evaluates \$\\lim_\{R \\rightarrow 0\} \\frac\{M\}\{R\} = \\infty\$, triggering a Lisp floating-point exception",
    r"Upon receiving $x_{adv}$, Node A evaluates the AST natively. It does not calculate limits; rather, the hardware Floating-Point Unit (FPU) hits a mathematical singularity, throwing a Lisp `DIVISION-BY-ZERO` runtime condition. The Lisp condition system catches this exception",
    content
)

# 2. Fix the Healing example from M/(R+1) to Dimensional Consistency M/(R^2 + L_p^2)
content = re.sub(
    r"Healed Equation: \(DIV M \(ADD R 1\)\).*?resists r=0 attack",
    r"Healed Equation: (DIV M (ADD (MUL R R) L_P))... resists r=0 attack",
    content,
    flags=re.DOTALL
)

content = re.sub(
    r"\\frac\{M\}\{R \+ C\}",
    r"\\frac{M}{R^2 + C^2}",
    content
)

content = re.sub(
    r"If \$F\(R\) = ADD\(R, 1\)\$, the new formula becomes \$M/\(R\+1\)\$. While this heals the singularity at \$R=0\$, the Adversary will eventually learn to attack with \$R=-1\$.",
    r"Crucially, the simple topological patch $F(R) = ADD(R, 1)$ would be immediately rejected by Prolog's Dimensional Censor. One cannot physically add meters ($R$) to a dimensionless scalar ($1$). Thus, the Generator is forced to evolve dimensionally consistent topologies, such as adding the square of a length constant (like the Planck length, $L_p$): $F(R) = R^2 + L_p^2$.",
    content
)

# 3 & 4: Add CLP(R) and GAN Tradeoff sections
clp_and_tradeoff = r"""
### 2.4 The CLP(R) Root-Finding Adversary
A critical question is how the Adversary calculates $x_{adv}$. Node B does not use hardcoded syntactic heuristics (like searching for `[div, _, R]`). Instead, it leverages SWI-Prolog's **CLP(R)** (Constraint Logic Programming over Reals) library. When Node B receives an equation via NSPL, it extracts the denominator and passes it to the CLP(R) solver with the constraint `{Denominator = 0}`.

If the Generator proposes $M / (\sin(R) - 0.5)$, the CLP(R) engine algebraically solves $\{\sin(R) - 0.5 = 0\} \implies R = \arcsin(0.5)$ and fires $x_{adv} = 0.523$ back at the Generator. This makes the Adversary a true mathematical hacker, capable of breaking arbitrary nonlinear topologies without human guidance.

### 2.5 The GAN Trade-off: Accuracy vs. Robustness
Healing a singularity introduces a "Mode Collapse" dilemma. The Generator's total loss function is a weighted sum:
$$ \mathcal{L}_{Total} = \alpha \mathcal{L}_{MSE}(Dataset) + \beta \mathcal{L}_{Adversarial} $$

If the evolved constant $C^2$ is too large (e.g., $10^5$), the singularity is avoided, but the curve diverges wildly from the target dataset (gravity), causing $\mathcal{L}_{MSE}$ to spike. The evolutionary loop must find the absolute minimal topology—a $C$ so infinitesimally small (like $10^{-35}$) that it survives the Adversary's division-by-zero attack while leaving the macroscopic $\mathcal{L}_{MSE}$ completely unaffected. This perfectly mirrors the historical process of renormalization in quantum field theory.
"""

content = re.sub(
    r"### 3\. Experimental Setup",
    clp_and_tradeoff.replace('\\', '\\\\') + "\n### 3. Experimental Setup",
    content
)

# 5. Remove hardcoded Prolog ban example and rewrite section 9
new_section_9 = r"""
## 9. Dynamic Extensibility via CLP(R)

The true power of the Adversarial Node relies on the fact that it is not reliant on static syntax rules. Because the Adversary uses CLP(R), it dynamically adapts to the Generator's defenses.

If the Generator attempts a lazy topological patch that passes dimensional checks, such as $M / (R - L_p)$, the Adversary does not need a new hardcoded rule to break it. The CLP(R) solver simply processes the new denominator: `{R - L_p = 0} \implies R = L_p`. The Adversary instantly generates a new NSPL attack packet with the value of $L_p$.

This forces the Generator into a relentless evolutionary arms race, driving it away from linear shifts and toward absolute mathematical robustness (like squared sums or absolute values) where the CLP(R) engine mathematically proves no real roots exist.
"""

content = re.sub(
    r"## 9\. Dynamic Extensibility of the Censor Logic.*?## 10\. Summary of Outcomes",
    new_section_9.replace('\\', '\\\\') + "\n## 10. Summary of Outcomes",
    content,
    flags=re.DOTALL
)

with open(filepath, "w") as f:
    f.write(content)

print("Exp2 Documentation patched successfully.")
