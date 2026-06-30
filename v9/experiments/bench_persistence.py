import subprocess
import time
import os
import json
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

def run_lisp_script(script_path, args=None):
    if args is None:
        args = []
    cmd = ["sbcl", "--script", script_path] + args
    print(f"Executing: {' '.join(cmd)}")
    start_time = time.time()
    result = subprocess.run(cmd, capture_output=True, text=True)
    end_time = time.time()
    if result.returncode != 0:
        print(f"Error executing {script_path}: {result.stderr}")
    return result.stdout, end_time - start_time

def parse_metrics(output):
    metrics = {'iterations': 0, 'elapsed_time': 0, 'throughput': 0}
    for line in output.split('\n'):
        if "Total ASTs Evaluated" in line:
            metrics['iterations'] = int(line.split(':')[-1].strip())
        if "Total Elapsed Time" in line:
            metrics['elapsed_time'] = float(line.split(':')[-1].strip().split()[0])
        if "Throughput (AST/sec)" in line:
            metrics['throughput'] = float(line.split(':')[-1].strip())
    return metrics

def run_experiment_group(script_path, name, iterations=1, args=None):
    print(f"Running Experiment Group: {name}")
    all_metrics = []
    for i in range(iterations):
        print(f"  Run {i+1}/{iterations}...")
        stdout, duration = run_lisp_script(script_path, args)
        metrics = parse_metrics(stdout)
        metrics['total_duration'] = duration
        all_metrics.append(metrics)
    return all_metrics

def main():
    os.makedirs("benchmarks_output/docs/assets/", exist_ok=True)

    # 1. Complexity Ceiling Experiment
    results_two_phase = run_experiment_group("v9/experiments/exp_complexity_ceiling.lisp", "Complexity Ceiling (Two-Phase)", iterations=1)
    results_one_shot = run_experiment_group("v9/experiments/exp_complexity_ceiling.lisp", "Complexity Ceiling (One-Shot)", iterations=1, args=["--one-shot"])

    # 2. Cross-Domain Transfer Experiment
    results_cross_domain = run_experiment_group("v9/experiments/exp_cross_domain.lisp", "Cross-Domain Transfer", iterations=1)

    # Data Aggregation & Plotting
    df_two_phase = pd.DataFrame(results_two_phase)
    df_one_shot = pd.DataFrame(results_one_shot)

    # Plot 1: Iterations to Discovery (Comparison)
    plt.figure(figsize=(10, 6))
    plt.bar(['Two-Phase', 'One-Shot'], [df_two_phase['iterations'].mean(), df_one_shot['iterations'].mean()])
    plt.title('Complexity Ceiling: Mean Iterations to Discovery')
    plt.ylabel('Iterations')
    plt.savefig('benchmarks_output/docs/assets/iterations_comparison.png')

    # Plot 2: Time to Discovery
    plt.figure(figsize=(10, 6))
    plt.bar(['Two-Phase', 'One-Shot'], [df_two_phase['total_duration'].mean(), df_one_shot['total_duration'].mean()])
    plt.title('Complexity Ceiling: Mean Time to Discovery (seconds)')
    plt.ylabel('Seconds')
    plt.savefig('benchmarks_output/docs/assets/time_comparison.png')

    # Save summary data
    summary = {
        "complexity_ceiling": {
            "two_phase": results_two_phase,
            "one_shot": results_one_shot
        },
        "cross_domain": results_cross_domain
    }
    with open("benchmarks_output/summary_metrics.json", "w") as f:
        json.dump(summary, f, indent=2)

    print("Orchestrator finished. Results saved to benchmarks_output/")

if __name__ == "__main__":
    main()
