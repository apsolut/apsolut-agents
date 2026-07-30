<!-- apsolut-agents: tier=0 kind=doc -->
# INSTALL — apsolut-agents workspace

A drop-in workspace for coordinating multiple AI coding agents (Claude, Grok, Codex,
Gemini, …) on **one repo**, from a tiny solo app to a multi-week SaaS. Stack-agnostic:
all project specifics live in **`PROJECT.md`**; everything else is generic.

Plain markdown + git + three small POSIX-sh scripts (they run in Git Bash on Windows).
No servers, no daemons, no build step.

---

## 1. Install into a project

One-liner from inside your repo (no clone needed; `--wire` appends the bootstrap
block to CLAUDE.md/AGENTS.md; `--tag vX.Y.Z` pins a release):

```
curl -fsSL https://raw.githubusercontent.com/apsolut/apsolut-agents/main/install.sh | sh -s -- . --wire
```

or from a clone: `sh install.sh <path-to-your-repo> --wire`.

Add **`--dry-run`** to either form to print every file it would write and the exact
`CLAUDE.md` block, without touching anything under the target. (On the `curl` form it
still fetches the payload to a temp dir; the target repo is untouched.) Use it to get
a human — or a permission prompt — something concrete to approve.

**What `--wire` does to your agent-instructions file.** It *appends* the block from
`CLAUDE-SNIPPET.md`, wrapped in `<!-- apsolut-agents:begin -->` / `<!-- apsolut-agents:end -->`.
It never rewrites, reorders, or deletes existing content, and it skips a file that
already contains the begin marker, so re-running is safe. Existing `CLAUDE.md` and
`AGENTS.md` both get wired; if neither exists, `CLAUDE.md` is created.

### 1a. Installing without executing the script

Some agent harnesses and CI policies won't run a fetched shell script. A fresh install
is exactly three file operations — do them by hand and you get a byte-identical result:

```sh
# 1. copy the payload (the trailing /. is required — it picks up .gitignore
#    and archive/.gitkeep, which a bare `template/*` glob would miss)
mkdir -p <your-repo>/.apsolut-agents
cp -R <source>/template/. <your-repo>/.apsolut-agents/

# 2. stamp the version (install.sh writes this; template/ does not contain it)
cp <source>/VERSION <your-repo>/.apsolut-agents/VERSION

# 3. wire (optional, = --wire): append to CLAUDE.md / AGENTS.md, skipping if the
#    begin marker is already present:
#      <!-- apsolut-agents:begin -->
#      …the content between the ```markdown fences in CLAUDE-SNIPPET.md…
#      <!-- apsolut-agents:end -->
```

`<source>` is a clone, or an unpacked
`https://github.com/apsolut/apsolut-agents/archive/refs/heads/main.tar.gz`.

**Verify it.** This is the same check the project uses to keep `template/` and its own
dogfood instance honest:

```sh
diff -r <source>/template <your-repo>/.apsolut-agents --exclude=VERSION
```

Silence means identical. `VERSION` is the only legitimate exclusion. Two caveats: run
it *immediately* after copying — step 3 below regenerates `STATUS.md` and you will then
fill in `PROJECT.md`, both of which are supposed to diverge. And diff against the same
`<source>` you copied from: a Windows clone under `* text=auto` has CRLF markdown while
the release tarball has LF, so cross-comparing sources flags every file.

### 1b. Then, either way

1. Open **`PROJECT.md`** and fill in the blanks (build/test commands, hot files,
   what needs a human, deploy). This is the only place with project specifics.
2. Delete the tiers you don't need (see §2).
3. Fill in the narrative sections of **`state/PROJECT_STATE.md`** with where the
   project is right now, then run `sh .apsolut-agents/scripts/status.sh` to generate
   the facts.
4. If you skipped `--wire`: paste the contents of **`CLAUDE-SNIPPET.md`** into your
   project's `CLAUDE.md` / `AGENTS.md` so every agent bootstraps automatically — or
   paste the §3 prompt per session by hand.

That's it. Agents now have one place to read state and talk.

## 2. Pick your tier (delete the rest)

Start as small as the project. Add a layer only when the pain is real.

| Tier | Use when | Keep these files |
|---|---|---|
| **0 — Core** | Any project, even solo / one agent at a time | `README.md`, `PROJECT.md`, `agent-log.md`, `agents/`, `state/PROJECT_STATE.md`, `scripts/status.sh`, `scripts/session-end.sh`, `CLAUDE-SNIPPET.md` |
| **1 — Long-run** | Weeks-long, or history won't fit in one context | + `PROTOCOL.md`, `PLAYBOOK.md`, `decisions/DECISIONS.md`, `runs/`, `archive/` |
| **2 — Concurrent** | 2–3 agents editing the **same day / same files** | + `WORKTREES.md`, `STATUS.md`, `work/`, `scripts/worktree.sh`, `NIGHTSHIFT.md`, `HEARTBEAT.md`, `scripts/runner.sh`, `DELEGATION.md`, `scripts/delegate.sh` |

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
| `scripts/upgrade.sh` | 0 | doc | Self-upgrade from GitHub — no source clone needed |
| `VERSION` | 0 | generated | Installed release — written by install/upgrade |
| `.gitignore` | 0 | doc | Ignores the `.primary` worktree pointer |
| `PROTOCOL.md` | 1 | doc | Long-run rules: sessions, compaction, decisions, runs |
| `PLAYBOOK.md` | 1 | doc | Delivery practices: small batches, card contract, risk tags |
| `decisions/DECISIONS.md` | 1 | instance | Durable "why" record (grep it, don't read it whole) |
| `runs/README.md` | 1 | doc | Where subagent fan-out results land |
| `archive/` | 1 | — | Rotated old `agent-log` slices |
| `WORKTREES.md` | 2 | doc | True concurrency: per-agent git worktrees |
| `NIGHTSHIFT.md` | 2 | doc | Unattended overnight runs — rules + morning ritual |
| `DELEGATION.md` | 2 | doc | Agent drives another agent's CLI in-session — caps, loop, rails |
| `HEARTBEAT.md` | 2 | instance | Night Shift + delegation policy: budgets, timeouts, agent commands |
| `STATUS.md` | 2 | generated | At-a-glance board — rendered by `status.sh` |
| `work/_TEMPLATE.md` | 2 | doc | One file per task — the ownership atom |
| `scripts/worktree.sh` | 2 | doc | Spawn / list / merge+cleanup agent worktrees |
| `scripts/runner.sh` | 2 | doc | Night Shift single-lane runner (see `NIGHTSHIFT.md`) |
| `scripts/delegate.sh` | 2 | doc | `run`/`status`/`tail`/`stop` a delegated peer agent (see `DELEGATION.md`) |
| `reference/multi-agent-cli-foundations.md` | 1 | doc | Someday-maybe inbox/orchestrator architecture — reference only |

## 6. Upgrading

The installed folder upgrades itself — no source clone needed:

```
sh .apsolut-agents/scripts/upgrade.sh [--tag vX.Y.Z] [--dry-run]
```

`--dry-run` lists every file as `would add` / `would update` / `keep` and writes
nothing — the fastest way to see exactly which of your files an upgrade would replace.
(From a clone, `sh install.sh <path-to-your-repo> --refresh [--dry-run]` does the same.)

Refresh overwrites files labeled `kind=doc` or `kind=generated` and **never touches
`kind=instance` files** — your log, state, decisions, PROJECT.md, charters, and work
files survive every upgrade.

Two things an upgrade therefore cannot do for you:

- **The block already pasted into your `CLAUDE.md` is not updated.** Refresh replaces
  `.apsolut-agents/CLAUDE-SNIPPET.md`, and `--wire` skips any file that already contains
  the begin marker. If a release changes the snippet, re-paste it — or delete the
  `<!-- apsolut-agents:begin -->…end -->` block and re-run with `--wire`. Everything
  agents *must* read every session lives in `README.md` (`kind=doc`, so it does update);
  the snippet only has to get them there.
- **New `HEARTBEAT.md` keys don't appear** (it's `kind=instance`). Scripts default every
  key they read, so nothing breaks — compare against `template/HEARTBEAT.md` when you want
  the new knobs.

> **Upgrading a pre-label (old-format) workspace:** the overwrite decision comes from
> the *template's* label, so old customized doc files — especially a README with a
> filled-in roster — get overwritten. Port any customizations (roster → `PROJECT.md`)
> BEFORE refreshing, or recover them from git afterwards. Also: refresh adds ALL
> template files; if the project chose a lower tier, delete the higher-tier additions
> after (tier labels are on line 1).
