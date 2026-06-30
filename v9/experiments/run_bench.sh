#!/bin/bash
export NEON_DATABASE_URL="postgresql://neondb_owner:npg_H4EoMslx2YCV@ep-solitary-flower-aje52ci9-pooler.c-3.us-east-2.aws.neon.tech/neondb?channel_binding=require&sslmode=require"
python3 v9/experiments/bench_persistence.py
python3 v9/telemetry/telemetry_logger.py flush
