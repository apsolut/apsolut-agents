<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT — stack facts

**The only file with project-specific details.** Everything else in `.apsolut-agents/`
is generic and points here.

_Tier: 0 (core). Last updated: 2026-07-28 by Claude._

---

## Identity

| | |
|---|---|
| **Project** | apsolut-agents — the multi-agent workspace boilerplate itself (this repo dogfoods it) |
| **Repo / remote** | local only, branch `main` — no remote yet |
| **Stack** | Markdown + POSIX sh (Git Bash on Windows). No runtime, no deps beyond git/sed/awk/grep. |
| **Deploy target** | none — "shipping" = users copying `template/` via `install.sh` |

## Commands (how agents verify their work)

| Purpose | Command |
|---|---|
| Tier labels present | `grep -rLE "apsolut-agents: tier=" template --include="*.md"` → must print nothing |
| No stale lock refs | `grep -rilE "locks/" template --include="*.md"` → only WORKTREES.md + reference/ |
| Script smoke test | fresh repo in scratchpad → `sh install.sh <dir>` → `status.sh`, `worktree.sh spawn/done`, `session-end.sh` all exit 0 |
| Board regen | `sh .apsolut-agents/scripts/status.sh` |
| No instance leakage into payload | `grep -rniE "joyci\|D:/sites\|scratchpad\|T-00[0-9]\|2026-" template/ \| grep -v "<date>" \| grep -v reference/` → must print nothing |
| **"Green" =** | all five of the above |

> Agents: **read this table before running any tool.** There is no formatter, linter,
> or test framework here — don't invent one.

## Roster

| Agent | Default lane |
|---|---|
| Claude | protocol design, scripts, template rewrites, verification |
| Human | direction calls (tiers/packaging), remote/publish, one-way doors |

## Hot files (declare INTENT before large edits)

- `template/PROTOCOL.md`, `template/WORKTREES.md`, `template/README.md` — the protocol; changes ripple into every install
- `template/scripts/*.sh` — behavior contract for every instance; keep POSIX sh, no new deps
- `install.sh` — the refresh rules (`kind=` handling) guard user data; test before committing
- `template/INSTALL.md §5` — the file table must match `find template -type f` 1:1

## Human gates (never auto-decide these)

- Renaming/removing template files (breaks `--refresh` for existing installs)
- Changing the `kind=`/tier label convention (every instance depends on it)
- Adding a runtime dependency beyond git + POSIX sh
- Pushing to a remote / publishing

## Deploy (the ship sequence)

N/A — users run `sh install.sh <repo>` (or `--refresh` to upgrade).

## Do-not-undo (load-bearing invariants)

- Coordination lives ONLY in the primary worktree; `.primary` pointer redirects secondaries — see D-001 in `decisions/DECISIONS.md`
- `install.sh --refresh` must NEVER overwrite `kind=instance` files — see D-002
- Scripts stay POSIX sh — Git Bash is the only guaranteed runtime on all platforms
- `STATUS.md` + the state facts block are generated; hand-edits get overwritten by design
