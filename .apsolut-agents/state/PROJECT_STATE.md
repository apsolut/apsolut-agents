<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT_STATE — save-game checkpoint

Two zones. The **facts block** below is written by `scripts/status.sh` — never
hand-edit between its markers; it cannot go stale because it is derived from git.
The **narrative** sections are yours: hand-edit them **when they change**, delete
anything no longer true (git keeps history), keep the whole file to ~1 screen.

---

## Facts (generated)

<!-- facts:begin -->
_Generated 2026-07-28 21:26 by status.sh — do not hand-edit this block._

| | |
|--|--|
| Branch | `main` |
| Ahead/behind upstream | no upstream configured |
| Dirty files | 1 |
| Worktrees | 1 (incl. primary) |
| Last session token | claude — 2026-07-28 — HOLD |
| agent-log.md | 45 lines |

Recent commits:
```
b460002 fix: roster is instance data — move it from README.md to PROJECT.md (dogfood catch)
bcb1713 fix: status.sh table spacing + warnings newline (found in scratchpad acceptance test)
9e373fa feat: status/session-end/worktree scripts, installer, repo README
e46fabb docs: rewrite payload — worktrees replace locks, pruned protocol, tier labels, runs/, CLAUDE snippet
e980707 refactor: move payload into template/, drop locks + CONCURRENCY (worktrees replace them)
```
<!-- facts:end -->

## HOLD

yes — no remote exists yet; human decides if/where to publish. Only the human lifts a HOLD.

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
