import numpy as np
import pandas as pd

def target_formula(x):
    # Deep formula: sin(x + sin(x + sin(x + sin(x + sin(x)))))
    val = x
    for _ in range(5):
        val = np.sin(x + val)
    return val

x_vals = np.linspace(-5, 5, 200)
y_vals = target_formula(x_vals)

df = pd.DataFrame({'v1': x_vals, 'target': y_vals})
df.to_csv('v9/data/complex_formula.csv', index=False)
print("Generated v9/data/complex_formula.csv")
