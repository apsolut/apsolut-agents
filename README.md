# apsolut-agents

A drop-in, markdown-first workspace for coordinating multiple AI coding agents
(Claude, Grok, Codex, Gemini, …) on **one repo**. Agents talk in one append-only
log, state facts are derived from git by small scripts (so they can never go
stale), and true same-day concurrency runs on **git worktrees** — one isolated
checkout per agent, one shared coordination folder, zero merge conflicts on the
coordination files.

No servers, no daemons, no orchestrator. Markdown + git + three POSIX-sh scripts
(they run in Git Bash on Windows).

## Install

```
sh install.sh <path-to-your-repo>
```

This copies `template/` into your repo as `.apsolut-agents/`. Then follow the
checklist it prints — full instructions in [`template/INSTALL.md`](template/INSTALL.md).

Upgrade an existing installation without touching your log/state/decisions:

```
sh install.sh <path-to-your-repo> --refresh
```

## The tier model

| Tier | Use when | Adds |
|---|---|---|
| **0 — Core** | any project, even solo | one log, one state file, agent charters, `status.sh` + `session-end.sh` |
| **1 — Long-run** | weeks-long work | protocol, decision register, `runs/` for subagent fan-outs, log archiving |
| **2 — Concurrent** | 2–3 agents, same day/same files | **git-worktree multiplexing** (`WORKTREES.md`, `worktree.sh`), work files, generated `STATUS.md` |

Start at Tier 0. Golden rule: don't build Tier 2 before concurrent edits actually hurt.

## How Tier-2 concurrency works (30 seconds)

```
sh .apsolut-agents/scripts/worktree.sh spawn grok T-014
```

gives agent *grok* an isolated checkout on branch `agent/grok/T-014`, with a
`.primary` pointer back to the one true coordination folder. The agent codes in
its worktree, talks in the shared log, and merges back through a normal git merge.
The log and state never fork — that's the whole trick. Spec: [`template/WORKTREES.md`](template/WORKTREES.md).

## This repo dogfoods itself

`.apsolut-agents/` at the root of this repo is a **live instance** of the template,
tracking the development of apsolut-agents itself — open it for a real, filled-in
example. `template/` is the pristine payload that `install.sh` copies; the two are
kept honest by the `kind=doc|instance|generated` labels on line 1 of every file.

## Layout

```
install.sh        installer / upgrader
template/         the payload — what lands in your repo as .apsolut-agents/
.apsolut-agents/  this repo's own live workspace (dogfood)
```

Design lineage: the protocol was pruned against evidence from a real multi-week,
two-agent run — ceremony that agents skipped in practice was cut or automated;
facts that drifted when hand-written are now derived from git.
