"""Smoke test for symbolic_quality.py"""
import sys, os, shutil
sys.path.insert(0, r"F:\Кейс\AGI-lite")

import numpy as np
from v9.analysis.symbolic_quality import (
    pareto_frontier, semantic_equivalence, ood_robustness,
    noise_sensitivity_profile, occams_razor, cross_domain_transfer,
    full_quality_report, _evaluate_formula, _parse_ast
)

np.random.seed(42)
variables = ["x"]

# --- Test 0: AST evaluation ---
print("=== Test 0: AST evaluation ===")
X = np.linspace(-5, 5, 200).reshape(-1, 1)
y_true = X[:, 0] ** 2  # target: x^2
y_pred = _evaluate_formula("(mul x x)", X, variables)
mse = np.mean((y_true - y_pred) ** 2)
print(f" MSE for (mul x x) vs x^2: {mse:.10f}")
assert mse < 1e-20

# --- Test 1: Pareto frontier ---
print("\n=== Test 1: pareto_frontier ===")
records = [
    {"ast_expr": "(mul x x)", "mse": 0.001, "r2": 0.999},
    {"ast_expr": "(add (mul x x) (mul x x))", "mse": 0.002, "r2": 0.998},
    {"ast_expr": "(add (mul x x) 1)", "mse": 0.0005, "r2": 0.9995},
    {"ast_expr": "(add (add (mul x x) (mul x x)) (mul x x))", "mse": 0.003, "r2": 0.997},
    {"ast_expr": "(mul x x)", "mse": 0.01, "r2": 0.99},  # dominated by first
]
pf = pareto_frontier(records)
print(f"Total candidates: {len(records)}")
print(f"Pareto-optimal: {len(pf['pareto_set'])}")
print(f"Dominance ratio: {pf['dominance_ratio']:.1%}")
print(f"Best tradeoff: {pf['pareto_set'][pf['best_tradeoff_idx']]['ast_expr']}")
assert len(pf["pareto_set"]) >= 2
assert pf["dominance_ratio"] > 0

# --- Test 2: Semantic equivalence ---
print("\n=== Test 2: semantic_equivalence ===")
X_test = np.linspace(-3, 3, 100).reshape(-1, 1)
eq1 = semantic_equivalence("(mul x x)", "(add 0 (mul x x))", X_test, variables)
print(f"  (mul x x) vs (add 0 (mul x x)): corr={eq1['output_correlation']:.6f}, equiv={eq1['is_equivalent']}")
assert eq1["is_equivalent"] is True

eq2 = semantic_equivalence("(mul x x)", "(add x 1)", X_test, variables)
print(f"  (mul x x) vs (add x 1): corr={eq2['output_correlation']:.6f}, equiv={eq2['is_equivalent']}")
assert eq2["is_equivalent"] == False

# --- Test 3: OOD robustness ---
print("\n=== Test 3: ood_robustness ===")
X_train = np.linspace(-3, 3, 100).reshape(-1, 1)
y_train = X_train[:, 0] ** 2
X_ood = np.linspace(3, 6, 50).reshape(-1, 1)
y_ood = X_ood[:, 0] ** 2

ood = ood_robustness("(mul x x)", X_train, y_train, X_ood, y_ood, variables)
print(f"  Train R2: {ood['train_r2']:.6f}")
print(f"  OOD R2:   {ood['ood_r2']:.6f}")
print(f"  Gap:      {ood['generalization_gap']:.4f}")
assert ood["train_r2"] > 0.99
assert ood["ood_r2"] > 0.99
assert abs(ood["generalization_gap"]) < 0.01

# --- Test 4: Noise sensitivity ---
print("\n=== Test 4: noise_sensitivity_profile ===")
noise = noise_sensitivity_profile(
    "(mul x x)", X_train, y_train, variables,
    noise_levels=[0.0, 0.05, 0.1, 0.5, 1.0], n_trials=3)
print(f"  Decay rate: {noise['decay_rate']:.4f}")
print(f"  50% threshold: sigma={noise['noise_threshold_50']:.4f}")
print(f"  Base MSE: {noise['base_mse']:.6f}")
assert noise["decay_rate"] > 0  # should degrade
assert noise["noise_curve"]["mean_r2"][0] > 0.99  # clean data = high R²

# --- Test 5: Occam's razor ---
print("\n=== Test 5: occams_razor ===")
y_pred = _evaluate_formula("(mul x x)", X_train, variables)
aic_result = occams_razor("(mul x x)", y_train, y_pred)
print(f"  AIC: {aic_result['aic']:.2f}")
print(f"  BIC: {aic_result['bic']:.2f}")
print(f"  n_params: {aic_result['n_params']}")
assert aic_result["n_params"] > 0
assert aic_result["aic"] < aic_result["bic"]  # BIC penalizes more

# --- Test 6: Cross-domain transfer ---
print("\n=== Test 6: cross_domain_transfer ===")
no_transfer = [100, 120, 110, 130, 115]
with_transfer = [60, 70, 65, 75, 55]
cdt = cross_domain_transfer(no_transfer, with_transfer)
print(f"  Transfer ratio: {cdt['transfer_ratio']:.2f}x")
print(f"  Significant: {cdt['speedup_significant']}")
print(f"  p-value: {cdt['p_value']:.4f}")
assert cdt["transfer_ratio"] > 1.0

# --- Test 7: Full report ---
print("\n=== Test 7: full_quality_report ===")
out_dir = r"F:\Кейс\AGI-lite\v9\analysis\_test_qreport"
noise2 = noise_sensitivity_profile("(mul x x)", X_train, y_train, variables,
                                    noise_levels=[0.0, 0.1, 0.5], n_trials=2)
pf_all = pf.copy()
pf_all["all_records"] = records

md_path = full_quality_report(
    pf_all, noise2, ood, [eq1, eq2], out_dir)
print(f"Report: {md_path}")
assert os.path.exists(md_path)
assert os.path.exists(os.path.join(out_dir, "pareto_frontier.png"))
assert os.path.exists(os.path.join(out_dir, "noise_sensitivity.png"))

with open(md_path, encoding="utf-8") as f:
    lines = f.readlines()
print(f"Report lines: {len(lines)}")
for line in lines[:12]:
    print(f"  {line.rstrip().encode('ascii', errors='replace').decode()}")

shutil.rmtree(out_dir, ignore_errors=True)

print("\n" + "=" * 40)
print("ALL 7 TESTS PASSED")
