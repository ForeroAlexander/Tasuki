# Credits & Acknowledgments

Tasuki uses and integrates with the following open-source projects and services. None of these are owned by or affiliated with Tasuki.

## MCP Servers (configured by default)

| MCP Server | Author | License | Purpose in Tasuki |
|------------|--------|---------|-------------------|
| [Context7](https://github.com/upstash/context7-mcp) | Upstash | MIT | Up-to-date documentation for 9000+ libraries |
| [Taskmaster AI](https://github.com/eyaltoledano/claude-task-master) | Eyal Toledano | MIT | Task management and project orchestration |
| [Semgrep MCP](https://github.com/semgrep/semgrep) | Semgrep, Inc. | LGPL-2.1 | Static analysis and security scanning |
| [Sentry](https://sentry.io) | Sentry | BSL-1.1 | Error tracking and monitoring |
| [GitHub MCP](https://github.com/github/github-mcp-server) | GitHub | MIT | GitHub integration (PRs, issues, actions) |
| [Playwright MCP](https://github.com/anthropics/anthropic-quickstarts) | Anthropic | MIT | Browser automation for E2E testing |
| [Figma MCP](https://figma.com) | Figma, Inc. | Proprietary | Design specs and assets |
| [Stitch MCP](https://github.com/nicepkg/stitch) | NicePkg | MIT | UI preview and design generation |

## MCP Servers (available in plugin catalog)

| MCP Server | Author | License | Purpose |
|------------|--------|---------|---------|
| [PostgreSQL MCP](https://github.com/bytebase/dbhub) | Bytebase | MIT | Database access and schema inspection |
| [SQLite MCP](https://github.com/modelcontextprotocol/servers) | Anthropic | MIT | SQLite database operations |
| [MongoDB Lens](https://github.com/furey/mongodb-lens) | James Furey | MIT | MongoDB management |
| [DuckDB MCP](https://github.com/MotherDuck-Open-Source/mcp-server-duckdb) | MotherDuck | MIT | Analytics database |
| [Elasticsearch MCP](https://github.com/elastic/elasticsearch-mcp-server) | Elastic | Apache-2.0 | Full-text search |
| [BigQuery MCP](https://github.com/ergut/mcp-bigquery-server) | Ergut | MIT | Google BigQuery access |
| [ChromaDB MCP](https://github.com/chroma-core/chroma-mcp) | Chroma | Apache-2.0 | Vector database for RAG |
| [Puppeteer MCP](https://github.com/modelcontextprotocol/servers) | Anthropic | MIT | Browser automation |
| [Mermaid MCP](https://github.com/jmagar/mcp-mermaid) | JMagar | MIT | Diagram generation |
| [Cloudflare MCP](https://github.com/cloudflare/mcp-server-cloudflare) | Cloudflare | Apache-2.0 | Workers, KV, R2, D1 |
| [Kubernetes MCP](https://github.com/kubernetes-sigs/mcp-k8s) | Kubernetes SIGs | Apache-2.0 | Cluster operations |
| [Brave Search](https://github.com/nicepkg/brave-search-mcp) | NicePkg | MIT | Web search API |

## Skills (included or referenced)

| Skill | Author | License | Purpose |
|-------|--------|---------|---------|
| [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | NextLevelBuilder | MIT | Design intelligence (161 rules, 67 styles, 57 font pairings) |

## Visualization Libraries (loaded via CDN in dashboard)

| Library | Author | License | Purpose |
|---------|--------|---------|---------|
| [D3.js](https://d3js.org) | Mike Bostock / Observable | ISC | Knowledge graph force-directed visualization |
| [Chart.js](https://www.chartjs.org) | Chart.js Contributors | MIT | Bar charts, doughnut charts, line charts |

## AI Platforms (adapters generate config for)

Tasuki generates configuration files for these platforms but is not affiliated with any of them:

- [Claude Code](https://claude.ai/code) by Anthropic
- [Cursor](https://cursor.com) by Anysphere
- [Codex CLI](https://github.com/openai/codex) by OpenAI
- [GitHub Copilot](https://github.com/features/copilot) by GitHub/Microsoft
- [Continue](https://continue.dev) by Continue Dev
- [Windsurf](https://windsurf.com) by Codeium
- [Roo Code](https://github.com/RooVetGit/Roo-Code) by RooVet
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) by Google

## Built With

- Bash — all engine scripts, zero external dependencies
- AWK — template rendering engine

## Special Thanks

- The WatchTower project — the production pipeline that inspired Tasuki's architecture
- The MCP ecosystem — for making AI tool integration standardized
