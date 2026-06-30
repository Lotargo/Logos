import sys

engine_path = "v9/src/engine.lisp"
with open(engine_path, "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    if "(defun run-engine-parallel (base-ast domain iterations num-threads)" in line:
        new_lines.append('  (log-telemetry "experiment_started" (format nil "Starting experiment in domain ~A" domain))\n')

with open(engine_path, "w") as f:
    f.writelines(new_lines)
