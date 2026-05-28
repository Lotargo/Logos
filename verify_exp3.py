import pandas as pd
import matplotlib.pyplot as plt

def verify():
    csv_file = "benchmarks_output/experiment_3_cross/exp3_raw_metrics.csv"
    try:
        df = pd.read_csv(csv_file)
    except Exception as e:
        print(f"Error reading CSV: {e}")
        return

    attempts = df['translation_attempts']
    valid = df['valid_functors']
    hit_rate = df['hit_rate_percent']
    neg_trans = df['negative_transfers']

    print(f"Mean Translation Attempts: {attempts.mean():.2f}")
    print(f"Mean Hit Rate: {hit_rate.mean():.2f}%")
    print(f"Mean Negative Transfers: {neg_trans.mean():.2f}")

    # Plot Hit Rate vs Negative Transfers
    plt.figure(figsize=(8, 6))

    total_valid = valid.sum()
    total_neg = neg_trans.sum()

    plt.pie([total_valid, total_neg], labels=['Successful Isomorphisms', 'Negative Transfers'],
            autopct='%1.1f%%', colors=['#4CAF50', '#F44336'], startangle=140)
    plt.title('Cross-Domain Translation Outcomes')
    plt.savefig('benchmarks_output/experiment_3_cross/translation_outcomes.png')
    print("Saved benchmarks_output/experiment_3_cross/translation_outcomes.png")

if __name__ == "__main__":
    verify()
