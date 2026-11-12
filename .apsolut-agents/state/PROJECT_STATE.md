<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT_STATE — save-game checkpoint

Two zones. The **facts block** below is written by `scripts/status.sh` — never
hand-edit between its markers; it cannot go stale because it is derived from git.
The **narrative** sections are yours: hand-edit them **when they change**, delete
anything no longer true (git keeps history), keep the whole file to ~1 screen.

---

## Facts (generated)

<!-- facts:begin -->
_Generated 2026-11-12 04:44 by status.sh — do not hand-edit this block._

| | |
|--|--|
| Branch | `main` |
| Ahead/behind upstream | 4 ahead / 0 behind upstream |
| Dirty files | 1 |
| Worktrees | 1 (incl. primary) |
| Last session token | claude — 2026-11-12 — PUSHED |
| agent-log.md | 295 lines |

Recent commits:
```
14a9d54 fix: brace the escape variable in colour codes (shellcheck SC1087)
1428e8b agents: claude session end 2026-11-11 (HOLD)
5e7b469 docs: record the two-lane real run and the open gaps for v0.13.0
1c3c0cf feat: v0.13.0 — a night no longer dies waiting for a human
c65eba8 agents: claude session end 2026-11-11 (PUSHED)
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

1. Review and land v0.13.0 (branch `v0.13-fail-fast`, not pushed, not tagged): no-prompt switches, lane parking on a locked signing key or a signed-out CLI (exit 7), `nightshift.sh`, leaner `cmd_claude`/`cmd_grok`, and a fix for a runner crash when the verifier CLI exits non-zero. `tests/goal-loop.sh` 84/84 locally; CI has not run on it. — human
2. Known gaps: (a) with two lanes, both write the same `runs/night-<date>.md` and the last one wins — make the report per lane or merged; (b) the report's spend line is written before the reviewer is charged; (c) a signing key that locks while the agent itself is committing is only caught at the next check, and the park was never exercised with a real locked key (only the test's fake signer); (d) still never run with real models: a verifier rejection and retry, the advisor, a blocked card, a conflict on the night branch, STUCK, a budget stop; (e) `intake.sh` has never written a card from a live issue. Ideas weighed and not built: Enola as a `green_cmd` gate, Jev for risk routing, async verification, more parallel lanes. — human / next agent
3. Installed copies elsewhere (e.g. the n8n project) need `sh .apsolut-agents/scripts/upgrade.sh`, then `doctor.sh`: no upgrade rewrites `HEARTBEAT.md`, so the new `cmd_` lines, `risk_tags:` and `intake_label:` are copied by hand from `template/HEARTBEAT.md`. Leftover ideas are in `../FUTURE.md` (stall detector, failure-mode routing, score ratchet, worker routing by risk). Merged branches `v0.9-goal-loop` and `v0.10-hardening` can be deleted. — human

## Do-not-undo

- Coordination only in the primary worktree (`.primary` redirect) — D-001
- `--refresh` never touches `kind=instance` files — D-002
- Generated facts are script-owned — D-003

## Active docs

- Talk: `agent-log.md` · Rules: `PROTOCOL.md` · Stack: `PROJECT.md` · Concurrency: `WORKTREES.md`
- Decisions: `decisions/DECISIONS.md` (D-001…D-007) · Ideas: `../FUTURE.md` · Releases: `../CHANGELOG.md`
