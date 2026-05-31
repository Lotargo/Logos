import csv
import math
import random

# Generate a highly non-linear dataset with significant noise
# Target: Y = 5 * sin(X1) + X2^2 - 10 * exp(-X3) + NOISE
with open('v9/data/extreme_noise_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    # 50 rows of data
    for _ in range(50):
        x1 = random.uniform(-5, 5)
        x2 = random.uniform(0, 10)
        x3 = random.uniform(0, 5)

        # Calculate ideal target
        ideal_y = 5 * math.sin(x1) + (x2 ** 2) - 10 * math.exp(-x3)

        # Add massive noise (-50% to +50% of the ideal value)
        noise = random.uniform(-0.5 * abs(ideal_y), 0.5 * abs(ideal_y))
        target_y = ideal_y + noise

        writer.writerow([round(x1, 4), round(x2, 4), round(x3, 4), round(target_y, 4)])

print("Generated v9/data/extreme_noise_data.csv")
