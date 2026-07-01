"""
LangChain Tool wrappers over DS/ML analysis functions.

Each tool wraps an existing analysis function so the LLM agent
can call it independently during deep-dive verification.
"""
from __future__ import annotations

import json
from typing import Optional

from langchain_core.tools import tool

import numpy as np


# ---------------------------------------------------------------------------
# Statistical tools
# ---------------------------------------------------------------------------

@tool
def rerun_statistical_test(
    fitness_values: list[float],
    split_point: int,
) -> dict:
    """Recalculate statistical comparison (Mann-Whitney U + Cohen's d)
    with a custom split_point dividing early vs late fitness values.

    Args:
        fitness_values: Flat list of fitness scores over time.
        split_point: Index at which to split early/late groups.

    Returns:
        Dict with test_used, p_value, effect_size, significant, interpretation.
    """
    from v9.analysis.stats import compare_groups, cohens_d, bootstrap_ci

    if len(fitness_values) < 10:
        return {"error": "insufficient data (< 10 values)"}
    if split_point < 1 or split_point >= len(fitness_values):
        return {"error": f"split_point {split_point} out of range [1, {len(fitness_values)-1}]"}

    early = fitness_values[:split_point]
    late = fitness_values[split_point:]
    result = compare_groups(early, late)
    ci = bootstrap_ci(fitness_values)
    return {**result, "ci_95": ci}


@tool
def compute_confidence_interval(
    fitness_values: list[float],
    confidence: float = 0.95,
) -> dict:
    """Compute bootstrap confidence interval for the fitness mean.

    Args:
        fitness_values: Flat list of fitness scores.
        confidence: Confidence level (default 0.95).

    Returns:
        Dict with ci_low, ci_high, observed, std.
    """
    from v9.analysis.stats import bootstrap_ci

    ci = bootstrap_ci(fitness_values)
    return {
        **ci,
        "std": float(np.std(fitness_values)),
        "confidence": confidence,
    }


# ---------------------------------------------------------------------------
# Evolutionary tools
# ---------------------------------------------------------------------------

@tool
def check_stagnation(fitness_series: list[float], window: int = 5) -> dict:
    """Detect stagnation in a fitness series using windowed variance.

    Args:
        fitness_series: Fitness values over generations.
        window: Sliding window size for variance check.

    Returns:
        Dict with is_stagnant, stagnant_from, stagnant_generations, variance_trend.
    """
    from v9.analysis.evolutionary import stagnation_detection

    return stagnation_detection(fitness_series, window=window)


@tool
def analyze_operator_usage(operator_counts: dict) -> dict:
    """Analyze operator usage distribution for rationality.

    Checks for: dead operators (count=0), dominance (single operator >60%),
    diversity score (Shannon entropy of usage distribution).

    Args:
        operator_counts: Mapping of operator name to usage count.

    Returns:
        Dict with total, dead_operators, dominant, shannon_entropy, rationality_score.
    """
    if not operator_counts:
        return {"error": "no operator data"}

    total = sum(operator_counts.values())
    if total == 0:
        return {"error": "all operator counts are zero"}

    # Shannon entropy
    probs = [c / total for c in operator_counts.values() if c > 0]
    entropy = -sum(p * np.log2(p) for p in probs if p > 0)
    max_entropy = np.log2(len(probs)) if probs else 0
    norm_entropy = entropy / max_entropy if max_entropy > 0 else 0

    # Dead operators
    dead = [op for op, c in operator_counts.items() if c == 0]

    # Dominance check
    dominant = None
    for op, c in operator_counts.items():
        if c / total > 0.6:
            dominant = {"operator": op, "share": round(c / total, 3)}

    # Rationality score: balanced usage = high score
    rationality = round(float(norm_entropy), 3)

    return {
        "total": total,
        "unique_operators": len(operator_counts),
        "dead_operators": dead,
        "dominant": dominant,
        "shannon_entropy": round(float(entropy), 3),
        "normalized_entropy": round(float(norm_entropy), 3),
        "rationality_score": rationality,
    }


@tool
def measure_convergence_speed(
    fitness_history: list[float],
    threshold: float = 0.9,
) -> dict:
    """Measure how quickly the engine reaches a fitness threshold.

    Args:
        fitness_history: Fitness values over time.
        threshold: Target fitness to reach (default 0.9).

    Returns:
        Dict with threshold, first_reached (generation), total_generations,
        speed_ratio, reached.
    """
    reached = False
    first_gen = None
    for i, f in enumerate(fitness_history):
        if f >= threshold:
            first_gen = i
            reached = True
            break

    total = len(fitness_history)
    speed_ratio = (first_gen / total) if reached and total > 0 else None

    return {
        "threshold": threshold,
        "first_reached": first_gen,
        "total_generations": total,
        "speed_ratio": round(speed_ratio, 3) if speed_ratio is not None else None,
        "reached": reached,
    }


# ---------------------------------------------------------------------------
# Symbolic quality tools
# ---------------------------------------------------------------------------

@tool
def check_ast_complexity(ast_depths: list[int]) -> dict:
    """Analyze AST complexity distribution from depth list.

    Args:
        ast_depths: List of integer depths from knowledge passports.

    Returns:
        Dict with count, mean_depth, max_depth, min_depth, std_depth,
        depth_distribution, overfitting_risk.
    """
    if not ast_depths:
        return {"error": "no AST depth data"}

    depths = np.array(ast_depths)
    dist = {}
    for d in depths:
        dist[str(int(d))] = dist.get(str(int(d)), 0) + 1

    # Overfitting risk: high mean depth + low variance = likely overfit
    mean_d = float(np.mean(depths))
    std_d = float(np.std(depths))
    risk = "low"
    if mean_d > 5 and std_d < 1:
        risk = "high"
    elif mean_d > 3:
        risk = "medium"

    return {
        "count": len(depths),
        "mean_depth": round(mean_d, 2),
        "max_depth": int(np.max(depths)),
        "min_depth": int(np.min(depths)),
        "std_depth": round(std_d, 2),
        "depth_distribution": dist,
        "overfitting_risk": risk,
    }


@tool
def stress_test_fitness(
    fitness_values: list[float],
    noise_levels: list[float] = None,
    n_trials: int = 10,
) -> dict:
    """Test fitness robustness by adding Gaussian noise.

    Args:
        fitness_values: Original fitness values.
        noise_levels: List of noise std deviations to test.
        n_trials: Number of trials per noise level.

    Returns:
        Dict with results per noise level showing mean/std degradation.
    """
    if noise_levels is None:
        noise_levels = [0.01, 0.05, 0.1, 0.2]

    arr = np.array(fitness_values)
    base_mean = float(np.mean(arr))
    base_std = float(np.std(arr))

    results = []
    for noise in noise_levels:
        trial_means = []
        for _ in range(n_trials):
            noisy = arr + np.random.normal(0, noise, len(arr))
            noisy = np.clip(noisy, 0, 1)
            trial_means.append(float(np.mean(noisy)))
        results.append({
            "noise_std": noise,
            "mean_fitness": round(float(np.mean(trial_means)), 4),
            "std_fitness": round(float(np.std(trial_means)), 4),
            "degradation": round(base_mean - float(np.mean(trial_means)), 4),
        })

    return {
        "base_mean": round(base_mean, 4),
        "base_std": round(base_std, 4),
        "results": results,
    }


# ---------------------------------------------------------------------------
# All tools registry
# ---------------------------------------------------------------------------

JUDGE_TOOLS = [
    rerun_statistical_test,
    compute_confidence_interval,
    check_stagnation,
    analyze_operator_usage,
    measure_convergence_speed,
    check_ast_complexity,
    stress_test_fitness,
]
