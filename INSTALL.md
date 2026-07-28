# INSTALL — apsolut-agents boilerplate

A drop-in workspace for coordinating multiple AI coding agents (Claude, Grok, Codex,
Gemini, …) on **one repo**, from a tiny solo app to a multi-week SaaS. Stack-agnostic:
all project specifics live in **`PROJECT.md`**; everything else is generic.

The whole thing is plain markdown + git. No servers, no scripts required to start.

---

## 1. Install into a project

1. Copy this folder into your repo and rename it to **`.apsolut-agents/`**
   (the leading dot keeps it grouped and out of the way).
2. Open **`PROJECT.md`** and fill in the blanks (build/test commands, hot files,
   what needs a human, deploy). This is the only place with project specifics.
3. Delete the tiers you don't need (see §2).
4. Rewrite **`state/PROJECT_STATE.md`** with where the project is right now.
5. Point every agent at it with the bootstrap prompt in §3.

That's it. Agents now have one place to read state and talk.

## 2. Pick your tier (delete the rest)

Start as small as the project. Add a layer only when the pain is real.

| Tier | Use when | Keep these files |
|---|---|---|
| **0 — Core** | Any project, even solo / one agent at a time | `README.md`, `PROJECT.md`, `agent-log.md`, `agents/`, `state/PROJECT_STATE.md` |
| **1 — Long-run** | Weeks-long, or history won't fit in one context | + `PROTOCOL.md`, `decisions/DECISIONS.md`, `archive/` |
| **2 — Concurrent** | 2–3 agents editing the **same day / same files** | + `CONCURRENCY.md`, `STATUS.md`, `work/`, `locks/` |

Deleting a tier is safe — each file names its tier at the top. When unsure, start at
Tier 0; you can add layers later without rework.

> Golden rule (from hard experience): **do not build Tier 2 before concurrent edits
> actually hurt.** A lock protocol you don't need is pure friction.

## 3. Bootstrap prompt (paste to each agent, once per session)

```
This repo uses a shared multi-agent workspace in .apsolut-agents/.
Before doing anything:
1. Read .apsolut-agents/README.md and PROJECT.md.
2. Read .apsolut-agents/state/PROJECT_STATE.md and the tail of agent-log.md.
3. Run: git log -12 --oneline
Then follow the workspace rules: talk in agent-log.md (append-only), respect HOLD,
declare INTENT before large edits to the hot files listed in PROJECT.md, and end your
session with a PUSHED | HOLD | FAILED line in the log. Do not push unless allowed.
```

For an always-on setup, put that in the project's `CLAUDE.md` / `AGENTS.md` / equivalent
so agents read it every session without being told.

## 4. The one rule that saves you

**Committed ≠ done.** A change isn't done until it's pushed to the remote (or the log
says `HOLD`). The most common multi-agent failure is an agent that commits great work
locally and never pushes it — the next agent (and prod) never sees it.

## 5. What's in the box

| File | Tier | Purpose |
|---|---|---|
| `README.md` | 0 | Agent entry point + file map |
| `PROJECT.md` | 0 | **The only stack-specific file** — you fill it in |
| `agent-log.md` | 0 | The live conversation (append-only) |
| `agents/agent-TEMPLATE.md` | 0 | Copy per agent → `agent-claude.md`, `agent-grok.md`, … |
| `state/PROJECT_STATE.md` | 0 | Save-game — rewritten each session, kept small |
| `PROTOCOL.md` | 1 | Long-run rules: session protocol, compaction, decisions |
| `decisions/DECISIONS.md` | 1 | Durable "why" record (grep it, don't read it whole) |
| `archive/` | 1 | Rotated old `agent-log` slices |
| `CONCURRENCY.md` | 2 | Status board + locks + "don't read dirty files" |
| `STATUS.md` | 2 | At-a-glance board (**generated**, not hand-edited) |
| `work/_TEMPLATE.md` | 2 | One file per task — the ownership atom |
| `locks/` | 2 | Advisory exclusive-write markers |

`multi-agent-cli-foundations.md` (optional) is the deeper architecture reference for if
you ever outgrow markdown+git and want inbox/orchestrator/A2A — you almost certainly won't
for a long time.
