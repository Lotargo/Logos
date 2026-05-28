import csv
import math
import random
import os

def generate_poincare_data(filepath):
    # D: Dimension (only D=3 is relevant for Poincare conjecture directly, but we add noise D=2, 4)
    # P1: Pi_1 triviality (1 = simply connected, 0 = not)
    # C: Compactness (1 = compact, 0 = not)
    # B: Boundary (0 = no boundary, 1 = has boundary)
    # S3: Is homeomorphic to 3-sphere (Target)

    data = [["D", "P1", "C", "B", "S3"]]

    for _ in range(100):
        d = random.choice([2, 3, 4])
        p1 = random.choice([0, 1])
        c = random.choice([0, 1])
        b = random.choice([0, 1])

        # Poincare conjecture: Every simply connected, closed (compact, no boundary) 3-manifold is homeomorphic to the 3-sphere.
        if d == 3 and p1 == 1 and c == 1 and b == 0:
            s3 = 1
        else:
            s3 = 0

        data.append([d, p1, c, b, s3])

    with open(filepath, mode='w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(data)

def generate_ricci_flow_data(filepath):
    # Time (t), Metric Tensor Component (g), Ricci Curvature Tensor Component (R)
    # We want to regress: dg/dt = -2 * R
    # Let g(t) = exp(-2 * k * t), then dg/dt = -2k * exp(-2kt) = -2 * k * g. If R = k*g, then dg/dt = -2 * R.
    # We provide t, g, R, and the target is dg_dt.

    data = [["t", "g", "R", "dg_dt"]]

    k = 0.5
    for i in range(100):
        t = i * 0.1
        g = math.exp(-2 * k * t)
        r = k * g
        dg_dt = -2 * r

        data.append([round(t, 4), round(g, 4), round(r, 4), round(dg_dt, 4)])

    with open(filepath, mode='w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(data)

if __name__ == "__main__":
    os.makedirs("v8/data", exist_ok=True)
    generate_poincare_data("v8/data/poincare_data.csv")
    generate_ricci_flow_data("v8/data/ricci_flow.csv")
    print("Poincare datasets generated successfully.")
