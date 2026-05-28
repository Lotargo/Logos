import subprocess
import csv
import re
import os
import sys

def run_experiment():
    command = ["sbcl", "--script", "v9/experiments/experiment_nspl_coop.lisp"]

    csv_file = "benchmarks_output/experiment_1_coop/exp1_raw_metrics.csv"
    with open(csv_file, mode="w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["run_id", "cycles_to_converge", "time_sec", "lost_packets"])

        for i in range(1, 21):
            run_id = f"run_{i:03d}"
            log_file = f"benchmarks_output/experiment_1_coop/logs/{run_id}.log"
            print(f"Running iteration {i}/20...")

            with open(log_file, "w") as log_f:
                process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                log_f.write(process.stdout)

                # Parse metrics from stdout
                match = re.search(r"METRICS_OUTPUT: cycles_to_converge=(\d+) time_sec=([\d\.]+) lost_packets=(\d+)", process.stdout)
                if match:
                    cycles = int(match.group(1))
                    time_sec = float(match.group(2))
                    lost_packets = int(match.group(3))
                    writer.writerow([run_id, cycles, time_sec, lost_packets])
                else:
                    print(f"Warning: Failed to parse metrics for run {i}")

if __name__ == "__main__":
    run_experiment()
