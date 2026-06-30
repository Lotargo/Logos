import subprocess
import json
import os
import time
import pandas as pd
import numpy as np

def run_trial(mode, knowledge=None):
    session_id = f"exp1-{mode}-{int(time.time() * 1000)}"
    launcher_path = f"v9/experiments/tmp_launcher_{session_id}.lisp"

    with open(launcher_path, "w") as f:
        f.write(f"(defpackage :cognitive-engine (:use :cl))\n")
        f.write(f"(in-package :cognitive-engine)\n")
        f.write(f"(defvar *is-cli* t)\n")
        f.write(f"(defvar *telemetry-session-id* \"{session_id}\")\n")
        f.write(f"(load \"v9/src/engine.lisp\")\n")
        f.write(f"(setf *current-dataset* \"v9/data/exp1_data.csv\")\n")

        if mode == 'persistent' and knowledge:
            f.write(f"(defun fetch-telemetry-knowledge (&key (min-fitness 0.9))\n")
            f.write(f"  '(:asts {json.dumps(knowledge['asts']).replace('[', '(').replace(']', ')').replace(',', '')} \n")
            f.write(f"    :axioms {json.dumps(knowledge['axioms']).replace('[', '(').replace(']', ')').replace(',', '')}))\n")
        elif mode == 'baseline':
            f.write(f"(defun fetch-telemetry-knowledge (&key (min-fitness 0.9)) nil)\n")

        f.write(f"(run-engine-parallel '(+ v1 0) :regression 3000 1)\n")
        f.write(f"(uiop:quit)\n")

    start_t = time.time()
    env = os.environ.copy()
    env["NEON_DATABASE_URL"] = ""
    result = subprocess.run(["sbcl", "--script", launcher_path], capture_output=True, text=True, env=env)
    end_t = time.time()

    os.remove(launcher_path)

    output = result.stdout
    iterations = 3000
    converged = False

    for line in output.split('\n'):
        if "CONVERGED" in line:
            converged = True
            # Extract iteration from line "[Thread 1] [CONVERGED] Iteration 123: ..."
            try:
                iterations = int(line.split('Iteration')[1].split(':')[0].strip())
            except:
                pass
        if "Total ASTs Evaluated" in line and not converged:
             try:
                iterations = int(line.split(':')[-1].strip())
             except:
                pass

    return {
        "session_id": session_id,
        "mode": mode,
        "iterations": iterations,
        "time_sec": end_t - start_t,
        "converged": converged,
        "output": output
    }

def main():
    trials_per_mode = 5
    results = []

    print("Starting Baseline Trials...")
    for i in range(trials_per_mode):
        print(f"  Baseline Trial {i+1}/{trials_per_mode}...")
        res = run_trial('baseline')
        results.append(res)

    knowledge = {
        "asts": ["(mul v1 v1)", "(add v1 v1)"],
        "axioms": []
    }

    print("Starting Persistent Trials...")
    for i in range(trials_per_mode):
        print(f"  Persistent Trial {i+1}/{trials_per_mode}...")
        res = run_trial('persistent', knowledge)
        results.append(res)

    df = pd.DataFrame(results)
    df.drop(columns=['output']).to_csv("benchmarks_output/experiment_1/results.csv", index=False)
    with open("benchmarks_output/experiment_1/raw_logs.json", "w") as f:
        json.dump(results, f)
    print("\nExperiment 1 Complete.")

if __name__ == "__main__":
    main()
