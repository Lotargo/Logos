-- Logos V9 DS/ML Verification Tools — Schema Migration
-- Adds 4 new tables for statistical verification pipeline.
-- Apply AFTER existing schema (schema.sql).
-- Idempotent: uses IF NOT EXISTS throughout.

-- =============================================================================
-- Table 1: logos_population_snapshots
-- Stores diversity metrics per evolutionary iteration.
-- =============================================================================
CREATE TABLE IF NOT EXISTS logos_population_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID REFERENCES logos_runs(id) ON DELETE CASCADE,
    iteration INTEGER NOT NULL,
    population_size INTEGER,
    avg_edit_distance DOUBLE PRECISION,
    shannon_entropy DOUBLE PRECISION,
    avg_fitness DOUBLE PRECISION,
    best_fitness DOUBLE PRECISION,
    fitness_std DOUBLE PRECISION,
    avg_depth DOUBLE PRECISION,
    unique_operators INTEGER,
    stagnant BOOLEAN DEFAULT FALSE,
    snapshot_data JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pop_snap_run ON logos_population_snapshots (run_id);
CREATE INDEX IF NOT EXISTS idx_pop_snap_iter ON logos_population_snapshots (run_id, iteration);

-- =============================================================================
-- Table 2: logos_operator_stats
-- Tracks operator usage frequency and success rates per run.
-- =============================================================================
CREATE TABLE IF NOT EXISTS logos_operator_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID REFERENCES logos_runs(id) ON DELETE CASCADE,
    operator_name TEXT NOT NULL,
    phase TEXT,
    total_uses INTEGER DEFAULT 0,
    successful_uses INTEGER DEFAULT 0,
    success_rate DOUBLE PRECISION,
    avg_fitness_improvement DOUBLE PRECISION,
    chi_square_stat DOUBLE PRECISION,
    p_value DOUBLE PRECISION,
    domain TEXT,
    sample_size INTEGER,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_op_stats_run ON logos_operator_stats (run_id);
CREATE INDEX IF NOT EXISTS idx_op_stats_name ON logos_operator_stats (operator_name);
CREATE INDEX IF NOT EXISTS idx_op_stats_rate ON logos_operator_stats (success_rate DESC);

-- =============================================================================
-- Table 3: logos_experiment_configs
-- Records hyperparameters, seeds, and dataset hashes for reproducibility.
-- =============================================================================
CREATE TABLE IF NOT EXISTS logos_experiment_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID REFERENCES logos_runs(id) ON DELETE CASCADE,
    experiment_name TEXT,
    config JSONB NOT NULL,
    seed INTEGER,
    dataset_name TEXT,
    dataset_hash TEXT,
    dataset_rows INTEGER,
    dataset_columns INTEGER,
    model_id TEXT,
    population_size INTEGER,
    max_generations INTEGER,
    mutation_rate DOUBLE PRECISION,
    crossover_rate DOUBLE PRECISION,
    selection_method TEXT,
    fitness_function TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_exp_config_run ON logos_experiment_configs (run_id);
CREATE INDEX IF NOT EXISTS idx_exp_config_name ON logos_experiment_configs (experiment_name);
CREATE INDEX IF NOT EXISTS idx_exp_config_hash ON logos_experiment_configs (dataset_hash);

-- =============================================================================
-- Table 4: logos_verification_results
-- Caches computed verification metrics with confidence intervals and p-values.
-- =============================================================================
CREATE TABLE IF NOT EXISTS logos_verification_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID REFERENCES logos_runs(id) ON DELETE CASCADE,
    metric_name TEXT NOT NULL,
    metric_value DOUBLE PRECISION,
    ci_lower DOUBLE PRECISION,
    ci_upper DOUBLE PRECISION,
    ci_level DOUBLE PRECISION DEFAULT 0.95,
    p_value DOUBLE PRECISION,
    effect_size DOUBLE PRECISION,
    effect_size_name TEXT,
    test_used TEXT,
    sample_size INTEGER,
    significant BOOLEAN,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_verif_run ON logos_verification_results (run_id);
CREATE INDEX IF NOT EXISTS idx_verif_metric ON logos_verification_results (metric_name);
CREATE INDEX IF NOT EXISTS idx_verif_sig ON logos_verification_results (significant) WHERE significant = TRUE;
CREATE INDEX IF NOT EXISTS idx_verif_p ON logos_verification_results (p_value);

-- =============================================================================
-- Migration record
-- =============================================================================
INSERT INTO schema_migrations (version, description)
VALUES (2, 'DS/ML verification: population_snapshots, operator_stats, experiment_configs, verification_results')
ON CONFLICT (version) DO NOTHING;
