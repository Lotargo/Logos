#!/bin/bash
: "${NEON_DATABASE_URL:?Set NEON_DATABASE_URL before running this script}"
export NEON_DATABASE_URL
python3 v9/experiments/bench_persistence.py
python3 v9/telemetry/telemetry_logger.py flush
