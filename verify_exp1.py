import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

def verify():
    csv_file = "benchmarks_output/experiment_1_coop/exp1_raw_metrics.csv"
    try:
        df = pd.read_csv(csv_file)
    except Exception as e:
        print(f"Error reading CSV: {e}")
        return

    cycles = df['cycles_to_converge']
    times = df['time_sec']
    lost = df['lost_packets']

    print(f"Mean cycles: {cycles.mean():.2f} (std: {cycles.std():.2f})")
    print(f"Mean time: {times.mean():.4f}s (std: {times.std():.4f}s)")
    print(f"Mean lost packets: {lost.mean():.2f}")

    # Plot Boxplot for convergence time
    plt.figure(figsize=(8, 6))
    plt.boxplot(times, patch_artist=True)
    plt.title('Convergence Time Distribution (Swarm Intelligence)')
    plt.ylabel('Time (seconds)')
    plt.xticks([1], ['Cooperative Swarm'])
    plt.grid(True, axis='y')
    plt.savefig('benchmarks_output/experiment_1_coop/convergence_time_boxplot.png')
    print("Saved benchmarks_output/experiment_1_coop/convergence_time_boxplot.png")

if __name__ == "__main__":
    verify()
