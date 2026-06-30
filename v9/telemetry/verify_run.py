"""
verify_run.py — Post-run verification script for Logos V9.

Called from Lisp engine via subprocess after each experiment run.
Collects population snapshots, computes verification metrics,
and generates a dashboard + report.

Usage:
  python verify_run.py --run-id <uuid> --domain <domain> --session-id <sid> \
      [--output-dir verification_report/] [--best-ast <ast>]
"""
import argparse
import json
import os
import sys
import io

# Fix UTF-8 encoding on Windows for Lisp subprocess pipe
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# Add project root to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from v9.analysis.stats import compare_groups, cohens_d, bootstrap_ci, full_stat_report
from v9.analysis.evolutionary import (
    population_diversity, fitness_landscape, stagnation_detection,
    operator_importance, full_evolutionary_report
)
from v9.analysis.symbolic_quality import (
    pareto_frontier, semantic_equivalence, noise_sensitivity_profile,
    occams_razor, full_quality_report
)
from v9.analysis.dashboard import (
    build_fitness_trace, build_diversity_trace, build_pareto_plot,
    build_operator_heatmap, build_stat_table, assemble_dashboard
)

import numpy as np


def load_population_data(run_id, data_dir=None):
    """Load population snapshots from JSONL cache or generate synthetic data."""
    if data_dir is None:
        data_dir = os.path.join(os.path.dirname(__file__), "cache")

    jsonl_path = os.path.join(data_dir, f"pop_snapshots_{run_id}.jsonl")
    snapshots = []

    if os.path.exists(jsonl_path):
        with open(jsonl_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    snapshots.append(json.loads(line))
        return snapshots

    # Fallback: load from telemetry events cache
    events_path = os.path.join(data_dir, "logos_memory.jsonl")
    if os.path.exists(events_path):
        with open(events_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                    if (event.get("session_id") == run_id or
                            event.get("run_id") == run_id):
                        payload = event.get("payload", {})
                        if isinstance(payload, str):
                            payload = json.loads(payload)
                        if payload.get("iteration") is not None:
                            snapshots.append(payload)
                except (json.JSONDecodeError, KeyError):
                    continue

    return snapshots


def load_fitness_history(run_id, data_dir=None):
    """Load fitness values over time from telemetry events."""
    if data_dir is None:
        data_dir = os.path.join(os.path.dirname(__file__), "cache")

    events_path = os.path.join(data_dir, "logos_memory.jsonl")
    fitness_values = []

    if os.path.exists(events_path):
        with open(events_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                    if (event.get("session_id") == run_id or
                            event.get("run_id") == run_id):
                        payload = event.get("payload", {})
                        if isinstance(payload, str):
                            payload = json.loads(payload)
                        if "fitness_score" in payload:
                            fitness_values.append(payload["fitness_score"])
                except (json.JSONDecodeError, KeyError):
                    continue

    return fitness_values


def run_verification(run_id, domain, session_id, output_dir, best_ast=None):
    """Run the full verification pipeline for a completed experiment."""
    os.makedirs(output_dir, exist_ok=True)

    np.random.seed(42)

    # Load data
    pop_data = load_population_data(run_id)
    fitness_history = load_fitness_history(run_id)

    results = {"run_id": run_id, "domain": domain, "metrics": {}}

    # --- Phase 1: Statistical analysis ---
    print("[1/4] Statistical analysis...")
    if len(fitness_history) >= 10:
        # Split into first half vs second half to check for improvement
        mid = len(fitness_history) // 2
        early = fitness_history[:mid]
        late = fitness_history[mid:]
        stat_result = compare_groups(early, late)
        results["metrics"]["improvement_test"] = stat_result

        # Bootstrap CI for overall fitness
        ci = bootstrap_ci(fitness_history)
        results["metrics"]["fitness_ci"] = ci
    else:
        results["metrics"]["improvement_test"] = {"skipped": True, "reason": "insufficient data"}
        results["metrics"]["fitness_ci"] = {"skipped": True}

    # --- Phase 2: Evolutionary analysis ---
    print("[2/4] Evolutionary analysis...")
    evo_report_path = None
    if pop_data:
        evo_report_path = full_evolutionary_report(
            pop_data, output_dir, domain=domain)
        results["metrics"]["evo_report"] = evo_report_path

        # Detect stagnation
        if "avg_fitness" in pop_data[0] or "best_fitness" in pop_data[0]:
            fitness_key = "best_fitness" if "best_fitness" in pop_data[0] else "avg_fitness"
            fitness_series = [s.get(fitness_key, 0) for s in pop_data]
            stagnation = stagnation_detection(fitness_series)
            results["metrics"]["stagnation"] = stagnation

    # --- Phase 3: Symbolic quality ---
    print("[3/4] Symbolic quality analysis...")
    quality_report_path = None
    if best_ast and fitness_history:
        # Basic quality metrics
        y_pred = np.array(fitness_history)
        y_true = np.ones_like(y_pred)  # target is fitness=1.0
        aic_result = occams_razor(best_ast, y_true, y_pred)
        results["metrics"]["complexity_penalty"] = aic_result

        # Noise sensitivity (using fitness history as proxy)
        noise_result = noise_sensitivity_profile(
            best_ast,
            np.array(fitness_history).reshape(-1, 1),
            np.ones(len(fitness_history)),
            ["fitness"],
            noise_levels=[0.0, 0.1, 0.2, 0.5],
            n_trials=3
        )
        results["metrics"]["noise_sensitivity"] = {
            "decay_rate": noise_result["decay_rate"],
            "base_mse": float(noise_result["base_mse"]),
        }

    # --- Phase 4: Dashboard ---
    print("[4/4] Building dashboard...")
    dashboard_path = None
    try:
        figs = {}

        if fitness_history:
            gens = list(range(len(fitness_history)))
            ci_lo = [f - 0.05 for f in fitness_history]
            ci_hi = [f + 0.05 for f in fitness_history]
            figs["fitness"] = build_fitness_trace(gens, fitness_history, ci_lo, ci_hi)

        if pop_data and "edit_distances" in pop_data[0]:
            gens = list(range(len(pop_data)))
            ed = [s.get("avg_edit_distance", 0) for s in pop_data]
            ent = [s.get("shannon_entropy", 0) for s in pop_data]
            figs["diversity"] = build_diversity_trace(gens, ed, ent)

        if pop_data:
            records = []
            for s in pop_data:
                records.append({
                    "ast_expr": s.get("best_ast", "?"),
                    "mse": 1.0 - s.get("best_fitness", 0),
                    "r2": s.get("best_fitness", 0),
                    "complexity": s.get("avg_depth", 1),
                    "is_pareto": False,
                })
            if records:
                figs["pareto"] = build_pareto_plot(records)

        # Build stat table from available metrics
        stat_metrics = []
        imp = results["metrics"].get("improvement_test", {})
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
            dashboard_path = assemble_dashboard(
                fitness_fig=figs.get("fitness"),
                diversity_fig=figs.get("diversity"),
                pareto_fig=figs.get("pareto"),
                heatmap_fig=figs.get("heatmap"),
                stat_table_fig=figs.get("stats"),
                output_path=os.path.join(output_dir, f"dashboard_{run_id[:8]}.html"),
            )
            results["dashboard"] = dashboard_path
    except Exception as e:
        print(f"[WARN] Dashboard generation failed: {e}")
        results["dashboard_error"] = str(e)

    # Save results
    results_path = os.path.join(output_dir, f"verification_{run_id[:8]}.json")
    with open(results_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, default=str)

    print(f"[OK] Verification complete: {results_path}")
    if dashboard_path:
        print(f"[OK] Dashboard: {dashboard_path}")

    return results


def main():
    parser = argparse.ArgumentParser(description="Post-run verification for Logos V9")
    parser.add_argument("--run-id", required=True, help="Run UUID from telemetry")
    parser.add_argument("--domain", default="algebra", help="Experiment domain")
    parser.add_argument("--session-id", default=None, help="Telemetry session ID")
    parser.add_argument("--output-dir", default=None, help="Output directory")
    parser.add_argument("--best-ast", default=None, help="Best AST string from run")
    args = parser.parse_args()

    output_dir = args.output_dir or os.path.join(
        os.path.dirname(__file__), "..", "..", "verification_report")

    run_verification(
        run_id=args.run_id,
        domain=args.domain,
        session_id=args.session_id or args.run_id,
        output_dir=output_dir,
        best_ast=args.best_ast,
    )


if __name__ == "__main__":
    main()
