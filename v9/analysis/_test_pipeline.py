"""Smoke test for verify_pipeline.py"""
import sys, os, json, shutil
sys.path.insert(0, r"F:\Кейс\AGI-lite")

import numpy as np
from v9.analysis.verify_pipeline import collect_run_data, run_stats_phase, run_evolutionary_phase, run_quality_phase, run_dashboard_phase, main

np.random.seed(42)

# Create test run directory
run_dir = r"F:\Кейс\AGI-lite\v9\analysis\_test_pipeline_run"
out_dir = r"F:\Кейс\AGI-lite\v9\analysis\_test_pipeline_out"
shutil.rmtree(run_dir, ignore_errors=True)
shutil.rmtree(out_dir, ignore_errors=True)
os.makedirs(run_dir, exist_ok=True)

# Generate test data
fitness = [0.5 + 0.4 * (1 - np.exp(-g / 10)) + np.random.normal(0, 0.02) for g in range(50)]
with open(os.path.join(run_dir, "fitness_history.json"), "w") as f:
    json.dump(fitness, f)

pop = []
for i in range(10):
    pop.append({
        "iteration": i * 5,
        "avg_edit_distance": 10 - i * 0.8 + np.random.normal(0, 0.5),
        "shannon_entropy": 2.0 + i * 0.1 + np.random.normal(0, 0.1),
        "best_fitness": 0.5 + i * 0.04 + np.random.normal(0, 0.01),
        "avg_fitness": 0.4 + i * 0.03 + np.random.normal(0, 0.01),
        "avg_depth": 3 + i * 0.2,
        "best_ast": f"(add x {i})",
    })
with open(os.path.join(run_dir, "population_snapshots.json"), "w") as f:
    json.dump(pop, f)

with open(os.path.join(run_dir, "best_ast.txt"), "w") as f:
    f.write("(mul x x)")

# Test 1: collect_run_data
print("=== Test 1: collect_run_data ===")
data = collect_run_data(run_dir)
assert len(data["fitness_history"]) == 50
assert len(data["population_snapshots"]) == 10
assert data["best_ast"] == "(mul x x)"
print(f"  fitness: {len(data['fitness_history'])}, pop: {len(data['population_snapshots'])}")

# Test 2: run_stats_phase
print("\n=== Test 2: run_stats_phase ===")
stats = run_stats_phase(data, out_dir)
print(f"  Keys: {list(stats.keys())}")
assert "fitness_summary" in stats

# Test 3: run_evolutionary_phase
print("\n=== Test 3: run_evolutionary_phase ===")
evo = run_evolutionary_phase(data, out_dir, domain="algebra")
print(f"  Keys: {list(evo.keys())}")

# Test 4: run_quality_phase
print("\n=== Test 4: run_quality_phase ===")
quality = run_quality_phase(data, out_dir, domain="algebra")
print(f"  Keys: {list(quality.keys())}")

# Test 5: run_dashboard_phase
print("\n=== Test 5: run_dashboard_phase ===")
dash = run_dashboard_phase(stats, evo, quality, data, out_dir)
if dash:
    print(f"  Dashboard: {dash}")
    assert os.path.exists(dash)
else:
    print("  No dashboard (no figs)")

# Cleanup
shutil.rmtree(run_dir, ignore_errors=True)
shutil.rmtree(out_dir, ignore_errors=True)

print("\n" + "=" * 40)
print("ALL 5 TESTS PASSED")
