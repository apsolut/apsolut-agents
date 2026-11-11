<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT_STATE — save-game checkpoint

Two zones. The **facts block** below is written by `scripts/status.sh` — never
hand-edit between its markers; it cannot go stale because it is derived from git.
The **narrative** sections are yours: hand-edit them **when they change**, delete
anything no longer true (git keeps history), keep the whole file to ~1 screen.

---

## Facts (generated)

<!-- facts:begin -->
_Generated 2026-11-11 04:45 by status.sh — do not hand-edit this block._

| | |
|--|--|
| Branch | `main` |
| Ahead/behind upstream | 0 ahead / 0 behind upstream |
| Dirty files | 1 |
| Worktrees | 1 (incl. primary) |
| Last session token | claude — 2026-11-11 — PUSHED |
| agent-log.md | 226 lines |

Recent commits:
```
0ed9d37 agents: claude session end 2026-11-11 (HOLD)
6155ab7 docs: rebuild the README around a first screen for newcomers
40cc504 agents: claude session end 2026-11-11 (PUSHED)
ed39094 chore: name the copyright holder — Aleksandar Perisic (apsolut)
9d608ed agents: claude session end 2026-11-11 (PUSHED)
```
<!-- facts:end -->

## HOLD

no — HOLD lifted 2026-07-29: human provided the remote (github.com/apsolut/apsolut-agents); push allowed.

## Ownership / claims

| Task / id | Owner | Status |
|---|---|---|
| v0.9.0 (goal loop) + v0.10.0 (runner-enforced checks, four-model review) | Claude | done — on main, tagged and pushed 2026-11-10 (PR #1) |
| v0.11.0 (lane caps) + v0.12.0 (risk routing, `Blocked by:`, `intake.sh`) | Claude | done — on main, pushed 2026-11-11 (fast-forward, no PR), CI green. NOT tagged yet |

## Blockers

1. None.

## Top 3 next actions

1. Tag the two releases if you want them pinnable: `v0.11.0` on `1cce412`, `v0.12.0` on the main tip. Local branches `v0.11-lane-caps` and `v0.12-risk-intake` are merged and can be deleted. — human
2. Run the first supervised real-model `runner.sh <agent> --once` goal night on a small repo. Everything since v0.9 (goal loop, verifier ladder, lane caps, risk routing, `Blocked by:`) is proven only by `tests/goal-loop.sh` (64/64) against a fake CLI; the v0.11 `cmd_` lines also answer a live `doctor.sh` probe. `intake.sh` has never written a card from a live issue: label one issue `agents` and run it. — human + any agent
3. Installed copies elsewhere (e.g. the n8n project) need `sh .apsolut-agents/scripts/upgrade.sh`, then `doctor.sh`: no upgrade rewrites `HEARTBEAT.md`, so the new `cmd_` lines, `risk_tags:` and `intake_label:` are copied by hand from `template/HEARTBEAT.md`. Leftover ideas are in `../FUTURE.md` (stall detector, failure-mode routing, score ratchet, worker routing by risk). Merged branches `v0.9-goal-loop` and `v0.10-hardening` can be deleted. — human

## Do-not-undo

- Coordination only in the primary worktree (`.primary` redirect) — D-001
- `--refresh` never touches `kind=instance` files — D-002
- Generated facts are script-owned — D-003

## Active docs

- Talk: `agent-log.md` · Rules: `PROTOCOL.md` · Stack: `PROJECT.md` · Concurrency: `WORKTREES.md`
- Decisions: `decisions/DECISIONS.md` (D-001…D-007) · Ideas: `../FUTURE.md` · Releases: `../CHANGELOG.md`
