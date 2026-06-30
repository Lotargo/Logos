"""
Phase 1 — Statistical Rigor
============================
SciPy-based statistical tests for experiment comparison.

Provides:
  compare_groups             t-test / MWU + Cohen's d + 95% CI
  bootstrap_ci               nonparametric bootstrap confidence interval
  power_analysis             required N for desired power
  multi_group_compare        ANOVA / Kruskal-Wallis + post-hoc
  full_stat_report           markdown report generator
"""

import numpy as np
from scipy import stats as sp_stats


def compare_groups(group_a, group_b, test="auto"):
    """
    Compare two independent groups. Auto-detects parametric vs non-parametric.

    Parameters
    ----------
    group_a, group_b : array-like
        Metric values for each group.
    test : str
        "auto" (Shapiro-Wilk → t-test or MWU), "ttest", "mannwhitney".

    Returns
    -------
    dict with keys: statistic, p_value, cohens_d, ci_95, interpretation
    """
    raise NotImplementedError("Phase 1 — TODO")


def bootstrap_ci(data, n_resamples=10000, ci=0.95, func=np.mean):
    """Bootstrap confidence interval via scipy.stats.bootstrap."""
    raise NotImplementedError("Phase 1 — TODO")


def cohens_d(group_a, group_b):
    """Cohen's d with pooled std and interpretation string."""
    raise NotImplementedError("Phase 1 — TODO")


def hedges_g(group_a, group_b):
    """Hedges' g (bias-corrected Cohen's d for small samples)."""
    raise NotImplementedError("Phase 1 — TODO")


def power_analysis(effect_size=None, n_observations=None,
                   power=None, alpha=0.05, alternative="two-sided"):
    """Power analysis via statsmodels. Solves for missing parameter."""
    raise NotImplementedError("Phase 1 — TODO")


def multi_group_compare(groups, group_names=None):
    """ANOVA or Kruskal-Wallis + post-hoc (Tukey / Dunn)."""
    raise NotImplementedError("Phase 1 — TODO")


def full_stat_report(results, output_path=None):
    """Assemble all results into a markdown report string."""
    raise NotImplementedError("Phase 1 — TODO")
