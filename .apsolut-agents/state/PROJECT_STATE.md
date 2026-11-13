<!-- apsolut-agents: tier=0 kind=instance -->
# PROJECT_STATE — save-game checkpoint

Two zones. The **facts block** below is written by `scripts/status.sh` — never
hand-edit between its markers; it cannot go stale because it is derived from git.
The **narrative** sections are yours: hand-edit them **when they change**, delete
anything no longer true (git keeps history), keep the whole file to ~1 screen.

---

## Facts (generated)

<!-- facts:begin -->
_Generated 2026-11-13 22:42 by status.sh — do not hand-edit this block._

| | |
|--|--|
| Branch | `main` |
| Ahead/behind upstream | 2 ahead / 0 behind upstream |
| Dirty files | 2 |
| Worktrees | 1 (incl. primary) |
| Last session token | claude — 2026-11-13 — PUSHED |
| agent-log.md | 379 lines |

Recent commits:
```
9543707 test: a failed stress round prints where each lane stopped
490a122 feat: v0.14.0 — spend caps off by default; status.sh survives D-008
b90e583 agents: claude session end 2026-11-12 (PUSHED)
16eb6a7 chore: ignore the local TODO.md
d3d950f agents: claude session end 2026-11-12 (HOLD)
```
<!-- facts:end -->

## HOLD

no — HOLD lifted 2026-07-29: human provided the remote (github.com/apsolut/apsolut-agents); push allowed.

## Ownership / claims

| Task / id | Owner | Status |
|---|---|---|
| v0.9.0 (goal loop) + v0.10.0 (runner-enforced checks, four-model review) | Claude | done — on main, tagged and pushed 2026-11-10 (PR #1) |
| v0.11.0 (lane caps) + v0.12.0 (risk routing, `Blocked by:`, `intake.sh`) | Claude | done — on main and tagged, pushed 2026-11-11 (fast-forward, no PR) |
| v0.13.0 (fail fast, lane parking, `nightshift.sh`), v0.13.1 (full access by default, one report for all lanes), v0.13.2 (crash safety) | Claude | done — on main and tagged (PRs #2 to #5); v0.13.2 pushed 2026-11-12 |
| v0.14.0 (spend caps off by default; empty or `0` = no cap; README caution block) — D-008. Also in it: `status.sh` no longer dies on a decision id of 008 or above | Claude | done — on main and tagged, pushed 2026-11-13 (PR #6, fast-forward). This repo's own `HEARTBEAT.md` still says 100 / 25 (the human's file) |

## Blockers

1. None.

## Top 3 next actions

1. Waiting on the human: (a) one run with the real signing key locked (lock 1Password once during a night); (b) a harder real night with real models, see 2(b); (c) the `GROK_CLAUDE_*_ENABLED=0` prefix on the template's Grok line: keep it, or make Grok full access by default like Claude; (d) Antigravity's consumer-plan terms. The human keeps the full list in a local, git-ignored `TODO.md` at the repo root. — human
2. Known gaps after v0.13.2: (a) parking and the git time limit were tested with a fake signing program only, never with the real key locked; (b) still never run with real models: a verifier rejection and retry, the advisor, a blocked card, a conflict on the night branch, STUCK, a budget stop, two lanes in goal mode; (c) `intake.sh` has never written a card from a live issue; (d) found by the 2026-11-12 Codex audits and not fixed (CHANGELOG v0.13.2 "Known, not fixed"), plus: `session-end.sh` log compaction can drop a line appended in the same moment; two runners for the same agent started in the same instant can both pass the lane check; a lane that joins while the last lane's reviewer runs can add a second Attention section; `install.sh --refresh` and `upgrade.sh` overwrite local edits of doc and generated files by design, with no backup; (e) Grok, asked headless for a code audit, returned only its opening lines and no findings — not looked into. Ideas weighed and not built: Enola as a `green_cmd` gate, Jev for risk routing, async verification, more parallel lanes. — human / next agent
3. Installed copies elsewhere (e.g. the n8n project) need `sh .apsolut-agents/scripts/upgrade.sh`, then `doctor.sh`: no upgrade rewrites `HEARTBEAT.md`, so the new `cmd_` lines, `risk_tags:`, `intake_label:` and `git_timeout_seconds:` (optional, 300 when absent) are copied by hand from `template/HEARTBEAT.md`. Leftover ideas are in `../FUTURE.md` (stall detector, failure-mode routing, score ratchet, worker routing by risk). Merged branches on GitHub can be deleted: `lane-reports`, `v0.13.1-full-access`, `v0.13-fail-fast`, `v0.10-hardening`, `feat/delegation-and-installer-fixes`, `v0.13.2-crash-safety`. — human

## Do-not-undo

- Coordination only in the primary worktree (`.primary` redirect) — D-001
- `--refresh` never touches `kind=instance` files — D-002
- Generated facts are script-owned — D-003

## Active docs

- Talk: `agent-log.md` · Rules: `PROTOCOL.md` · Stack: `PROJECT.md` · Concurrency: `WORKTREES.md`
- Decisions: `decisions/DECISIONS.md` (D-001…D-008) · Ideas: `../FUTURE.md` · Releases: `../CHANGELOG.md`
