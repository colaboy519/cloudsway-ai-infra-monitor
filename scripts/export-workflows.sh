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
