import csv
import random
import os

def generate_singularity_data(filepath):
    # m: Mass
    # r: Distance
    # l: Planck-scale cutoff length
    # f: Force (F = M / (r^2 + L^2))

    data = [["m", "r", "l", "f"]]

    # We deliberately inject strict adversarial cases where r = 0.0
    # A standard Newtonian formula (div m (mul r r)) will crash/evaluate to infinity here,
    # forcing the engine to receive a 1000.0 penalty and evolve a healing mechanism.

    for i in range(200):
        m = random.uniform(10.0, 100.0)
        l = random.uniform(0.1, 1.0)

        if i % 10 == 0:
            # 10% of cases are direct singularity hits
            r = 0.0
        else:
            r = random.uniform(0.5, 20.0)

        f = m / ((r ** 2) + (l ** 2))
        f += random.uniform(-0.01, 0.01) # Noise

        data.append([round(m, 4), round(r, 4), round(l, 4), round(f, 4)])

    with open(filepath, mode='w', newline='') as file:
        writer = csv.writer(file)
        writer.writerows(data)

if __name__ == "__main__":
    os.makedirs("v9/data", exist_ok=True)
    generate_singularity_data("v9/data/adversarial_singularity.csv")
    print("Adversarial Singularity dataset generated successfully.")
