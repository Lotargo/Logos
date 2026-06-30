import numpy as np
import pandas as pd
import os

def generate_data(n_samples=100):
    np.random.seed(42)
    x = np.linspace(-5, 5, n_samples)
    # Target: f(x) = x^2 + 2x + 1
    y = x**2 + 2*x + 1

    noise = np.random.normal(0, 0.001, n_samples)
    y_noisy = y + noise

    df = pd.DataFrame({'x': x, 'target': y_noisy})
    os.makedirs('v9/data', exist_ok=True)
    df.to_csv('v9/data/exp1_data.csv', index=False, header=False)
    print(f"Dataset generated at v9/data/exp1_data.csv with {n_samples} samples.")

if __name__ == "__main__":
    generate_data()
