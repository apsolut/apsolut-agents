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

### claude — 2026-11-11 — each agent drew and committed its own README icon (branch agent-icons, not pushed)
- The human asked that each agent add its own icon and commit it, so they are credited the right way. In a worktree on branch agent-icons, Codex, Grok and Antigravity were each run headless with one prompt: draw an original 64x64 SVG for yourself in docs/icons/, replace your own line in the README "Runs with" row, commit. Each did, touching only its two files; commits are SSH-signed by the human key. Claude drew docs/icons/claude.svg in this session.
- None of the three CLIs added a co-author trailer by itself. I re-applied the three commits to add `Co-authored-by: Codex <noreply@openai.com>` to the Codex commit (the trailer Codex documents as its default). Grok has no known trailer address, and the one reported for Antigravity (antigravity@google.com) is said to resolve to an unrelated person on GitHub, so those two commits carry no trailer and will not produce a Contributors avatar.

### claude — 2026-11-11 — HOLD
agent icons on branch agent-icons; human reviews before main

### claude — 2026-11-11 — agent icons on main
- The human said to push all to main. Fast-forwarded main to agent-icons (70f0f77, fd808ef, df3fc49, 9601c16, b32b6ca). The HOLD above is lifted by the human.

### claude — 2026-11-11 — PUSHED
agent icons on main

### claude — 2026-11-11 — Grok credited through its official GitHub account
- The human asked to make Grok and Antigravity show under Contributors too. Grok: xAI owns the GitHub App "Grok (by xAI)" (`grok-by-xai[bot]`, owner xai-org), and other public repos credit Grok commits to its noreply address. Grok was run headless and wrote docs/icons/README.md (who drew each icon), committing with that co-author line (dce492c). Pushed to main at the human request to make it show.
- Antigravity: not done. No official Antigravity account or app was found. The addresses seen in the wild resolve to unrelated people (antigravity-agent@google.com -> a personal account; antigravity@google.com is reported to do the same) or to no account (noreply@google.com). Crediting any of them would be wrong or would do nothing.

### claude — 2026-11-11 — PUSHED
Grok credited via its official account

### claude — 2026-11-11 — v0.13.0 fail-fast, built while the human slept (branch v0.13-fail-fast, not pushed)
- The human asked how a night keeps working when something waits on GitHub or 1Password, asked for coloured output and a "nightshift" command, then went to sleep with "finish all tasks without me". Four vendor-doc research agents (Claude Code, Codex, Grok Build, Antigravity) ran first; their findings shaped the list.
- Checked first: agy 1.5.5 still reports its own timeout as the runner expects (real call: exit 3, finished_reason print_timeout; cli_stop returns "timeout"). No change needed.
- Built: no-prompt env for runner and delegate; sign_ok probe (signed commit-tree, 30s cap) before the night and before every card; probe_role after a failed worker or verifier call; park() with human_wait_minutes / park_poll_seconds and exit 7; unattempt() returns the attempt; `.parked.diff` when the runner's salvage commit cannot be signed; doctor [unattended]; nightshift.sh; doctor colour.
- Found and fixed a pre-existing crash: `why="...$(throttled ... && echo ...)"` returned non-zero under set -e whenever the verifier CLI exited non-zero without a throttle, killing the lane with no report. Scenario 23 covers it.
- Command lines, measured with a one-word prompt: claude 42.0k tokens → 33.6k with --strict-mcp-config (adopted; 28.8k with --disable-slash-commands, not adopted because project skills may matter); grok 21.2k → 18.8k with GROK_CLAUDE_*_ENABLED=0 (adopted); codex --ignore-user-config and agy --disable-slash-commands: no change (not adopted). `--disallowedTools Agent,Task` confirmed to remove both tools.
- --strict-mcp-config had been left as the human's open decision. I made it the template default because the human asked for the lines to be tuned and it also closes the account-connector exposure; it is one flag to remove. My call, flagged for review.
- Real proof: throwaway repo, `nightshift.sh claude --drain` and `nightshift.sh grok --drain` at the same time, codex verifying. Both cards landed first attempt (claude lane 2 min, grok lane 6 min). First real two-lane run. Gap seen: both lanes write the same night report file.
- Not done from the research: per-role models, Codex spend from token usage, session resume, the Claude usage-limit retry switch (CLAUDE_CODE_RETRY_WATCHDOG, unverified), `.claude/` in protect:, Antigravity's consumer-plan terms question (the human's call).

### claude — 2026-11-11 — HOLD
v0.13.0 fail-fast on branch v0.13-fail-fast; human reviews before main

### claude — 2026-11-12 — v0.13.0 shipped to main
- The human said "ship". Pushed v0.13-fail-fast, opened PR #2 for CI. shellcheck failed once (SC1087: `"$E[31m"` reads as an array index); fixed with `${E}[` in doctor.sh and nightshift.sh (14a9d54). Second run: shellcheck, goal-loop, install-smoke all pass. Fast-forwarded main, tagged v0.13.0.
- The human's priorities, stated today: token and money accounting is not important (the target user runs on subscriptions); stability comes first, and they want things double-checked. This moves the spend-line and Codex-spend items off the list and the untested real-model paths (retry, blocked card, conflict, real locked key) to the top.
- The human kept --strict-mcp-config undecided; explained, recommended keeping it.

### claude — 2026-11-12 — PUSHED
v0.13.0 shipped to main

### claude — 2026-11-12 — v0.13.1: full access is the default again (branch v0.13.1-full-access)
- The human's decision: workers run with every permission, so restricting MCP by default makes no sense; the lock-down should be advertised as an option. Removed --strict-mcp-config from the template cmd_claude line; HEARTBEAT comment now describes it as an optional lock-down; doctor prints an uncounted cyan `note` (full access, how to lock down) or an `ok` when the flag is set; README "What you get" has a bullet for it.
- Left as is: the GROK_CLAUDE_*_ENABLED=0 prefix on the Grok line (it stops Grok borrowing Claude Code's servers, hooks and skills). Same kind of restriction; the human has not ruled on it.
- Not run locally: tests/goal-loop.sh (CI runs it on the PR).

### claude — 2026-11-12 — HOLD
v0.13.1 on branch, CI then the human's word

### claude — 2026-11-12 — stability pass on the runner (branch lane-reports, on top of v0.13.1-full-access)
- The human asked "next?" after saying stability matters most. Did the items that need no human.
- One night report for all lanes: each lane writes runs/.lane-end-<date>-<agent>; finish() rebuilds the report from all of them under a .report lock. The reviewer runs only from the last lane standing. Scenario 25.
- Independent review: Codex read runner.sh read-only (prompt gave it the functions to look at and failure classes, not my conclusions). Six findings; I checked each against the code and all were real. Two were in the report change above (both lanes seeing each other alive; releasing a lock not taken), one in v0.13.0 (a key locking before the integration merge counted as a merge conflict), three older (reviewer resetting the night worktree under a joining lane; shared fm_set temp file; reviewer's untracked files left in the night worktree). All fixed. Scenario 26 and a snapshot check added.
- Not tested: the same-moment finish races (no deterministic way); they rest on reading the code.
- `.claude/` protection: not made a default. The human's stance is full access by default, and some cards are about those files. Documented as an optional protect: entry in HEARTBEAT.md.
- tests/goal-loop.sh locally: 94 ok, 0 failed.

### claude — 2026-11-12 — HOLD
stability pass on lane-reports; CI then the human's word

### claude — 2026-11-12 — v0.13.1 shipped to main
- The human said "ship". PR #3 (full access by default) and PR #4 (one report for all lanes, six runner fixes from the Codex review) were green in CI; fast-forwarded main to both, tagged v0.13.1.
- Still open for the human: the GROK_CLAUDE_*_ENABLED=0 prefix on the Grok line; a harder real night (retry, blocked card, lane conflict, a really locked key).

### claude — 2026-11-12 — PUSHED
v0.13.1 shipped to main

### claude — 2026-11-12 — audit of main after v0.13.1, and the fixes (branch v0.13.2-crash-safety, not pushed to main)
- The human asked to check the latest commits and the project's stability. Commits: all 32 since v0.12.0 carry a good SSH signature, main equals origin/main, CI green on every push, installed copy identical to the template, tests/goal-loop.sh 94/94 on main.
- Stress test written for this (scratchpad, not in the repo): two fake lanes started together on four cards, end-of-night state checked. On main: 4 of 4 goal-mode rounds lost a lane (night_setup: both lanes saw "no night yet", the second died on "branch already exists", exit 255, no report); 4 of 4 plain rounds clean. The real two-lane run on 2026-11-11 was a plain board, so it never showed.
- Two Codex audits (read-only, told the failure classes, not my conclusions): the whole runner (13 ranked findings and an inventory), then the other scripts (16). I checked what I acted on against the code or by experiment. Confirmed by experiment: `trap cleanup EXIT INT TERM` lets the script run on after TERM; `rm -rf` fails on Windows while a native process sits in the folder.
- I told the human two things that were wrong and corrected both: the undeletable-folder death is in the verifier evidence, role output and reviewer snapshot paths, not the login probe (that runs where set -e is off); CRLF cards do not break worktree.sh in Git Bash (its awk strips the CR) — only on Linux, macOS, WSL.
- Fixed in runner.sh: night_setup under the lock; INT/TERM exit; DIED line + lane-end on any exit that is not finish(); merge journal runs/.integrating-<date> with heal_night and a verified rollback (Andon if it fails); card marked integrated inside the lock before the journal goes; card stays `writing` until its merge is decided; per-card start marker runs/.pre-<date>-<id> so an interrupted attempt restarts clean with its work kept (ref + .diff); git_timeout_seconds on the runner's own commits and merges; non-fatal clean-up of role files; bounded lock and spend mutex; curl timeout; probe output to a file; zero durations; boot recovery only resets `writing`; planner publishes with cp+mv. Other scripts: worktree.sh/status.sh CRLF, worktree remove non-fatal in `done`, install/upgrade curl timeouts and trap, delegate claim release.
- Then Codex reviewed the fixes as a diff: eight findings, all in my new recovery code, all real, all fixed (see CHANGELOG v0.13.2).
- Grok was asked for the second audit headless in a throwaway clone: it returned three opening sentences and no findings (exit 0). Not looked into; Codex did that audit.
- Tests: scenarios 27, 28, 29. 27 and 28 fail on v0.13.1 (8 of 10 checks) and pass here. Stress on the first round of fixes: 10 of 10 rounds clean.
- Not fixed, listed in CHANGELOG "Known, not fixed" and PROJECT_STATE: TERM waits for the running CLI call; delegate/worktree green_cmd without a time limit; delegate supervisor TERM; swallowed reset failures in card worktrees; archive gaps in --jar/--reject; never tested with a real locked key.

### claude — 2026-11-12 — HOLD
v0.13.2 crash-safety on a branch; CI green; the human decides

### claude — 2026-11-12 — TODO.md (local, git-ignored)
- The human asked for a TODO.md holding everything that is not done, kept out of git. It is at the repo root and ignored in `.gitignore`, so it exists only on the human's machine: what waits on the human, known defects not fixed, what was never run with real models, housekeeping. Ideas stay in FUTURE.md.
- Seen while writing it, listed there, not fixed: the hand-written part of PROJECT_STATE.md is out of date (next action 1 still says v0.13.0 is not pushed; the ownership table says v0.11.0 and v0.12.0 are not tagged).

### claude — 2026-11-12 — v0.13.2 shipped to main
- The human said to commit and push everything but the local TODO.md to main. PR #5 was green in CI on 16eb6a7 (shellcheck, install-smoke, goal-loop with the four-round two-lane stress step); main fast-forwarded to it, tagged v0.13.2.
- PROJECT_STATE.md, hand-written part, brought up to date: the ownership table (v0.11.0 to v0.13.2 are on main and tagged), next action 1 (what waits on the human), the list of merged branches that can be deleted.
- Still open for the human: one run with the real signing key locked; a harder real night with real models; the GROK_CLAUDE_*_ENABLED=0 prefix on the Grok line; Antigravity's consumer-plan terms. Known defects not fixed are in CHANGELOG v0.13.2 "Known, not fixed" and PROJECT_STATE next action 2.

### claude — 2026-11-12 — PUSHED
v0.13.2 shipped to main

### claude — 2026-11-13 — v0.14.0: spend caps off by default (working tree on main, not committed)
- The human asked for the budget limits to be off from the start, with a red note at the top of the README saying the option can be switched on. Background: in another project both caps had been set to 1000000 as a way out, because `0` blocked everything and an empty value fell back to the default. Recorded as D-008.
- Scripts (`template/scripts/`, copied to this repo's `.apsolut-agents/scripts/`): `night_budget_usd` and `delegate_budget_usd` empty, absent or `0` = no cap; a number above zero is the same hard stop as before (exit 3, `reason: budget`; a refused dispatch). Before: empty meant $100 a night and $25 a day, `0` ended the night before its first card. With no cap `$APSOLUT_CALL_BUDGET_USD` is 1000000.00, so the default Claude line with `--max-budget-usd` still gets a number; `call_budget_usd` still caps one call by itself. The report reads `spend: $4.20 (no cap)`, the start line `budget off`.
- `doctor.sh`: the `--max-budget-usd` warning only with a cap set; with no night cap a `note` (not counted) and no "no spend history yet" warning.
- `template/HEARTBEAT.md` ships the three keys empty with the reason and the one line that switches a cap on. `NIGHTSHIFT.md`, `DELEGATION.md` and the root README say "optional, off by default"; the README has a `> [!CAUTION]` block at the top and a short "Spend caps" section.
- Not changed: this repo's own `HEARTBEAT.md` still says 100 / 25. It is the human's file and a cap is the human's to lift.
- Checked: `tests/goal-loop.sh` 120 of 120 (30 scenarios, Git Bash on Windows); new scenario 30 has 12 checks, 8 of them fail on v0.13.2. `tests/stress-two-lanes.sh 4`: 4 rounds ok. The CI install-smoke steps by hand: install equals payload, refresh, wire, VERSION stamped 0.14.0. A real call, `claude -p --max-budget-usd 1000000.00` on claude 2.1.323: answered, `is_error:false`. `sh -n` on every script. Not run: shellcheck (not installed here; CI runs it).
- The `PROJECT.md` leakage check prints six dated comments in `runner.sh` and `doctor.sh` ("field incident 2026-08-11"). They were there before this change; not touched.
- Waits on the human: commit, PR, tag. A copy elsewhere that holds 1000000 can go back to empty after `upgrade.sh`.

### claude — 2026-11-13 — HOLD
v0.14.0 (spend caps off by default, D-008) is finished in the working tree on `main`: 19 tracked files changed, nothing committed, nothing pushed. The human said they commit tonight, so no agent commits this. For the commit: all 19 files belong to the one change (the entry above lists them by area). Suggested: a branch and a PR rather than straight onto `main`, because shellcheck has not run on this change and CI runs it; everything else in CI was run by hand and passed. After the merge: tag `v0.14.0`. Still the human's call: this repo's own `HEARTBEAT.md` keeps 100 / 25 until they empty it. The local `TODO.md` holds the full list.

### claude — 2026-11-13 — status.sh died on D-008 (fixed, same working tree)
- Running `session-end.sh` for the handoff failed: `status.sh` line 125, "008: value too great for base". The next decision id was computed with shell arithmetic, which reads `008` as a bad octal number (and `010` as eight). This repo's own D-008 was the first to hit it. Leading zeros now come off first (`template/scripts/status.sh`, copied to `.apsolut-agents/scripts/`). CHANGELOG v0.14.0 "Fixed".
- Scenario 31 in `tests/goal-loop.sh`: D-008 and D-010 in the decisions file, then `status.sh` and `session-end.sh`. 3 of its 4 checks fail on v0.13.2. Full suite: 124 ok, 0 failed (31 scenarios).

### claude — 2026-11-13 — HOLD
v0.14.0 plus the status.sh fix: 20 tracked files changed in the working tree on `main`, nothing committed. The human commits tonight. Suggested: a branch and a PR so CI runs shellcheck (not run here), then tag `v0.14.0`.

### claude — 2026-11-13 — v0.14.0 pushed as PR #6; one stress round failed in CI
- Branch `v0.14.0-spend-caps-off`, PR #6 (the human said to commit and push). CI on 490a122: shellcheck, install-smoke and goal-loop (124 ok) pass; the two-lane stress step failed 1 of 4 rounds: round 1 (goal), one lane exited 255. Every other check of that round passed (both lanes' endings in the report, one Attention section, all four cards verified and integrated, no claim dropped).
- Not reproduced: 12 rounds in Git Bash and 16 under WSL Linux, all ok. The CI log could not say where the lane stopped, because the fixture is thrown away; `tests/stress-two-lanes.sh` now prints the last lines of each lane and the DIED/error lines of a failed round.
- Not looked into further, and not caused by anything I can tie to this change. Listed in TODO.md "Known defects".

### claude — 2026-11-13 — v0.14.0 shipped to main
- The human said to commit and put it on main. PR #6 was green in CI on 9543707 (shellcheck, install-smoke, goal-loop 124 ok, four stress rounds); main fast-forwarded to it, tagged v0.14.0.
- Still open: the one stress round that failed in CI before (a lane exited 255, not reproduced in 28 local rounds; TODO.md "Known defects"); this repo's own caps are still 100 / 25.

### claude — 2026-11-13 — PUSHED
v0.14.0 shipped to main
