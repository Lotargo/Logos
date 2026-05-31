import csv
import random
import math
import os

def generate_healing_data(filepath):
    # T: Lattice Temperature (K)
    # F: Phonon frequency (THz)
    # C: Micro-fracture size (nm) - New parameter from Red Team vulnerability
    # Prob: Tunneling probability / Resonance stability

    data = [["T", "F", "C", "Prob"]]

    for _ in range(200):
        t = random.uniform(250.0, 500.0)
        f_freq = random.uniform(5.0, 20.0)
        c_size = random.uniform(0.0, 10.0)

        # Perfect resonance logic (from previous discovery)
        resonance = math.exp(-((t - 320) / 20)**2) * math.exp(-((f_freq - 10) / 3)**2)

        # Healing Logic: If there is a crack (C > 0), the probability must smoothly decay to 0
        # instead of exploding or throwing mathematical errors.
        # We model this physical truth into the dataset so V8 can discover a universal formula.
        crack_penalty = math.exp(-c_size)

        prob = resonance * crack_penalty

        # Add some noise to make the regression challenging
        prob = max(0.0, prob + random.uniform(-0.01, 0.01))

        data.append([round(t, 2), round(f_freq, 2), round(c_size, 2), round(prob, 4)])

    with open(filepath, mode='w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(data)

if __name__ == "__main__":
    os.makedirs("v9/data", exist_ok=True)
    generate_healing_data("v9/data/healing_lenr_data.csv")
    print("Healing dataset generated successfully.")
