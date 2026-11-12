<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT_STATE — save-game checkpoint

Two zones. The **facts block** below is written by `scripts/status.sh` — never
hand-edit between its markers; it cannot go stale because it is derived from git.
The **narrative** sections are yours: hand-edit them **when they change**, delete
anything no longer true (git keeps history), keep the whole file to ~1 screen.

---

## Facts (generated)

<!-- facts:begin -->
_Generated 2026-11-12 09:45 by status.sh — do not hand-edit this block._

| | |
|--|--|
| Branch | `v0.13.2-crash-safety` |
| Ahead/behind upstream | 1 ahead / 0 behind upstream |
| Dirty files | 1 |
| Worktrees | 1 (incl. primary) |
| Last session token | claude — 2026-11-12 — HOLD |
| agent-log.md | 335 lines |

Recent commits:
```
fde8e13 test: two lanes started together, as a stress test in the repo and in CI
2ccced3 fix: v0.13.2 — a stopped or crashed lane says so, and the night heals
b866867 agents: claude session end 2026-11-12 (PUSHED)
eabe5e9 agents: claude session end 2026-11-12 (HOLD)
968b6fa docs: .claude/ as an optional protect entry; log the stability pass
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
2. Known gaps after v0.13.2: (a) parking and the git time limit were tested with a fake signing program only, never with the real key locked; (b) still never run with real models: a verifier rejection and retry, the advisor, a blocked card, a conflict on the night branch, STUCK, a budget stop, two lanes in goal mode; (c) `intake.sh` has never written a card from a live issue; (d) found by the 2026-11-12 Codex audits and not fixed (CHANGELOG v0.13.2 "Known, not fixed"), plus: `session-end.sh` log compaction can drop a line appended in the same moment; two runners for the same agent started in the same instant can both pass the lane check; a lane that joins while the last lane's reviewer runs can add a second Attention section; `install.sh --refresh` and `upgrade.sh` overwrite local edits of doc and generated files by design, with no backup; (e) Grok, asked headless for a code audit, returned only its opening lines and no findings — not looked into. Ideas weighed and not built: Enola as a `green_cmd` gate, Jev for risk routing, async verification, more parallel lanes. — human / next agent
3. Installed copies elsewhere (e.g. the n8n project) need `sh .apsolut-agents/scripts/upgrade.sh`, then `doctor.sh`: no upgrade rewrites `HEARTBEAT.md`, so the new `cmd_` lines, `risk_tags:` and `intake_label:` are copied by hand from `template/HEARTBEAT.md`. Leftover ideas are in `../FUTURE.md` (stall detector, failure-mode routing, score ratchet, worker routing by risk). Merged branches `v0.9-goal-loop` and `v0.10-hardening` can be deleted. — human

## Do-not-undo

- Coordination only in the primary worktree (`.primary` redirect) — D-001
- `--refresh` never touches `kind=instance` files — D-002
- Generated facts are script-owned — D-003

## Active docs

- Talk: `agent-log.md` · Rules: `PROTOCOL.md` · Stack: `PROJECT.md` · Concurrency: `WORKTREES.md`
- Decisions: `decisions/DECISIONS.md` (D-001…D-007) · Ideas: `../FUTURE.md` · Releases: `../CHANGELOG.md`
