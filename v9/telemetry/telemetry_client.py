import os
import json
import subprocess

def log_event(event_type, message, session_id="python-session", source="python_script", payload=None):
    """Utility function for Python scripts to log telemetry."""
    cmd = [
        "python3", "v9/telemetry/telemetry_logger.py", "write-local",
        "--event-type", event_type,
        "--event-source", source,
        "--session-id", session_id,
        "--message", message
    ]
    if payload:
        cmd.extend(["--payload", json.dumps(payload)])

    try:
        subprocess.run(cmd, check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        print(f"Telemetry logging failed: {e.stderr.decode()}")

if __name__ == "__main__":
    log_event("test_python", "Hello from telemetry_client.py")
