# Roadmap

What's coming next for Tasuki. These are features we've designed but haven't implemented yet.

---

## v1.1 — Intelligence

### Gemini Embedding 2 for RAG
Replace local embeddings with Google's Gemini Embedding 2 (3072 dimensions, free tier). Better semantic search for Layer 2 deep memory. Opt-in — default stays offline.

```bash
tasuki config set embedding-provider gemini    # opt-in
tasuki config set embedding-provider local     # default (offline)
```

### Cloud memory sync
Team memory beyond git. A private cloud vault that syncs automatically — only accessible to people you invite. No public repos, no exposed heuristics.

Currently `vault push/pull` uses a git branch. This would add a hosted option for teams that want real-time sync without managing branches.

### OpenRouter integration
Headless pipeline execution without an IDE. Run Tasuki's pipeline directly via API:

```bash
tasuki run "add auth endpoint" --provider openrouter --model claude-sonnet
```

This makes Tasuki usable in CI/CD, scripts, and environments where no IDE is available.

---

## v1.2 — DevOps expansion

### Cloud execution with credentials
DevOps agent currently generates infrastructure files but doesn't execute them. With user-provided credentials (opt-in, explicit consent):

- `terraform plan` AND `terraform apply`
- AWS/GCP/Azure resource creation
- Kubernetes deployments
- Still shows what it will do and asks for confirmation

### Cost optimization agent
Analyzes current cloud infrastructure and suggests cost reductions. Reads Terraform state, AWS billing data, and suggests right-sizing, reserved instances, spot instances.

---

## v1.3 — Dashboard & Observability

### Pixel office view
Inspired by [Pixel Agents](https://github.com/pablodelucca/pixel-agents) — a 2D pixel art office in the dashboard where each agent is a character at their desk. They type when editing code, read documents when loading files, discuss when doing reviews. Synchronized with the real pipeline state. Pure eye candy that makes the invisible work visible.

### Chatbot on landing page
AI assistant on usetasuki.dev powered by Claude API with CONTEXT.md as system prompt. Answers questions about Tasuki without reading docs.

---

## v1.4 — Multi-session & Teams

### Pipeline state recovery
Robust session continuity with snapshot/restore. If the AI tool crashes mid-pipeline, the next session has full mechanical state — files created, tests passed, agent outputs — not just a markdown file to interpret.

### Shared dashboards
Team dashboard that aggregates pipeline runs across developers. See who ran what, total costs, common errors, most-used heuristics.

### Memory conflict resolution UI
When `vault pull` creates `-team` duplicates, a simple web UI (like the dashboard) to compare and merge memories side by side instead of editing markdown manually.

---

## Recently shipped

| Feature | Version | Details |
|---------|---------|---------|
| **Agent Teams** | v1.0.16 | Claude Code agents run as real teammates with separate context windows, per-agent model selection, and shared task lists. Enabled automatically on `tasuki onboard .` |
| **Path translation** | v1.0.16 | All adapters translate `.tasuki/` paths to the target's equivalents. Hooks include a note that they only run in Claude Code |
| **TeammateIdle / TaskCompleted hooks** | v1.0.16 | Quality gates for Agent Teams — tests + security before idle, acceptance criteria before task completion |

---

## Not planned (and why)

| Feature | Why not |
|---------|---------|
| SaaS/paid tier | Tasuki is free and open source by design |
| Custom LLM training | Tasuki configures existing models, doesn't train new ones |
| VS Code extension | The CLI + hooks approach works across all tools already |
| Auto-commit | Too dangerous — user should always review and commit |
