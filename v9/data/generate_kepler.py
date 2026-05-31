import random
import csv

with open('v9/data/kepler_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    for _ in range(10):
        a = random.uniform(1.0, 10.0)
        targetT2 = a**3
        targetT2 += random.uniform(-0.01, 0.01)
        writer.writerow([round(a, 4), round(targetT2, 4)])
