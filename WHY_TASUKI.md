# Why Tasuki

## The name

Tasuki (襷) is the cloth sash used in Japan to tie back kimono sleeves before working. You put it on, your sleeves get out of the way, and you can move freely.

The tool does the same for AI coding assistants — it prepares them with structure, workflow, and memory so they can work properly.

Without Tasuki, your AI assistant has its sleeves loose: no process, no context, no memory. It guesses file paths, skips tests, ignores security, and repeats the same mistakes.

With Tasuki, the sleeves are tied back: 9 specialized agents, a sequential pipeline, TDD enforcement, security audits, and a knowledge graph that gets smarter with every task.

## The problem

I was building projects with Claude Code and kept hitting the same walls:

- **No structure.** I'd ask for a feature and get a wall of code with no tests, no security review, no plan. Just raw implementation.
- **No memory.** Task #89 would repeat the exact same mistake from task #45. Every session started cold. After 20+ tasks with Tasuki's vault, repeated errors drop to zero — the agent loads heuristics before acting and knows what not to do.
- **No specialization.** One agent trying to be planner, developer, QA, security auditor, and code reviewer at the same time. It's like asking one person to do five jobs — they do all of them poorly.
- **No enforcement.** I could write "always write tests first" in my instructions, but the AI would ignore it whenever it felt like going straight to implementation.

## The idea

What if the AI assistant wasn't one generalist, but a team of specialists?

A planner who designs before anyone codes. A QA engineer who writes failing tests first. A backend developer who implements until those tests pass. A security auditor who checks for OWASP vulnerabilities. A code reviewer who approves or rejects.

And what if the pipeline was enforced mechanically — not by asking nicely, but by hooks that physically block the AI from skipping steps?

And what if the team had a shared memory — a knowledge graph where every lesson learned, every bug found, every architectural decision was saved and loaded automatically on the next task?

That's Tasuki. And on Claude Code, this isn't simulated — each agent runs as a real teammate with its own context window and model via Agent Teams. On other tools, the same pipeline runs through role-switching.

## Why I built it

I was tired of babysitting my AI. I wanted to give it a task, walk away, and come back to production-ready code with tests, security review, and a clean PR.

Every framework I found was either:
- A prompt template (no enforcement, AI ignores it)
- A RAG system (expensive, complex, black box)
- A specific tool plugin (only works with one AI)

None of them combined all three: specialized agents + mechanical enforcement + persistent memory.

So I built it.

## Why it's open source

Because the problem isn't unique to me. Every developer using AI assistants hits these walls. The solution should be free, hackable, and community-driven.

## Why bash

Because zero dependencies. No Python virtualenv, no Node packages, no Docker required. You install it, run one command, and it works. The engine scripts are bash because they need to run everywhere — Mac, Linux, WSL, CI/CD, SSH servers.

The heavy lifting (graph traversal, dashboard, RAG sync) uses Python when needed, but the core is bash by design.

---

*Tasuki v1.0 — built by Alexander Forero.*
*Like the sash, it's simple. You put it on, and everything works better.*
