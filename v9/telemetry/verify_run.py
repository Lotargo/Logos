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
    build_operator_heatmap, build_stat_table, assemble_dashboard,
    build_operator_pie, build_adf_bar, build_complexity_hist,
    build_convergence_trace, build_executive_summary
)

import numpy as np
import re


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


def load_knowledge_cache(data_dir=None):
    """Load passports from logos_knowledge.jsonl and extract metrics."""
    if data_dir is None:
        data_dir = os.path.join(os.path.dirname(__file__), "cache")

    knowledge_path = os.path.join(data_dir, "logos_knowledge.jsonl")
    entries = []

    if not os.path.exists(knowledge_path):
        return entries

    with open(knowledge_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                # Parse Lisp plist format
                entry = _parse_lisp_plist(line)
                if entry:
                    entries.append(entry)
            except Exception:
                continue

    return entries


def _parse_lisp_plist(line):
    """Parse a Lisp plist line into a Python dict."""
    entry = {}
    # Extract key-value pairs using regex
    # Format: (:key1 value1 :key2 value2 ...)
    # Remove outer parens
    s = line.strip()
    if s.startswith("(") and s.endswith(")"):
        s = s[1:-1]

    # Split by keywords
    parts = re.split(r'(\:\w[\w-]*)', s)
    i = 1  # skip empty first part
    while i < len(parts) - 1:
        key = parts[i].lstrip(":")
        val = parts[i + 1].strip()
        i += 2

        # Clean value
        if val.startswith('"') and val.endswith('"'):
            val = val[1:-1]
        elif val.startswith("((") and val.endswith("))"):
            # Alist like ((+ . 1) (div . 2)) — extract operator counts
            inner = val[2:-2]
            alist = {}
            for pair in re.findall(r'\((\S+)\s*\.\s*(\d+)\)', inner):
                op_name = pair[0].split("::")[-1]  # strip package prefix
                alist[op_name] = int(pair[1])
            val = alist
        elif val.startswith("(") and val.endswith(")"):
            # List value - extract items
            inner = val[1:-1].strip()
            if inner:
                val = [x.strip().strip('"') for x in re.findall(r'"[^"]*"|\S+', inner)]
            else:
                val = []
        elif val.isdigit():
            val = int(val)
        elif _is_float(val):
            val = float(val)
        elif val == "nil":
            val = None

        entry[key] = val

    return entry


def _is_float(s):
    """Check if string is a float."""
    try:
        float(s)
        return True
    except (ValueError, TypeError):
        return False


def _ast_depth_from_str(expr):
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


def _extract_operators_from_str(expr):
    """Extract operator names from AST string."""
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

    ops = []
    i = 0
    while i < len(tokens):
        if tokens[i] == "(":
            i += 1
            if i < len(tokens) and tokens[i] not in ("(", ")"):
                ops.append(tokens[i])
        i += 1
    return ops


def run_verification(run_id, domain, session_id, output_dir, best_ast=None,
                     experiment="default"):
    """Run the full verification pipeline for a completed experiment."""
    # Structured output: verification_report/{experiment}/{session_id}/
    run_dir = os.path.join(output_dir, experiment, session_id)
    os.makedirs(run_dir, exist_ok=True)

    np.random.seed(42)

    # Load data
    pop_data = load_population_data(run_id)
    fitness_history = load_fitness_history(run_id)
    knowledge = load_knowledge_cache()

    # Extract knowledge metrics
    operator_counts = {}
    adf_entries = []
    ast_depths = []
    for entry in knowledge:
        # Operator profile
        op_profile = entry.get("operator-profile", {})
        if isinstance(op_profile, dict):
            for op, count in op_profile.items():
                operator_counts[op] = operator_counts.get(op, 0) + (count if isinstance(count, (int, float)) else 1)

        # ADF entries (have :adf-symbol)
        adf_sym = entry.get("adf-symbol")
        if adf_sym and adf_sym != "nil" and adf_sym is not None:
            ast_str = entry.get("ast-str", "")
            depth = _ast_depth_from_str(ast_str) if ast_str else 0
            fitness = entry.get("fitness-scores", [0])
            if isinstance(fitness, list) and fitness:
                fitness = fitness[0] if isinstance(fitness[0], (int, float)) else 0
            elif not isinstance(fitness, (int, float)):
                fitness = 0
            adf_entries.append({
                "symbol": adf_sym,
                "fitness": fitness,
                "domains": entry.get("domains", []) if isinstance(entry.get("domains"), list) else [],
                "depth": depth,
            })

        # AST complexity
        ast_str = entry.get("ast-str", "")
        if ast_str:
            ast_depths.append(_ast_depth_from_str(ast_str))

    results = {
        "experiment": experiment,
        "run_id": run_id,
        "domain": domain,
        "knowledge_count": len(knowledge),
        "adf_count": len(adf_entries),
        "operator_counts": operator_counts,
        "fitness_history": fitness_history,
        "metrics": {},
    }

    # --- Phase 1: Statistical analysis ---
    print("[1/6] Statistical analysis...")
    if len(fitness_history) >= 10:
        mid = len(fitness_history) // 2
        early = fitness_history[:mid]
        late = fitness_history[mid:]
        stat_result = compare_groups(early, late)
        results["metrics"]["improvement_test"] = stat_result

        ci = bootstrap_ci(fitness_history)
        results["metrics"]["fitness_ci"] = ci
    else:
        results["metrics"]["improvement_test"] = {"skipped": True, "reason": "insufficient data"}
        results["metrics"]["fitness_ci"] = {"skipped": True}

    # --- Phase 2: Evolutionary analysis ---
    print("[2/6] Evolutionary analysis...")
    if pop_data:
        try:
            full_evolutionary_report(pop_data, output_dir, domain=domain)
        except Exception:
            pass

        if "avg_fitness" in pop_data[0] or "best_fitness" in pop_data[0]:
            fitness_key = "best_fitness" if "best_fitness" in pop_data[0] else "avg_fitness"
            fitness_series = [s.get(fitness_key, 0) for s in pop_data]
            stagnation = stagnation_detection(fitness_series)
            results["metrics"]["stagnation"] = stagnation

    # --- Phase 3: Symbolic quality ---
    print("[3/6] Symbolic quality analysis...")
    if best_ast and fitness_history:
        try:
            y_pred = np.array(fitness_history)
            y_true = np.ones_like(y_pred)
            aic_result = occams_razor(best_ast, y_true, y_pred)
            results["metrics"]["complexity_penalty"] = aic_result
        except Exception:
            pass

    # --- Phase 4: Knowledge analysis ---
    print("[4/6] Knowledge analysis...")
    results["metrics"]["operator_counts"] = operator_counts
    results["metrics"]["adf_entries"] = adf_entries[:20]  # top 20
    results["metrics"]["ast_depths"] = ast_depths

    # --- Phase 5: Build charts ---
    print("[5/6] Building charts...")
    figs = {}

    if fitness_history:
        gens = list(range(len(fitness_history)))
        ci_lo = [f - 0.05 for f in fitness_history]
        ci_hi = [f + 0.05 for f in fitness_history]
        figs["fitness"] = build_fitness_trace(gens, fitness_history, ci_lo, ci_hi)
        figs["convergence"] = build_convergence_trace(fitness_history)

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

    if operator_counts:
        figs["operator_pie"] = build_operator_pie(operator_counts)

    if adf_entries:
        figs["adf_bar"] = build_adf_bar(adf_entries[:15])

    if ast_depths:
        figs["complexity_hist"] = build_complexity_hist(ast_depths)

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

    # --- Phase 6: Save results (dashboard built later by _rebuild_dashboard) ---
    print("[6/6] Saving verification results...")

    # Save results
    results_path = os.path.join(run_dir, f"verification.json")
    with open(results_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, default=str)

    print(f"[OK] Verification complete: {results_path}")

    return results, run_dir, figs


def run_judge_phase(verification_json_path: str) -> dict:
    """Phase 7: LLM Judge — independent review of verification results."""
    print("[7/7] LLM Judge verification...")
    try:
        from v9.telemetry.llm.judge_agent import run_judge, save_judge_report
    except ImportError as e:
        print(f"[SKIP] LLM Judge unavailable: {e}")
        return {"skipped": True, "reason": str(e)}

    judge_result = run_judge(verification_json_path)
    output_dir = os.path.dirname(verification_json_path)
    report_path = save_judge_report(judge_result, output_dir)

    print(f"[OK] Judge verdict: {judge_result['verdict']}")
    print(f"[OK] Judge report: {report_path}")

    return {
        **judge_result,
        "report_path": report_path,
    }


def main():
    parser = argparse.ArgumentParser(description="Post-run verification for Logos V9")
    parser.add_argument("--run-id", required=True, help="Run UUID from telemetry")
    parser.add_argument("--domain", default="algebra", help="Experiment domain")
    parser.add_argument("--experiment", default="default",
                        help="Experiment name (used as folder name under verification_report/)")
    parser.add_argument("--session-id", default=None, help="Telemetry session ID")
    parser.add_argument("--output-dir", default=None, help="Output directory")
    parser.add_argument("--best-ast", default=None, help="Best AST string from run")
    parser.add_argument("--judge", action="store_true",
                        help="Run LLM Judge agent after DS/ML analysis (phase 7)")
    args = parser.parse_args()

    output_dir = args.output_dir or os.path.join(
        os.path.dirname(__file__), "..", "..", "verification_report")

    results, run_dir, figs = run_verification(
        run_id=args.run_id,
        domain=args.domain,
        session_id=args.session_id or args.run_id,
        output_dir=output_dir,
        best_ast=args.best_ast,
        experiment=args.experiment,
    )

    if args.judge:
        verification_json = os.path.join(run_dir, "verification.json")
        judge_result = run_judge_phase(verification_json)
        results["judge"] = judge_result

        # Re-save results with judge verdict
        with open(verification_json, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2, default=str)

    # --- Rebuild dashboard with text content ---
    _rebuild_dashboard(results, run_dir, args.experiment, figs)


def _rebuild_dashboard(results: dict, run_dir: str, experiment: str, figs: dict):
    """Rebuild dashboard with metrics section + judge report.

    Uses importlib.reload() to force a fresh import of the dashboard module,
    ensuring server-side rendered markdown (not stale JS-based rendering).
    """
    import importlib
    import sys

    mod_name = "v9.analysis.dashboard"
    # Remove stale cached module and force a fresh import
    sys.modules.pop(mod_name, None)
    mod = importlib.import_module(mod_name)
    mod = importlib.reload(mod)

    build_metrics_section = mod.build_metrics_section
    build_judge_section = mod.build_judge_section
    build_executive_summary = mod.build_executive_summary
    assemble_dashboard = mod.assemble_dashboard

    fitness_history = results.get("fitness_history", [])
    adf_entries = results.get("metrics", {}).get("adf_entries", [])
    knowledge_count = results.get("knowledge_count", 0)

    # Extract judge verdict (if available) for the Executive Summary
    judge_verdict = None
    if "judge" in results and not results["judge"].get("skipped"):
        judge_verdict = results["judge"].get("verdict")

    summary_html = build_executive_summary(
        run_id=results.get("run_id", "N/A"),
        domain=results.get("domain", "N/A"),
        fitness_history=fitness_history,
        adf_count=len(adf_entries),
        knowledge_count=knowledge_count,
        experiment_name=experiment,
        judge_verdict=judge_verdict,
    )

    metrics_html = build_metrics_section(results, title=f"Verification Metrics — {experiment}")

    judge_html = ""
    if "judge" in results and not results["judge"].get("skipped"):
        judge_html = build_judge_section(results["judge"])

    try:
        dashboard_path = assemble_dashboard(
            fitness_fig=figs.get("fitness"),
            diversity_fig=figs.get("diversity"),
            pareto_fig=figs.get("pareto"),
            heatmap_fig=figs.get("heatmap"),
            stat_table_fig=figs.get("stats"),
            operator_pie_fig=figs.get("operator_pie"),
            adf_bar_fig=figs.get("adf_bar"),
            complexity_hist_fig=figs.get("complexity_hist"),
            convergence_fig=figs.get("convergence"),
            executive_summary_html=summary_html,
            metrics_section_html=metrics_html,
            judge_section_html=judge_html,
            output_path=os.path.join(run_dir, f"dashboard.html"),
            title=f"Logos V9 — {experiment}",
        )
        print(f"[OK] Dashboard rebuilt: {dashboard_path}")
    except Exception as e:
        print(f"[WARN] Dashboard rebuild failed: {e}")


if __name__ == "__main__":
    main()
