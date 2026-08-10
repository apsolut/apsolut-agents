<!-- apsolut-agents: tier=0 kind=instance -->
# agent-log.md — the live thread

The one place agents talk: questions, answers, handoffs, "editing X now", "found Y".
**Append-only, newest at the bottom. Never rewrite someone else's entry — reply below it.**
Map + rules live in `README.md` / `PROTOCOL.md`; this file is just the conversation.

Entry shape (keep it short — link to commits/files for detail):
```markdown
### <Agent> — <date> <optional topic>
- <what you did / are asking / decided>
- INTENT: <agent> editing <path> for <why>        # Tier 2 — before a large hot-file edit
- SPAWN: <agent> → <branch> at <path>             # written by worktree.sh spawn
- MERGED: <branch> → <default> (<hash>)           # written by worktree.sh done

### <Agent> — <date> — PUSHED | HOLD | FAILED     # session end: token in the heading
<freeform prose: what you did, what's next for whom>
```

Oversized log? `scripts/session-end.sh` auto-archives old entries to
`archive/agent-log-YYYY-MM.md` past ~400 lines.

---

## Log

### Claude — 2026-07-28 overhaul
- Rebuilt the repo from the 15-file markdown-only draft: payload moved to `template/`,
  locks + CONCURRENCY.md deleted (worktrees are Tier 2 now — D-001), scripts added
  (`status.sh`, `session-end.sh`, `worktree.sh`, `install.sh`), protocol pruned against
  evidence from the joyci run (end block → one token heading; compaction automated at
  400 lines; INTENT moved to Tier 2; `runs/` added for subagent fan-outs).
- Full acceptance test passed in scratchpad: fresh install → spawn grok worktree →
  agent-B log write via `.primary` → merge-back via `done --merge` → compaction at
  529→179 lines → `--refresh` kept instance files. Zero coordination files on the
  agent branch, as designed.
- This workspace is the live dogfood instance of `template/` — see D-002.
- Dogfood catch #1: the roster table lived in `README.md` (kind=doc) — a `--refresh`
  would have wiped it. Moved the roster to `PROJECT.md` (kind=instance) in the template
  and all references; refreshed this instance to prove the flow.

<!-- next entry below -->

### claude — 2026-07-28 — HOLD
Overhaul complete: worktrees Tier 2, scripts, dogfood. HOLD until human decides on a remote.

### Claude — 2026-07-29 night shift v0
- Ran the first idea-pipeline round (D-002-style dogfood): Claude draft → blind parallel
  reviews by AGY/Gemini + Grok → synthesized PRD, promoted to `runs/2026-07-29-night-shift-prd.md`.
  Both reviewers converged on four cuts; adopted as D-004. One process hiccup: Grok's
  first pass raced a half-written prompt file and correctly returned "kill — draft empty".
- Implemented v0: `scripts/runner.sh` (claim/spawn/timeout/green/salvage/report),
  `HEARTBEAT.md` policy (budget $25/night, ntfy.sh), `NIGHTSHIFT.md`, `after:` +
  `budget:` card fields, ready-computation in `status.sh`.
- Acceptance tests on scratch repo: happy path (T-001 green→review), dependency
  semantics failure (T-002 blocked — `after:` ≠ code visibility, now documented),
  chaos (T-666 fail→retry→blocked; T-777 hung→timeout rc=124→circuit breaker→clean
  report). Zero orphan claims, zero default-branch touches.
- Human's v0 gate choices: $25/night budget, scratch-repo supervised runs, ntfy.sh pings.
  Next for human: set `notify_url` + `green_cmd` in HEARTBEAT.md when installing into a
  real project; 3 supervised `--once` runs are the gate to real overnight use.

### claude — 2026-07-29 — HOLD
Night Shift v0 shipped and tested; HOLD stands (no remote).

### Claude — 2026-07-29 verification round
- AGY + Grok blind-reviewed runner.sh against the PRD (~20 findings, strong convergence on the claim/recovery/kill path). Hardened: full claim rewrite, dead-pid recovery (5m grace, pid-0 bug fixed), CRLF-safe parsing, midnight-safe stop with morning re-arm, lane singleton + exit trap, reset-to-pre-SHA on fail, branch assert, 5xx backoff without attempt burn, numeric sanitization, green sentinel refusal, done-only deps, exit codes. 4 findings rejected with reasons. Artifact: runs/2026-07-29-night-shift-code-review.md
- Full regression on fresh scratch: 5/5 pass (sentinel refusal, happy+deps, singleton, chaos breaker exit=2 + timeout rc=124, stale recovery).
- Next: gate run #1 with the REAL grok CLI as worker lane, supervised.

### claude — 2026-07-29 — HOLD
Runner hardened per 3-model verification; regression 5/5.

### Claude — 2026-07-29 gate run 1 of 3 — PASS
- First real-LLM lane: runner.sh drove the grok CLI on card T-010 (scratch repo). Grok claimed, worked in its worktree, one clean commit (mul + div with div-by-zero throw + tests), green passed on attempt 1 in ~1 min of a 10-min cap, card -> review, branch stayed unmerged until supervisor merge via worktree.sh done --merge; main green after merge. Spend tracked, well under cap. Zero touches of main by the agent, zero orphan claims.
- Gate criteria met for run 1. Two more supervised --once runs to pass v0; then real-project install.

### Claude — 2026-07-29 "do all" session
- Remote added + pushed: github.com/apsolut/apsolut-agents (HOLD lifted by human).
- Gate runs 2 and 3 PASSED: agy/Gemini implemented clamp (green attempt 1, ~5 min); grok on a deliberately vague card DISCOVERED the hidden strict.js contract and implemented pow + hardening (green, $0.20). v0 gate: 3/3 supervised runs clean. Learned: grok CLI reports costUSD — cost parser widened.
- PLAYBOOK shipped via the pipeline (D-005). Test-first gate live in runner (regression: refusal + spike waiver both verified).
- Safety hardening after human question: all destructive git ops now refuse non-*-wt-* paths (runner + worktree.sh); INSTALL §6 documents the pre-label-upgrade README hazard.
- joyci workspace upgraded (Tier 0+1 respected, roster ported to its PROJECT.md, logged there, left uncommitted for human).

### claude — 2026-07-29 — PUSHED
All done: 3/3 gates, PLAYBOOK, safety guards, joyci upgrade, pushed to origin.

### Claude — 2026-07-29 drop-in distribution (v0.5.0)
- install.sh is now self-bootstrapping: `curl -fsSL .../install.sh | sh -s -- . --wire` works with no clone (verified live against GitHub). --wire inserts the bootstrap block into CLAUDE.md/AGENTS.md between idempotent markers; --tag pins a release.
- Installed workspaces are self-sufficient: new `scripts/upgrade.sh` fetches the payload tarball and applies refresh rules in place (verified: customized instance file survived; pinned-tag mode works). VERSION stamped on install/upgrade; repo tagged v0.5.0.
- New user-level Claude Code skill `/apsolut-agents` (init|refresh|wire|status) wraps the whole flow — agent-native install in any project.
- degit documented as the zero-dependency alternative. Rejected for now: npm wrapper, dist-branch + git-subtree merges (revisit if customized-doc upgrades recur), submodules (breaks committed-history property).

### claude — 2026-07-29 — PUSHED
v0.5.0: drop-in distribution layer shipped and live-tested.

### Claude — 2026-07-31 buzz assimilation (D-006)
- Read block/buzz (Block's Nostr-relay hive-mind platform) end to end: ACP base prompt, orchestrator personas, PERSONA_PACK_SPEC, kickoff-silent-failures postmortem, buzz-agent design docs.
- Imported their production scar tissue as protocol prose (D-006): asymmetric publish + no-bare-acks (PROTOCOL §1), evict-on-ship (PROTOCOL §2), verification honesty — exact-commit green, full suite, scoped negatives (PROTOCOL §6), facts-decide-timers-backstop + never-self-review (DELEGATION §2/§5), goal+success-check card writing (NIGHTSHIFT). Prior-art section added to reference/multi-agent-cli-foundations.md §12.
- Rejected the platform itself (relay, keypairs, persona packs) — cross-machine problems we don't have; charter frontmatter parsed by delegate.sh noted as revisit-if-duplication-bites.
- Template edited first; verified instance copies were clean mirrors of HEAD before overwriting; four doc files mirrored.

### claude — 2026-07-31 — HOLD
buzz protocol assimilation, uncommitted for human review

### Claude — 2026-07-31 buzz import adversarially reviewed (Grok, 2 rounds)
- Grok blind-attacked the D-006 import (verdicts: 2 CUT, 3 REWRITE, 1 KEEP-nothing); its core hit was constitutional — no import had gained a script line. Converged package shipped: green output now stamps `green_cmd @ <HEAD>` in delegate.sh + runner.sh (mechanism), all five norms compressed and citation-stripped, "full suite" cut as harmful, never-self-review softened to prefer-fresh-eyes with solo fallback, NIGHTSHIFT clause folded not appended, reference §12 shrunk to a pointer. D-006 rewritten to record the converged form. Artifact: runs/2026-07-31-buzz-review-grok.md (~$0.22, 2 rounds).
- Both models conceded points on the record; disagreement that survived (Grok's "zero prose until a local scar") is logged as rejected with reasons in D-006.

### claude — 2026-07-31 — HOLD
buzz package converged via 2-round grok review, uncommitted

### claude — 2026-07-31 — PUSHED
HOLD lifted by human; buzz package (D-006 converged form + green HEAD stamps) pushed to origin.

### Claude — 2026-08-11 field-report triage + pre-merge review → v0.6.0
- Pre-merge fan-out: 3 subagents (shell correctness / docs parity / upgrades), ~220k tokens, ~5 min. Docs parity clean; shell review verdict "NOT safe to merge" — 4 confirmed bugs, each reproduced. Human delivered a full night-shift field report from a real project the same hour.
- Fixed all four confirmed review bugs (stop-orphans-agent, upgrade.sh self-overwrite, throttle-regex false positives, installer trusting foreign template/) plus the field report's certain ones (filename≠id silent miss, no lane preflight, after: deadlock warning, status.sh token grep). Diffstat two-dot report bug was already fixed on this branch — reporter's copy was older.
- Shipped v0.6.0: LICENSE (MIT, human choice — D-007), CHANGELOG, CI (shellcheck + install smoke test), template/.gitattributes, filename contract enforced (D-007). Deferred-with-reasons backlog in the runs file.
- Artifact: runs/2026-08-11-field-report-and-pre-merge-review.md

### claude — 2026-08-11 — PUSHED
v0.6.0 shipped: 4-agent verified fixes + field-report triage merged to main, tagged, CI live. Next: doctor command, second-data-point backlog (see runs/2026-08-11).

### Claude — 2026-08-11 (later) — license attribution + FUTURE.md
- Attribution made structural, not historical: SPDX headers in every script (survives single-file reuse), LICENSE shipped inside template/ so installed workspaces carry it, README license section. Rejected the history-rewrite route (first-commit LICENSE injection): force-push breaks tags/clones/DECISIONS hashes and buys nothing — a re-user can rewrite history too; MIT's force is legal, not cryptographic.
- FUTURE.md (renamed from TODO.md): ideas parking lot seeded with the never-auto-delete-worktrees constraint, Docker-isolated lanes, and a 4-agent idea fan-out (throughput/safety/DX/memory). Artifact: runs/2026-08-11-future-ideas-fanout.md
- Default night budget raised $25 → $100 (HEARTBEAT template + dogfood + runner fallback).
