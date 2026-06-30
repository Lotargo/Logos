import sys

engine_path = "v9/src/engine.lisp"
with open(engine_path, "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    # Hook for run-engine-parallel start
    if "(defun run-engine-parallel (base-ast domain iterations num-threads)" in line:
        # Find next line or suitable place
        pass

    # Hook for convergence
    if '(format t "[Thread ~D] [CONVERGED] Iteration ~D: ~A (Penalty: 0.0)~%" thread-id i best-ast)' in line:
        indent = line[:line.find('(format')]
        new_lines.append(f'{indent}(log-fitness-telemetry (format nil "thread-~D-iter-~D" thread-id i) 1.0 base-ast best-ast)\n')

    # Hook for experiment finished
    if '          (let ((hybrids (synthesize-hybrids winners domain 3 20000)))' in line:
         indent = line[:line.find('(let')]
         new_lines.append(f'{indent}(log-telemetry "experiment_finished" (format nil "Experiment in domain ~A finished" domain))\n')

with open(engine_path, "w") as f:
    f.writelines(new_lines)
