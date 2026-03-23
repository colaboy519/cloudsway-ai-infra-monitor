-- Create separate database for n8n internal state
SELECT 'CREATE DATABASE n8n' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')\gexec

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Raw collected signals from all sources
CREATE TABLE raw_signals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source VARCHAR(50) NOT NULL,
    source_category VARCHAR(50),
    title TEXT NOT NULL,
    url TEXT,
    raw_content TEXT,
    entities JSONB DEFAULT '[]'::jsonb,
    metadata JSONB DEFAULT '{}'::jsonb,
    collected_at TIMESTAMPTZ NOT NULL,
    content_hash VARCHAR(64),
    duplicate_of UUID REFERENCES raw_signals(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_raw_signals_url ON raw_signals(url) WHERE url IS NOT NULL;
CREATE UNIQUE INDEX idx_raw_signals_hash ON raw_signals(content_hash) WHERE content_hash IS NOT NULL;
CREATE INDEX idx_raw_signals_source ON raw_signals(source);
CREATE INDEX idx_raw_signals_collected ON raw_signals(collected_at);

-- Triage results from LLM classification
CREATE TABLE triage_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    signal_id UUID NOT NULL REFERENCES raw_signals(id),
    significance_score INT NOT NULL CHECK (significance_score BETWEEN 1 AND 5),
    category VARCHAR(50),
    urgency VARCHAR(20),
    triage_reasoning TEXT,
    triaged_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_triage_score ON triage_results(significance_score);
CREATE INDEX idx_triage_signal ON triage_results(signal_id);

-- Agent investigation results for high-signal items
CREATE TABLE investigations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    signal_id UUID NOT NULL REFERENCES raw_signals(id),
    analysis TEXT,
    confidence FLOAT,
    related_signals UUID[],
    human_reviewed BOOLEAN DEFAULT FALSE,
    human_notes TEXT,
    investigated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tracked entities (companies, projects, people of interest)
CREATE TABLE tracked_entities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(200) NOT NULL,
    type VARCHAR(50) NOT NULL,
    aliases JSONB DEFAULT '[]'::jsonb,
    metadata JSONB DEFAULT '{}'::jsonb,
    tracking_since TIMESTAMPTZ DEFAULT NOW()
);

-- Delivery log (track what was sent where)
CREATE TABLE delivery_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    channel VARCHAR(50) NOT NULL,
    delivery_type VARCHAR(50) NOT NULL,
    content_summary TEXT,
    signal_ids UUID[],
    delivered_at TIMESTAMPTZ DEFAULT NOW()
);
