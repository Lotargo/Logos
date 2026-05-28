import pandas as pd
import matplotlib.pyplot as plt

def verify():
    csv_file = "benchmarks_output/experiment_2_gan/exp2_raw_metrics.csv"
    try:
        df = pd.read_csv(csv_file)
    except Exception as e:
        print(f"Error reading CSV: {e}")
        return

    rounds = df['adversarial_rounds']
    ast_sizes = df['final_ast_size']
    times = df['time_sec']

    print(f"Mean Adversarial Rounds: {rounds.mean():.2f}")
    print(f"Mean Final AST Size: {ast_sizes.mean():.2f}")
    print(f"Mean Time: {times.mean():.4f}s")

    # Plot AST Size vs Rounds (in our simplified simulation it's constant, but good to visualize)
    plt.figure(figsize=(8, 6))
    plt.bar(['Initial AST (div m r)', 'Healed AST (with L_p)'], [3, ast_sizes.mean()], color=['red', 'green'])
    plt.title('AST Complexity (Parsimony Pressure)')
    plt.ylabel('Nodes in AST')
    plt.grid(True, axis='y', linestyle='--', alpha=0.7)
    plt.savefig('benchmarks_output/experiment_2_gan/ast_complexity.png')
    print("Saved benchmarks_output/experiment_2_gan/ast_complexity.png")

if __name__ == "__main__":
    verify()
