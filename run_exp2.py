import subprocess
import csv
import re
import os

def run_experiment():
    command = ["sbcl", "--script", "v9/experiments/experiment_nspl_gan.lisp"]

    csv_file = "benchmarks_output/experiment_2_gan/exp2_raw_metrics.csv"
    with open(csv_file, mode="w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["run_id", "adversarial_rounds", "final_ast_size", "time_sec"])

        for i in range(1, 21):
            run_id = f"run_{i:03d}"
            log_file = f"benchmarks_output/experiment_2_gan/logs/{run_id}.log"
            print(f"Running GAN iteration {i}/20...")

            with open(log_file, "w") as log_f:
                process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                log_f.write(process.stdout)

                # Parse metrics from stdout
                match = re.search(r"METRICS_OUTPUT: adversarial_rounds=(\d+) final_ast_size=(\d+) time_sec=([\d\.]+)", process.stdout)
                if match:
                    rounds = int(match.group(1))
                    ast_size = int(match.group(2))
                    time_sec = float(match.group(3))
                    writer.writerow([run_id, rounds, ast_size, time_sec])
                else:
                    print(f"Warning: Failed to parse metrics for run {i}")
                    print("Output was:")
                    print(process.stdout)

if __name__ == "__main__":
    run_experiment()
