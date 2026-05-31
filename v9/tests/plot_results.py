import csv
import os
import numpy as np
import matplotlib.pyplot as plt

def generate_plots():
    print("Generating verification plots...")
    os.makedirs("v9/docs/assets", exist_ok=True)
    
    # 1. Kepler Plot
    kepler_data = []
    with open("v9/data/kepler_data.csv", "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                kepler_data.append([float(x) for x in row])
    kepler_data = np.array(kepler_data)
    a = kepler_data[:, 0]
    T2_actual = kepler_data[:, 1]
    
    # Sort for plotting smooth curve
    sort_idx = np.argsort(a)
    a_sorted = a[sort_idx]
    T2_pred = a_sorted ** 3
    
    plt.figure(figsize=(6, 4))
    plt.scatter(a, T2_actual, color='crimson', label='Empirical Data ($T^2$)', zorder=5)
    plt.plot(a_sorted, T2_pred, color='navy', linestyle='-', linewidth=2, label='Logos Discovered: $T^2 = a^3$')
    plt.title("Kepler's Third Law Verification", fontsize=12, fontweight='bold')
    plt.xlabel("Semi-major axis $a$ (AU)", fontsize=10)
    plt.ylabel("Orbital Period $T^2$ ($yr^2$)", fontsize=10)
    plt.grid(True, linestyle='--', alpha=0.5)
    plt.legend()
    plt.tight_layout()
    plt.savefig("v9/docs/assets/kepler_plot.png", dpi=150)
    plt.close()
    
    # 2. Gravity Plot: Predicted vs Actual Force
    gravity_data = []
    with open("v9/data/gravity_data.csv", "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                gravity_data.append([float(x) for x in row])
    gravity_data = np.array(gravity_data)
    m1 = gravity_data[:, 0]
    m2 = gravity_data[:, 1]
    r = gravity_data[:, 2]
    F_actual = gravity_data[:, 3]
    F_pred = (m1 * m2) / (r ** 2)
    
    plt.figure(figsize=(6, 4))
    plt.scatter(F_actual, F_pred, color='teal', alpha=0.8, label='Empirical Points')
    # Perfect diagonal
    lims = [np.min(F_actual), np.max(F_actual)]
    plt.plot(lims, lims, color='darkorange', linestyle='--', linewidth=2, label='Perfect Fit ($y=x$)')
    plt.title("Newtonian Gravity Verification", fontsize=12, fontweight='bold')
    plt.xlabel("Actual Force $F$", fontsize=10)
    plt.ylabel("Predicted Force $F = \\frac{m_1 m_2}{r^2}$", fontsize=10)
    plt.grid(True, linestyle='--', alpha=0.5)
    plt.legend()
    plt.tight_layout()
    plt.savefig("v9/docs/assets/gravity_plot.png", dpi=150)
    plt.close()
    
    # 3. Relativity Plot
    rel_data = []
    with open("v9/data/relativity_data.csv", "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                rel_data.append([float(x) for x in row])
    rel_data = np.array(rel_data)
    v = rel_data[:, 0]
    c = rel_data[:, 1]
    gamma_actual = rel_data[:, 2]
    
    beta = v / c
    gamma_pred = 1.0 / np.sqrt(1.0 - beta**2)
    
    sort_idx = np.argsort(beta)
    beta_sorted = beta[sort_idx]
    gamma_pred_sorted = gamma_pred[sort_idx]
    
    plt.figure(figsize=(6, 4))
    plt.scatter(beta, gamma_actual, color='darkorchid', label='Empirical Data ($\gamma$)', zorder=5)
    plt.plot(beta_sorted, gamma_pred_sorted, color='forestgreen', linestyle='-', linewidth=2, label='Logos Discovered: $\gamma = \\frac{1}{\\sqrt{1-\\frac{v^2}{c^2}}}$')
    plt.title("Relativistic Kinematics (Lorentz Factor)", fontsize=12, fontweight='bold')
    plt.xlabel("Relativistic Velocity $\\beta = v/c$", fontsize=10)
    plt.ylabel("Lorentz Factor $\gamma$", fontsize=10)
    plt.grid(True, linestyle='--', alpha=0.5)
    plt.legend()
    plt.tight_layout()
    plt.savefig("v9/docs/assets/relativity_plot.png", dpi=150)
    plt.close()
    
    print("Plots generated successfully in v9/docs/assets/")

if __name__ == '__main__':
    generate_plots()
