import csv
import random
import os

def generate_schrodinger_data(filepath):
    # p: momentum
    # m: mass
    # V: potential energy
    # E: total energy (E = p^2 / 2m + V)

    data = [["p", "m", "V", "E"]]
    for _ in range(100):
        p = random.uniform(1.0, 10.0)
        m = random.uniform(0.5, 5.0)
        v = random.uniform(0.0, 20.0)

        # E = p^2 / (2 * m) + V
        e = (p ** 2) / (2 * m) + v

        # Add slight noise
        e += random.uniform(-0.01, 0.01)

        data.append([round(p, 4), round(m, 4), round(v, 4), round(e, 4)])

    with open(filepath, mode='w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(data)

def generate_entropy_data(filepath):
    # A: Area
    # S: Holographic Entropy (S = A / 4)

    data = [["A", "S"]]
    for _ in range(100):
        a = random.uniform(10.0, 1000.0)

        s = a / 4.0

        # Add slight noise
        s += random.uniform(-0.01, 0.01)

        data.append([round(a, 4), round(s, 4)])

    with open(filepath, mode='w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(data)

if __name__ == "__main__":
    os.makedirs("v8/data", exist_ok=True)
    generate_schrodinger_data("v8/data/schrodinger_data.csv")
    generate_entropy_data("v8/data/holographic_entropy_data.csv")
    print("New experiment datasets generated successfully.")
