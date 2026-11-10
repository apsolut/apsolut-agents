# apsolut-agents

A drop-in, markdown-first workspace for coordinating multiple AI coding agents
(Claude, Grok, Codex, Gemini, …) on **one repo**. Agents talk in one append-only
log, state facts are derived from git by small scripts (so they can never go
stale), and true same-day concurrency runs on **git worktrees** — one isolated
checkout per agent, one shared coordination folder, zero merge conflicts on the
coordination files.

No servers, no daemons, no orchestrator. Markdown + git + a handful of small
POSIX-sh scripts (they run in Git Bash on Windows).

## Install

One-liner, no clone needed (from inside your project):

```
curl -fsSL https://raw.githubusercontent.com/apsolut/apsolut-agents/main/install.sh | sh -s -- . --wire
```

Pin a release with `--tag vX.Y.Z`. Add `--dry-run` to print every file it would
write plus the exact `CLAUDE.md` block, changing nothing. Alternatives:

```
sh install.sh <path-to-your-repo> --wire      # from a local clone
npx degit apsolut/apsolut-agents/template .apsolut-agents   # payload only, no refresh logic
```

**What `--wire` does to your `CLAUDE.md`:** it *appends* the bootstrap block from
`CLAUDE-SNIPPET.md` between `<!-- apsolut-agents:begin -->` and
`<!-- apsolut-agents:end -->`. It never rewrites or reorders existing content, and
it skips the file entirely if the begin marker is already there — so re-running is
safe. If neither `CLAUDE.md` nor `AGENTS.md` exists, it creates `CLAUDE.md`.
Omit `--wire` and you can paste the block yourself.

**No-exec install (sandboxed agents, restrictive permission policies):** the
installer is three file operations, all doable with plain copies — see
[`template/INSTALL.md` §1](template/INSTALL.md), which also gives the `diff -r`
command that proves a hand-rolled install matches the installer byte-for-byte.

Full instructions in [`template/INSTALL.md`](template/INSTALL.md). Upgrading later
needs nothing but the installed folder itself:

```
sh .apsolut-agents/scripts/upgrade.sh          # fetches latest, never touches your data
sh .apsolut-agents/scripts/upgrade.sh --dry-run   # show add/update/keep, write nothing
```

`kind=instance` files (your log, state, decisions, PROJECT.md, cards) survive every
upgrade; `VERSION` records what you're on.

## The tier model

| Tier | Use when | Adds |
|---|---|---|
| **0 — Core** | any project, even solo | one log, one state file, agent charters, `status.sh` + `session-end.sh` |
| **1 — Long-run** | weeks-long work | protocol, decision register, `runs/` for subagent fan-outs, log archiving |
| **2 — Concurrent** | 2–3 agents, same day/same files | **git-worktree multiplexing** (`WORKTREES.md`, `worktree.sh`), **agent-drives-agent delegation** (`DELEGATION.md`, `delegate.sh`), work files, generated `STATUS.md` |

Start at Tier 0. Golden rule: don't build Tier 2 before concurrent edits actually hurt.

## How Tier-2 concurrency works (30 seconds)

```
sh .apsolut-agents/scripts/worktree.sh spawn grok T-014
```

gives agent *grok* an isolated checkout on branch `agent/grok/T-014`, with a
`.primary` pointer back to the one true coordination folder. The agent codes in
its worktree, talks in the shared log, and merges back through a normal git merge.
The log and state never fork — that's the whole trick. Spec: [`template/WORKTREES.md`](template/WORKTREES.md).

## Agents drive other agents (Tier 2)

Any agent in the roster can run any other agent's CLI as a subordinate worker and stay
in charge of it — Claude driving Grok, Grok driving Claude, either driving Codex or
Gemini. Symmetric by design.

```
sh .apsolut-agents/scripts/delegate.sh run grok T-014 --detach   # dispatch headless
sh .apsolut-agents/scripts/delegate.sh status                    # who's running, spend
sh .apsolut-agents/scripts/delegate.sh tail T-014                # live progress
sh .apsolut-agents/scripts/delegate.sh run grok T-014 --note "…" # correction round
sh .apsolut-agents/scripts/delegate.sh stop T-014                # kill + salvage-commit
```

Delegates run with whatever permission posture you put in `HEARTBEAT.md` — including
fully bypassed approvals, which is what makes headless rounds work at all. What keeps
that safe is structural, not a prompt: a delegate lives in its own worktree, its
remote push URL is sealed at spawn (`no_push://refused`, that worktree only), it
cannot merge, cannot write to the coordination folder, and cannot spawn delegates
of its own (depth cap). Do not put `claude --bare` on a `cmd_` line in
`HEARTBEAT.md`: that flag ignores the signed-in account, so the delegate reports
"Not logged in" while your own terminal is signed in. Every round is one unmerged branch and one `git diff` away from
being discarded. Rounds, fan-out, and daily spend are all capped; agents can't raise a
cap. Protocol: [`template/DELEGATION.md`](template/DELEGATION.md).

Unattended variant — write cards in the evening, review branches in the morning:
[`template/NIGHTSHIFT.md`](template/NIGHTSHIFT.md) (`runner.sh`). Same cards, same claim
mutex, same spend ledger, so the two never collide.

### Run the night until the final product (v0.9 goal loop)

Write what "done" means as a command that can fail, in `GOAL.md`:

```
goal: a signed-in user can export their library as a zip
done_cmd: pnpm --filter web e2e journeys/export.spec.ts
```

The runner then works the board through a per-card pipeline. A **worker** writes
the test first and the root cause before any fix, and ends with a structured
handoff. `green_cmd` runs. An **independent verifier** on another model runs the
change and returns `live / test / typecheck / blocked / failed`. On a retry, an
**advisor** diagnoses the failure first. Verified cards merge onto one **night
branch**, and later cards build on it. When the board runs dry, the runner checks
`done_cmd` there. If it is red, a **planner** writes the next cards from the gap.
The night ends when the goal is met, the planner says a human is needed (`STUCK.md`),
two rounds in a row land nothing (plateau), or a cap trips. Every decision is a row
in `runs/trail-<date>.tsv`. In the morning, a **reviewer** puts an *Attention*
section at the top of the night report, and one `worktree.sh done NIGHT-<date>
--merge` lands the night. The default branch never moves on its own. Any agent can
pull the **Andon** (`andon.sh raise`), and only you clear it. An agent that edits
its own rules trips the tamper canary. Details: [`template/NIGHTSHIFT.md`](template/NIGHTSHIFT.md).
Proven end to end in CI against a scripted fake CLI (`tests/goal-loop.sh`).

**v0.10: the runner enforces, the prompts only explain.** A blind review by four
models (Claude, Codex, Grok, agy) moved every rule a script can check into
`runner.sh`. Each card's `check:` must fail before the change and pass after.
`protect:` paths (the judge: the predicate's tests, the green script) are off limits
to cards. Added `.skip`/`@ts-ignore`-style patches are red. Every check has a
timeout. `setup_cmd` bootstraps fresh worktrees. Prompts go by stdin or by a file
pointer, so they survive Windows' command-line limit. A card that conflicts on the
night branch retries from the night tip instead of stranding.

**v0.11: caps for CLIs that grew their own agents.** claude, codex, grok and agy now
ship native subagents and goal loops. The default `cmd_` lines switch those off, so
a lane stays inside the card clock and the spend ledger. One call cannot outspend
the night (`call_budget_usd`). A CLI that exits 0 without finishing its turn is
red. Codex is a lane. `doctor.sh` warns when your own `HEARTBEAT.md` lacks the caps.

**Run the v0 gate first.** `scripts/doctor.sh <agent>` preflights everything in one
command — tools, config sanity, every card's contract and `after:` graph, green on
the primary, rolling cost vs budget, plus a live probe of the agent's CLI. Then a
supervised `runner.sh <agent> --once` pass costs about a dollar and catches the
misconfiguration that would otherwise burn the entire night — it is the feature,
not a formality. The runner also probes the CLI on boot and refuses the lane if
the model can't answer at all.

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

## License

MIT ([`LICENSE`](LICENSE)). Reuse, fork, sell — the one obligation is keeping the
copyright and license notice with copies. So that this survives partial reuse,
every script carries an SPDX header and installed workspaces ship their own copy
at `.apsolut-agents/LICENSE`; please keep the headers when lifting a single file.
Ideas parking lot: [`FUTURE.md`](FUTURE.md).
