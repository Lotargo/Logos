"""
Phase 3 — Symbolic Regression Quality
=======================================
Quality metrics for discovered formulas: Pareto optimality,
semantic equivalence, OOD robustness, noise sensitivity, Occam's razor.

Provides:
  pareto_frontier              complexity vs accuracy trade-off
  semantic_equivalence         output correlation between ASTs
  ood_robustness               extrapolation test
  noise_sensitivity_profile    accuracy vs noise level
  occams_razor                 AIC/BIC-style penalty
  cross_domain_transfer        knowledge reuse score
  plot_pareto_frontier         pareto_frontier.png
  full_quality_report          markdown + plots
"""

import numpy as np
from scipy import stats as sp_stats
import os


# ---------------------------------------------------------------------------
# AST evaluation (from verify_results.py, extended)
# ---------------------------------------------------------------------------

def _parse_ast(expr_str):
    """Parse Lisp AST string into nested list."""
    expr_str = expr_str.strip()
    if not expr_str.startswith("("):
        try:
            return float(expr_str)
        except ValueError:
            return expr_str
    tokens = []
    buf = []
    for ch in expr_str:
        if ch == "(":
            tokens.append("(")
        elif ch == ")":
            if buf:
                tokens.append("".join(buf))
                buf = []
            tokens.append(")")
        elif ch.isspace():
            if buf:
                tokens.append("".join(buf))
                buf = []
        else:
            buf.append(ch)
    if buf:
        tokens.append("".join(buf))

    stack = []
    current = []
    for tok in tokens:
        if tok == "(":
            stack.append(current)
            current = []
        elif tok == ")":
            if stack:
                parent = stack.pop()
                parent.append(current)
                current = parent
        else:
            try:
                current.append(float(tok))
            except ValueError:
                current.append(tok)
    return current[0] if current else None


def _eval_ast(ast, row_dict):
    """Evaluate parsed AST with variable dict."""
    if isinstance(ast, (int, float)):
        return ast
    if isinstance(ast, str):
        val = row_dict.get(ast)
        if val is None:
            try:
                return float(ast)
            except ValueError:
                raise ValueError(f"Unknown variable: {ast}")
        return val
    if not isinstance(ast, list) or len(ast) == 0:
        raise ValueError(f"Invalid AST: {ast}")

    op = ast[0].lower() if isinstance(ast[0], str) else str(ast[0])

    if op == "add":
        return _eval_ast(ast[1], row_dict) + _eval_ast(ast[2], row_dict)
    elif op == "sub":
        if len(ast) == 2:
            return -_eval_ast(ast[1], row_dict)
        return _eval_ast(ast[1], row_dict) - _eval_ast(ast[2], row_dict)
    elif op == "mul":
        return _eval_ast(ast[1], row_dict) * _eval_ast(ast[2], row_dict)
    elif op == "div":
        denom = _eval_ast(ast[2], row_dict)
        if denom == 0:
            return 1e9
        return _eval_ast(ast[1], row_dict) / denom
    elif op == "pow":
        return _eval_ast(ast[1], row_dict) ** _eval_ast(ast[2], row_dict)
    elif op == "sin":
        return np.sin(_eval_ast(ast[1], row_dict))
    elif op == "cos":
        return np.cos(_eval_ast(ast[1], row_dict))
    elif op == "exp":
        return np.exp(np.clip(_eval_ast(ast[1], row_dict), -500, 500))
    elif op == "log":
        val = _eval_ast(ast[1], row_dict)
        return np.log(max(abs(val), 1e-300))
    elif op == "sqrt":
        return np.sqrt(abs(_eval_ast(ast[1], row_dict)))
    else:
        raise NotImplementedError(f"Unknown operator: {op}")


def _evaluate_formula(expr_str, X, variables):
    """Evaluate AST string over a dataset X (n_samples × n_vars)."""
    ast = _parse_ast(expr_str)
    preds = []
    for row in X:
        row_dict = {variables[i]: row[i] for i in range(len(variables))}
        preds.append(_eval_ast(ast, row_dict))
    return np.array(preds)


def _ast_node_count(expr_str):
    """Count nodes in AST (depth proxy)."""
    depth = 0
    max_depth = 0
    nodes = 0
    for ch in expr_str:
        if ch == "(":
            depth += 1
            max_depth = max(max_depth, depth)
            nodes += 1
        elif ch == ")":
            depth -= 1
        elif ch.isspace() and depth > 0:
            nodes += 1
    return max_depth, max(nodes, 1)


# ---------------------------------------------------------------------------
# Pareto frontier
# ---------------------------------------------------------------------------

def pareto_frontier(ast_records):
    """
    Compute Pareto frontier (non-dominated sorting).

    Parameters
    ----------
    ast_records : list of dict
        Each has keys:
            ast_expr : str (AST expression)
            ast_depth : int or None (auto-computed if missing)
            ast_size  : int or None (auto-computed if missing)
            mse : float
            r2  : float

    Returns
    -------
    dict with pareto_set, dominance_ratio, best_tradeoff_idx
    """
    if not ast_records:
        return {"pareto_set": [], "dominance_ratio": 0.0, "best_tradeoff_idx": -1}

    # Auto-compute depth/size if missing
    for rec in ast_records:
        expr = rec.get("ast_expr", "")
        if "ast_depth" not in rec or rec["ast_depth"] is None:
            rec["ast_depth"], _ = _ast_node_count(expr)
        if "ast_size" not in rec or rec["ast_size"] is None:
            _, rec["ast_size"] = _ast_node_count(expr)

    n = len(ast_records)

    # Dominance: A dominates B if A is better or equal in ALL objectives
    # and strictly better in at least one.
    # Objectives: minimize depth, minimize MSE
    dominated_by = [0] * n  # how many records dominate this one
    dominates = [[] for _ in range(n)]  # which records this one dominates

    for i in range(n):
        for j in range(n):
            if i == j:
                continue
            a_depth = ast_records[i]["ast_depth"]
            a_mse = ast_records[i]["mse"]
            b_depth = ast_records[j]["ast_depth"]
            b_mse = ast_records[j]["mse"]

            # A dominates B?
            better_or_equal = (a_depth <= b_depth and a_mse <= b_mse)
            strictly_better = (a_depth < b_depth or a_mse < b_mse)
            if better_or_equal and strictly_better:
                dominates[i].append(j)
                dominated_by[j] += 1

    # Pareto front: nothing dominates them
    pareto_indices = [i for i in range(n) if dominated_by[i] == 0]
    pareto_set = [ast_records[i] for i in pareto_indices]

    dominance_ratio = len(pareto_set) / n if n > 0 else 0.0

    # Best tradeoff: closest to utopia point (min depth, min MSE)
    if pareto_set:
        depths = np.array([r["ast_depth"] for r in pareto_set])
        mses = np.array([r["mse"] for r in pareto_set])
        # Normalize to [0, 1]
        d_range = depths.max() - depths.min()
        m_range = mses.max() - mses.min()
        d_norm = (depths - depths.min()) / max(d_range, 1e-12)
        m_norm = (mses - mses.min()) / max(m_range, 1e-12)
        distances = np.sqrt(d_norm ** 2 + m_norm ** 2)
        best_tradeoff_idx = int(np.argmin(distances))
    else:
        best_tradeoff_idx = -1

    return {
        "pareto_set": pareto_set,
        "pareto_indices": pareto_indices,
        "dominance_ratio": dominance_ratio,
        "best_tradeoff_idx": best_tradeoff_idx,
    }


# ---------------------------------------------------------------------------
# Semantic equivalence
# ---------------------------------------------------------------------------

def semantic_equivalence(ast_expr_a, ast_expr_b, X, variables):
    """
    Check if two ASTs produce near-identical outputs.

    Parameters
    ----------
    ast_expr_a, ast_expr_b : str
        Lisp AST expressions.
    X : array-like (n_samples × n_vars)
        Input data.
    variables : list of str
        Variable names matching X columns.

    Returns
    -------
    dict with is_equivalent, output_correlation, max_abs_diff, structural_distance
    """
    y_a = _evaluate_formula(ast_expr_a, X, variables)
    y_b = _evaluate_formula(ast_expr_b, X, variables)

    # Correlation
    if np.std(y_a) > 0 and np.std(y_b) > 0:
        corr, _ = sp_stats.pearsonr(y_a, y_b)
    else:
        corr = 1.0 if np.allclose(y_a, y_b) else 0.0

    max_diff = float(np.max(np.abs(y_a - y_b)))

    # Structural distance
    d_a, s_a = _ast_node_count(ast_expr_a)
    d_b, s_b = _ast_node_count(ast_expr_b)
    depth_diff = abs(d_a - d_b) / max(d_a + d_b, 1)
    size_diff = abs(s_a - s_b) / max(s_a + s_b, 1)
    structural_dist = 0.5 * depth_diff + 0.5 * size_diff

    is_equiv = bool(abs(corr) > 0.999 and max_diff < 0.01)

    return {
        "is_equivalent": is_equiv,
        "output_correlation": float(corr),
        "max_abs_diff": max_diff,
        "structural_distance": structural_dist,
    }


# ---------------------------------------------------------------------------
# OOD robustness
# ---------------------------------------------------------------------------

def ood_robustness(ast_expr, X_train, y_train, X_ood, y_ood, variables):
    """
    Compute generalization gap: train R² vs OOD R².

    Parameters
    ----------
    ast_expr : str
        Lisp AST expression.
    X_train, y_train : array-like
        In-distribution data.
    X_ood, y_ood : array-like
        Out-of-distribution data.
    variables : list of str

    Returns
    -------
    dict with train_r2, ood_r2, generalization_gap, train_mse, ood_mse
    """
    pred_train = _evaluate_formula(ast_expr, X_train, variables)
    pred_ood = _evaluate_formula(ast_expr, X_ood, variables)

    # Train metrics
    mse_train = float(np.mean((y_train - pred_train) ** 2))
    var_train = np.var(y_train)
    r2_train = 1 - mse_train / var_train if var_train > 0 else 1.0

    # OOD metrics
    mse_ood = float(np.mean((y_ood - pred_ood) ** 2))
    var_ood = np.var(y_ood)
    r2_ood = 1 - mse_ood / var_ood if var_ood > 0 else 1.0

    gap = r2_train - r2_ood

    return {
        "train_r2": float(r2_train),
        "ood_r2": float(r2_ood),
        "generalization_gap": float(gap),
        "train_mse": mse_train,
        "ood_mse": mse_ood,
    }


# ---------------------------------------------------------------------------
# Noise sensitivity profile
# ---------------------------------------------------------------------------

def noise_sensitivity_profile(ast_expr, X, y_true, variables,
                              noise_levels=None, n_trials=5):
    """
    Accuracy degradation curve across noise levels.

    Parameters
    ----------
    ast_expr : str
    X, y_true : array-like
    variables : list of str
    noise_levels : list of float
        Standard deviations of Gaussian noise to add to y_true.
    n_trials : int
        Repeat each noise level for stability.

    Returns
    -------
    dict with noise_curve (DataFrame-like), decay_rate, noise_threshold_50%
    """
    if noise_levels is None:
        noise_levels = [0.0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0]

    y_clean = _evaluate_formula(ast_expr, X, variables)
    base_mse = float(np.mean((y_true - y_clean) ** 2))

    curve = {"noise_level": [], "mean_r2": [], "std_r2": [], "mean_mse": []}

    for sigma in noise_levels:
        r2s = []
        mses = []
        for _ in range(n_trials):
            y_noisy = y_true + np.random.normal(0, sigma, size=len(y_true))
            mse = float(np.mean((y_noisy - y_clean) ** 2))
            var = np.var(y_noisy)
            r2 = 1 - mse / var if var > 0 else 1.0
            r2s.append(r2)
            mses.append(mse)
        curve["noise_level"].append(sigma)
        curve["mean_r2"].append(float(np.mean(r2s)))
        curve["std_r2"].append(float(np.std(r2s)))
        curve["mean_mse"].append(float(np.mean(mses)))

    # Fit exponential decay: R² ≈ A * exp(-B * sigma) + C
    sigmas = np.array(curve["noise_level"])
    r2s = np.array(curve["mean_r2"])
    try:
        # Simple exponential fit via log-linear regression
        valid = r2s > 0
        if valid.sum() >= 3:
            log_r2 = np.log(r2s[valid] + 1e-30)
            slope, intercept, _, _, _ = sp_stats.linregress(sigmas[valid], log_r2)
            decay_rate = -slope
        else:
            decay_rate = 0.0
    except Exception:
        decay_rate = 0.0

    # 50% noise threshold: sigma where R² drops to 50% of clean R²
    clean_r2 = curve["mean_r2"][0] if curve["mean_r2"] else 1.0
    threshold_50 = 0.0
    for i, r2 in enumerate(curve["mean_r2"]):
        if r2 < clean_r2 * 0.5:
            threshold_50 = curve["noise_level"][i]
            break

    return {
        "noise_curve": curve,
        "decay_rate": float(decay_rate),
        "noise_threshold_50": float(threshold_50),
        "base_mse": base_mse,
    }


# ---------------------------------------------------------------------------
# Occam's razor
# ---------------------------------------------------------------------------

def occams_razor(ast_expr, y_true, y_pred, n_params=None):
    """
    AIC and BIC complexity-adjusted scores.

    Parameters
    ----------
    ast_expr : str
    y_true, y_pred : array-like
    n_params : int or None
        Number of parameters (operators + constants). Auto-computed if None.

    Returns
    -------
    dict with aic, bic, complexity_penalty, n_params, n_samples
    """
    n = len(y_true)
    if n_params is None:
        # Auto-compute: count operators + numeric constants in AST
        tokens = ast_expr.replace("(", " ").replace(")", " ").split()
        n_params = 0
        for t in tokens:
            try:
                float(t)
                n_params += 1  # constant
            except ValueError:
                if t.lower() not in ("x", "y", "z", "v0", "v1", "v2", "a", "b", "c",
                                      "r", "m1", "m2", "t", "c_light", "v"):
                    n_params += 1  # operator

    mse = float(np.mean((y_true - y_pred) ** 2))
    if mse <= 0:
        mse = 1e-300

    log_likelihood = -0.5 * n * np.log(mse)

    aic = 2 * n_params - 2 * log_likelihood
    bic = n_params * np.log(n) - 2 * log_likelihood

    return {
        "aic": float(aic),
        "bic": float(bic),
        "n_params": n_params,
        "n_samples": n,
        "mse": mse,
    }


# ---------------------------------------------------------------------------
# Cross-domain transfer
# ---------------------------------------------------------------------------

def cross_domain_transfer(results_no_transfer, results_with_transfer):
    """
    Transfer ratio: iterations without / with cross-domain knowledge.

    Parameters
    ----------
    results_no_transfer : list of int
        Iterations to converge WITHOUT cross-domain knowledge.
    results_with_transfer : list of int
        Iterations to converge WITH cross-domain knowledge.

    Returns
    -------
    dict with transfer_ratio, mean_no_transfer, mean_with_transfer,
          speedup_significant (bool), p_value
    """
    a = np.asarray(results_no_transfer, dtype=float)
    b = np.asarray(results_with_transfer, dtype=float)

    mean_a = float(np.mean(a)) if len(a) > 0 else 0.0
    mean_b = float(np.mean(b)) if len(b) > 0 else 0.0

    ratio = mean_a / mean_b if mean_b > 0 else float("inf")

    # Statistical test
    if len(a) >= 2 and len(b) >= 2:
        stat, p = sp_stats.mannwhitneyu(a, b, alternative="two-sided")
    else:
        p = 1.0

    return {
        "transfer_ratio": ratio,
        "mean_no_transfer": mean_a,
        "mean_with_transfer": mean_b,
        "speedup_significant": p < 0.05,
        "p_value": float(p),
    }


# ---------------------------------------------------------------------------
# Plotting
# ---------------------------------------------------------------------------

def plot_pareto_frontier(pareto_data, output_path):
    """
    Generate pareto_frontier.png — scatter with Pareto front highlighted.
    """
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    pareto_set = pareto_data.get("pareto_set", [])
    all_records = pareto_data.get("all_records", pareto_set)

    if not all_records:
        return

    fig, ax = plt.subplots(figsize=(8, 5))

    # All records
    depths = [r["ast_depth"] for r in all_records]
    mses = [r["mse"] for r in all_records]
    ax.scatter(depths, mses, c="#90CAF9", s=40, alpha=0.6, label="All candidates", zorder=2)

    # Pareto front
    if pareto_set:
        p_depths = [r["ast_depth"] for r in pareto_set]
        p_mses = [r["mse"] for r in pareto_set]
        # Sort by depth for line plot
        sorted_pts = sorted(zip(p_depths, p_mses))
        p_depths_s, p_mses_s = zip(*sorted_pts)
        ax.plot(p_depths_s, p_mses_s, "o-", color="#F44336", markersize=8,
                linewidth=2, label="Pareto front", zorder=3)

        # Highlight best tradeoff
        best_idx = pareto_data.get("best_tradeoff_idx", -1)
        if 0 <= best_idx < len(pareto_set):
            bx = pareto_set[best_idx]["ast_depth"]
            by = pareto_set[best_idx]["mse"]
            ax.scatter([bx], [by], c="#FFD600", s=150, marker="*",
                       zorder=4, label="Best tradeoff")

    ax.set_xlabel("AST Depth (complexity)")
    ax.set_ylabel("MSE (error)")
    ax.set_title("Pareto Frontier: Complexity vs Accuracy")
    ax.legend()
    ax.set_yscale("log")
    fig.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)


def plot_noise_profile(noise_data, output_path):
    """Generate noise_sensitivity.png"""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    curve = noise_data.get("noise_curve", {})
    if not curve.get("noise_level"):
        return

    fig, ax1 = plt.subplots(figsize=(8, 5))

    sigmas = curve["noise_level"]
    r2s = curve["mean_r2"]
    r2_errs = curve["std_r2"]

    ax1.errorbar(sigmas, r2s, yerr=r2_errs, fmt="o-", color="#2196F3",
                 linewidth=2, markersize=6, capsize=3, label="R²")
    ax1.set_xlabel("Noise level (σ)")
    ax1.set_ylabel("R²", color="#2196F3")
    ax1.tick_params(axis="y", labelcolor="#2196F3")

    ax2 = ax1.twinx()
    mses = curve["mean_mse"]
    ax2.plot(sigmas, mses, "s--", color="#F44336", linewidth=1.5,
             markersize=5, alpha=0.7, label="MSE")
    ax2.set_ylabel("MSE", color="#F44336")
    ax2.tick_params(axis="y", labelcolor="#F44336")
    ax2.set_yscale("log")

    lines1, labels1 = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines1 + lines2, labels1 + labels2, loc="upper right")

    ax1.set_title("Noise Sensitivity Profile")
    fig.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)


# ---------------------------------------------------------------------------
# Full report
# ---------------------------------------------------------------------------

def full_quality_report(pareto_data, noise_data, ood_data, equivalence_results,
                        output_dir):
    """
    Generate quality report with plots + markdown.
    """
    os.makedirs(output_dir, exist_ok=True)

    # Generate plots
    if pareto_data.get("pareto_set"):
        plot_pareto_frontier(pareto_data, os.path.join(output_dir, "pareto_frontier.png"))
    if noise_data and noise_data.get("noise_curve", {}).get("noise_level"):
        plot_noise_profile(noise_data, os.path.join(output_dir, "noise_sensitivity.png"))

    # Markdown report
    lines = [
        "# Symbolic Regression Quality Analysis",
        "",
        "*Generated by Logos V9 Verification Suite*",
        "",
        "---",
        "",
    ]

    # Pareto
    lines.append("## Pareto Frontier (Complexity vs Accuracy)")
    lines.append("")
    if pareto_data.get("pareto_set"):
        lines.append(f"- **Total candidates:** {len(pareto_data.get('all_records', []))}")
        lines.append(f"- **Pareto-optimal candidates:** {len(pareto_data['pareto_set'])}")
        lines.append(f"- **Dominance ratio:** {pareto_data['dominance_ratio']:.1%}")
        best_idx = pareto_data.get("best_tradeoff_idx", -1)
        if 0 <= best_idx < len(pareto_data["pareto_set"]):
            best = pareto_data["pareto_set"][best_idx]
            lines.append(f"- **Best tradeoff:** depth={best['ast_depth']}, "
                         f"MSE={best['mse']:.6f}, R²={best.get('r2', 0):.6f}")
    else:
        lines.append("- No Pareto data available.")
    lines.append("")

    # Noise
    lines.append("## Noise Sensitivity")
    lines.append("")
    if noise_data and noise_data.get("noise_curve", {}).get("noise_level"):
        lines.append(f"- **Decay rate:** {noise_data['decay_rate']:.4f}")
        lines.append(f"- **50% noise threshold:** σ={noise_data['noise_threshold_50']:.4f}")
        lines.append(f"- **Base MSE (no noise):** {noise_data['base_mse']:.6f}")
    else:
        lines.append("- No noise profile data available.")
    lines.append("")

    # OOD
    lines.append("## Out-of-Distribution Robustness")
    lines.append("")
    if ood_data:
        lines.append(f"- **Train R²:** {ood_data['train_r2']:.6f}")
        lines.append(f"- **OOD R²:** {ood_data['ood_r2']:.6f}")
        lines.append(f"- **Generalization gap:** {ood_data['generalization_gap']:.4f}")
    else:
        lines.append("- No OOD data available.")
    lines.append("")

    # Equivalence
    lines.append("## Semantic Equivalence")
    lines.append("")
    if equivalence_results:
        for i, eq in enumerate(equivalence_results, 1):
            lines.append(f"- **Pair {i}:** correlation={eq['output_correlation']:.6f}, "
                         f"max_diff={eq['max_abs_diff']:.6f}, "
                         f"equivalent={'Yes' if eq['is_equivalent'] else 'No'}")
    else:
        lines.append("- No equivalence checks performed.")
    lines.append("")

    lines.extend(["---", "", "*End of report.*", ""])

    md_path = os.path.join(output_dir, "quality_report.md")
    with open(md_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    return md_path
