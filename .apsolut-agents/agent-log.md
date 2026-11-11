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

### Claude — 2026-08-11 (later) — failure-context retries + evidence refs shipped
- Graduated from FUTURE.md after 2026 ecosystem research validated both (Ralph-loop re-feed mechanism; evidence preservation): runner red path now pins each attempt under refs/apsolut/attempts/ and feeds the failed diff + output tail into the next attempt prompt; backoff path salvages + pins before reset (a 429 no longer destroys work). Logic reviewed + syntax-checked, not yet night-tested — first real night validates.

### Claude — 2026-08-11 (later) — doctor.sh shipped (v0.7.0)
- scripts/doctor.sh: one-command preflight (tools, HEARTBEAT sanity, card contract + after: graph incl. cycles, claims, green on primary, rolling cost vs budget, opt-in live CLI probes; exit 1 on any FAIL). Tested on a scratch board with planted defects (bad filename, missing dep, cycle — all caught) and a clean board (exit 0).
- Dogfood catch: doctor flagged that this workspace never defined green_cmd — now set to sh -n over all scripts; doctor exits 0 here.
- VERSION 0.7.0, CHANGELOG, NIGHTSHIFT gate + README updated; doctor entry evicted from FUTURE.md.

### Claude — 2026-08-11 (later) — field incident #2 fixed (v0.7.1)
- Human night run: green_cmd was a relative path to an untracked helper — passed on primary, failed in every worktree, read as cards failing; breaker tripped, 3 cards never ran. Evidence refs held (first field validation — both branches restored from refs/apsolut/attempts/).
- Shipped: runner baseline green on pristine worktree (harness failure = exit 4, no cards charged); doctor proves green in a throwaway worktree + flags untracked files: inputs + missing frontmatter keys; worktree.sh fm_set inserts missing keys (was silently dropping spawn records). End-to-end tested on scratch with a fake CLI lane, both paths. Artifact: runs/2026-08-11-field-incident-green-in-worktree.md

### Claude — 2026-11-07 — v0.8.x tagged, state caught up
- v0.8.0 / v0.8.1 / v0.8.2 (2026-10-24: `worktree.sh review`, `done --jar/--reject` + verdicts, push seal at spawn, doctor `--bare` check, proven `done --merge` that never moves primary on red, refusal when green_cmd mutates the merge) were pushed to main but never tagged — `install.sh --tag` users were pinned to v0.7.1. Tagged on their release commits and pushed.
- PROJECT_STATE narrative refreshed (no-push item done; tamper canary is next Safer). The 2026-08-11 HANDOFF.md was stale and untracked; its live content is folded into PROJECT_STATE, so it was dropped rather than published.

### claude — 2026-11-07 — PUSHED
v0.8.x tagged; state caught up before machine reinstall.

### claude — 2026-11-09 — v0.9.0 goal loop (branch v0.9-goal-loop, not pushed)
- Read cursor/plugins pstack, orchestrate, advisor, thermos, dyl-stack, agent-compatibility and pr-review-canvas. Kept only what a script here can enforce or a one-line prompt rule can carry. Mapping and credits: template/prompts/README.md.
- Shipped in a6c812a: GOAL.md (done_cmd predicate), the goal loop in runner.sh (night integration branch, planner rounds, plateau/STUCK stops), role prompts (worker, verifier, planner, advisor, review), structured handoffs, the verifier verdict ladder, advisor retries, a morning Attention section, the trail TSV + trail.sh, andon.sh, the tamper canary, `spawn --base`, and the doctor [goal loop] checks.
- Verified: tests/goal-loop.sh, 28/28 checks over 7 scenarios against a scripted fake CLI. shellcheck -S error is clean, and install parity holds. A 0.8.2→0.9.0 refresh keeps HEARTBEAT.md and runs plain mode. NOT yet run against a real model night. The first supervised `runner.sh <agent> --once` with real cmd_ lines is the v0 gate.
- Decision for the human: the goal loop merges onto a night branch overnight, which loosens "no overnight merges" (the default branch still never moves). It only happens when GOAL.md done_cmd is set.

### claude — 2026-11-09 — HOLD
v0.9.0 is committed on branch v0.9-goal-loop and not pushed. The human reviews it, merges to main, and tags v0.9.0. Next: a supervised real-model `--once` goal night on a small repo.

### claude — 2026-11-10 — v0.10.0 from a four-model review (branch v0.10-hardening, not pushed)
- v0.9.0 merged to main (b96e82b) and tagged; the push was denied by the promptstash quorum, so it is a human push.
- Round 1, blind: Claude, Codex, Grok and agy each reviewed v0.9 against the Cursor plugins. 4/4 said keep this engine and port the plugins' mechanisms as code. Round 2: Codex and Grok reviewed the diff and found 13 issues, all fixed. Record: runs/2026-11-10-four-model-review.md.
- aa50077 + 8881f39: see CHANGELOG v0.10.0. tests/goal-loop.sh 43/43, shellcheck -S error clean, install parity OK. Still not run against a real model night.

### claude — 2026-11-10 — HOLD
v0.10.0 is on branch v0.10-hardening, unpushed. The human pushes main + v0.9.0, then reviews and merges v0.10-hardening and tags v0.10.0. Next: one supervised real-model `runner.sh <agent> --once`.

### claude — 2026-11-10 — v0.10.0 shipped, state caught up
- The human pushed main + v0.9.0, merged PR #1 (v0.10-hardening → main, 444b782) and tagged v0.10.0; the tag is on the remote and CI is green on main. The session that did it ended before its session-end (machine trouble), so the HOLD entry above was left standing.
- Checked after the fact: `git fsck` clean, no interrupted git operation, main == origin/main, tests/goal-loop.sh 43/43 locally.
- This repo's own workspace refreshed 0.8.2 → 0.10.0 (`install.sh . --refresh`; instance files untouched). PROJECT_STATE ownership and next actions rewritten for v0.10.

### claude — 2026-11-10 — PUSHED
v0.10.0 merged, tagged and pushed; workspace refreshed to 0.10.0, state caught up.

### claude — 2026-11-10 — v0.11.0 lane caps from a three-model consult (branch v0.11-lane-caps, not pushed)
- Read the installed CLIs (claude 2.1.322, codex 0.167.0, grok 1.0.70, agy 1.5.3): all four now ship native subagents, goal loops and spend or time flags. Wrote six proposals. Claude, Grok and agy judged them alone, read-only. Record: runs/2026-11-10-lane-caps-consult.md.
- Shipped the four all three would ship, with their corrections: a per-call budget ($APSOLUT_CALL_BUDGET_USD, a cap hit blocks), native subagents off on the cmd_ lines, agy's own timeout read as a timeout, a Codex lane with per-agent cost rates. Also fixed "exit 0 is read as finished" (a cancelled turn or a denied tool went to green_cmd), which the consult itself hit twice.
- Not shipped: native sandboxes (2 for, 1 against) and schema output (0 for, 3 against). Reasons in FUTURE.md.
- Verified: tests/goal-loop.sh 48/48, install parity, and a live doctor.sh probe of all four cmd_ lines. NOT yet run against a real model night.
- Decision for the human: doctor.sh now warns that a headless claude can reach the signed-in account's MCP servers and claude.ai connectors. --strict-mcp-config closes it and also drops a project .mcp.json, so it is a warning, not a default.

### claude — 2026-11-10 — HOLD
v0.11.0 is on branch v0.11-lane-caps, unpushed. The human reviews it, merges to main and tags v0.11.0. Next: one supervised real-model runner.sh <agent> --once with the new cmd_ lines.

### claude — 2026-11-11 — v0.12.0: risk routing, blocked-by, issue intake (branch v0.12-risk-intake, not pushed)
- Source: the human asked for what was worth taking from a public video of the same pattern (ZazenCodes, "Build a Better Software Factory with Claude Code", 2026-11-09). Read from the auto-captions only, not its source repo. Not taken: its auto-merge approver and its model-as-orchestrator.
- Shipped: `risk_tags` + `risk_verifier_agent` (a tagged card goes to the stronger verifier; with no verifier it never integrates on its check alone), `Blocked by: task | rule | cli` on every blocked card and in the night report, `scripts/intake.sh` (labelled GitHub issues become draft cards on hold; issue text quoted as data), and a doctor.sh warning for a verifier that runs a smaller model than the workers.
- Verified: tests/goal-loop.sh 64/64 (three new scenarios; tests/fake-gh.sh stands in for GitHub), install parity, doctor on this repo 28 ok / 4 warn / 0 fail. intake.sh ran once against this repo read-only (--dry-run, no labelled issues); it has NOT written a card from a live issue. shellcheck is not installed here; CI runs it on push.
- This branch is stacked on v0.11-lane-caps: merging it lands v0.11.0 and v0.12.0 together.

### claude — 2026-11-11 — HOLD
v0.12.0 (risk routing, blocked-by, issue intake) on branch v0.12-risk-intake, stacked on v0.11-lane-caps; human reviews, merges, tags

### claude — 2026-11-11 — docs brought up to v0.12
- The human asked for all docs to be updated. `INSTALL.md` "What's in the box" was missing doctor, andon, trail, intake, `GOAL.md` and `prompts/`; added. `NIGHTSHIFT.md`, `DELEGATION.md`, `prompts/README.md`, `runs/README.md` and both READMEs now cover risk routing, `Blocked by:` and issue intake. `HEARTBEAT.md` template gained `intake_label:`. PROJECT_STATE next actions rewritten.
- Re-verified after the edits: tests/goal-loop.sh 64/64, install parity, doctor 28 ok / 4 warn / 0 fail.

### claude — 2026-11-11 — HOLD
docs up to v0.12 on branch v0.12-risk-intake

### claude — 2026-11-11 — v0.11.0 + v0.12.0 on main
- The human said "commit and push all to main". Fast-forwarded main 861aa5d → 264e772 (branch v0.12-risk-intake, which carried v0.11-lane-caps) and pushed. No PR this time, at the human's instruction.
- CI on main is green for the first time on these two releases: shellcheck, goal-loop (64/64) and install-smoke all pass (run 42938285854).
- Not done: no tags (v0.11.0, v0.12.0) were created; the human did not ask for them. Still no real-model night, and intake.sh has not written a card from a live issue.

### claude — 2026-11-11 — PUSHED
v0.11.0 + v0.12.0 on main, CI green, not tagged

### claude — 2026-11-11 — copyright holder named
- The human chose the notice "Copyright (c) 2026 Aleksandar Perisic (apsolut)" over the handle alone. Changed in LICENSE, template/LICENSE, the SPDX header of install.sh, every template script and every test, and this repo's installed copy. Licence terms (MIT) unchanged. tests/goal-loop.sh 64/64 after the change.

### claude — 2026-11-11 — PUSHED
copyright holder named in LICENSE and SPDX headers

### claude — 2026-11-11 — README rebuilt for newcomers (branch readme-first-screen, not pushed)
- The human asked what would make the README attract users, then said to do it. New first screen: one promise, an honest status line, quickstart, a Mermaid diagram of a night, a sample night report, the enforced rules as a list, "why this, and not". The v0.9–v0.12 paragraphs left the README; CHANGELOG has them.
- docs/sample-night-report.md is real runner output from tests/goal-loop.sh scenario 2 (scripted agents), labelled as such. docs/demo/night.tape is a VHS script for the demo GIF. It is NOT recorded and NOT test-run (vhs is not installed here): it needs a finished real-model night to replay. The image line in the README stays commented out until then.
- No script changed. The status line claims plain nights ran on a real project; that rests on the field incidents recorded in the scripts' comments (2026-08-11), not on anything run this session.

### claude — 2026-11-11 — HOLD
README rebuilt on branch readme-first-screen; human reviews before it goes to main

### claude — 2026-11-11 — README on main
- The human said to put the README work on main. Fast-forwarded main to readme-first-screen (6155ab7, 0ed9d37) and pushed. The HOLD above is lifted by the human.

### claude — 2026-11-11 — PUSHED
README first screen on main

### claude — 2026-11-11 — first real-model night; demo GIF recorded (branch demo-gif, not pushed)
- The human said to do the rest (the GIF and the other open items). Ran the first real-model goal-loop night: a throwaway `todo-cli` repo in the session scratchpad, `runner.sh claude --drain`, claude as worker and planner, codex as verifier and reviewer. Two hand-written cards landed, `done_cmd` was still red, the planner wrote G1111r1-1, it landed, goal met. About 8.5 minutes, reported spend $9.26. Every card passed first attempt, so no retry, advisor call or block was exercised.
- Recorded `docs/demo/night.gif` from that repo with VHS (installed vhs, ttyd and ffmpeg through winget). The README shows it, and `docs/demo/night-report.md` holds the real report and trail. On Windows VHS starts WSL bash, not Git Bash; the tape's hidden block sets safe.directory and the prompt for that.
- Created and pushed signed tags `v0.11.0` (1cce412) and `v0.12.0` (264e772), as earlier releases were tagged. Deleted the merged local branches readme-first-screen, v0.12-risk-intake, v0.11-lane-caps, v0.10-hardening, v0.9-goal-loop.
- Seen on the real night, not fixed: the report's spend line ($9.26) is written before the reviewer's call is charged (ledger ended at 11.26).
- The demo repo lives in the session scratchpad and will not survive the session; the GIF cannot be re-recorded without a new night.

### claude — 2026-11-11 — HOLD
demo GIF from the first real-model night on branch demo-gif; human reviews before main

### claude — 2026-11-11 — demo GIF on main
- The human said to commit to main and push. Fast-forwarded main to demo-gif (1f0d131, 61aef01). The HOLD above is lifted by the human.

### claude — 2026-11-11 — PUSHED
demo GIF and real night report on main

### claude — 2026-11-11 — "Runs with" badges in the README (branch runs-with-badges, not pushed)
- The human wants Grok, Cursor, Codex and Agy shown on the repo like the Contributors icons. That sidebar cannot be edited; it comes from commit authorship only. Added a "Runs with" badge row for the four CLIs the template has cmd_ lines for. Cursor is left out: nothing here has run with it. The badge service has no OpenAI or xAI logo, so Codex and Grok are text-only.

### claude — 2026-11-11 — HOLD
Runs-with badges on branch runs-with-badges; human reviews before main

### claude — 2026-11-11 — badges on main
- The human said to commit to main and push. Fast-forwarded main to runs-with-badges (72d8b9c, 289f01d). The HOLD above is lifted by the human.

### claude — 2026-11-11 — PUSHED
Runs-with badges on main
