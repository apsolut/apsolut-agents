<!-- apsolut-agents: tier=0 kind=doc -->
# INSTALL — apsolut-agents workspace

A drop-in workspace for coordinating multiple AI coding agents (Claude, Grok, Codex,
Gemini, …) on **one repo**, from a tiny solo app to a multi-week SaaS. Stack-agnostic:
all project specifics live in **`PROJECT.md`**; everything else is generic.

Plain markdown + git + three small POSIX-sh scripts (they run in Git Bash on Windows).
No servers, no daemons, no build step.

---

## 1. Install into a project

From the apsolut-agents repo:

```
sh install.sh <path-to-your-repo>
```

or manually: copy `template/` into your repo as **`.apsolut-agents/`**. Then:

1. Open **`PROJECT.md`** and fill in the blanks (build/test commands, hot files,
   what needs a human, deploy). This is the only place with project specifics.
2. Delete the tiers you don't need (see §2).
3. Fill in the narrative sections of **`state/PROJECT_STATE.md`** with where the
   project is right now, then run `sh .apsolut-agents/scripts/status.sh` to generate
   the facts.
4. Paste the contents of **`CLAUDE-SNIPPET.md`** into your project's `CLAUDE.md` /
   `AGENTS.md` so every agent bootstraps automatically — or paste the §3 prompt per
   session by hand.

That's it. Agents now have one place to read state and talk.

## 2. Pick your tier (delete the rest)

Start as small as the project. Add a layer only when the pain is real.

| Tier | Use when | Keep these files |
|---|---|---|
| **0 — Core** | Any project, even solo / one agent at a time | `README.md`, `PROJECT.md`, `agent-log.md`, `agents/`, `state/PROJECT_STATE.md`, `scripts/status.sh`, `scripts/session-end.sh`, `CLAUDE-SNIPPET.md` |
| **1 — Long-run** | Weeks-long, or history won't fit in one context | + `PROTOCOL.md`, `PLAYBOOK.md`, `decisions/DECISIONS.md`, `runs/`, `archive/` |
| **2 — Concurrent** | 2–3 agents editing the **same day / same files** | + `WORKTREES.md`, `STATUS.md`, `work/`, `scripts/worktree.sh`, `NIGHTSHIFT.md`, `HEARTBEAT.md`, `scripts/runner.sh` |

Deleting a tier is safe — every file carries a machine-readable label on line 1:
`<!-- apsolut-agents: tier=<0|1|2> kind=<doc|instance|generated> -->`. When unsure,
start at Tier 0; you can add layers later without rework.

> Golden rule (from hard experience): **do not build Tier 2 before concurrent edits
> actually hurt.** Coordination machinery you don't need is pure friction.

## 3. Bootstrap prompt (paste to each agent, once per session)

```
This repo uses a shared multi-agent workspace in .apsolut-agents/.
If .apsolut-agents/.primary exists, the path inside it is the real workspace —
use it for every coordination read/write.
Before doing anything, read in order:
1. .apsolut-agents/README.md and PROJECT.md
2. .apsolut-agents/state/PROJECT_STATE.md and the tail of agent-log.md
3. Run: git log -12 --oneline
4. If .apsolut-agents/scripts/status.sh exists, run: sh .apsolut-agents/scripts/status.sh
5. Your own .apsolut-agents/agents/agent-<you>.md — first session: create it from
   agent-TEMPLATE.md and add your roster row in PROJECT.md before your first task.
Then follow the workspace rules: talk in agent-log.md (append-only), respect HOLD,
note in the log what you're editing when another agent is active (Tier 2: INTENT),
and end your session with a "### <you> — <date> — PUSHED|HOLD|FAILED" heading, then
run: sh .apsolut-agents/scripts/session-end.sh <you> <TOKEN>. Do not push unless allowed.
```

For an always-on setup, paste `CLAUDE-SNIPPET.md` into the project's `CLAUDE.md` /
`AGENTS.md` / equivalent so agents read it every session without being told.

## 4. The one rule that saves you

**Committed ≠ done.** A change isn't done until it's pushed to the remote (or the log
says `HOLD`). The most common multi-agent failure is an agent that commits great work
locally and never pushes it — the next agent (and prod) never sees it.

## 5. What's in the box

| File | Tier | Kind | Purpose |
|---|---|---|---|
| `README.md` | 0 | doc | Agent entry point + file map + roster |
| `INSTALL.md` | 0 | doc | This file |
| `PROJECT.md` | 0 | instance | **The only stack-specific file** — you fill it in |
| `CLAUDE-SNIPPET.md` | 0 | doc | Paste-into-`CLAUDE.md` bootstrap block |
| `agent-log.md` | 0 | instance | The live conversation (append-only) |
| `agents/agent-TEMPLATE.md` | 0 | doc | Copy per agent → `agent-claude.md`, `agent-grok.md`, … |
| `state/PROJECT_STATE.md` | 0 | instance | Save-game — generated facts + hand-written narrative |
| `scripts/status.sh` | 0 | doc | Renders `STATUS.md` + the state facts block from git |
| `scripts/session-end.sh` | 0 | doc | Verifies end token, compacts log, refreshes facts |
| `.gitignore` | 0 | doc | Ignores the `.primary` worktree pointer |
| `PROTOCOL.md` | 1 | doc | Long-run rules: sessions, compaction, decisions, runs |
| `PLAYBOOK.md` | 1 | doc | Delivery practices: small batches, card contract, risk tags |
| `decisions/DECISIONS.md` | 1 | instance | Durable "why" record (grep it, don't read it whole) |
| `runs/README.md` | 1 | doc | Where subagent fan-out results land |
| `archive/` | 1 | — | Rotated old `agent-log` slices |
| `WORKTREES.md` | 2 | doc | True concurrency: per-agent git worktrees |
| `NIGHTSHIFT.md` | 2 | doc | Unattended overnight runs — rules + morning ritual |
| `HEARTBEAT.md` | 2 | instance | Night Shift policy: budgets, timeouts, lane commands |
| `STATUS.md` | 2 | generated | At-a-glance board — rendered by `status.sh` |
| `work/_TEMPLATE.md` | 2 | doc | One file per task — the ownership atom |
| `scripts/worktree.sh` | 2 | doc | Spawn / list / merge+cleanup agent worktrees |
| `scripts/runner.sh` | 2 | doc | Night Shift single-lane runner (see `NIGHTSHIFT.md`) |
| `reference/multi-agent-cli-foundations.md` | 1 | doc | Someday-maybe inbox/orchestrator architecture — reference only |

## 6. Upgrading

Newer apsolut-agents version? From its repo:

```
sh install.sh <path-to-your-repo> --refresh
```

Refresh overwrites files labeled `kind=doc` or `kind=generated` and **never touches
`kind=instance` files** — your log, state, decisions, PROJECT.md, charters, and work
files survive every upgrade.

> **Upgrading a pre-label (old-format) workspace:** the overwrite decision comes from
> the *template's* label, so old customized doc files — especially a README with a
> filled-in roster — get overwritten. Port any customizations (roster → `PROJECT.md`)
> BEFORE refreshing, or recover them from git afterwards. Also: refresh adds ALL
> template files; if the project chose a lower tier, delete the higher-tier additions
> after (tier labels are on line 1).
