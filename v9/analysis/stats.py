"""
Phase 1 — Statistical Rigor
============================
SciPy-based statistical tests for experiment comparison.

Provides:
  compare_groups             t-test / MWU + Cohen's d + 95% CI
  bootstrap_ci               nonparametric bootstrap confidence interval
  cohens_d                   effect size
  hedges_g                   bias-corrected effect size
  power_analysis             required N for desired power
  multi_group_compare        ANOVA / Kruskal-Wallis + post-hoc
  full_stat_report           markdown report generator
"""

import numpy as np
from scipy import stats as sp_stats


# ---------------------------------------------------------------------------
# Effect sizes
# ---------------------------------------------------------------------------

def cohens_d(group_a, group_b):
    """
    Cohen's d with pooled standard deviation.

    Returns dict with d value and interpretation:
        |d| < 0.2  → negligible
        |d| < 0.5  → small
        |d| < 0.8  → medium
        |d| >= 0.8 → large
    """
    a = np.asarray(group_a, dtype=float)
    b = np.asarray(group_b, dtype=float)
    n1, n2 = len(a), len(b)
    var_a, var_b = np.var(a, ddof=1), np.var(b, ddof=1)
    pooled_std = np.sqrt(((n1 - 1) * var_a + (n2 - 1) * var_b) / (n1 + n2 - 2))
    if pooled_std == 0:
        d = 0.0
    else:
        d = (np.mean(a) - np.mean(b)) / pooled_std
    abs_d = abs(d)
    if abs_d < 0.2:
        interp = "negligible"
    elif abs_d < 0.5:
        interp = "small"
    elif abs_d < 0.8:
        interp = "medium"
    else:
        interp = "large"
    return {"d": d, "abs_d": abs_d, "interpretation": interp}


def hedges_g(group_a, group_b):
    """
    Hedges' g — bias-corrected Cohen's d for small samples.
    """
    d_result = cohens_d(group_a, group_b)
    n1 = len(group_a)
    n2 = len(group_b)
    df = n1 + n2 - 2
    # Bias correction factor (Hedges & Olkin, 1985)
    correction = 1.0 - (3.0 / (4.0 * df - 1.0))
    g = d_result["d"] * correction
    abs_g = abs(g)
    if abs_g < 0.2:
        interp = "negligible"
    elif abs_g < 0.5:
        interp = "small"
    elif abs_g < 0.8:
        interp = "medium"
    else:
        interp = "large"
    return {"g": g, "abs_g": abs_g, "correction_factor": correction, "interpretation": interp}


# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

def bootstrap_ci(data, n_resamples=10000, ci=0.95, func=np.mean):
    """
    Nonparametric bootstrap confidence interval.

    Parameters
    ----------
    data : array-like
        Observed values.
    n_resamples : int
        Number of bootstrap resamples.
    ci : float
        Confidence level (e.g. 0.95 for 95% CI).
    func : callable
        Statistic to bootstrap (default: mean).

    Returns
    -------
    dict with ci_low, ci_high, observed_stat
    """
    data = np.asarray(data, dtype=float)
    observed = func(data)
    n = len(data)
    boot_stats = np.empty(n_resamples)
    for i in range(n_resamples):
        sample = np.random.choice(data, size=n, replace=True)
        boot_stats[i] = func(sample)
    alpha = (1.0 - ci) / 2.0
    ci_low = np.percentile(boot_stats, alpha * 100)
    ci_high = np.percentile(boot_stats, (1.0 - alpha) * 100)
    return {"ci_low": ci_low, "ci_high": ci_high, "observed": observed}


# ---------------------------------------------------------------------------
# Normality check helper
# ---------------------------------------------------------------------------

def _is_normal(data, alpha=0.05):
    """Shapiro-Wilk test. Returns True if data likely normal."""
    if len(data) < 3:
        return True
    if len(data) > 5000:
        # Shapiro-Wilk unreliable for n>5000, use D'Agostino-Pearson
        try:
            stat, p = sp_stats.normaltest(data)
            return p > alpha
        except Exception:
            return False
    stat, p = sp_stats.shapiro(data)
    return p > alpha


# ---------------------------------------------------------------------------
# Two-group comparison
# ---------------------------------------------------------------------------

def compare_groups(group_a, group_b, test="auto"):
    """
    Compare two independent groups.

    Parameters
    ----------
    group_a, group_b : array-like
        Metric values for each group.
    test : str
        "auto" — Shapiro-Wilk decides t-test vs Mann-Whitney U
        "ttest" — always Welch's t-test
        "mannwhitney" — always Mann-Whitney U

    Returns
    -------
    dict: statistic, p_value, test_used, cohens_d, hedges_g, ci_95, interpretation
    """
    a = np.asarray(group_a, dtype=float)
    b = np.asarray(group_b, dtype=float)

    # Choose test
    if test == "auto":
        normal = _is_normal(a) and _is_normal(b)
        test_name = "ttest" if normal else "mannwhitney"
    else:
        test_name = test

    # Run test
    if test_name == "ttest":
        stat, p = sp_stats.ttest_ind(a, b, equal_var=False)  # Welch's
    else:
        stat, p = sp_stats.mannwhitneyu(a, b, alternative="two-sided")

    # Effect size
    d_result = cohens_d(a, b)
    g_result = hedges_g(a, b)

    # 95% CI for difference of means
    ci = bootstrap_ci(
        np.concatenate([a, b]),
        n_resamples=10000, ci=0.95,
        func=lambda x: np.mean(x[:len(a)]) - np.mean(x[len(a):])
    )

    # Interpretation
    if p < 0.05:
        interpretation = f"significant difference (p={p:.4e}), effect={d_result['interpretation']}"
    else:
        interpretation = f"no significant difference (p={p:.4e})"

    return {
        "statistic": stat,
        "p_value": p,
        "test_used": test_name,
        "cohens_d": d_result,
        "hedges_g": g_result,
        "ci_95_diff": {"low": ci["ci_low"], "high": ci["ci_high"]},
        "interpretation": interpretation,
    }


# ---------------------------------------------------------------------------
# Power analysis
# ---------------------------------------------------------------------------

def power_analysis(effect_size=None, n_observations=None,
                   power=None, alpha=0.05, alternative="two-sided"):
    """
    Statistical power analysis. Pass exactly 3 of 4 parameters,
    the 4th is solved for.

    Parameters
    ----------
    effect_size : float
        Cohen's d (for independent t-test).
    n_observations : int
        Total sample size (n_a + n_b).
    power : float
        Desired power (1 - beta).
    alpha : float
        Significance level.
    alternative : str
        "two-sided" or "larger" / "smaller".

    Returns
    -------
    dict with the solved parameter
    """
    # Require statsmodels
    try:
        from statsmodels.stats.power import TTestIndPower
    except ImportError:
        return {"error": "statsmodels not installed. pip install statsmodels"}

    analysis = TTestIndPower()
    params = {"effect_size": effect_size, "nobs1": n_observations,
              "power": power, "alpha": alpha, "alternative": alternative}

    # Count missing
    missing = [k for k, v in params.items() if v is None and k != "alpha"]
    if len(missing) != 1:
        return {"error": f"Exactly 3 parameters must be provided. Missing: {missing}"}

    target = missing[0]
    try:
        if target == "effect_size":
            val = analysis.effect_size_from_power(
                power=power, nobs1=n_observations, alpha=alpha, ratio=1.0)
        elif target == "nobservations":
            val = analysis.solve_power(
                effect_size=effect_size, power=power, alpha=alpha,
                ratio=1.0, alternative=alternative)
            val = int(np.ceil(val))
        elif target == "power":
            val = analysis.solve_power(
                effect_size=effect_size, nobs1=n_observations, alpha=alpha,
                ratio=1.0, alternative=alternative)
        else:
            return {"error": f"Unknown parameter: {target}"}
    except Exception as e:
        return {"error": str(e)}

    return {target: val}


# ---------------------------------------------------------------------------
# Multi-group comparison
# ---------------------------------------------------------------------------

def multi_group_compare(groups, group_names=None):
    """
    Omnibus test for 3+ groups, then post-hoc pairwise comparisons.

    Parameters
    ----------
    groups : list of array-like
        Each element is a group of metric values.
    group_names : list of str, optional
        Names for each group (for report readability).

    Returns
    -------
    dict: omnibus_test, omnibus_p, post_hoc_table (DataFrame-like)
    """
    arrays = [np.asarray(g, dtype=float) for g in groups]
    k = len(arrays)

    if group_names is None:
        group_names = [f"Group_{i}" for i in range(k)]

    # Omnibus test
    normal = all(_is_normal(a) for a in arrays)
    if normal:
        omnibus_stat, omnibus_p = sp_stats.f_oneway(*arrays)
        omnibus_name = "one-way ANOVA"
    else:
        omnibus_stat, omnibus_p = sp_stats.kruskal(*arrays)
        omnibus_name = "Kruskal-Wallis"

    # Post-hoc: pairwise Mann-Whitney with Bonferroni correction
    post_hoc = []
    n_comparisons = k * (k - 1) // 2
    for i in range(k):
        for j in range(i + 1, k):
            stat, p_raw = sp_stats.mannwhitneyu(
                arrays[i], arrays[j], alternative="two-sided")
            p_adj = min(p_raw * n_comparisons, 1.0)  # Bonferroni
            d = cohens_d(arrays[i], arrays[j])
            post_hoc.append({
                "group_a": group_names[i],
                "group_b": group_names[j],
                "statistic": stat,
                "p_raw": p_raw,
                "p_adjusted": p_adj,
                "cohens_d": d["d"],
                "significant": p_adj < 0.05,
            })

    return {
        "omnibus_test": omnibus_name,
        "omnibus_statistic": omnibus_stat,
        "omnibus_p": omnibus_p,
        "omnibus_significant": omnibus_p < 0.05,
        "post_hoc": post_hoc,
    }


# ---------------------------------------------------------------------------
# Markdown report
# ---------------------------------------------------------------------------

def full_stat_report(results, title="Statistical Analysis", output_path=None):
    """
    Generate a markdown report from analysis results.

    Parameters
    ----------
    results : list of dict
        Each dict is output from compare_groups or multi_group_compare.
    title : str
        Report title.
    output_path : str, optional
        If provided, write markdown to this file.

    Returns
    -------
    str — markdown content
    """
    lines = [
        f"# {title}",
        "",
        f"*Generated by Logos V9 Verification Suite*",
        "",
        "---",
        "",
    ]

    for i, r in enumerate(results, 1):
        if "omnibus_test" in r:
            # Multi-group result
            lines.append(f"## {i}. {r['omnibus_test']}")
            lines.append("")
            lines.append(f"- **Test:** {r['omnibus_test']}")
            lines.append(f"- **Statistic:** {r['omnibus_statistic']:.4f}")
            lines.append(f"- **p-value:** {r['omnibus_p']:.6f}")
            lines.append(f"- **Significant:** {'Yes' if r['omnibus_significant'] else 'No'}")
            lines.append("")
            if r.get("post_hoc"):
                lines.append("### Post-hoc pairwise comparisons (Bonferroni)")
                lines.append("")
                lines.append("| A | B | Stat | p (raw) | p (adj) | d | Significant |")
                lines.append("|---|---|---|---|---|---|---|")
                for ph in r["post_hoc"]:
                    sig = "Yes" if ph["significant"] else "No"
                    lines.append(
                        f"| {ph['group_a']} | {ph['group_b']} "
                        f"| {ph['statistic']:.2f} "
                        f"| {ph['p_raw']:.6f} "
                        f"| {ph['p_adjusted']:.6f} "
                        f"| {ph['cohens_d']:.3f} "
                        f"| {sig} |")
                lines.append("")
        elif "test_used" in r:
            # Two-group result
            lines.append(f"## {i}. {r.get('test_used', 'comparison').upper()}")
            lines.append("")
            lines.append(f"- **Test used:** {r['test_used']}")
            lines.append(f"- **Statistic:** {r.get('statistic', 0):.4f}")
            lines.append(f"- **p-value:** {r.get('p_value', 1):.6f}")
            d = r.get("cohens_d", {})
            if isinstance(d, dict):
                lines.append(f"- **Cohen's d:** {d.get('d', 0):.3f} ({d.get('interpretation', '')})")
            g = r.get("hedges_g", {})
            if isinstance(g, dict):
                lines.append(f"- **Hedges' g:** {g.get('g', 0):.3f} ({g.get('interpretation', '')})")
            ci = r.get("ci_95_diff", {})
            if isinstance(ci, dict):
                lines.append(f"- **95% CI (diff):** [{ci.get('low', 0):.4f}, {ci.get('high', 0):.4f}]")
            lines.append(f"- **Interpretation:** {r.get('interpretation', '')}")
            lines.append("")
        elif "fitness_summary" in r or "mean" in r:
            # Summary-only result (no comparison test)
            summary = r.get("fitness_summary", r)
            lines.append(f"## {i}. Summary Statistics")
            lines.append("")
            for key in ["mean", "std", "min", "max", "n", "skewness", "kurtosis"]:
                if key in summary:
                    lines.append(f"- **{key.title()}:** {summary[key]:.4f}" if isinstance(summary[key], float) else f"- **{key.title()}:** {summary[key]}")
            lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("*End of report.*")
    lines.append("")

    md = "\n".join(lines)

    if output_path:
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(md)

    return md
