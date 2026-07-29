<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT_STATE — save-game checkpoint

Two zones. The **facts block** below is written by `scripts/status.sh` — never
hand-edit between its markers; it cannot go stale because it is derived from git.
The **narrative** sections are yours: hand-edit them **when they change**, delete
anything no longer true (git keeps history), keep the whole file to ~1 screen.

---

## Facts (generated)

<!-- facts:begin -->
_Generated 2026-07-29 03:39 by status.sh — do not hand-edit this block._

| | |
|--|--|
| Branch | `main` |
| Ahead/behind upstream | 0 ahead / 0 behind upstream |
| Dirty files | 5 |
| Worktrees | 1 (incl. primary) |
| Last session token | claude — 2026-07-29 — PUSHED |
| agent-log.md | 95 lines |

Recent commits:
```
e333038 feat: drop-in distribution — self-bootstrapping install.sh (curl|sh, --wire, --tag), in-payload upgrade.sh, VERSION stamping
f33a7d0 agents: claude session end 2026-07-29 (PUSHED)
f8aa8a2 feat: PLAYBOOK.md (3-model synthesis) — risk tags, hard test-first gate, card contract; widen cost parser
102c885 fix: destructive git ops refuse any path that is not a spawned *-wt-* worktree
6d1e320 agents: gate run 1 of 3 passed (real grok lane, scratch)
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
