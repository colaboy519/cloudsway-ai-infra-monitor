# AI Infra Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a daily AI infrastructure sector monitoring system using n8n (orchestration) + Dify (intelligence) + PostgreSQL (shared data), with end-to-end signal collection → triage → delivery.

**Architecture:** Docker Compose runs all services locally. n8n handles scheduled collection from RSS/APIs, LLM-based triage, and delivery to Telegram/Obsidian. Dify handles agentic investigation of high-signal items. PostgreSQL is the shared data layer.

**Tech Stack:** Docker Compose, n8n, Dify, PostgreSQL, Anthropic API (Haiku for triage, Sonnet/Opus for investigation)

**Spec:** `docs/superpowers/specs/2026-03-23-ai-infra-monitor-design.md`

---

## File Structure

```
ai-infra-monitor/
├── docker-compose.yml              # All services: n8n, Dify, PostgreSQL, Redis
├── .env                             # API keys, ports, credentials (gitignored)
├── .env.example                     # Template for .env
├── .gitignore
├── db/
│   └── init.sql                     # Schema: raw_signals, triage_results, investigations, tracked_entities
├── n8n/
│   ├── workflows/                   # Exported n8n workflow JSON files (version controlled)
│   │   ├── 01-rss-collector.json
│   │   ├── 02-hn-collector.json
│   │   ├── 03-github-collector.json
│   │   ├── 04-arxiv-collector.json
│   │   ├── 10-triage-router.json
│   │   ├── 20-daily-briefing.json
│   │   ├── 21-realtime-alerts.json
│   │   └── 22-weekly-digest.json
│   └── credentials/                 # Credential templates (no secrets)
├── dify/
│   └── workflows/                   # Exported Dify workflow DSL files
│       └── investigation-agent.yml
├── scripts/
│   ├── seed-entities.sql            # Initial tracked companies/projects
│   ├── test-pipeline.sh             # End-to-end smoke test
│   └── export-workflows.sh          # Export n8n/Dify workflows to version control
├── docs/
│   ├── superpowers/
│   │   ├── specs/
│   │   │   └── 2026-03-23-ai-infra-monitor-design.md
│   │   └── plans/
│   │       └── 2026-03-23-ai-infra-monitor-plan.md
│   └── sources.md                   # Curated source list (user provides)
└── dev-log.md
```

**Key point:** n8n and Dify workflows are built in their respective UIs, then exported to JSON/YAML for version control. The `n8n/workflows/` and `dify/workflows/` directories are *exports*, not source-of-truth — the running instances are the source of truth during development.

---

## Task 1: Docker Compose — Get All Services Running

**Files:**
- Create: `docker-compose.yml`
- Create: `.env.example`
- Create: `.env` (gitignored)
- Create: `.gitignore`

- [ ] **Step 1: Create .gitignore**

```gitignore
.env
n8n/data/
dify/data/
postgres-data/
*.pyc
__pycache__/
```

- [ ] **Step 2: Create .env.example with all required variables**

```env
# PostgreSQL
POSTGRES_USER=aimonitor
POSTGRES_PASSWORD=changeme
POSTGRES_DB=ai_infra_monitor

# n8n
N8N_PORT=5678
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=changeme
N8N_ENCRYPTION_KEY=generate-a-random-key

# Dify
DIFY_PORT=3000

# API Keys (for n8n LLM nodes and Dify)
ANTHROPIC_API_KEY=sk-ant-...
```

- [ ] **Step 3: Create docker-compose.yml**

```yaml
services:
  postgres:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    ports:
      - "6379:6379"

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - GENERIC_TIMEZONE=Asia/Shanghai
    ports:
      - "${N8N_PORT:-5678}:5678"
    volumes:
      - n8n-data:/home/node/.n8n
      - ~/shared/vault:/shared/vault  # Obsidian vault for briefing/digest writes
    depends_on:
      postgres:
        condition: service_healthy

  # Dify uses its own docker-compose internally.
  # We integrate by running Dify's compose alongside ours,
  # or embedding its services. See Step 5 for approach.

volumes:
  postgres-data:
  n8n-data:
```

**Note on Dify:** Dify's official deployment uses its own `docker-compose.yml` with ~10 services (API, worker, web, sandbox, weaviate, etc.). Rather than embedding all of them, we have two options:
- **Option A:** Run Dify's compose separately alongside ours, sharing the same Docker network
- **Option B:** Use Dify Cloud free tier for the intelligence layer, keep local compose simple

The implementer should check Dify's current install docs and choose based on Mac resource constraints.

- [ ] **Step 4: Create placeholder db/init.sql**

```sql
-- Create separate database for n8n internal state (keeps it isolated from app data)
SELECT 'CREATE DATABASE n8n' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')\gexec

-- Placeholder for app schema, will be populated in Task 2
SELECT 1;
```

- [ ] **Step 5: Start services and verify**

```bash
cd ~/dev/active/ai-infra-monitor
cp .env.example .env
# Edit .env with real values

docker compose up -d postgres redis n8n
```

Verify:
- `docker compose ps` — all services healthy
- Open http://localhost:5678 — n8n login page loads
- `psql postgresql://aimonitor:changeme@localhost:5432/ai_infra_monitor -c 'SELECT 1'` — returns 1

- [ ] **Step 6: Set up Dify**

**Recommended: Start with Dify Cloud** (de-risks initial build — Dify's local docker-compose runs ~10 services which is heavy on Mac resources. Migrate to self-hosted later if needed.)

1. Sign up at cloud.dify.ai
2. Create a workspace
3. Note the API base URL (e.g. `https://api.dify.ai/v1`)
4. Add `DIFY_API_URL` and `DIFY_API_KEY` to `.env`

**Alternative: Local Docker (if you have 32GB+ RAM):**
```bash
git clone https://github.com/langgenius/dify.git ~/dev/tools/dify
cd ~/dev/tools/dify/docker
cp .env.example .env
docker compose up -d
```
Verify: Open http://localhost:3000 — Dify setup page loads

- [ ] **Step 7: Commit**

```bash
git add docker-compose.yml .env.example .gitignore db/init.sql
git commit -m "feat: Docker Compose setup for n8n + PostgreSQL + Redis"
```

---

## Task 2: Database Schema

**Files:**
- Create: `db/init.sql`
- Create: `scripts/seed-entities.sql`

- [ ] **Step 1: Write the schema in db/init.sql**

```sql
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
    type VARCHAR(50) NOT NULL, -- 'company', 'project', 'person'
    aliases JSONB DEFAULT '[]'::jsonb,
    metadata JSONB DEFAULT '{}'::jsonb,
    tracking_since TIMESTAMPTZ DEFAULT NOW()
);

-- Delivery log (track what was sent where)
CREATE TABLE delivery_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    channel VARCHAR(50) NOT NULL, -- 'telegram', 'obsidian', 'email'
    delivery_type VARCHAR(50) NOT NULL, -- 'briefing', 'alert', 'digest'
    content_summary TEXT,
    signal_ids UUID[],
    delivered_at TIMESTAMPTZ DEFAULT NOW()
);
```

- [ ] **Step 2: Write seed data for initial tracked entities**

```sql
-- scripts/seed-entities.sql
-- Initial AI infra companies to track
INSERT INTO tracked_entities (name, type, aliases, metadata) VALUES
('OpenAI', 'company', '["openai"]', '{"sector": "foundation_models"}'),
('Anthropic', 'company', '["anthropic"]', '{"sector": "foundation_models"}'),
('Google DeepMind', 'company', '["deepmind", "google ai"]', '{"sector": "foundation_models"}'),
('Meta AI', 'company', '["meta fair", "llama"]', '{"sector": "foundation_models"}'),
('Mistral AI', 'company', '["mistral"]', '{"sector": "foundation_models"}'),
('Cohere', 'company', '["cohere"]', '{"sector": "foundation_models"}'),
('Databricks', 'company', '["mosaic ml", "dbrx"]', '{"sector": "infra_platform"}'),
('Hugging Face', 'company', '["huggingface", "hf"]', '{"sector": "infra_platform"}'),
('NVIDIA', 'company', '["nvidia"]', '{"sector": "compute"}'),
('AMD', 'company', '["amd"]', '{"sector": "compute"}'),
('Groq', 'company', '["groq"]', '{"sector": "inference"}'),
('Together AI', 'company', '["together"]', '{"sector": "inference"}'),
('Fireworks AI', 'company', '["fireworks"]', '{"sector": "inference"}'),
('Anyscale', 'company', '["anyscale", "ray"]', '{"sector": "infra_platform"}'),
('LangChain', 'company', '["langchain", "langsmith"]', '{"sector": "tooling"}'),
('LlamaIndex', 'company', '["llamaindex"]', '{"sector": "tooling"}'),
('Weights & Biases', 'company', '["wandb"]', '{"sector": "mlops"}'),
('Scale AI', 'company', '["scale"]', '{"sector": "data"}'),
('Replit', 'company', '["replit"]', '{"sector": "ai_coding"}'),
('Cursor', 'company', '["cursor", "anysphere"]', '{"sector": "ai_coding"}');
```

- [ ] **Step 3: Apply schema (recreate postgres container to trigger init.sql)**

```bash
cd ~/dev/active/ai-infra-monitor
docker compose down -v  # Remove old volume to re-run init
docker compose up -d postgres
# Wait for healthy
docker compose exec postgres psql -U aimonitor -d ai_infra_monitor -c '\dt'
```

Expected: 5 tables listed (raw_signals, triage_results, investigations, tracked_entities, delivery_log)

- [ ] **Step 4: Run seed data**

```bash
docker compose exec -T postgres psql -U aimonitor -d ai_infra_monitor < scripts/seed-entities.sql
docker compose exec postgres psql -U aimonitor -d ai_infra_monitor -c 'SELECT name, type FROM tracked_entities LIMIT 5'
```

Expected: 5 company rows returned

- [ ] **Step 5: Commit**

```bash
git add db/init.sql scripts/seed-entities.sql
git commit -m "feat: database schema and initial tracked entities seed"
```

---

## Task 3: First n8n Collector — Hacker News

Build the simplest collector to prove the pipeline end-to-end. HN is ideal: free API, no auth, AI content is frequent.

**Files:**
- Create: `n8n/workflows/02-hn-collector.json` (exported after building in UI)

- [ ] **Step 1: Open n8n UI and create new workflow "HN Collector"**

Open http://localhost:5678, create a new workflow. Add these nodes:

1. **Schedule Trigger** — Cron: every 6 hours (for testing; change to daily later)
2. **HTTP Request** — GET `https://hacker-news.firebaseio.com/v0/topstories.json` → returns array of IDs
3. **Split In Batches** — Take first 30 story IDs
4. **HTTP Request** — GET `https://hacker-news.firebaseio.com/v0/item/{{$json.id}}.json` → story details
5. **Filter** — Keep only stories with score > 50 (reduce noise)
6. **Code Node** — Transform to signal schema:

```javascript
// Code node: Transform HN story to signal schema
const item = $input.item.json;
const title = item.title || '';
const url = item.url || `https://news.ycombinator.com/item?id=${item.id}`;
const crypto = require('crypto');
const content_hash = crypto.createHash('sha256')
  .update(`${title.toLowerCase().trim()}|hn`)
  .digest('hex');

return {
  json: {
    source: 'hackernews',
    source_category: 'social',
    title: title,
    url: url,
    raw_content: title,
    entities: [],
    metadata: {
      hn_id: item.id,
      score: item.score,
      comments: item.descendants || 0,
      by: item.by
    },
    collected_at: new Date(item.time * 1000).toISOString(),
    content_hash: content_hash
  }
};
```

7. **Postgres Node** — INSERT into raw_signals (use "Insert" operation, handle conflict on url with DO NOTHING)

- [ ] **Step 2: Configure PostgreSQL credentials in n8n**

In n8n Settings → Credentials → Add "Postgres":
- Host: `postgres` (Docker service name)
- Port: 5432
- Database: `ai_infra_monitor`
- User: `aimonitor`
- Password: (from .env)

- [ ] **Step 3: Test the workflow manually**

Click "Test Workflow" in n8n. Check:
- Each node shows green checkmark
- Final Postgres node shows rows inserted

Verify in DB:
```bash
docker compose exec postgres psql -U aimonitor -d ai_infra_monitor \
  -c "SELECT source, title, (metadata->>'score')::int as score FROM raw_signals ORDER BY collected_at DESC LIMIT 5"
```

Expected: 5+ HN stories with scores

- [ ] **Step 4: Activate the workflow**

Toggle workflow to Active in n8n UI. It will now run on the cron schedule.

- [ ] **Step 5: Export workflow and commit**

```bash
# Export via n8n CLI or API
curl -u admin:changeme http://localhost:5678/api/v1/workflows \
  | python3 -c "import sys,json; wfs=json.load(sys.stdin)['data']; [open(f'n8n/workflows/02-hn-collector.json','w').write(json.dumps(w, indent=2)) for w in wfs if 'HN' in w.get('name','')]"

git add n8n/workflows/02-hn-collector.json
git commit -m "feat: HN collector workflow — first source online"
```

---

## Task 4: Dedup + LLM Triage Workflow (n8n)

**Files:**
- Create: `n8n/workflows/10-triage-router.json` (exported after building)

The triage workflow first deduplicates new signals, then triages the unique ones.

- [ ] **Step 1: Create new n8n workflow "Triage Router"**

Nodes:

**Dedup phase:**

1. **Schedule Trigger** — Runs every hour (processes new untriaged signals)
2. **Postgres Node** — Find signals that need dedup check:

```sql
UPDATE raw_signals new_sig
SET duplicate_of = existing.id
FROM raw_signals existing
WHERE new_sig.duplicate_of IS NULL
  AND existing.id != new_sig.id
  AND existing.created_at < new_sig.created_at
  AND (existing.url = new_sig.url OR existing.content_hash = new_sig.content_hash)
RETURNING new_sig.id, existing.id as original_id, new_sig.title
```

This links duplicate signals to the original rather than deleting them — multi-source coverage is itself a relevance signal.

**Triage phase:**

3. **Postgres Node** — Query untriaged, non-duplicate signals:

```sql
SELECT rs.* FROM raw_signals rs
LEFT JOIN triage_results tr ON rs.id = tr.signal_id
WHERE tr.id IS NULL AND rs.duplicate_of IS NULL
ORDER BY rs.collected_at DESC
LIMIT 20
```

4. **IF Node** — Check if any results returned (skip if empty)
5. **Code Node** — Build prompt for batch triage:

```javascript
const signals = $input.all().map(item => item.json);
const prompt = `You are an AI infrastructure sector analyst. Score each signal 1-5 for significance to someone tracking AI infra companies, compute, tooling, and capital flows.

Scoring:
1-2: Background noise
3: Notable (meaningful release, modest funding)
4: Significant (major funding, important launch, key hire)
5: Critical (paradigm shift, mega-deal, major pivot)

For each signal, return JSON:
{"signal_id": "...", "score": N, "category": "funding|release|paper|hiring|partnership|regulation|other", "urgency": "low|medium|high", "reasoning": "one sentence"}

Signals:
${signals.map((s, i) => `[${i+1}] id=${s.id} source=${s.source} title="${s.title}"`).join('\n')}

Return a JSON array of objects. Nothing else.`;

return { json: { prompt, signal_count: signals.length } };
```

6. **HTTP Request Node** — POST to Anthropic API (Claude Haiku):

```
URL: https://api.anthropic.com/v1/messages
Method: POST
Headers:
  x-api-key: {{$env.ANTHROPIC_API_KEY}}
  anthropic-version: 2023-06-01
  content-type: application/json
Body:
{
  "model": "claude-haiku-4-5-20251001",
  "max_tokens": 4096,
  "messages": [{"role": "user", "content": "{{$json.prompt}}"}]
}
```

7. **Code Node** — Parse response and prepare inserts:

```javascript
const response = $input.item.json;
const content = response.content[0].text;

// Extract JSON from response — handles markdown code blocks or raw JSON
let jsonStr = content;
const match = content.match(/```(?:json)?\s*([\s\S]*?)```/);
if (match) jsonStr = match[1];
// Also try bare array extraction
if (!jsonStr.trim().startsWith('[')) {
  const arrMatch = jsonStr.match(/\[[\s\S]*\]/);
  if (arrMatch) jsonStr = arrMatch[0];
}

let results;
try {
  results = JSON.parse(jsonStr.trim());
} catch (e) {
  console.error('Failed to parse triage response:', content);
  return []; // Skip this batch rather than crash the workflow
}

return results.map(r => ({
  json: {
    signal_id: r.signal_id,
    significance_score: r.score,
    category: r.category,
    urgency: r.urgency,
    triage_reasoning: r.reasoning
  }
}));
```

8. **Split In Batches** — Process each triage result
9. **Postgres Node** — INSERT into triage_results
10. **IF Node** — Score >= 4?
   - **Yes** → HTTP Request to Dify API (placeholder — wired in Task 6)
   - **No** → End

- [ ] **Step 2: Test with existing HN data**

Run the triage workflow manually. Verify:
```bash
docker compose exec postgres psql -U aimonitor -d ai_infra_monitor \
  -c "SELECT rs.title, tr.significance_score, tr.category FROM triage_results tr JOIN raw_signals rs ON tr.signal_id = rs.id ORDER BY tr.significance_score DESC LIMIT 10"
```

Expected: Signals scored 1-5 with categories

- [ ] **Step 3: Export and commit**

```bash
# Export workflow
git add n8n/workflows/10-triage-router.json
git commit -m "feat: LLM triage workflow — Haiku scores and routes signals"
```

---

## Task 5: Daily Briefing Delivery (n8n → Telegram + Obsidian)

**Files:**
- Create: `n8n/workflows/20-daily-briefing.json`

- [ ] **Step 1: Create Telegram bot (if not reusing existing)**

Message @BotFather on Telegram → /newbot → name it "AI Infra Monitor" → save token to .env as `TELEGRAM_BOT_TOKEN` and your chat ID as `TELEGRAM_CHAT_ID`.

- [ ] **Step 2: Create n8n workflow "Daily Briefing"**

Nodes:

1. **Schedule Trigger** — Cron: daily at 06:00 Asia/Shanghai
2. **Postgres Node** — Fetch today's triaged signals:

```sql
SELECT rs.title, rs.url, rs.source, tr.significance_score, tr.category, tr.triage_reasoning
FROM triage_results tr
JOIN raw_signals rs ON tr.signal_id = rs.id
WHERE tr.triaged_at >= CURRENT_DATE
ORDER BY tr.significance_score DESC, tr.triaged_at DESC
```

3. **Code Node** — Format briefing message:

```javascript
const signals = $input.all().map(i => i.json);
const now = new Date().toISOString().split('T')[0];

const highSignal = signals.filter(s => s.significance_score >= 4);
const notable = signals.filter(s => s.significance_score === 3);
const routine = signals.filter(s => s.significance_score <= 2);

let msg = `🔍 *AI Infra Daily Briefing — ${now}*\n`;
msg += `${signals.length} signals collected | ${highSignal.length} high-signal | ${notable.length} notable\n\n`;

if (highSignal.length > 0) {
  msg += `*⚡ HIGH SIGNAL*\n`;
  highSignal.forEach(s => {
    msg += `• [${s.category}] ${s.title}\n  ${s.triage_reasoning}\n  ${s.url}\n\n`;
  });
}

if (notable.length > 0) {
  msg += `*📌 NOTABLE*\n`;
  notable.slice(0, 10).forEach(s => {
    msg += `• [${s.category}] ${s.title}\n  ${s.url}\n`;
  });
  msg += '\n';
}

msg += `_${routine.length} routine signals archived_`;

return { json: { telegram_message: msg, obsidian_content: msg.replace(/\*/g, '**') } };
```

4. **Telegram Node** — Send message to your chat (use Telegram credentials with bot token)
5. **Write to Obsidian** — Use n8n's "Execute Command" node to write the briefing as a markdown file:

```bash
# Writes to the user's Obsidian vault at ~/shared/vault/
cat > /shared/vault/projects/ai-infra-monitor/briefings/{{$now.format('YYYY-MM-DD')}}-briefing.md << 'BRIEFING'
{{$json.obsidian_content}}
BRIEFING
```

Or use the "Write Binary File" node to write directly to `/shared/vault/projects/ai-infra-monitor/briefings/YYYY-MM-DD-briefing.md` (container path, mapped to `~/shared/vault/` on host via docker-compose bind mount). Ensure the directory exists on the host before starting.

- [ ] **Step 3: Test manually**

Trigger the workflow. Check:
- Telegram message received with formatted briefing
- Obsidian note created/appended

- [ ] **Step 4: Export and commit**

```bash
git add n8n/workflows/20-daily-briefing.json
git commit -m "feat: daily briefing delivery to Telegram and Obsidian"
```

---

## Task 6: Dify Investigation Agent

**Files:**
- Create: `dify/workflows/investigation-agent.yml` (exported after building)

- [ ] **Step 1: Set up Dify workspace**

Open Dify UI (http://localhost:3000 or cloud.dify.ai):
1. Create a new App → type "Agent"
2. Name: "AI Infra Investigator"
3. Set system prompt:

```
You are an AI infrastructure sector intelligence analyst. You receive high-signal items (score 4-5) about the AI infra sector and investigate them deeply.

Your job:
1. Understand what happened and why it matters
2. Cross-reference with known context about the company/project
3. Assess implications for the AI infra landscape
4. Rate your confidence in the analysis (0.0-1.0)
5. Flag if human review is needed (contradictory signals, high stakes, or low confidence)

Output structured JSON:
{
  "summary": "2-3 sentence analysis",
  "implications": ["implication 1", "implication 2"],
  "confidence": 0.85,
  "needs_human_review": false,
  "review_reason": null,
  "related_topics": ["topic1", "topic2"]
}
```

4. Add tools:
   - **Web Search** (built-in) — for following leads
   - **HTTP Request** — for fetching URLs
   - **Database Query** (if Dify supports PostgreSQL plugin) — for cross-referencing signals

5. Set model: Claude Sonnet (balance of quality and cost)

- [ ] **Step 2: Test with a manual query**

In Dify's chat interface, paste a sample high-signal item:
```
Investigate: "Anthropic raises $5B Series D at $60B valuation" (source: TechCrunch, score: 5, category: funding)
```

Verify the agent:
- Searches for additional context
- Produces structured JSON output
- Confidence score is reasonable

- [ ] **Step 3: Get the Dify API endpoint**

In Dify App settings → API Access:
- Note the API endpoint URL
- Generate an API key
- Add to .env as `DIFY_API_KEY` and `DIFY_API_URL`

- [ ] **Step 4: Test API call from command line**

```bash
curl -X POST "${DIFY_API_URL}/chat-messages" \
  -H "Authorization: Bearer ${DIFY_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": {},
    "query": "Investigate: Anthropic raises $5B Series D at $60B valuation",
    "response_mode": "blocking",
    "user": "n8n-pipeline"
  }'
```

Expected: JSON response with investigation analysis

- [ ] **Step 5: Commit Dify workflow export**

```bash
# Export from Dify UI (Settings → Export DSL)
# Save to dify/workflows/investigation-agent.yml
git add dify/workflows/investigation-agent.yml
git commit -m "feat: Dify investigation agent for high-signal items"
```

---

## Task 7: Wire n8n → Dify Integration

**Files:**
- Modify: `n8n/workflows/10-triage-router.json` (update the score>=4 branch)

- [ ] **Step 1: Update triage workflow's high-signal branch**

In n8n, edit the "Triage Router" workflow. On the Score >= 4 branch, add:

1. **Code Node** — Format Dify request:

```javascript
const signal = $input.item.json;
const query = `Investigate this high-signal AI infra item:
Title: ${signal.title}
Source: ${signal.source}
Category: ${signal.category}
Score: ${signal.significance_score}
URL: ${signal.url}
Reasoning: ${signal.triage_reasoning}`;

return { json: { query, signal_id: signal.signal_id } };
```

2. **HTTP Request Node** — POST to Dify API:
   - URL: `{{$env.DIFY_API_URL}}/chat-messages`
   - Auth: Bearer `{{$env.DIFY_API_KEY}}`
   - Body: `{"inputs": {}, "query": "{{$json.query}}", "response_mode": "blocking", "user": "n8n-pipeline"}`

3. **Code Node** — Parse Dify response and prepare DB insert
4. **Postgres Node** — INSERT into investigations table

- [ ] **Step 2: Test end-to-end**

1. Manually trigger HN collector → verify signals in DB
2. Manually trigger triage → verify scores
3. If any score >= 4, verify Dify investigation triggered and result stored

```bash
docker compose exec postgres psql -U aimonitor -d ai_infra_monitor \
  -c "SELECT i.analysis, i.confidence, rs.title FROM investigations i JOIN raw_signals rs ON i.signal_id = rs.id LIMIT 5"
```

- [ ] **Step 3: Export and commit**

```bash
git add n8n/workflows/10-triage-router.json
git commit -m "feat: wire n8n triage to Dify investigation for high-signal items"
```

---

## Task 8a: RSS Collector

**Files:**
- Create: `n8n/workflows/01-rss-collector.json`

- [ ] **Step 1: Build RSS Collector workflow in n8n**

New n8n workflow "RSS Collector":
1. Schedule Trigger — every 6 hours
2. RSS Feed Read nodes (parallel) for each feed:
   - https://techcrunch.com/category/artificial-intelligence/feed/
   - https://venturebeat.com/category/ai/feed/
   - (Add user's curated RSS feeds here — including company blogs for OpenAI, Anthropic, etc.)
3. Merge node — combine all items
4. Code node — transform to signal schema (same pattern as HN collector)
5. Postgres node — INSERT with conflict handling

Test: Run manually, verify signals in DB with source='rss'

- [ ] **Step 2: Export and commit**

```bash
git add n8n/workflows/01-rss-collector.json
git commit -m "feat: RSS collector for AI news and company blogs"
```

---

## Task 8b: GitHub Collector

**Files:**
- Create: `n8n/workflows/03-github-collector.json`

- [ ] **Step 1: Build GitHub Collector workflow in n8n**

New n8n workflow "GitHub Collector":
1. Schedule Trigger — daily
2. HTTP Request — Use GitHub Search API (NOT trending page scraping):

```
GET https://api.github.com/search/repositories?q=created:>{{$now.minus(7,'days').format('YYYY-MM-DD')}}+topic:machine-learning+topic:llm&sort=stars&order=desc&per_page=30
```

Also search for: `topic:ai`, `topic:deep-learning`, `topic:transformers`

3. HTTP Request — For each repo, GET `/repos/{owner}/{name}` for full stats
4. Code node — Calculate stars velocity (stars / days_since_creation)
5. Filter — Keep repos with velocity > 10 stars/day or total stars > 100
6. Code node — Transform to signal schema
7. Postgres node — INSERT

Test: Run manually, verify signals in DB with source='github'

- [ ] **Step 2: Export and commit**

```bash
git add n8n/workflows/03-github-collector.json
git commit -m "feat: GitHub collector using Search API for new AI repos"
```

---

## Task 8c: arXiv Collector

**Files:**
- Create: `n8n/workflows/04-arxiv-collector.json`

- [ ] **Step 1: Build arXiv Collector workflow in n8n**

New n8n workflow "arXiv Collector":
1. Schedule Trigger — daily
2. HTTP Request — Query arXiv API for recent AI papers:

```
GET http://export.arxiv.org/api/query?search_query=cat:cs.AI+OR+cat:cs.CL+OR+cat:cs.LG&start=0&max_results=30&sortBy=submittedDate&sortOrder=descending
```

3. Code node — Parse Atom XML response, extract papers:

```javascript
const xml = $input.item.json.data;
// n8n has XML parsing — use the XML node or parse in code
// Extract: title, authors, abstract, arxiv_id, categories, published date
```

4. Code node — Transform to signal schema with source='arxiv', source_category='paper'
5. Postgres node — INSERT

Test: Run manually, verify signals in DB with source='arxiv'

- [ ] **Step 2: Export and commit**

```bash
git add n8n/workflows/04-arxiv-collector.json
git commit -m "feat: arXiv collector for cs.AI/cs.CL/cs.LG papers"
```

---

## Task 9: Real-Time Alerts (n8n)

**Files:**
- Create: `n8n/workflows/21-realtime-alerts.json`

- [ ] **Step 1: Create alert workflow**

Modify the triage workflow to also trigger an immediate alert path for score-5 signals:

1. In the triage router, after the score >= 4 IF node, add another IF: score === 5?
2. **Yes** → Telegram Node — Send immediate alert:

```javascript
const s = $input.item.json;
const msg = `🚨 *CRITICAL AI INFRA SIGNAL*\n\n` +
  `*${s.title}*\n` +
  `Category: ${s.category}\n` +
  `${s.triage_reasoning}\n\n` +
  `${s.url}`;
return { json: { message: msg } };
```

- [ ] **Step 2: Test by inserting a fake score-5 signal**

```bash
docker compose exec -T postgres psql -U aimonitor -d ai_infra_monitor <<'SQL'
INSERT INTO raw_signals (source, source_category, title, url, raw_content, collected_at, content_hash)
VALUES ('test', 'funding', 'TEST: Major AI company raises $10B', 'https://example.com/test', 'test content', NOW(), 'test_hash_alert');
SQL
```

Trigger triage manually. If scored 5, verify Telegram alert received.

- [ ] **Step 3: Export and commit**

```bash
git add n8n/workflows/21-realtime-alerts.json
git commit -m "feat: real-time Telegram alerts for critical (score 5) signals"
```

---

## Task 10: End-to-End Smoke Test Script

**Files:**
- Create: `scripts/test-pipeline.sh`
- Create: `scripts/export-workflows.sh`

- [ ] **Step 1: Write smoke test script**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== AI Infra Monitor — Smoke Test ==="

# 1. Check services
echo "Checking services..."
docker compose ps --format json | python3 -c "
import sys, json
for line in sys.stdin:
    svc = json.loads(line)
    status = svc.get('Health', svc.get('State', 'unknown'))
    print(f\"  {svc['Service']}: {status}\")
"

# 2. Check DB tables
echo "Checking database..."
TABLE_COUNT=$(docker compose exec -T postgres psql -U aimonitor -d ai_infra_monitor -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
echo "  Tables: $TABLE_COUNT"

# 3. Check signal count
SIGNAL_COUNT=$(docker compose exec -T postgres psql -U aimonitor -d ai_infra_monitor -t -c "SELECT count(*) FROM raw_signals")
echo "  Raw signals: $SIGNAL_COUNT"

# 4. Check triage count
TRIAGE_COUNT=$(docker compose exec -T postgres psql -U aimonitor -d ai_infra_monitor -t -c "SELECT count(*) FROM triage_results")
echo "  Triaged signals: $TRIAGE_COUNT"

# 5. Check n8n is responsive
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/healthz)
echo "  n8n health: HTTP $HTTP_CODE"

echo "=== Done ==="
```

- [ ] **Step 2: Write workflow export script**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Exporting n8n workflows..."
mkdir -p n8n/workflows

# Export all workflows via n8n API
curl -s -u "${N8N_BASIC_AUTH_USER}:${N8N_BASIC_AUTH_PASSWORD}" \
  http://localhost:5678/api/v1/workflows | \
  python3 -c "
import sys, json, re
data = json.load(sys.stdin)
for wf in data.get('data', []):
    name = re.sub(r'[^a-z0-9]+', '-', wf['name'].lower()).strip('-')
    path = f'n8n/workflows/{name}.json'
    with open(path, 'w') as f:
        json.dump(wf, f, indent=2)
    print(f'  Exported: {path}')
"

echo "Done. Remember to git add and commit."
```

- [ ] **Step 3: Make scripts executable and commit**

```bash
chmod +x scripts/test-pipeline.sh scripts/export-workflows.sh
git add scripts/
git commit -m "feat: smoke test and workflow export scripts"
```

---

## Task 11: Documentation and Dev Log

**Files:**
- Create: `docs/sources.md`
- Update: `dev-log.md`
- Update: `README.md` (if exists)

- [ ] **Step 1: Create sources documentation template**

```markdown
# AI Infra Monitor — Source List

## Active Sources

| Source | Category | Method | Frequency | n8n Workflow |
|---|---|---|---|---|
| Hacker News | Social | API | 6h | 02-hn-collector |
| TechCrunch AI | News | RSS | 6h | 01-rss-collector |
| VentureBeat AI | News | RSS | 6h | 01-rss-collector |
| GitHub AI repos | Open Source | Search API | Daily | 03-github-collector |
| arXiv cs.AI/CL/LG | Research | API | Daily | 04-arxiv-collector |

## Planned Sources (User to Provide)

- [ ] User's curated monitoring list
- [ ] Crunchbase / funding data
- [ ] Twitter/X accounts
- [ ] Reddit r/LocalLLaMA, r/MachineLearning

## Adding a New Source

1. Create new n8n workflow or add RSS feed to existing RSS collector
2. Transform output to signal schema (see spec for schema)
3. Test manually, then activate on schedule
4. Export workflow: `./scripts/export-workflows.sh`
5. Update this table
```

- [ ] **Step 2: Update dev-log.md**

Add entry documenting the initial build.

- [ ] **Step 3: Commit**

```bash
git add docs/sources.md dev-log.md
git commit -m "docs: source list and dev log for initial build"
```

- [ ] **Step 4: Push to GitHub**

```bash
git push origin main
```

---

## Task 12: Weekly Digest (n8n)

**Files:**
- Create: `n8n/workflows/22-weekly-digest.json`

- [ ] **Step 1: Create n8n workflow "Weekly Digest"**

Nodes:

1. **Schedule Trigger** — Cron: every Sunday at 09:00 Asia/Shanghai
2. **Postgres Node** — Aggregate the week's data:

```sql
SELECT
  tr.category,
  COUNT(*) as signal_count,
  COUNT(*) FILTER (WHERE tr.significance_score >= 4) as high_signal_count,
  ARRAY_AGG(DISTINCT rs.source) as sources
FROM triage_results tr
JOIN raw_signals rs ON tr.signal_id = rs.id
WHERE tr.triaged_at >= NOW() - INTERVAL '7 days'
GROUP BY tr.category
ORDER BY high_signal_count DESC
```

3. **Postgres Node** — Get top signals of the week:

```sql
SELECT rs.title, rs.url, rs.source, tr.significance_score, tr.category,
       i.analysis, i.confidence
FROM triage_results tr
JOIN raw_signals rs ON tr.signal_id = rs.id
LEFT JOIN investigations i ON rs.id = i.signal_id
WHERE tr.triaged_at >= NOW() - INTERVAL '7 days'
ORDER BY tr.significance_score DESC, tr.triaged_at DESC
LIMIT 20
```

4. **HTTP Request Node** — Call Anthropic API (Sonnet) to synthesize trends:

Prompt: "You are an AI infra sector analyst. Given this week's top signals, write a 3-paragraph weekly digest covering: (1) Key events and why they matter, (2) Emerging trends and patterns, (3) What to watch next week. Be concise and opinionated."

5. **Code Node** — Format as Obsidian note with frontmatter:

```javascript
const now = new Date();
const weekStart = new Date(now - 7*24*60*60*1000).toISOString().split('T')[0];
const weekEnd = now.toISOString().split('T')[0];
const synthesis = $input.item.json.content[0].text;
const stats = $('Postgres').all(); // category stats

let note = `---\ntype: weekly-digest\nperiod: ${weekStart} to ${weekEnd}\n---\n\n`;
note += `# AI Infra Weekly Digest: ${weekStart} → ${weekEnd}\n\n`;
note += synthesis + '\n\n';
note += `## Signal Breakdown\n\n| Category | Signals | High-Signal |\n|---|---|---|\n`;
stats.forEach(s => {
  note += `| ${s.json.category} | ${s.json.signal_count} | ${s.json.high_signal_count} |\n`;
});

return { json: { content: note, filename: `${weekEnd}-weekly-digest.md` } };
```

6. **Execute Command Node** — Write to Obsidian vault:

```bash
cat > /shared/vault/projects/ai-infra-monitor/digests/{{$json.filename}} << 'EOF'
{{$json.content}}
EOF
```

- [ ] **Step 2: Test manually**

Trigger the workflow. Verify:
- Obsidian note created at `~/shared/vault/projects/ai-infra-monitor/digests/` (host path)
- Contains trend synthesis and signal breakdown table

- [ ] **Step 3: Export and commit**

```bash
git add n8n/workflows/22-weekly-digest.json
git commit -m "feat: weekly digest with LLM trend synthesis to Obsidian"
```

---

## Execution Order Summary

| Task | Depends On | Delivers |
|---|---|---|
| 1. Docker Compose | — | Services running |
| 2. Database Schema | 1 | Tables + seed data |
| 3. HN Collector | 1, 2 | First signals in DB |
| 4. Dedup + LLM Triage | 2, 3 | Deduped, scored signals |
| 5. Daily Briefing | 4 | Telegram + Obsidian delivery |
| 6. Dify Agent | 1 | Investigation capability |
| 7. n8n → Dify Wire | 4, 6 | End-to-end pipeline |
| 8a. RSS Collector | 2 | News + company blog coverage |
| 8b. GitHub Collector | 2 | Open source signal coverage |
| 8c. arXiv Collector | 2 | Research paper coverage |
| 9. Real-Time Alerts | 4 | Score-5 push notifications |
| 10. Smoke Test | All | Validation script |
| 11. Documentation | All | Source list, dev log |
| 12. Weekly Digest | 4, 5 | Sunday trend synthesis |

**Minimum viable pipeline:** Tasks 1-5 give you a working daily briefing from HN data. Tasks 6-7 add agentic investigation. Tasks 8-12 expand coverage and harden the system.
