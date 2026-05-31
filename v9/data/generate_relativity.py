import random
import csv
import math

with open('v9/data/relativity_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    c = 3.0
    for _ in range(10):
        v = random.uniform(0.1, 2.9)
        gamma_sq = 1.0 / (1.0 - (v**2)/(c**2))
        gamma_sq += random.uniform(-0.01, 0.01)
        writer.writerow([round(v, 4), round(c, 4), round(gamma_sq, 4)])
