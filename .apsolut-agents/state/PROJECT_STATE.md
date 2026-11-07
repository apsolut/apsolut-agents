<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT_STATE — save-game checkpoint

Two zones. The **facts block** below is written by `scripts/status.sh` — never
hand-edit between its markers; it cannot go stale because it is derived from git.
The **narrative** sections are yours: hand-edit them **when they change**, delete
anything no longer true (git keeps history), keep the whole file to ~1 screen.

---

## Facts (generated)

<!-- facts:begin -->
_Generated 2026-11-07 16:05 by status.sh — do not hand-edit this block._

| | |
|--|--|
| Branch | `main` |
| Ahead/behind upstream | 0 ahead / 0 behind upstream |
| Dirty files | 3 |
| Worktrees | 1 (incl. primary) |
| Last session token | claude — 2026-11-07 — PUSHED |
| agent-log.md | 147 lines |

Recent commits:
```
f0fb80c feat: v0.8.2 — refuse a check that changes the merge
5329c33 feat: v0.8.1 — prove the merge before the primary branch moves
445b244 feat: v0.8.0 — review leftover worktrees, seal delegate push
5ad36fb fix: v0.7.1 — harness failures no longer read as card failures (field incident #2)
29d5e9b feat: v0.7.0 — scripts/doctor.sh one-command workspace preflight
```
<!-- facts:end -->

## HOLD

no — HOLD lifted 2026-07-29: human provided the remote (github.com/apsolut/apsolut-agents); push allowed.

## Ownership / claims

| Task / id | Owner | Status |
|---|---|---|
| v0.8.0–v0.8.2 (worktree review, push seal, proven merge) | Claude | done — on main, tagged 2026-11-07 |

## Blockers

1. None.

## Top 3 next actions

1. Night-test the runner paths with a real supervised `--once` run on a live project: baseline green (v0.7.1), failure-context retries, evidence refs, preflight probe, and the v0.8.1/0.8.2 proven `done --merge`. Scratch-tested with a fake CLI lane only. — human + any agent
2. Second-data-point items from the field report: refusal/infra classification, rolling per-card cost fallback, pre-card budget check, `files:` post-card enforcement (backlog in `runs/2026-08-11-field-report-and-pre-merge-review.md`; field incident #2 is a data point for harness-vs-card attribution). — any agent
3. Next Safer item from FUTURE.md: round-boundary tamper canary (structural no-push shipped in v0.8.0). Installed copies elsewhere (e.g. the n8n project) need `sh .apsolut-agents/scripts/upgrade.sh` to pick up v0.8.2. — any agent

## Do-not-undo

- Coordination only in the primary worktree (`.primary` redirect) — D-001
- `--refresh` never touches `kind=instance` files — D-002
- Generated facts are script-owned — D-003

## Active docs

- Talk: `agent-log.md` · Rules: `PROTOCOL.md` · Stack: `PROJECT.md` · Concurrency: `WORKTREES.md`
- Decisions: `decisions/DECISIONS.md` (D-001…D-007) · Ideas: `../FUTURE.md` · Releases: `../CHANGELOG.md`
