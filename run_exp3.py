import subprocess
import csv
import re
import os

def run_experiment():
    command = ["sbcl", "--script", "v9/experiments/experiment_nspl_cross_domain.lisp"]

    csv_file = "benchmarks_output/experiment_3_cross/exp3_raw_metrics.csv"
    with open(csv_file, mode="w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["run_id", "translation_attempts", "valid_functors", "hit_rate_percent", "negative_transfers"])

        for i in range(1, 21):
            run_id = f"run_{i:03d}"
            log_file = f"benchmarks_output/experiment_3_cross/logs/{run_id}.log"
            print(f"Running Cross-Domain iteration {i}/20...")

            with open(log_file, "w") as log_f:
                process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                log_f.write(process.stdout)

                # Parse metrics from stdout
                match = re.search(r"METRICS_OUTPUT: translation_attempts=(\d+) valid_functors=(\d+) hit_rate_percent=([\d\.]+) negative_transfers=(\d+)", process.stdout)
                if match:
                    attempts = int(match.group(1))
                    valid = int(match.group(2))
                    hit_rate = float(match.group(3))
                    neg_trans = int(match.group(4))
                    writer.writerow([run_id, attempts, valid, hit_rate, neg_trans])
                else:
                    print(f"Warning: Failed to parse metrics for run {i}")

if __name__ == "__main__":
    run_experiment()
