import matplotlib.pyplot as plt
import numpy as np
import os

def analyze_healing():
    assets_dir = "v8/docs/assets"
    os.makedirs(assets_dir, exist_ok=True)

    # Simulate variables
    temperature = np.linspace(250, 450, 200) # Kelvin
    f_freq = 10.0 # Optimal phonon resonance frequency

    # 1. The old "Broken" V8 Formula (No crack awareness)
    # Explodes or crashes when crack size (C) is introduced. We simulate it staying blindly optimistic.
    broken_prob = np.exp(-((temperature - 320) / 20)**2) * np.exp(-((f_freq - 10) / 3)**2)

    # 2. The New "Healed" Universal V8 Formula
    # Aware of C (Micro-fracture size). We show it dynamically quenching the reaction as C increases.
    c_size_small = 0.5  # nm
    c_size_large = 2.0  # nm

    # The healed AST acts like: Prob = Old_Prob * exp(-C)
    healed_prob_small = broken_prob * np.exp(-c_size_small)
    healed_prob_large = broken_prob * np.exp(-c_size_large)

    plt.figure(figsize=(10, 6))

    # Plotting
    plt.plot(temperature, broken_prob, label='Original V8 Theory (No Crack Awareness)', color='red', linestyle='--')
    plt.plot(temperature, healed_prob_small, label='Healed V8 Theory (Minor Fracture, C=0.5nm)', color='blue', linewidth=2)
    plt.plot(temperature, healed_prob_large, label='Healed V8 Theory (Major Fracture, C=2.0nm)', color='green', linewidth=2)

    plt.title('Theory Healing: LENR Reaction Quenching due to Lattice Fractures')
    plt.xlabel('Lattice Temperature (K)')
    plt.ylabel('Normalized Fusion Probability')
    plt.legend()
    plt.grid(True)

    chart_path = os.path.join(assets_dir, 'lenr_healing_process.png')
    plt.savefig(chart_path)
    print(f"Healing simulation chart saved to {chart_path}")

if __name__ == "__main__":
    analyze_healing()