<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT_STATE — save-game checkpoint

Two zones. The **facts block** below is written by `scripts/status.sh` — never
hand-edit between its markers; it cannot go stale because it is derived from git.
The **narrative** sections are yours: hand-edit them **when they change**, delete
anything no longer true (git keeps history), keep the whole file to ~1 screen.

---

## Facts (generated)

<!-- facts:begin -->
_Generated 2026-11-10 03:19 by status.sh — do not hand-edit this block._

| | |
|--|--|
| Branch | `main` |
| Ahead/behind upstream | 0 ahead / 0 behind upstream |
| Dirty files | 17 |
| Worktrees | 1 (incl. primary) |
| Last session token | claude — 2026-11-10 — PUSHED |
| agent-log.md | 172 lines |

Recent commits:
```
444b782 Merge pull request #1 from apsolut/v0.10-hardening
c995c27 fix: doctor probes a stdin lane through stdin, like the runner
db6bb84 agents: claude session end 2026-11-10 (HOLD) — v0.10.0 four-model review on branch
8881f39 fix: v0.10.0 second review round (Codex + Grok on the diff)
aa50077 feat: v0.10.0 — the runner enforces what the prompts only asked
```
<!-- facts:end -->

## HOLD

no — HOLD lifted 2026-07-29: human provided the remote (github.com/apsolut/apsolut-agents); push allowed.

## Ownership / claims

| Task / id | Owner | Status |
|---|---|---|
| v0.9.0 (goal loop) + v0.10.0 (runner-enforced checks, four-model review) | Claude | done — on main, tagged and pushed 2026-11-10 (PR #1) |

## Blockers

1. None.

## Top 3 next actions

1. Run the first supervised real-model `runner.sh <agent> --once` goal night on a small repo. v0.9/v0.10 (goal loop, verifier ladder, stdin prompts, throttle detection, night-branch integration) are proven only by `tests/goal-loop.sh` (43/43) against a fake CLI. — human + any agent
2. Pick from the v0.10 review leftovers in `../FUTURE.md` ("raised, not shipped"): stall detector, failure-mode routing, and one design for the score ratchet. Process-group containment and real isolation both point at Docker lanes. Record: `runs/2026-11-10-four-model-review.md`. — any agent
3. Installed copies elsewhere (e.g. the n8n project) need `sh .apsolut-agents/scripts/upgrade.sh` to pick up v0.10.0; `--once` now means one card (old behaviour is `--drain`). Merged branches `v0.9-goal-loop` and `v0.10-hardening` can be deleted. — human

## Do-not-undo

- Coordination only in the primary worktree (`.primary` redirect) — D-001
- `--refresh` never touches `kind=instance` files — D-002
- Generated facts are script-owned — D-003

## Active docs

- Talk: `agent-log.md` · Rules: `PROTOCOL.md` · Stack: `PROJECT.md` · Concurrency: `WORKTREES.md`
- Decisions: `decisions/DECISIONS.md` (D-001…D-007) · Ideas: `../FUTURE.md` · Releases: `../CHANGELOG.md`
