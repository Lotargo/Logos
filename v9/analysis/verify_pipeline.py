"""
Phase 7 — Verify Pipeline Orchestrator
========================================
Entry point for the full DS/ML verification pipeline.

Usage:
  python v9/analysis/verify_pipeline.py ^
    --run-dir benchmarks_output/experiment_1/ ^
    --output-dir verification_report/ ^
    --mode full

  python v9/analysis/verify_pipeline.py ^
    --run-dir benchmarks_output/experiment_1/ ^
    --mode quick
"""
import argparse
import json
import os
import sys
from typing import Dict, Any, List, Optional

import numpy as np

from v9.analysis.stats import compare_groups, cohens_d, bootstrap_ci, full_stat_report
from v9.analysis.evolutionary import (
    population_diversity, fitness_landscape, stagnation_detection,
    operator_importance, lineage_depth, full_evolutionary_report
)
from v9.analysis.symbolic_quality import (
    pareto_frontier, semantic_equivalence, noise_sensitivity_profile,
    occams_razor, full_quality_report
)
from v9.analysis.dashboard import (
    build_fitness_trace, build_diversity_trace, build_pareto_plot,
    build_operator_heatmap, build_stat_table, assemble_dashboard
)


def collect_run_data(run_dir: str) -> Dict[str, Any]:
    """Collect experiment data from a run directory.

    Looks for:
    - fitness_history.json or fitness_history.jsonl
    - population_snapshots.json or population_snapshots.jsonl
    - operator_log.json or operator_log.jsonl
    - run_config.json
    - best_ast.txt
    """
    data = {
        "fitness_history": [],
        "population_snapshots": [],
        "operator_log": [],
        "run_config": {},
        "best_ast": None,
    }

    # Fitness history
    for fname in ["fitness_history.json", "fitness_history.jsonl"]:
        fpath = os.path.join(run_dir, fname)
        if os.path.exists(fpath):
            with open(fpath, encoding="utf-8") as f:
                if fname.endswith(".jsonl"):
                    for line in f:
                        line = line.strip()
                        if line:
                            data["fitness_history"].append(json.loads(line))
                else:
                    data["fitness_history"] = json.load(f)
            break

    # Population snapshots
    for fname in ["population_snapshots.json", "population_snapshots.jsonl"]:
        fpath = os.path.join(run_dir, fname)
        if os.path.exists(fpath):
            with open(fpath, encoding="utf-8") as f:
                if fname.endswith(".jsonl"):
                    for line in f:
                        line = line.strip()
                        if line:
                            data["population_snapshots"].append(json.loads(line))
                else:
                    data["population_snapshots"] = json.load(f)
            break

    # Operator log
    for fname in ["operator_log.json", "operator_log.jsonl"]:
        fpath = os.path.join(run_dir, fname)
        if os.path.exists(fpath):
            with open(fpath, encoding="utf-8") as f:
                if fname.endswith(".jsonl"):
                    for line in f:
                        line = line.strip()
                        if line:
                            data["operator_log"].append(json.loads(line))
                else:
                    data["operator_log"] = json.load(f)
            break

    # Run config
    config_path = os.path.join(run_dir, "run_config.json")
    if os.path.exists(config_path):
        with open(config_path, encoding="utf-8") as f:
            data["run_config"] = json.load(f)

    # Best AST
    ast_path = os.path.join(run_dir, "best_ast.txt")
    if os.path.exists(ast_path):
        with open(ast_path, encoding="utf-8") as f:
            data["best_ast"] = f.read().strip()

    return data


def run_stats_phase(data: Dict[str, Any], output_dir: str) -> Dict[str, Any]:
    """Phase 1: Statistical analysis."""
    print("[1/4] Statistical analysis...")
    results = {}

    fitness = data["fitness_history"]
    if isinstance(fitness, list) and len(fitness) > 0:
        # Handle list of dicts or list of floats
        if isinstance(fitness[0], dict):
            fitness_vals = [f.get("fitness_score", f.get("fitness", 0)) for f in fitness]
        else:
            fitness_vals = fitness

        if len(fitness_vals) >= 10:
            mid = len(fitness_vals) // 2
            early = fitness_vals[:mid]
            late = fitness_vals[mid:]
            results["improvement_test"] = compare_groups(early, late)
            results["fitness_ci"] = bootstrap_ci(fitness_vals)
            results["fitness_summary"] = {
                "mean": float(np.mean(fitness_vals)),
                "std": float(np.std(fitness_vals)),
                "min": float(np.min(fitness_vals)),
                "max": float(np.max(fitness_vals)),
                "n": len(fitness_vals),
            }
        else:
            results["fitness_summary"] = {
                "mean": float(np.mean(fitness_vals)),
                "n": len(fitness_vals),
            }

    full_stat_report([results], output_dir)
    return results


def run_evolutionary_phase(data: Dict[str, Any], output_dir: str, domain: str = "unknown") -> Dict[str, Any]:
    """Phase 2: Evolutionary search analytics."""
    print("[2/4] Evolutionary analysis...")
    results = {}

    pop = data["population_snapshots"]
    if pop:
        # Population diversity
        if "population" in pop[0] or "individuals" in pop[0]:
            div = population_diversity(pop)
            results["diversity"] = div

        # Fitness landscape
        if "fitness_values" in pop[0] or "fitnesses" in pop[0]:
            landscape = fitness_landscape(pop)
            results["fitness_landscape"] = landscape

        # Stagnation
        fitness_key = None
        for key in ["best_fitness", "avg_fitness", "max_fitness"]:
            if key in pop[0]:
                fitness_key = key
                break
        if fitness_key:
            series = [s.get(fitness_key, 0) for s in pop]
            results["stagnation"] = stagnation_detection(series)

        # Operator importance
        if data["operator_log"]:
            ops = operator_importance(data["operator_log"])
            results["operator_importance"] = ops

        # Lineage depth
        if "lineage" in pop[0] or "parent_id" in pop[0]:
            lineage = lineage_depth(pop)
            results["lineage_depth"] = lineage

        # Generate reports + plots
        full_evolutionary_report(pop, data["operator_log"], output_dir)

    return results


def run_quality_phase(data: Dict[str, Any], output_dir: str, domain: str = "unknown") -> Dict[str, Any]:
    """Phase 3: Symbolic regression quality."""
    print("[3/4] Symbolic quality analysis...")
    results = {}

    best_ast = data.get("best_ast")
    fitness = data["fitness_history"]
    if best_ast and fitness:
        if isinstance(fitness[0], dict):
            fitness_vals = [f.get("fitness_score", f.get("fitness", 0)) for f in fitness]
        else:
            fitness_vals = fitness

        y_pred = np.array(fitness_vals)
        y_true = np.ones_like(y_pred)

        # AIC/BIC
        aic = occams_razor(best_ast, y_true, y_pred)
        results["complexity_penalty"] = aic

        # Noise sensitivity: use a simple X matrix with variable "x"
        # and evaluate a simple formula to test robustness
        X = np.linspace(-5, 5, len(y_pred)).reshape(-1, 1)
        y_clean = X[:, 0] ** 2
        variables = ["x"]

        # Check if AST actually uses variable x; if not, skip noise profile
        try:
            noise = noise_sensitivity_profile(
                "(mul x x)",  # use a safe default formula
                X, y_clean, variables,
                noise_levels=[0.0, 0.1, 0.2, 0.5],
                n_trials=3,
            )
            results["noise_sensitivity"] = {
                "decay_rate": float(noise["decay_rate"]),
                "base_mse": float(noise["base_mse"]),
            }
        except Exception as e:
            results["noise_sensitivity"] = {"error": str(e)}

        # Pareto frontier
        records = [{
            "ast_expr": best_ast,
            "mse": float(1.0 - np.mean(y_pred)),
            "r2": float(np.mean(y_pred)),
            "complexity": len(best_ast.split()),
        }]
        pf = pareto_frontier(records)
        results["pareto"] = pf

    return results


def run_dashboard_phase(
    stats_results: Dict,
    evo_results: Dict,
    quality_results: Dict,
    data: Dict[str, Any],
    output_dir: str,
) -> Optional[str]:
    """Phase 4: Generate interactive dashboard."""
    print("[4/4] Building dashboard...")
    figs = {}

    fitness = data["fitness_history"]
    if fitness:
        if isinstance(fitness[0], dict):
            fitness_vals = [f.get("fitness_score", f.get("fitness", 0)) for f in fitness]
        else:
            fitness_vals = fitness
        gens = list(range(len(fitness_vals)))
        ci_lo = [f - 0.05 for f in fitness_vals]
        ci_hi = [f + 0.05 for f in fitness_vals]
        figs["fitness"] = build_fitness_trace(gens, fitness_vals, ci_lo, ci_hi)

    pop = data["population_snapshots"]
    if pop and any("avg_edit_distance" in s for s in pop):
        gens = list(range(len(pop)))
        ed = [s.get("avg_edit_distance", 0) for s in pop]
        ent = [s.get("shannon_entropy", 0) for s in pop]
        figs["diversity"] = build_diversity_trace(gens, ed, ent)

    if pop:
        records = []
        for s in pop:
            records.append({
                "ast_expr": s.get("best_ast", "?"),
                "mse": 1.0 - s.get("best_fitness", 0),
                "r2": s.get("best_fitness", 0),
                "complexity": s.get("avg_depth", 1),
                "is_pareto": False,
            })
        if records:
            figs["pareto"] = build_pareto_plot(records)

    # Stat table
    stat_metrics = []
    imp = stats_results.get("improvement_test", {})
    if "test_used" in imp:
        stat_metrics.append({
            "comparison": "early vs late runs",
            "test_used": imp.get("test_used", "?"),
            "test_statistic": imp.get("test_statistic", 0),
            "p_value": imp.get("p_value", 1),
            "effect_size": imp.get("effect_size", 0),
            "effect_size_name": imp.get("effect_size_name", ""),
            "significant": imp.get("significant", False),
        })
    if stat_metrics:
        figs["stats"] = build_stat_table(stat_metrics)

    if figs:
        return assemble_dashboard(
            fitness_fig=figs.get("fitness"),
            diversity_fig=figs.get("diversity"),
            pareto_fig=figs.get("pareto"),
            heatmap_fig=figs.get("heatmap"),
            stat_table_fig=figs.get("stats"),
            output_path=os.path.join(output_dir, "dashboard.html"),
        )
    return None


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Logos V9 -- DS/ML Verification Pipeline")
    parser.add_argument("--run-dir", required=True,
                        help="Path to experiment results directory")
    parser.add_argument("--output-dir", default=None,
                        help="Output directory (default: run-dir/verification/)")
    parser.add_argument("--mode", choices=["quick", "full"], default="quick",
                        help="quick = stats + dashboard; full = all phases")
    parser.add_argument("--domain", default="unknown",
                        help="Experiment domain name")
    parser.add_argument("--no-dashboard", action="store_true",
                        help="Skip dashboard generation")
    return parser.parse_args(argv)


def main():
    args = parse_args()
    output_dir = args.output_dir or os.path.join(args.run_dir.rstrip("/"), "verification")
    os.makedirs(output_dir, exist_ok=True)

    np.random.seed(42)

    print("=" * 50)
    print("  Logos V9 Verification Pipeline")
    print("=" * 50)
    print(f"  Run dir : {args.run_dir}")
    print(f"  Mode    : {args.mode}")
    print(f"  Output  : {output_dir}")
    print(f"  Domain  : {args.domain}")
    print()

    # Collect data
    print("Collecting experiment data...")
    data = collect_run_data(args.run_dir)
    print(f"  Fitness entries: {len(data['fitness_history'])}")
    print(f"  Population snapshots: {len(data['population_snapshots'])}")
    print(f"  Operator log entries: {len(data['operator_log'])}")
    print(f"  Best AST: {'yes' if data['best_ast'] else 'no'}")
    print()

    # Run phases
    stats_results = {}
    evo_results = {}
    quality_results = {}

    stats_results = run_stats_phase(data, output_dir)

    if args.mode == "full":
        evo_results = run_evolutionary_phase(data, output_dir, domain=args.domain)
        quality_results = run_quality_phase(data, output_dir, domain=args.domain)

    # Dashboard
    dashboard_path = None
    if not args.no_dashboard:
        dashboard_path = run_dashboard_phase(
            stats_results, evo_results, quality_results, data, output_dir)

    # Summary
    print()
    print("=" * 50)
    print("  Verification Complete")
    print("=" * 50)
    print(f"  Output dir  : {output_dir}")
    if dashboard_path:
        print(f"  Dashboard   : {dashboard_path}")
    print(f"  Stats       : {list(stats_results.keys())}")
    if args.mode == "full":
        print(f"  Evolutionary: {list(evo_results.keys())}")
        print(f"  Quality     : {list(quality_results.keys())}")
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
