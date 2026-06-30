"""
Phase 2 — Evolutionary Search Analytics
=========================================
Metrics for population diversity, fitness landscape, stagnation,
operator importance, and genealogical tracing.

Provides:
  population_diversity       AST edit distance + operator Shannon entropy
  fitness_landscape           FDC + ruggedness
  stagnation_detection        windowed variance + trend
  operator_importance         usage × success correlation
  lineage_depth               genealogical tracing
  plot_diversity_trend        diversity_trend.png
  plot_operator_heatmap       operator_heatmap.png
  full_evolutionary_report    markdown + plots
"""

import numpy as np
from scipy import stats as sp_stats
import os


# ---------------------------------------------------------------------------
# AST helpers (lightweight, no Lisp dependency)
# ---------------------------------------------------------------------------

def _tokenize_ast(expr):
    """Tokenize an AST string into a flat list of tokens."""
    tokens = []
    buf = []
    for ch in expr:
        if ch in ("(", ")"):
            if buf:
                tokens.append("".join(buf))
                buf = []
            tokens.append(ch)
        elif ch.isspace():
            if buf:
                tokens.append("".join(buf))
                buf = []
        else:
            buf.append(ch)
    if buf:
        tokens.append("".join(buf))
    return tokens


def _ast_depth(expr):
    """Compute depth of an AST expression string."""
    depth = 0
    max_depth = 0
    for ch in expr:
        if ch == "(":
            depth += 1
            max_depth = max(max_depth, depth)
        elif ch == ")":
            depth -= 1
    return max_depth


def _extract_operators(expr):
    """Extract operator names from AST string (non-leaf tokens after '(')."""
    tokens = _tokenize_ast(expr)
    ops = []
    i = 0
    while i < len(tokens):
        if tokens[i] == "(":
            i += 1
            if i < len(tokens) and tokens[i] not in ("(", ")"):
                ops.append(tokens[i])
        i += 1
    return ops


def _tree_edit_distance_simple(a_expr, b_expr):
    """
    Simplified tree edit distance based on operator-level overlap.
    Returns value in [0, 1] where 0 = identical, 1 = completely different.
    Full tree edit distance is O(n^3); this is a practical approximation
    using operator set Jaccard distance + depth difference.
    """
    ops_a = set(_extract_operators(a_expr))
    ops_b = set(_extract_operators(b_expr))

    # Jaccard distance on operator sets
    if ops_a or ops_b:
        jaccard = len(ops_a & ops_b) / max(len(ops_a | ops_b), 1)
    else:
        jaccard = 1.0  # both empty → identical

    # Depth difference
    d_a = _ast_depth(a_expr)
    d_b = _ast_depth(b_expr)
    depth_diff = abs(d_a - d_b) / max(d_a + d_b, 1)

    # Combined distance
    return 0.6 * (1.0 - jaccard) + 0.4 * depth_diff


# ---------------------------------------------------------------------------
# Population diversity
# ---------------------------------------------------------------------------

def population_diversity(snapshots):
    """
    Compute diversity metrics from population snapshots.

    Parameters
    ----------
    snapshots : list of dict
        Each dict has keys:
            iteration : int
            asts      : list of str (AST expressions)
            fitnesses : list of float

    Returns
    -------
    dict with per-iteration metrics:
        mean_pairwise_distance : list of float
        operator_entropy       : list of float
        mean_fitness           : list of float
        fitness_variance       : list of float
        phenotype_count        : list of int (unique fitness values, rounded)
    """
    results = {
        "iterations": [],
        "mean_pairwise_distance": [],
        "operator_entropy": [],
        "mean_fitness": [],
        "fitness_variance": [],
        "phenotype_count": [],
    }

    for snap in snapshots:
        asts = snap.get("asts", [])
        fitnesses = np.asarray(snap.get("fitnesses", []), dtype=float)
        iteration = snap.get("iteration", -1)
        results["iterations"].append(iteration)

        # Mean pairwise distance (sample up to 100 for O(n^2) feasibility)
        n = len(asts)
        if n < 2:
            results["mean_pairwise_distance"].append(0.0)
        else:
            sample_idx = np.arange(n)
            if n > 100:
                sample_idx = np.random.choice(n, 100, replace=False)
            dists = []
            for i in range(len(sample_idx)):
                for j in range(i + 1, len(sample_idx)):
                    dists.append(
                        _tree_edit_distance_simple(asts[sample_idx[i]], asts[sample_idx[j]])
                    )
            results["mean_pairwise_distance"].append(np.mean(dists) if dists else 0.0)

        # Operator Shannon entropy
        all_ops = []
        for expr in asts:
            all_ops.extend(_extract_operators(expr))
        if all_ops:
            ops, counts = np.unique(all_ops, return_counts=True)
            probs = counts / counts.sum()
            entropy = -np.sum(probs * np.log2(probs))
        else:
            entropy = 0.0
        results["operator_entropy"].append(entropy)

        # Fitness stats
        if len(fitnesses) > 0:
            results["mean_fitness"].append(float(np.mean(fitnesses)))
            results["fitness_variance"].append(float(np.var(fitnesses)))
            # Phenotype count: unique values rounded to 3 decimal places
            rounded = np.round(fitnesses, 3)
            results["phenotype_count"].append(len(np.unique(rounded)))
        else:
            results["mean_fitness"].append(0.0)
            results["fitness_variance"].append(0.0)
            results["phenotype_count"].append(0)

    return results


# ---------------------------------------------------------------------------
# Fitness landscape
# ---------------------------------------------------------------------------

def fitness_landscape(fitness_history):
    """
    Analyze fitness landscape properties.

    Parameters
    ----------
    fitness_history : array-like
        Best fitness per iteration (monotonically or non-monotonically improving).

    Returns
    -------
    dict with:
        fdc          : Fitness-Distance Correlation (absolute value)
        fdc_interp   : 'smooth' if |FDC| > 0.5, 'rugged' otherwise
        ruggedness   : lag-1 autocorrelation of fitness differences
        rugged_interp: 'smooth' if ruggedness < 0.3, 'rugged' otherwise
        trend_slope  : linear regression slope of fitness over iterations
        trend_r2     : R² of linear fit
        best_fitness : maximum fitness
        convergence_iter : iteration where best fitness was first reached
    """
    f = np.asarray(fitness_history, dtype=float)
    n = len(f)

    if n < 3:
        return {
            "fdc": 0.0, "fdc_interp": "insufficient data",
            "ruggedness": 0.0, "rugged_interp": "insufficient data",
            "trend_slope": 0.0, "trend_r2": 0.0,
            "best_fitness": float(np.max(f)) if n > 0 else 0.0,
            "convergence_iter": int(np.argmax(f)) if n > 0 else 0,
        }

    # FDC: correlation between fitness and "distance to best"
    best_idx = int(np.argmax(f))
    best_val = f[best_idx]
    distances = np.abs(f - best_val)
    if np.std(distances) > 0:
        fdc, _ = sp_stats.pearsonr(f, -distances)  # negative correlation = smooth
    else:
        fdc = 0.0
    fdc_interp = "smooth" if abs(fdc) > 0.5 else "rugged"

    # Ruggedness: lag-1 autocorrelation of first differences
    diffs = np.diff(f)
    if len(diffs) > 1 and np.std(diffs) > 0:
        ruggedness = float(np.corrcoef(diffs[:-1], diffs[1:])[0, 1])
    else:
        ruggedness = 0.0
    rugged_interp = "smooth" if abs(ruggedness) < 0.3 else "rugged"

    # Trend
    x = np.arange(n)
    slope, intercept, r_val, _, _ = sp_stats.linregress(x, f)

    # Convergence iteration: last time best fitness improved
    improvements = np.where(np.diff(f) > 1e-10)[0]
    convergence_iter = int(improvements[-1] + 1) if len(improvements) > 0 else 0

    return {
        "fdc": fdc,
        "fdc_interp": fdc_interp,
        "ruggedness": ruggedness,
        "rugged_interp": rugged_interp,
        "trend_slope": slope,
        "trend_r2": r_val ** 2,
        "best_fitness": float(best_val),
        "convergence_iter": convergence_iter,
    }


# ---------------------------------------------------------------------------
# Stagnation detection
# ---------------------------------------------------------------------------

def stagnation_detection(fitness_history, window=50):
    """
    Detect stagnation periods in fitness history.

    Parameters
    ----------
    fitness_history : array-like
        Best fitness per iteration.
    window : int
        Rolling window size for variance and slope computation.

    Returns
    -------
    dict with:
        is_stagnated     : bool (True if current window is stagnant)
        stagnation_index : float [0,1] (0 = active, 1 = fully stagnant)
        stagnation_start : int or None (iteration where stagnation began)
        rolling_variance : list of float
        rolling_slope    : list of float
    """
    f = np.asarray(fitness_history, dtype=float)
    n = len(f)

    if n < window:
        return {
            "is_stagnated": False,
            "stagnation_index": 0.0,
            "stagnation_start": None,
            "rolling_variance": [],
            "rolling_slope": [],
        }

    rolling_var = []
    rolling_slope = []
    stagnation_start = None

    for i in range(window, n + 1):
        w = f[i - window: i]
        rolling_var.append(float(np.var(w)))
        x = np.arange(window)
        slope, _, _, _, _ = sp_stats.linregress(x, w)
        rolling_slope.append(float(slope))

    rv = np.array(rolling_var)
    rs = np.array(rolling_slope)

    # Stagnation criteria: low variance AND near-zero slope
    var_threshold = np.percentile(rv, 25) if len(rv) > 0 else 0
    slope_threshold = 1e-6

    is_stag = bool(len(rv) > 0 and rv[-1] <= var_threshold and abs(rs[-1]) < slope_threshold)

    # Stagnation index: combine normalized variance and slope
    if len(rv) > 0:
        max_var = np.max(rv) if np.max(rv) > 0 else 1.0
        norm_var = rv[-1] / max_var
        norm_slope = min(abs(rs[-1]) / (slope_threshold * 100 + 1e-12), 1.0)
        stagnation_index = 0.5 * norm_var + 0.5 * (1.0 - norm_slope)
    else:
        stagnation_index = 0.0

    # Find stagnation start
    if is_stag:
        for i in range(len(rv) - 1, -1, -1):
            if rv[i] > var_threshold or abs(rs[i]) >= slope_threshold:
                stagnation_start = i + window
                break
        if stagnation_start is None:
            stagnation_start = 0

    return {
        "is_stagnated": is_stag,
        "stagnation_index": float(stagnation_index),
        "stagnation_start": stagnation_start,
        "rolling_variance": rolling_var,
        "rolling_slope": rolling_slope,
    }


# ---------------------------------------------------------------------------
# Operator importance
# ---------------------------------------------------------------------------

def operator_importance(operator_log):
    """
    Analyze operator importance from usage log.

    Parameters
    ----------
    operator_log : list of dict
        Each dict has keys:
            operator     : str
            success      : bool
            fitness_delta: float (improvement, can be negative)

    Returns
    -------
    dict with:
        table     : list of dict per operator (usage, success_rate, avg_delta)
        chi2      : chi-square statistic for operator×success independence
        chi2_p    : p-value of chi-square test
    """
    if not operator_log:
        return {"table": [], "chi2": 0.0, "chi2_p": 1.0}

    # Aggregate by operator
    from collections import defaultdict
    agg = defaultdict(lambda: {"usage": 0, "successes": 0, "deltas": []})
    for entry in operator_log:
        op = entry.get("operator", "unknown")
        agg[op]["usage"] += 1
        if entry.get("success", False):
            agg[op]["successes"] += 1
        agg[op]["deltas"].append(entry.get("fitness_delta", 0.0))

    table = []
    for op, data in sorted(agg.items(), key=lambda x: -x[1]["usage"]):
        usage = data["usage"]
        successes = data["successes"]
        deltas = data["deltas"]
        table.append({
            "operator": op,
            "usage_count": usage,
            "success_count": successes,
            "success_rate": successes / usage if usage > 0 else 0.0,
            "avg_fitness_delta": float(np.mean(deltas)) if deltas else 0.0,
        })

    # Chi-square test: operator independence from success
    ops = list(agg.keys())
    if len(ops) < 2:
        return {"table": table, "chi2": 0.0, "chi2_p": 1.0}

    # Build contingency table: rows=operators, cols=[failure, success]
    contingency = []
    for op in ops:
        total = agg[op]["usage"]
        succ = agg[op]["successes"]
        contingency.append([total - succ, succ])
    contingency = np.array(contingency)

    # Remove rows with zero totals
    row_totals = contingency.sum(axis=1)
    valid = row_totals > 0
    contingency = contingency[valid]

    if contingency.shape[0] < 2 or contingency.shape[1] < 2:
        return {"table": table, "chi2": 0.0, "chi2_p": 1.0}

    chi2, p, _, _ = sp_stats.chi2_contingency(contingency)

    return {"table": table, "chi2": float(chi2), "chi2_p": float(p)}


# ---------------------------------------------------------------------------
# Lineage depth
# ---------------------------------------------------------------------------

def lineage_depth(passport_records):
    """
    Analyze lineage chains from passport records.

    Parameters
    ----------
    passport_records : list of dict
        Each dict has keys:
            ast_hash : str
            lineage  : list of str (parent hashes, from most recent to oldest)

    Returns
    -------
    dict with:
        max_depth       : int
        mean_depth      : float
        depth_distribution : dict {depth: count}
    """
    if not passport_records:
        return {"max_depth": 0, "mean_depth": 0.0, "depth_distribution": {}}

    depths = []
    for rec in passport_records:
        lineage = rec.get("lineage", [])
        depths.append(len(lineage))

    dist = {}
    for d in depths:
        dist[d] = dist.get(d, 0) + 1

    return {
        "max_depth": max(depths) if depths else 0,
        "mean_depth": float(np.mean(depths)) if depths else 0.0,
        "depth_distribution": dist,
    }


# ---------------------------------------------------------------------------
# Plotting helpers
# ---------------------------------------------------------------------------

def plot_diversity_trend(diversity_data, output_path):
    """
    Generate diversity_trend.png — dual-axis plot:
      left axis  : mean pairwise distance + operator entropy
      right axis : fitness variance
    """
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    iters = diversity_data["iterations"]
    if not iters:
        return

    fig, ax1 = plt.subplots(figsize=(10, 5))

    color_dist = "#2196F3"
    color_ent = "#FF9800"
    color_var = "#4CAF50"

    ax1.set_xlabel("Iteration")
    ax1.set_ylabel("Mean Pairwise Distance / Operator Entropy", color="black")
    l1, = ax1.plot(iters, diversity_data["mean_pairwise_distance"],
                   color=color_dist, linewidth=1.5, label="Pairwise Distance")
    l2, = ax1.plot(iters, diversity_data["operator_entropy"],
                   color=color_ent, linewidth=1.5, label="Operator Entropy")
    ax1.tick_params(axis="y", labelcolor="black")

    ax2 = ax1.twinx()
    ax2.set_ylabel("Fitness Variance", color=color_var)
    l3, = ax2.plot(iters, diversity_data["fitness_variance"],
                   color=color_var, linewidth=1.0, linestyle="--",
                   alpha=0.7, label="Fitness Variance")
    ax2.tick_params(axis="y", labelcolor=color_var)

    lines = [l1, l2, l3]
    labels = [l.get_label() for l in lines]
    ax1.legend(lines, labels, loc="upper left", fontsize=9)

    ax1.set_title("Population Diversity Over Generations")
    fig.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)


def plot_operator_heatmap(operator_table, output_path, top_n=15):
    """
    Generate operator_heatmap.png — horizontal bar chart:
      bars = success_rate, color intensity = usage_count
    """
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    if not operator_table:
        return

    # Sort by usage, take top N
    sorted_ops = sorted(operator_table, key=lambda x: -x["usage_count"])[:top_n]
    ops = [o["operator"] for o in sorted_ops][::-1]
    usage = [o["usage_count"] for o in sorted_ops][::-1]
    rates = [o["success_rate"] for o in sorted_ops][::-1]

    fig, ax = plt.subplots(figsize=(8, max(4, len(ops) * 0.4)))
    colors = plt.cm.RdYlGn(np.array(rates))  # red=low, green=high

    bars = ax.barh(ops, usage, color=colors, edgecolor="white", linewidth=0.5)
    ax.set_xlabel("Usage Count")
    ax.set_title("Operator Usage & Success Rate")

    # Add rate labels
    for bar, rate in zip(bars, rates):
        ax.text(bar.get_width() + max(usage) * 0.01, bar.get_y() + bar.get_height() / 2,
                f"{rate:.0%}", va="center", fontsize=8)

    fig.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)


# ---------------------------------------------------------------------------
# Full report
# ---------------------------------------------------------------------------

def full_evolutionary_report(snapshots, operator_log, output_dir):
    """
    Run all evolutionary analytics, generate plots + markdown report.

    Parameters
    ----------
    snapshots : list of dict (from population_diversity)
    operator_log : list of dict (from operator_importance)
    output_dir : str

    Returns
    -------
    str — path to convergence_analysis.md
    """
    os.makedirs(output_dir, exist_ok=True)

    # 1. Population diversity
    div = population_diversity(snapshots)

    # 2. Fitness landscape (use mean_fitness from snapshots)
    fitness_history = div["mean_fitness"]
    landscape = fitness_landscape(fitness_history)

    # 3. Stagnation detection
    stag = stagnation_detection(fitness_history)

    # 4. Operator importance
    op_importance = operator_importance(operator_log)

    # 5. Lineage depth (if passport data available)
    passports = []
    for snap in snapshots:
        passports.extend(snap.get("passports", []))
    lineage = lineage_depth(passports)

    # --- Generate plots ---
    if div["iterations"]:
        plot_diversity_trend(div, os.path.join(output_dir, "diversity_trend.png"))
    if op_importance["table"]:
        plot_operator_heatmap(op_importance["table"], os.path.join(output_dir, "operator_heatmap.png"))

    # --- Generate markdown ---
    lines = [
        "# Convergence & Evolutionary Analysis",
        "",
        "*Generated by Logos V9 Verification Suite*",
        "",
        "---",
        "",
        "## Population Diversity",
        "",
    ]

    if div["iterations"]:
        lines.append(f"- **Iterations tracked:** {len(div['iterations'])}")
        lines.append(f"- **Final mean pairwise distance:** {div['mean_pairwise_distance'][-1]:.4f}")
        lines.append(f"- **Final operator entropy:** {div['operator_entropy'][-1]:.4f}")
        lines.append(f"- **Final fitness variance:** {div['fitness_variance'][-1]:.6f}")
        lines.append(f"- **Final phenotype count:** {div['phenotype_count'][-1]}")
    else:
        lines.append("- No snapshot data available.")

    lines.extend(["", "## Fitness Landscape", ""])
    lines.append(f"- **Best fitness:** {landscape['best_fitness']:.6f}")
    lines.append(f"- **Convergence iteration:** {landscape['convergence_iter']}")
    lines.append(f"- **FDC:** {landscape['fdc']:.4f} ({landscape['fdc_interp']})")
    lines.append(f"- **Ruggedness:** {landscape['ruggedness']:.4f} ({landscape['rugged_interp']})")
    lines.append(f"- **Trend slope:** {landscape['trend_slope']:.6f} (R²={landscape['trend_r2']:.4f})")

    lines.extend(["", "## Stagnation Detection", ""])
    lines.append(f"- **Is stagnant (current):** {'Yes' if stag['is_stagnated'] else 'No'}")
    lines.append(f"- **Stagnation index:** {stag['stagnation_index']:.4f}")
    if stag["stagnation_start"] is not None:
        lines.append(f"- **Stagnation started at iteration:** {stag['stagnation_start']}")

    lines.extend(["", "## Operator Importance", ""])
    if op_importance["table"]:
        lines.append(f"- **Chi² test:** χ²={op_importance['chi2']:.3f}, p={op_importance['chi2_p']:.4f}")
        lines.append(f"- **Operators with significant dependence on success:** "
                     f"{'Yes' if op_importance['chi2_p'] < 0.05 else 'No'}")
        lines.append("")
        lines.append("| Operator | Usage | Successes | Rate | Avg Δ fitness |")
        lines.append("|---|---|---|---|---|")
        for row in op_importance["table"][:15]:
            lines.append(
                f"| {row['operator']} | {row['usage_count']} "
                f"| {row['success_count']} "
                f"| {row['success_rate']:.1%} "
                f"| {row['avg_fitness_delta']:+.4f} |")
    else:
        lines.append("- No operator log data available.")

    lines.extend(["", "## Lineage Analysis", ""])
    if lineage["max_depth"] > 0:
        lines.append(f"- **Max lineage depth:** {lineage['max_depth']}")
        lines.append(f"- **Mean lineage depth:** {lineage['mean_depth']:.1f}")
    else:
        lines.append("- No passport lineage data available.")

    lines.extend(["", "---", "", "*End of report.*", ""])

    md_path = os.path.join(output_dir, "convergence_analysis.md")
    with open(md_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    return md_path
