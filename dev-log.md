# AI Infra Monitor — Dev Log

## 2026-03-23 — Task 1: Docker Compose Infrastructure

**Done:**
- Created `docker-compose.yml` with postgres, redis, n8n, dify services
- Configured volumes, environment variables, health checks
- Mounted Obsidian vault in n8n container for file access

**State:** All services defined and startable with `docker compose up`.

---

## 2026-03-23 — Task 2: Database Schema

**Done:**
- Replaced placeholder in `db/init.sql` with full production schema: `raw_signals`, `triage_results`, `investigations`, `tracked_entities`, `delivery_log` tables
- Added uuid-ossp extension and appropriate indexes (unique on url/hash, btree on source, collected_at, signal_id, significance_score)
- Created `scripts/seed-entities.sql` with 20 tracked AI infra companies across sectors: foundation_models, compute, inference, infra_platform, tooling, mlops, data, ai_coding
- Committed as `feat: add full database schema and seed entities`

**Decisions:**
- Kept n8n database creation line at top of init.sql per spec requirement
- Used JSONB for `entities`, `metadata`, and `aliases` fields for flexible querying
- Partial indexes on url/hash uniqueness (WHERE NOT NULL) to allow multiple null values

**State:** Schema ready; PostgreSQL container will auto-apply on first start. Next: Task 3 (Hacker News n8n collector workflow).

**Blockers:** None

---

## 2026-03-23 — Task 3: Hacker News n8n Collector Workflow

**Done:**
- Created `n8n/workflows/02-hn-collector.json` as a valid n8n workflow export
- 7-node pipeline: Schedule Trigger (every 6h) → HTTP fetch top stories → Code (slice 30 IDs) → HTTP fetch each item → IF filter score > 50 → Code transform to signal schema → Postgres INSERT with ON CONFLICT DO NOTHING
- Uses `n8n-nodes-base.scheduleTrigger`, `httpRequest`, `code`, `if`, `postgres` node types
- Committed as `feat: add Hacker News n8n collector workflow`

**Decisions:**
- Used `executeQuery` operation on Postgres node with parameterized SQL for full control over ON CONFLICT clause
- Credential reference (`postgres-ai-infra`) left as a placeholder name — must be created in n8n UI before the workflow runs
- `typeVersion` values match recent n8n stable releases (scheduleTrigger 1.1, httpRequest 4.2, code 2, if 2, postgres 2.5)

**State:** Workflow JSON ready to import via n8n UI (Settings → Import from file). Next task pending.

**Blockers:** None
