# AI Infra Monitor — Design Spec

## Overview

A daily-running intelligence system for monitoring the AI infrastructure sector. Tracks companies, capital movements, open source activity, research, and tech direction across diverse sources. Combines deterministic data collection with agentic investigation and human-in-the-loop steering.

## Architecture

Two layers:

1. **Platform infrastructure** — reusable foundation (n8n + Dify + PostgreSQL on Docker)
2. **Workflow application** — the AI infra monitoring logic (sources, triage, investigation, delivery)

### Platform Infrastructure Layer

All services run locally on Docker Compose.

| Service | Role | Port |
|---|---|---|
| n8n | Orchestration, scheduling, integrations, delivery | 5678 |
| Dify | Agent workflows, RAG, investigation, human-in-the-loop | 3000 |
| PostgreSQL | Shared data store (raw signals, analysis results, metadata) | 5432 |
| Langfuse (optional) | LLM observability (traces, costs, latency) | 3001 |

**Communication patterns:**
- n8n → Dify: HTTP calls to Dify workflow API endpoints
- Dify → PostgreSQL: Stores analysis, agent memory, RAG knowledge base
- n8n → PostgreSQL: Writes raw collected signals, reads results for delivery
- External → n8n: Webhooks for real-time triggers

### Workflow Application Layer

Three phases run daily.

#### Phase 1: Collection (n8n, deterministic, scheduled)

Runs on cron (configurable, default 6am daily). Each source is an independent n8n sub-workflow.

**Source categories:**

| Category | Examples | Method |
|---|---|---|
| News & analysis | TechCrunch, The Information, Semafor AI, VentureBeat | RSS + HTTP scrape |
| Funding & deals | Crunchbase, PitchBook, SEC filings | API + scheduled scrape |
| Open source signals | GitHub trending, key repo releases, stars velocity | GitHub API |
| Company channels | Blogs/changelogs from tracked companies (OpenAI, Anthropic, Google DeepMind, Meta AI, Mistral, etc.) | RSS + webhook |
| Social & discourse | Twitter/X, Reddit r/LocalLLaMA r/MachineLearning, Hacker News | API + scrape |
| Research | arXiv cs.AI, cs.CL, cs.LG new submissions | arXiv API |
| User-curated sources | Custom list from existing monitoring | Provided by user |

**Common signal schema:**

```json
{
  "signal_id": "uuid",
  "source": "string (e.g. 'github', 'techcrunch', 'arxiv')",
  "source_category": "string (e.g. 'funding', 'release', 'paper', 'hiring')",
  "timestamp": "ISO 8601",
  "title": "string",
  "url": "string",
  "raw_content": "text",
  "entities": ["company names, people, projects mentioned"],
  "metadata": {
    "// source-specific fields": "",
    "stars": 0,
    "funding_amount": 0,
    "paper_authors": []
  }
}
```

All signals written to PostgreSQL `raw_signals` table.

#### Phase 2: Triage & Investigation (n8n + Dify, hybrid)

**Step 2a — LLM Triage (n8n node, fast/cheap model e.g. Haiku):**

Batch-processes new raw signals. For each signal:
- Assigns significance score 1-5 for the AI infra sector
- Tags category and urgency
- Extracts key entities if not already identified

Scoring criteria:
- 1-2: Background noise (routine update, minor repo activity)
- 3: Notable (meaningful release, modest funding, interesting paper)
- 4: Significant (major funding round, important product launch, key hire)
- 5: Critical (paradigm-shifting announcement, mega-deal, major pivot)

**Step 2b — Routing:**
- Score 1-3: Stored in DB, included in daily briefing summary
- Score 4-5: Forwarded to Dify investigation agent

**Step 2c — Dify Investigation Agent:**

Triggered via API for high-signal items. Agent workflow:

1. **Context gather** — Pull related signals from DB (same company, same category, recent)
2. **Cross-reference** — Check against tracked company list, known funding history, recent activity
3. **Investigate** — Follow links, search for additional context, check related sources
4. **Synthesize** — Produce structured analysis with confidence level
5. **Flag for human** — If uncertain, high-stakes, or contradictory signals → queue for human review

**Human-in-the-loop (Dify UI):**
- Review pending items flagged by the agent
- Confirm or dismiss assessments
- Add guidance for further investigation
- Redirect investigation angles
- Add new sources or companies to track

#### Phase 3: Delivery (n8n, deterministic)

| Output | Frequency | Channel | Content |
|---|---|---|---|
| Morning briefing | Daily | Telegram + Obsidian | Top signals, key moves, agent findings |
| Real-time alerts | Immediate | Telegram | Score 5 signals, critical events |
| Weekly digest | Weekly (Sunday) | Obsidian note | Trends, patterns, sector movement summary |
| Data accumulation | Continuous | PostgreSQL | All signals queryable for historical analysis |
| Dashboard | Future phase | Web UI | Visual overview of sector state |

## Database Schema (PostgreSQL)

### Core tables

```sql
-- Raw collected signals
raw_signals (
  id UUID PRIMARY KEY,
  source VARCHAR,
  source_category VARCHAR,
  title TEXT,
  url TEXT,
  raw_content TEXT,
  entities JSONB,
  metadata JSONB,
  collected_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
)

-- Triage results
triage_results (
  id UUID PRIMARY KEY,
  signal_id UUID REFERENCES raw_signals(id),
  significance_score INT CHECK (1 <= significance_score AND significance_score <= 5),
  category VARCHAR,
  urgency VARCHAR,
  triage_reasoning TEXT,
  triaged_at TIMESTAMPTZ DEFAULT NOW()
)

-- Agent investigation results
investigations (
  id UUID PRIMARY KEY,
  signal_id UUID REFERENCES raw_signals(id),
  analysis TEXT,
  confidence FLOAT,
  related_signals UUID[],
  human_reviewed BOOLEAN DEFAULT FALSE,
  human_notes TEXT,
  investigated_at TIMESTAMPTZ DEFAULT NOW()
)

-- Tracked entities (companies, projects, people)
tracked_entities (
  id UUID PRIMARY KEY,
  name VARCHAR,
  type VARCHAR, -- 'company', 'project', 'person'
  aliases JSONB,
  metadata JSONB,
  tracking_since TIMESTAMPTZ DEFAULT NOW()
)
```

## Implementation Sequence

1. **Docker Compose setup** — n8n + Dify + PostgreSQL running locally
2. **Database schema** — Create tables
3. **n8n: First collector** — Start with RSS/HN (simplest, proven pattern from discovery-engine)
4. **n8n: Triage node** — LLM classification of signals
5. **n8n: Briefing delivery** — Telegram + Obsidian output
6. **Dify: Investigation agent** — Basic workflow for high-signal items
7. **n8n → Dify integration** — Wire triage routing to Dify API
8. **Add more collectors** — GitHub, arXiv, funding sources, company blogs
9. **Human-in-the-loop** — Dify UI for review and steering
10. **Alerts** — Real-time Telegram push for score-5 signals
11. **Weekly digest** — Aggregation and trend analysis workflow
12. **Dashboard** — Future: web UI over accumulated data

## Key Decisions

- **n8n for orchestration, Dify for intelligence** — each platform used for its strength
- **PostgreSQL as shared data layer** — both platforms read/write, single source of truth
- **Haiku for triage, stronger model for investigation** — cost optimization at scale
- **Signal schema is source-agnostic** — new sources plug in without schema changes
- **Each collector is independent** — can be enabled/disabled/tuned without affecting others
- **Human-in-the-loop at investigation, not collection** — don't bottleneck the sweep

## Open Questions

- Which specific companies to track at launch? (User to provide initial list)
- Existing source list from current monitoring? (User to provide)
- Preferred briefing time? (Default: 6am local)
- Telegram bot: reuse existing or create new?
- Budget constraints for LLM API costs?
