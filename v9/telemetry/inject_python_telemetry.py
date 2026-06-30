import os

scripts = [
    "v9/experiments/generate_new_experiments_report.py",
    "v9/experiments/analyze_healing.py"
]

for script in scripts:
    if not os.path.exists(script):
        continue
    with open(script, "r") as f:
        content = f.read()

    if "telemetry_client" in content:
        continue

    import_line = "import sys\nsys.path.append(os.path.join(os.path.dirname(__file__), '..', 'telemetry'))\nfrom telemetry_client import log_event\n"

    # Insert import
    if "import os" in content:
        content = content.replace("import os", "import os\n" + import_line, 1)
    else:
        content = import_line + content

    # Hook into main
    if 'if __name__ == "__main__":' in content:
        hook = f'    log_event("report_generation_started", "Starting generation for {os.path.basename(script)}", source="python_reporter")\n'
        content = content.replace('if __name__ == "__main__":', 'if __name__ == "__main__":\n' + hook)
        content += f'\n    log_event("report_generation_finished", "Finished generation for {os.path.basename(script)}", source="python_reporter")\n'

    with open(script, "w") as f:
        f.write(content)
