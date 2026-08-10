<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT_STATE — save-game checkpoint

Two zones. The **facts block** below is written by `scripts/status.sh` — never
hand-edit between its markers; it cannot go stale because it is derived from git.
The **narrative** sections are yours: hand-edit them **when they change**, delete
anything no longer true (git keeps history), keep the whole file to ~1 screen.

---

## Facts (generated)

<!-- facts:begin -->
_Generated 2026-08-11 01:44 by status.sh — do not hand-edit this block._

| | |
|--|--|
| Branch | `main` |
| Ahead/behind upstream | 0 ahead / 0 behind upstream |
| Dirty files | 1 |
| Worktrees | 1 (incl. primary) |
| Last session token | claude — 2026-08-11 — PUSHED |
| agent-log.md | 123 lines |

Recent commits:
```
771d128 feat: v0.6.0 — field-report fixes, lane preflight, filename contract, MIT license, CI
e949e61 agents: claude PUSHED token — HOLD lifted by human
dde25e4 agents: claude session end 2026-07-31 (PUSHED)
1661789 feat: green output stamps exact commit (delegate.sh, runner.sh); protocol norms from buzz review (D-006)
1ab218d feat: agent-drives-agent delegation; fix: install.sh exited 1 on success
```
<!-- facts:end -->

## HOLD

no — HOLD lifted 2026-07-29: human provided the remote (github.com/apsolut/apsolut-agents); push allowed.

## Ownership / claims

| Task / id | Owner | Status |
|---|---|---|
| v0.6.0 (delegation + field-report fixes) | Claude | done — merged to main 2026-08-11 |

## Blockers

1. None.

## Top 3 next actions

1. `doctor` command (probe + green_cmd + card/`after:` graph + rolling cost vs budget) — highest-leverage next feature per the 2026-08-11 field report. — any agent
2. Second-data-point items from the field report: refusal classification, rolling per-card cost fallback, pre-card budget check, `files:` post-card enforcement (backlog in `runs/2026-08-11-field-report-and-pre-merge-review.md`). — any agent
3. Watch the first CI run on main (shellcheck -S error + install smoke test) and fix anything it flags. — Claude

## Do-not-undo

- Coordination only in the primary worktree (`.primary` redirect) — D-001
- `--refresh` never touches `kind=instance` files — D-002
- Generated facts are script-owned — D-003

## Active docs

- Talk: `agent-log.md` · Rules: `PROTOCOL.md` · Stack: `PROJECT.md` · Concurrency: `WORKTREES.md`
- Decisions: `decisions/DECISIONS.md` (D-001…D-003)
