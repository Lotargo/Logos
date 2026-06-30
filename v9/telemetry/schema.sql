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
