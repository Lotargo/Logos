-- 002_add_indexes.sql
-- Performance indexes for Neon queries
-- Applied at: 2026-07-01

CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at TIMESTAMPTZ DEFAULT now(),
    description TEXT
);

CREATE INDEX IF NOT EXISTS idx_fitness_score ON logos_fitness_results (fitness_score DESC);
CREATE INDEX IF NOT EXISTS idx_fitness_created ON logos_fitness_results (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_fitness_high ON logos_fitness_results (fitness_score DESC, created_at DESC)
    WHERE fitness_score >= 0.9;
CREATE INDEX IF NOT EXISTS idx_events_type ON logos_events (event_type);
CREATE INDEX IF NOT EXISTS idx_events_created ON logos_events (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_run_id ON logos_events (run_id);
CREATE INDEX IF NOT EXISTS idx_runs_session ON logos_runs (session_id);
