<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT_STATE — save-game checkpoint

Two zones. The **facts block** below is written by `scripts/status.sh` — never
hand-edit between its markers; it cannot go stale because it is derived from git.
The **narrative** sections are yours: hand-edit them **when they change**, delete
anything no longer true (git keeps history), keep the whole file to ~1 screen.

---

## Facts (generated)

<!-- facts:begin -->
_Generated 2026-11-11 01:38 by status.sh — do not hand-edit this block._

| | |
|--|--|
| Branch | `v0.12-risk-intake` |
| Ahead/behind upstream | no upstream configured |
| Dirty files | 3 |
| Worktrees | 1 (incl. primary) |
| Last session token | claude — 2026-11-11 — HOLD |
| agent-log.md | 198 lines |

Recent commits:
```
e13a954 docs: bring every doc up to v0.12
5611a13 agents: claude session end 2026-11-11 (HOLD)
95e95da feat: v0.12.0 — risk picks the judge, blocked-by, GitHub issue intake
1cce412 agents: claude session end 2026-11-10 (HOLD) — v0.11.0 lane caps on branch
592ae6c feat: v0.11.0 — lane caps for CLIs that grew their own agents
```
<!-- facts:end -->

## HOLD

no — HOLD lifted 2026-07-29: human provided the remote (github.com/apsolut/apsolut-agents); push allowed.

## Ownership / claims

| Task / id | Owner | Status |
|---|---|---|
| v0.9.0 (goal loop) + v0.10.0 (runner-enforced checks, four-model review) | Claude | done — on main, tagged and pushed 2026-11-10 (PR #1) |
| v0.11.0 (lane caps: per-call budget, native subagents off, Codex lane, exit-0 fix) | Claude | on branch `v0.11-lane-caps`, not pushed — human reviews, merges, tags |
| v0.12.0 (risk routing, `Blocked by:`, `intake.sh`, weak-verifier warning) | Claude | on branch `v0.12-risk-intake` (stacked on `v0.11-lane-caps`), not pushed. Merging it lands both versions |

## Blockers

1. None.

## Top 3 next actions

1. Review and merge `v0.12-risk-intake` (it carries v0.11.0 and v0.12.0), then tag both. CI has not run on either: shellcheck is not installed locally. — human
2. Run the first supervised real-model `runner.sh <agent> --once` goal night on a small repo. Everything since v0.9 (goal loop, verifier ladder, lane caps, risk routing, `Blocked by:`) is proven only by `tests/goal-loop.sh` (64/64) against a fake CLI; the v0.11 `cmd_` lines also answer a live `doctor.sh` probe. `intake.sh` has never written a card from a live issue: label one issue `agents` and run it. — human + any agent
3. Installed copies elsewhere (e.g. the n8n project) need `sh .apsolut-agents/scripts/upgrade.sh`, then `doctor.sh`: no upgrade rewrites `HEARTBEAT.md`, so the new `cmd_` lines, `risk_tags:` and `intake_label:` are copied by hand from `template/HEARTBEAT.md`. Leftover ideas are in `../FUTURE.md` (stall detector, failure-mode routing, score ratchet, worker routing by risk). Merged branches `v0.9-goal-loop` and `v0.10-hardening` can be deleted. — human

## Do-not-undo

- Coordination only in the primary worktree (`.primary` redirect) — D-001
- `--refresh` never touches `kind=instance` files — D-002
- Generated facts are script-owned — D-003

## Active docs

- Talk: `agent-log.md` · Rules: `PROTOCOL.md` · Stack: `PROJECT.md` · Concurrency: `WORKTREES.md`
- Decisions: `decisions/DECISIONS.md` (D-001…D-007) · Ideas: `../FUTURE.md` · Releases: `../CHANGELOG.md`
