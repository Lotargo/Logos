# Logos v9 Telemetry Infrastructure

This module provides a persistent, structured memory for Logos v9 using Neon PostgreSQL and a Python-based telemetry logger.

## Architecture

Logos v9 (Lisp/Python) -> telemetry_logger.py -> local JSONL cache -> Neon PostgreSQL

## Components

- `telemetry_logger.py`: CLI tool for logging events and flushing them to the database.
- `db.py`: Handles PostgreSQL connections and batch insertions.
- `linear_client.py`: Optional integration with Linear for issue creation.
- `git_utils.py`: Extracts Git state (commit, branch, dirty status).
- `telemetry_helper.lisp`: Lisp interface for the telemetry system.
- `telemetry_client.py`: Python client for experiment scripts.

## Setup

1. Install dependencies:
   ```bash
   pip install psycopg2-binary PyYAML requests
   ```

2. Set environment variables:
   ```bash
   export NEON_DATABASE_URL="postgresql://user:pass@host/dbname?sslmode=require"
   export LINEAR_API_KEY="your-linear-key"
   export LINEAR_TEAM_ID="your-team-id"
   ```

3. Initialize the database:
   ```bash
   python3 v9/telemetry/telemetry_logger.py init-db
   ```

## Usage

### Logging from CLI
```bash
python3 v9/telemetry/telemetry_logger.py write-local \
  --event-type candidate_created \
  --event-source manual \
  --session-id exp-001 \
  --message "New candidate discovery" \
  --payload '{"fitness": 0.99}'
```

### Flushing to Database
```bash
python3 v9/telemetry/telemetry_logger.py flush
```

### Lisp Integration
```lisp
(log-telemetry "custom_event" "Something happened")
(log-fitness-telemetry "candidate-1" 0.98 '(+ x 1) '(+ x 1))
```

### Python Integration
```python
from telemetry_client import log_event
log_event("experiment_finished", "All done", session_id="exp-001")
```
