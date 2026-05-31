import csv
import math
import random
import os

def generate_tunneling_data(filepath):
    # E: Energy of incident particle (eV)
    # V: Coulomb barrier height (eV)
    # L: Barrier width (nm)
    # S: Electron screening potential factor (reduces effective V)
    # P_tunnel: Probability of tunneling
    # Real-world Gamow factor without screening is roughly exp(-sqrt(V/E) * L)
    # We introduce 'S' to simulate the hypothesized LENR screening effect.

    data = [["E", "V", "L", "S", "P_tunnel"]]

    for _ in range(100):
        e = random.uniform(1.0, 10.0)
        v = random.uniform(20.0, 50.0)
        l = random.uniform(0.1, 1.0)
        s = random.uniform(0.1, 0.9)  # 1.0 = no screening, 0.1 = heavy screening

        # Effective barrier
        v_eff = v * s

        # Probability exponentially dependent on effective barrier and width
        if v_eff > e:
            p_tunnel = math.exp(-2.0 * math.sqrt(v_eff - e) * l)
        else:
            p_tunnel = 1.0

        data.append([round(e, 4), round(v, 4), round(l, 4), round(s, 4), round(p_tunnel, 6)])

    with open(filepath, mode='w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(data)

def generate_phonon_resonance_data(filepath):
    # F: Phonon frequency (THz)
    # T: Lattice Temperature (K)
    # M: Mass of Palladium lattice atoms
    # A: Amplitude of resonance (Target)
    # We want V8 to discover a harmonic resonance state where high F and low T trigger a specific amplitude peak.

    data = [["F", "T", "M", "A"]]

    for _ in range(100):
        f_freq = random.uniform(1.0, 20.0)
        t = random.uniform(273.0, 500.0)
        m = 106.4 # Pd mass

        # Simulated hidden relation: Resonance peaks when F/T hits a sweet spot.
        # A = sin(F) * exp(-T / 1000) * (M/100)
        amp = math.sin(f_freq) * math.exp(-t / 1000.0) * (m / 100.0)

        data.append([round(f_freq, 4), round(t, 2), round(m, 2), round(amp, 4)])

    with open(filepath, mode='w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(data)

if __name__ == "__main__":
    os.makedirs("v9/data", exist_ok=True)
    generate_tunneling_data("v9/data/tunneling_data.csv")
    generate_phonon_resonance_data("v9/data/phonon_resonance.csv")
    print("LENR datasets generated successfully.")
