-- Logos v9 Infrastructure Memory Schema

CREATE TABLE IF NOT EXISTS logos_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id TEXT,
    experiment_id TEXT,
    run_type TEXT,
    started_at TIMESTAMPTZ DEFAULT now(),
    finished_at TIMESTAMPTZ,
    status TEXT,
    model_id TEXT,
    logos_version TEXT,
    git_commit_hash TEXT,
    git_branch TEXT,
    dirty_worktree BOOLEAN,
    metadata JSONB
);

CREATE TABLE IF NOT EXISTS logos_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID REFERENCES logos_runs(id),
    session_id TEXT,
    event_type TEXT NOT NULL,
    event_source TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    severity TEXT,
    message TEXT,
    payload JSONB,
    metadata JSONB
);

CREATE TABLE IF NOT EXISTS logos_fitness_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID REFERENCES logos_runs(id),
    event_id UUID REFERENCES logos_events(id),
    session_id TEXT,
    candidate_id TEXT,
    fitness_score DOUBLE PRECISION,
    fitness_metrics JSONB,
    input_ast JSONB,
    output_ast JSONB,
    input_ast_hash TEXT,
    output_ast_hash TEXT,
    execution_time_ms DOUBLE PRECISION,
    error_rate DOUBLE PRECISION,
    tokens_used INTEGER,
    created_at TIMESTAMPTZ DEFAULT now(),
    metadata JSONB
);

CREATE TABLE IF NOT EXISTS logos_ab_tests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID REFERENCES logos_runs(id),
    session_id TEXT,
    test_name TEXT,
    variant_a TEXT,
    variant_b TEXT,
    winner TEXT,
    metrics_a JSONB,
    metrics_b JSONB,
    comparison_summary TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    metadata JSONB
);

CREATE TABLE IF NOT EXISTS logos_linear_issues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID REFERENCES logos_events(id),
    run_id UUID REFERENCES logos_runs(id),
    linear_issue_id TEXT,
    linear_issue_url TEXT,
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    metadata JSONB
);

-- Migration tracking
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at TIMESTAMPTZ DEFAULT now(),
    description TEXT
);

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_fitness_score ON logos_fitness_results (fitness_score DESC);
CREATE INDEX IF NOT EXISTS idx_fitness_created ON logos_fitness_results (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_fitness_high ON logos_fitness_results (fitness_score DESC, created_at DESC)
    WHERE fitness_score >= 0.9;
CREATE INDEX IF NOT EXISTS idx_events_type ON logos_events (event_type);
CREATE INDEX IF NOT EXISTS idx_events_created ON logos_events (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_run_id ON logos_events (run_id);
CREATE INDEX IF NOT EXISTS idx_runs_session ON logos_runs (session_id);
