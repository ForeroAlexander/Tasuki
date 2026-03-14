# Tasuki

Multi-agent orchestration framework for software development.

## What it does

Tasuki transforms any codebase into a fully-configured Claude Code multi-agent pipeline. It detects your stack, generates specialized agents, and provides intelligent routing, TDD enforcement, security scanning, and a knowledge graph memory system.

## Install

```bash
# From Claude Code marketplace
/plugin marketplace add forero/tasuki

# Or manually
git clone https://github.com/forero/tasuki.git
cd tasuki && bash install.sh
```

## Quick Start

```bash
# New project
tasuki init fastapi my-api
tasuki init nextjs my-app

# Existing project
cd your-project
tasuki onboard .
```

## Features

- **9 Specialized Agents** — planner, qa, backend-dev, frontend-dev, db-architect, security, reviewer, devops, debugger
- **Capability-Based Routing** — agents selected by domain expertise, not by name
- **13 Stack Profiles** — FastAPI, Django, Flask, Next.js, SvelteKit, Nuxt, Express, NestJS, Rails, Gin, Spring Boot, Laravel, generic
- **TDD Guard** — hooks that block implementation code until tests exist
- **Knowledge Graph** — memory vault with wikilinks for navigable knowledge
- **Interactive Dashboard** — D3.js graph visualization, cost tracking, health score
- **Plugin System** — install/uninstall agents, skills, and MCPs
- **Smart Cleanup** — suggests removing unused components, restore anytime

## 30+ CLI Commands

```
tasuki init, onboard, status, validate, doctor, diff, monorepo,
mode, score, route, cost, dashboard, install, uninstall, plugins,
update-catalog, health, guardrails, changelog, vault, discover,
history, learn, cleanup, restore, hooks, help, version
```
