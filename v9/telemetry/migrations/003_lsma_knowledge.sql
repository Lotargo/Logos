-- 003_lsma_knowledge.sql
-- LSMA: Logos Knowledge table for AST passport storage
-- Applied at: 2026-07-01

CREATE TABLE IF NOT EXISTS logos_knowledge (
    ast_hash      TEXT PRIMARY KEY,
    ast           JSONB NOT NULL,
    passport      JSONB NOT NULL,
    adf_symbol    TEXT,
    created_at    TIMESTAMPTZ DEFAULT now(),
    updated_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_knowledge_ops
    ON logos_knowledge USING GIN ((passport -> 'operator_profile'));
CREATE INDEX IF NOT EXISTS idx_knowledge_domains
    ON logos_knowledge USING GIN ((passport -> 'domains'));
CREATE INDEX IF NOT EXISTS idx_knowledge_adf
    ON logos_knowledge (adf_symbol)
    WHERE adf_symbol IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_knowledge_updated
    ON logos_knowledge (updated_at DESC);

INSERT INTO schema_migrations (version, description)
VALUES (3, 'lsma_logos_knowledge')
ON CONFLICT (version) DO NOTHING;
