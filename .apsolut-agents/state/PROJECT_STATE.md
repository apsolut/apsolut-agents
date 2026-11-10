<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT_STATE — save-game checkpoint

Two zones. The **facts block** below is written by `scripts/status.sh` — never
hand-edit between its markers; it cannot go stale because it is derived from git.
The **narrative** sections are yours: hand-edit them **when they change**, delete
anything no longer true (git keeps history), keep the whole file to ~1 screen.

---

## Facts (generated)

<!-- facts:begin -->
_Generated 2026-11-10 02:18 by status.sh — do not hand-edit this block._

| | |
|--|--|
| Branch | `v0.10-hardening` |
| Ahead/behind upstream | no upstream configured |
| Dirty files | 2 |
| Worktrees | 1 (incl. primary) |
| Last session token | claude — 2026-11-10 — HOLD |
| agent-log.md | 164 lines |

Recent commits:
```
8881f39 fix: v0.10.0 second review round (Codex + Grok on the diff)
aa50077 feat: v0.10.0 — the runner enforces what the prompts only asked
b96e82b Merge v0.9-goal-loop: run the night until a final-product predicate passes
9a89a1f agents: claude session end 2026-11-09 (HOLD) — v0.9.0 goal loop on branch
a6c812a feat: v0.9.0 — goal loop: run the night until a final-product predicate passes
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
