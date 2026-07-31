<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT_STATE — save-game checkpoint

Two zones. The **facts block** below is written by `scripts/status.sh` — never
hand-edit between its markers; it cannot go stale because it is derived from git.
The **narrative** sections are yours: hand-edit them **when they change**, delete
anything no longer true (git keeps history), keep the whole file to ~1 screen.

---

## Facts (generated)

<!-- facts:begin -->
_Generated 2026-07-31 08:37 by status.sh — do not hand-edit this block._

| | |
|--|--|
| Branch | `feat/delegation-and-installer-fixes` |
| Ahead/behind upstream | 0 ahead / 0 behind upstream |
| Dirty files | 1 |
| Worktrees | 1 (incl. primary) |
| Last session token | claude — 2026-07-31 — PUSHED |
| agent-log.md | 114 lines |

Recent commits:
```
dde25e4 agents: claude session end 2026-07-31 (PUSHED)
1661789 feat: green output stamps exact commit (delegate.sh, runner.sh); protocol norms from buzz review (D-006)
1ab218d feat: agent-drives-agent delegation; fix: install.sh exited 1 on success
8d0ca92 agents: claude session end 2026-07-29 (PUSHED)
e333038 feat: drop-in distribution — self-bootstrapping install.sh (curl|sh, --wire, --tag), in-payload upgrade.sh, VERSION stamping
```
<!-- facts:end -->

## HOLD

no — HOLD lifted 2026-07-29: human provided the remote (github.com/apsolut/apsolut-agents); push allowed.

## Ownership / claims

| Task / id | Owner | Status |
|---|---|---|
| Overhaul (worktrees, scripts, dogfood) | Claude | done — see log 2026-07-28 |

## Blockers

1. None. Open question for the human: create a remote + push? (HOLD stands until then.)

## Top 3 next actions

1. Human: decide on a remote/publishing — lifts the HOLD. — human
2. Optionally run `sh install.sh <joyci> --refresh` to upgrade the joyci demo workspace docs without touching its log/state. — human or Claude
3. First real 2-agent worktree session on a live project to shake out `worktree.sh` ergonomics. — any agent

## Do-not-undo

- Coordination only in the primary worktree (`.primary` redirect) — D-001
- `--refresh` never touches `kind=instance` files — D-002
- Generated facts are script-owned — D-003

## Active docs

- Talk: `agent-log.md` · Rules: `PROTOCOL.md` · Stack: `PROJECT.md` · Concurrency: `WORKTREES.md`
- Decisions: `decisions/DECISIONS.md` (D-001…D-003)
