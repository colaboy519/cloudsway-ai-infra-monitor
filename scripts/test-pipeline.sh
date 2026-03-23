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
