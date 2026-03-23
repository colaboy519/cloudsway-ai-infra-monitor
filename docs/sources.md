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
