"""Smoke test for dashboard.py"""
import sys, os, shutil
sys.path.insert(0, r"F:\Кейс\AGI-lite")

import numpy as np
from v9.analysis.dashboard import (
    build_fitness_trace, build_diversity_trace, build_pareto_plot,
    build_operator_heatmap, build_stat_table, assemble_dashboard
)

np.random.seed(42)
out_dir = r"F:\Кейс\AGI-lite\v9\analysis\_test_dashboard"

# Test 1: fitness trace
print("=== Test 1: build_fitness_trace ===")
gens = list(range(50))
fit = [0.5 + 0.4 * (1 - np.exp(-g / 10)) + np.random.normal(0, 0.02) for g in gens]
ci_lo = [f - 0.05 for f in fit]
ci_hi = [f + 0.05 for f in fit]
fig1 = build_fitness_trace(gens, fit, ci_lo, ci_hi)
assert fig1 is not None
print("  OK - fitness trace figure created")

# Test 2: diversity trace
print("\n=== Test 2: build_diversity_trace ===")
ed = [10 - g * 0.15 + np.random.normal(0, 0.5) for g in gens]
ent = [2.0 + g * 0.01 + np.random.normal(0, 0.1) for g in gens]
fig2 = build_diversity_trace(gens, ed, ent)
assert fig2 is not None
print("  OK - diversity trace figure created")

# Test 3: pareto plot
print("\n=== Test 3: build_pareto_plot ===")
records = [
    {"ast_expr": "(mul x x)", "mse": 0.001, "r2": 0.999, "complexity": 1, "is_pareto": True},
    {"ast_expr": "(add (mul x x) (mul x x))", "mse": 0.002, "r2": 0.998, "complexity": 3, "is_pareto": True},
    {"ast_expr": "(add (mul x x) 1)", "mse": 0.0005, "r2": 0.9995, "complexity": 2, "is_pareto": True},
    {"ast_expr": "(add (add (mul x x) (mul x x)) (mul x x))", "mse": 0.003, "r2": 0.997, "complexity": 5, "is_pareto": False},
    {"ast_expr": "(mul x x)", "mse": 0.01, "r2": 0.99, "complexity": 1, "is_pareto": False},
]
fig3 = build_pareto_plot(records)
assert fig3 is not None
print("  OK - pareto plot figure created")

# Test 4: operator heatmap
print("\n=== Test 4: build_operator_heatmap ===")
ops = ["add", "mul", "sub", "div", "sin", "cos"]
doms = ["algebra", "calculus", "physics"]
usage = np.random.rand(len(ops), len(doms)).tolist()
fig4 = build_operator_heatmap(ops, doms, usage)
assert fig4 is not None
print("  OK - operator heatmap figure created")

# Test 5: stat table
print("\n=== Test 5: build_stat_table ===")
metrics = [
    {"comparison": "baseline vs v1", "test_used": "Mann-Whitney U", "test_statistic": 145.0, "p_value": 0.0023, "effect_size": 0.72, "effect_size_name": "medium", "significant": True},
    {"comparison": "baseline vs v2", "test_used": "t-test", "test_statistic": 2.1, "p_value": 0.04, "effect_size": 0.35, "effect_size_name": "small", "significant": True},
    {"comparison": "v1 vs v2", "test_used": "Mann-Whitney U", "test_statistic": 200.0, "p_value": 0.15, "effect_size": 0.18, "effect_size_name": "negligible", "significant": False},
]
fig5 = build_stat_table(metrics)
assert fig5 is not None
print("  OK - stat table figure created")

# Test 6: assemble dashboard
print("\n=== Test 6: assemble_dashboard ===")
os.makedirs(out_dir, exist_ok=True)
dash_path = assemble_dashboard(
    fitness_fig=fig1,
    diversity_fig=fig2,
    pareto_fig=fig3,
    heatmap_fig=fig4,
    stat_table_fig=fig5,
    output_path=os.path.join(out_dir, "dashboard.html"),
)
assert os.path.exists(dash_path)
size_kb = os.path.getsize(dash_path) / 1024
print(f"  Dashboard: {dash_path}")
print(f"  Size: {size_kb:.0f} KB")
assert size_kb > 5  # should have meaningful content

# Check basic HTML structure
with open(dash_path, encoding="utf-8") as f:
    content = f.read()
assert "<!DOCTYPE html>" in content
assert "plotly" in content.lower()
assert "div-diversity" in content
assert "div-pareto" in content
print("  OK - HTML structure valid")

# Cleanup
shutil.rmtree(out_dir, ignore_errors=True)

print("\n" + "=" * 40)
print("ALL 6 TESTS PASSED")
