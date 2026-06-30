"""Smoke test for verify_run.py"""
import sys, os
sys.path.insert(0, r"F:\Кейс\AGI-lite")

from v9.telemetry.verify_run import run_verification

out_dir = r"F:\Кейс\AGI-lite\v9\analysis\_test_verify"
os.makedirs(out_dir, exist_ok=True)

print("=== Smoke test: verify_run.py ===")
result = run_verification(
    run_id="test-run-001",
    domain="algebra",
    session_id="test-session-001",
    output_dir=out_dir,
    best_ast="(mul x x)",
)

print(f"Keys: {list(result.keys())}")
print(f"Metrics: {list(result.get('metrics', {}).keys())}")

import shutil
shutil.rmtree(out_dir, ignore_errors=True)

print("\nOK - verify_run.py works standalone")
