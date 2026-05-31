import csv
import random
import os

def generate_extreme_data(filepath):
    # E: Energy of incident particle (eV)
    # V: Coulomb barrier height (eV)
    # L: Barrier width (nm)
    # S: Electron screening potential factor
    # Target: P_tunnel (but we will intentionally create boundary cases that should break standard formulas)

    data = [["E", "V", "L", "S", "P_tunnel"]]

    # 1. Near Absolute Zero (Quantum Decoherence Zone)
    # T -> 0 translates to zero phonon momentum, S -> 0 (no acoustic screening assistance)
    for _ in range(25):
        e = random.uniform(0.0001, 0.01)
        v = random.uniform(50.0, 100.0)
        l = random.uniform(1.0, 5.0)
        s = random.uniform(0.00001, 0.001)
        data.append([e, v, l, s, 0.0]) # Should absolutely not tunnel

    # 2. Extreme Plasma Heat (Hot Fusion boundary)
    # T -> 10^7 K, V gets overwhelmed by E. S becomes irrelevant (S -> 1.0)
    for _ in range(25):
        e = random.uniform(10000.0, 50000.0)
        v = random.uniform(20.0, 50.0)
        l = random.uniform(0.01, 0.1)
        s = 1.0
        data.append([e, v, l, s, 1.0]) # Definite tunneling/fusion

    # 3. Lattice Micro-Fracture / Pressure Drop
    # Extreme L (barrier widens infinitely due to crack), but S spikes due to transient charge pooling
    for _ in range(25):
        e = random.uniform(1.0, 10.0)
        v = random.uniform(20.0, 50.0)
        l = random.uniform(100.0, 1000.0) # Massive width
        s = random.uniform(0.0001, 0.01) # Massive screening (lower is better in our convention)
        data.append([e, v, l, s, 0.0]) # The width should dominate and prevent fusion, testing if the formula breaks and outputs > 1

    # 4. Negative / Impossible Physical States
    # Testing mathematical robustness (V8 should prune these via Prolog constraints)
    for _ in range(25):
        e = random.uniform(-10.0, -1.0) # Negative energy
        v = random.uniform(-50.0, -20.0) # Negative barrier
        l = random.uniform(-1.0, -0.1) # Negative width
        s = random.uniform(-0.9, -0.1) # Negative screening
        data.append([e, v, l, s, 0.0])

    with open(filepath, mode='w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(data)

if __name__ == "__main__":
    os.makedirs("v9/data", exist_ok=True)
    generate_extreme_data("v9/data/extreme_lenr_data.csv")
    print("Extreme adversarial LENR dataset generated successfully.")
