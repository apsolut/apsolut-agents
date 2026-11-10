# Four-model blind review of v0.9 vs the Cursor plugins → v0.10.0 (2026-11-10)

**Ask (human):** "talk with all agents you can to check is this best approach, compare all plugins and make apsolut-agents best possible".

**Method:**
- Round 1: Claude (fresh subagent), Codex, Grok and agy each read v0.9 and cursor/plugins (pstack, orchestrate, advisor, thermos, dyl-stack, pr-review-canvas, agent-compatibility) alone, from the same brief. Each answered: approach, gaps, defects, top 10, cuts.
- Round 2: Codex and Grok reviewed the v0.10 diff for regressions.
- Every claim was checked against the code before any change. Changes ship only where two or more reviewers agreed, or where a single finding was a verified bug.

## Verdict (4/4)
Keep apsolut-agents as the engine; do not adopt the plugins. They run only Cursor's own runtime: orchestrate needs CURSOR_API_KEY and cloud VMs, pstack's overnight loop is Cursor `/loop`, and advisor is a Cursor hook. They cannot drive Claude Code, Grok, Codex and agy against each other. Port their *mechanisms* into runner.sh as code, not prompt prose.

## Shipped in v0.10.0
See CHANGELOG v0.10.0. Consensus items:
- false-throttle loop (4/4)
- stranded cards after a conflict, "merges are tasks" (4/4)
- prompts over the argv limit (3/4)
- protect the judge, plus a card snapshot (3/4)
- a runner-run check: (3/4)
- setup_cmd (4/4)
- timeouts on every check (2/4)
- honest timeout cost (3/4)
- dependency handoff relay (2/4)
- planner normalisation (2/4)
- sturdier handoff parsing (2/4)
- evidence kept (1/4, verified bug)
- planner snapshot (1/4, verified bug)
- --once (1/4, verified bug)

Round 2 found 13 regressions or gaps (7 Codex, 6 Grok, overlapping on 2). All are fixed in 8881f39.

## Raised, not shipped
FUTURE.md "From the v0.10 four-model review": process containment, real isolation, a score ratchet, failure-mode routing, a live-verification recipe, an advisor before the first done, a stall detector, and the single-reviewer cuts.

## Raw answers

### Round 1 — claude

# Review: apsolut-agents v0.9 vs the Cursor plugins (Claude)

## 1. Verdict

**Keep apsolut-agents as the engine. Don't adopt the plugins. Port about six of their mechanisms, all of them as runner code, not prompt text.** The plugins can't do the job as written. `orchestrate` only spawns Cursor cloud agents: it needs `CURSOR_API_KEY`, bun, and the Cursor SDK, and Slack is optional (`orchestrate/SKILL.md`, `references/planner.md`). pstack's overnight loop is an LLM session that keeps itself alive with Cursor's `/loop` and the instruction "Don't end your turn while…" (`playbooks/autonomous-run.md`, `prompts/loop-hygiene.md`). That is the drift-prone shape that apsolut's script-owned loop avoids. Neither plugin can drive Grok, Codex, or agy CLIs against each other. apsolut has the right skeleton: a POSIX runner owns the loop, a predicate defines "done", git provides isolation, and every decision goes to the trail. Its weakness is the judge. A worker can edit the predicate, the tests, the green script, and its own card, so most of what decides "correct" is still an LLM's verdict. Overnight, that is how you get eight hours of green nonsense. The plugins are better at keeping the judge honest: frozen harnesses, measurements the script re-runs, failure-mode routing, and checkpoint/resume. Take those ideas and build them into `runner.sh`.

## 2. Plugin ideas that are missing or weaker here, and matter overnight

- **Freeze the harness, never relax the predicate.** Source: `pstack/.../playbooks/hillclimb.md` step 2, "prove its sensitivity, then freeze it", and `autonomous-run.md` step 6. `autopilot-full.md` step 6 adds that loosening a gate needs a countersign. In apsolut, `done_cmd` points at "a committed script" (`GOAL.md:18-22`) that any card can rewrite, and the change then integrates.
- **The script re-runs the agent's claims.** Source: `orchestrate/scripts/core/agent-manager.ts:468-561` re-runs `measurements[]` on the worker branch and flags drift. apsolut's only checks are `green_cmd` and an LLM verifier. A card has no command of its own that the runner executes.
- **Path scopes.** Source: `orchestrate/prompts/worker.md` (`pathsAllowed`/`pathsForbidden`) and `references/planner.md` ("minimize path overlap"). apsolut cards have a `files:` field, but nothing enforces it. That raises integration conflicts when lanes run in parallel.
- **A failure-mode taxonomy that sets the retry policy.** Source: `orchestrate/prompts/loop-hygiene.md` and `core/failure-handoff.ts`: `cap-hit` → split the task, `tool-error` → retry on a different model, `network-drop` → retry as is. apsolut retries a timed-out card at the same size, even though its own synthetic handoff says "split it" (`runner.sh:759`).
- **Checkpoint and resume.** Source: `orchestrate` exit 100 plus `recoverRunning`, and `playbooks/pause-safely.md`. apsolut derives the night's identity from the calendar date, so a restart after midnight breaks it (see §3).
- **"Merges are tasks."** Source: `references/planner.md`. In apsolut, a merge conflict silently strands the card (see §3).
- **A project control skill for live verification.** Source: `pstack/skills/create-verification-skill/SKILL.md`. Without a launch, doctor, drive, and evidence recipe, `live-verified` is aspirational and a generic verifier falls back to reading tests.
- **Judging stuck agents by side effects, not status.** Source: `autopilot-full.md` step 6, the "stuck-after runtime". apsolut has only a 45-minute wall-clock timeout, so a hung CLI burns the whole cap.

## 3. Defects in a real night

1. **False throttle detection leads to an unbilled infinite loop.** `throttled()` (`runner.sh:114-116`) greps the whole worker output for `rate.?limit`, `internal server error`, and similar patterns. That catches a card about rate limiting, or a test log containing "Internal Server Error". When it fires (`:726-743`), the runner resets the work, counts no attempt, charges no spend (the throttle branch exits before `charge` at `:745`), sleeps 15 minutes, and repeats until `stop_time`. Good work is thrown away and the budget cap never trips.
2. **The worker can rewrite its own judge.**
   - `ws_sum` (`:158`) checksums HEARTBEAT, GOAL, prompts, and scripts, but not `work/*.md`. The runner reads the card again after the worker has run: `NEED=$(fm_get "$CARD" verify)` at `:788` and `pvf CARD` at `:794`. A worker that sets `verify: typecheck` or edits "Done when" lowers the bar the verifier applies.
   - `green_cmd` and `done_cmd` run the worktree's own `package.json` scripts and test files. A card that changes `"test"` to something weaker, or edits the predicate script, passes `integrate()` (`:310`) and `goal_met()` (`:325`).
3. **Dead states in goal mode.**
   - When a card hits a merge conflict, or green fails after the merge, it is left in `review`, never integrated, and `FAILS` is reset (`:824-834`).
   - The same happens to a card whose verifier is blocked (`:810-811`). That includes test runs that leave untracked files, because those trip `tree_state` (`:800-802`).
   - Dependents never unblock (`deps_met`, `:336`), and planner rule 7 (`planner.md:29`) tells the planner not to touch `review` cards. The night ends in a plateau. A verifier whose authentication dies mid-night turns every card into "review, unverified" without tripping the breaker.
4. **The prompt goes through argv.** `run_cli` (`:147`) passes the whole rendered prompt as one argument, despite the comment at `:119`. On this Windows host, an npm `claude.cmd` shim caps the command line at about 8 KB (CreateProcess caps it at 32 KB). The worker template plus GOAL, the card, PREVFAIL (120 lines), and ADVICE (60 lines) exceeds that on retries. The planner's HANDOFFS (200 lines) exceeds it by round 2. The result is rc 126 or 1, so the CLI never runs, yet the attempt counts as red. On retry the prompt grows, so the next attempt also fails, and the breaker trips.
5. **A restart after midnight starts a new night.** `DATE` (`:23`) sets `NIGHT_ID`, `SPENDF`, and `ROUND_FILE`. After a crash at 01:00, the restarted runner opens a fresh night branch from `main`, so cards integrated earlier are gone from its base. The budget ledger resets, effectively doubling the night's cap, and the round count resets.
6. **The budget is undercounted.** A timeout (rc 124) emits no cost JSON, so `charge` (`:107-110`) books `$2` for 45 minutes of a frontier model. The same happens for every CLI that doesn't print `total_cost_usd`. The cap is checked only between cards (`:586`).
7. **Orphaned processes.** `timeout` kills `sh` or the CLI, but not dev servers or test watchers the agent started. Under Git Bash, native child processes survive TerminateProcess. The next verifier finds the port taken and returns `verifier-blocked`, which leads to defect 3.
8. **No dependency setup.** `worktree.sh spawn` (`:360-403`) has no install step. Either `green_cmd` hides `pnpm install` inside itself, so every check pays for it and a failed install looks like a failed card, or the baseline check refuses the night (`:661-672`).
9. **Smaller defects.**
   - The probe accepts any output that contains "ok" (`:253`). "tokens" contains "ok".
   - `.attempts-$ID` is never scoped to a night (`:675`). A card re-queued the next night blocks on its first red attempt and is fed a stale PREVFAIL.
   - `grep -qi test` (`:626`, `:371`) also matches "latest" and "attestation", so the test-first gate is decorative.
   - `CARD IS WRONG:` matches anywhere in the advisor's text (`:696`), including a sentence quoting the instruction.

## 4. Top 10 changes, ranked

1. **Freeze the judge.**
   - **Change:** at night start, copy the `done_cmd` script and a `protected:` list (green script, test config, CI config, `package.json#scripts`, lockfile) out of the base commit into `runs/`. Run the predicate from that frozen copy. Refuse any card whose `git diff --name-only PRE HEAD` touches a protected path. Snapshot the card at claim time, give that snapshot to the verifier and to `NEED`, and add `work/` to `ws_sum`.
   - **Files:** `runner.sh`, `GOAL.md`.
   - **Test:** a fake worker rewrites `run-tests.sh` to `exit 0` → red, not integrated. A fake worker edits its own `verify:` → tamper.
2. **Make the throttle check honest.**
   - **Change:** classify a throttle only from the CLI's structured error (`is_error` or `api_error_status`, or a non-zero rc plus the last 20 lines). Always charge. Cap backoffs per card at 3, then block. Never reset a run that exited 0.
   - **File:** `runner.sh:114, 726`.
   - **Test:** a fake agent prints "rate limit exceeded" inside a successful run → the card integrates.
3. **Add a per-card `check:` command that the script runs.**
   - **Change:** the runner runs `check:` at PRE, where it must fail, and at HEAD, where it must pass. This makes test-first enforceable and replaces both `grep -qi test` gates. `card_ok` requires `check:`. The LLM verifier becomes an audit layered on top.
   - **Files:** `runner.sh`, `planner.md`, `work/_TEMPLATE.md`.
   - **Test:** a no-op worker with green passing → red, "check passes at base".
4. **Remove the dead states.**
   - **Change:** treat a merge conflict, or a green failure after the merge, as red. Re-spawn from the night tip with the conflict text in the prompt ("merges are tasks"). Two `verifier-blocked` results in a row raise the Andon ("verifier harness broken"). Drop rule 7's protection for `review` cards that were not integrated.
   - **File:** `runner.sh:810-834`.
   - **Test:** two cards that edit the same line → the second ends integrated or blocked with a reason, never stuck in `review`.
5. **Deliver the prompt through a file or stdin.**
   - **Change:** support `cmd_<agent>` with `{{PROMPT_FILE}}` or `<`. Keep argv only as a fallback, with a size check that raises the Andon instead of failing a card.
   - **File:** `runner.sh:147, 282`.
   - **Test:** a 200 KB card reaches the fake agent intact.
6. **Persist the night's identity.**
   - **Change:** write `runs/.night-current` (id, base, ledger) and have a restart reuse it until `finish`. Key the spend ledger and attempt counts to the night.
   - **Test:** kill -9 mid-card, override DATE to the next day, restart → same branch, same spend, claim recovered.
7. **Add a progress ratchet.**
   - **Change:** add an optional `score_cmd` (a number: acceptance tests passing, TODOs remaining). `integrate()` refuses a merge that lowers the score. A plateau then means the score is flat across rounds, not that two rounds landed nothing. Give the score history to the planner. This is the hillclimb keep-or-revert rule.
   - **Test:** a card that passes green but lowers the score → refused.
8. **Route retries by failure mode.**
   - **Change:** after a timeout, don't retry at the same size. In goal mode, hand the card to the planner as "split <id>". On a CLI crash or tool error, retry on `fallback_agent`, a different CLI. This replaces the advisor round-trip with a cross-model retry.
   - **Test:** a fake agent sleeps past the cap → one attempt, and the planner prompt contains "split".
9. **Count spend by wall clock.**
   - **Change:** when a run emits no cost output, charge `cost_per_minute_<agent>` for its runtime. Run a background watchdog that kills the current CLI when the budget runs out.
   - **Test:** a fake agent with no cost output, running N minutes → spend = N × rate.
10. **Contain processes and set up worktrees.**
    - **Change:** run each CLI in its own process group (`setsid`, or Job objects on Windows) and kill the group on timeout. Add a `setup_cmd` that runs once per spawned worktree, separate from green. Kill an attempt whose output has not grown and whose worktree has not changed for `stall_minutes`.
    - **Test:** a fake agent forks `sleep 9999 &` → no orphan survives.

## 5. What to cut

- **The `grep -qi test` gates.** They give false comfort. Item 3 replaces them.
- **The worker's self-reported `## Verification` ladder.** The runner only logs it (`:784`). Keep Status, Notes, and Suggested follow-ups.
- **The `typecheck` verify level.** In goal mode it is a way around the test bar.
- **`max_plan_rounds: 4` and the rule that two rounds without a landing count as a plateau.** These stop a night that is making slow progress. Use time, budget, and a flat score (item 7) instead.
- **TICK lines in `agent-log.md` and session-end ceremony during unattended runs.** The trail TSV already records this.
- **The separate advisor role.** Fold it into a cross-model retry (item 8): one call instead of two, and the retry comes from a model with different blind spots.
- **Keep the morning reviewer.** It makes the morning merge faster, not the night more likely to succeed, so keep it but don't extend it.

### Round 1 — codex

**Verdict: use a hybrid, with apsolut-agents owning execution and selected plugin mechanisms improving it.** Keep its cross-CLI commands, isolated worktrees, integration branch, budgets and executable goal predicate. Cursor’s `orchestrate` supplies real scripted orchestration, but depends on Cursor cloud agents/SDK; pstack’s Claude adapter explicitly drops unsupported capabilities and cross-family model choices. Neither directly supplies the requested interchangeable CLI runtime. Conversely, apsolut-agents v0.9 is not yet a reliable unattended product builder: it often converts recoverable failures into morning homework, and several advertised safeguards are optional or incomplete. Import recovery and verification mechanisms, not the entire plugin workflow.

This is a static review; I did not run tests because they create and modify repositories. Below, `R` means `apsolut-agents/template/scripts/runner.sh`, `P` means `apsolut-agents/template/prompts/`, and plugin paths are relative to `cursor-plugins/`.

**Plugin ideas that would materially improve nights**

- **Recovery by failure class.** `orchestrate/skills/orchestrate/prompts/loop-hygiene.md` distinguishes timeout/OOM, network and tool failures, then splits, retries or changes models accordingly. apsolut mostly resets and retries the same card, or blocks it.
- **Integration is actionable work.** `orchestrate/skills/orchestrate/references/handoffs.md`, “Merges are tasks,” provides explicit integration workers. apsolut detects merge failure but supplies no automatic repair path.
- **A runnable product verification recipe.** `pstack/skills/create-verification-skill/SKILL.md` requires launch, readiness, drive, evidence, teardown and feature coverage. `green_cmd` alone does not establish that the delivered application works.
- **Preserved, isolated evidence.** That same skill requires evidence to survive cleanup. `dyl-stack/skills/dyl-mode/SKILL.md` serializes shared UI driving. apsolut deletes verifier scratch evidence and lacks service/port ownership.
- **Cold-start and targeted validation.** `agent-compatibility/agents/startup-review.md` and `validation-review.md` examine actual startup and practical feedback loops. `doctor.sh` checks pristine trees, but offers no bootstrap lifecycle and treats most nonzero predicate exits—including timeout—as acceptable “red.”
- **Recovery before surrender.** `pstack/skills/poteto-mode/playbooks/autonomous-run.md` fixes reversible tooling failures and pivots through plateaus. Preserve bounded spending, but distinguish a failed strategy from a genuine human dependency.
- **Selective earlier advice.** `advisor/skills/advisor/SKILL.md` consults before consequential decisions and completion, not only after a failed attempt. Use this for risky cards; do not add another mandatory reviewer to every card.

Thermos’s correctness rubric is already substantially represented. PR Review Canvas primarily improves human comprehension; it contributes little to unattended convergence.

**Concrete defects and real-night scenarios**

1. **False verification.** `R:787–816` initializes `PASS=yes`; an empty verifier setting bypasses the required verification level. A no-op worker with an absent or partial handoff can pass an existing green suite (`R:756–784`). Even with a verifier, its exit code is ignored (`R:797`), and a verdict written before a crash can be accepted. No structured execution evidence is validated.

2. **The predicate’s implementation remains editable.** The canary covers coordination rules (`R:158–159`), not repository tests, acceptance scripts or package commands. A worker can accidentally weaken the script behind an unchanged `done_cmd`, producing “goal met” without the product.

3. **Checks can consume the entire night.** Baseline, worker green, integration green and final predicate run without timeouts (`R:662`, `780`, `310`, `325`). A hanging browser test prevents budget, stop-time and Andon polling.

4. **Planner can erase legitimate integration.** It snapshots the shared night worktree, runs without the integration lock, then resets any detected change (`R:410–417`). Another lane can claim and finish newly available work during planning. Its legitimate merge is then mistaken for planner misconduct. Card metadata can still claim that erased commit was integrated.

5. **Recoverable work becomes stranded.** A verifier blocked by a temporary port conflict leaves the card in `review`; an integration conflict also leaves it there (`R:810–834`). `pick_ready` selects only `waiting` (`R:352`). Meanwhile `P/planner.md:29` forbids replanning review cards.

6. **Prompt contradicts the implementation.** `P/planner.md:25` says dependent work must become one card and prohibits using `after:` for code visibility. Goal mode explicitly supports that visibility (`R:336–342`, `640–641`). Real planners therefore create oversized cards that timeout.

7. **Evidence is destroyed.** `P/verifier.md:8` directs screenshots, logs and repro scripts into scratch; `R:809` deletes that directory immediately. A handoff can point to proof that no longer exists.

8. **Accounting and classification are unreliable.** `R:106` updates shared spend through an unlocked read/modify/write and a common temporary filename. Concurrent lanes can lose charges or fail a rename. `R:115`, `726–742` interprets ordinary agent text such as “rate limit” as provider throttling, resets work and retries without charging or incrementing attempts.

9. **Containment is overstated.** Worktrees and sealed push URLs do not prevent bypass-permission processes from accessing the primary checkout or shared Git metadata. `R:349–357` does not enforce PROJECT human-gate paths. A post-call checksum cannot prevent damage outside its narrow file list.

10. **The supervised gate is not one pass.** `--once` only exits when no ready card exists (`R:616`); it does not stop after a card. In goal mode, planning happens before that check. The advertised single-pass smoke test can run the whole board.

**Top 10 changes, ranked**

Every row should add regression coverage to `tests/goal-loop.sh` or a dedicated harness suite.

| Rank | Change and files | Why; proving test |
|---|---|---|
| **1** | Freeze the acceptance contract in `GOAL.md` and `runner.sh`; run protected acceptance tests against the candidate SHA. Require independent verification in goal mode, exact verdict parsing, successful verifier completion and evidence references. | Prevent false completion. Modify/delete an acceptance test, omit the verifier, return malformed evidence or crash after writing “pass”: none may integrate. |
| **2** | Add a project runtime contract and lifecycle helpers; wire them into `doctor.sh` and `runner.sh`. Include bootstrap, service readiness, isolated data/ports and actual user journeys. | Makes “any project” operational. Start from a cold clone with no dependencies or database; build, exercise the product and preserve proof after teardown. |
| **3** | Put deadlines and process-tree supervision around **every** external command in `runner.sh`, including checks and notifications. | A timeout must release the night. Hang each phase, spawn a child server, then assert bounded termination, preserved evidence and no surviving child. |
| **4** | Give integration one owner; run planners on immutable snapshots. Replace conflicting shared-file updates in `runner.sh` with transactional state or a single state writer. | Prevent erased merges and corrupted metadata. Synchronize two lanes so integration happens during planning; assert both commits and consistent card states survive. |
| **5** | Add persistent `verification_pending` and `integration_failed` states plus bounded repair tasks in `runner.sh` and `P/planner.md`. Relay dependency handoffs and correct its sequencing rule. | Recover useful work instead of abandoning it. Inject a transient port failure and a merge conflict; finish both without rerunning successful implementation unnecessarily. |
| **6** | Add capability-tested CLI adapters around `run_cli`, configured in `HEARTBEAT.md`. Use stdin/files for prompts and structured provider events for errors, cost and completion. | Regex over model prose is not a protocol. Replay real captured envelopes, refusals, partial streams and oversized prompts; also run a supervised write/test/handoff smoke test per CLI. |
| **7** | Isolate agents in separate clones/containers with only their checkout and output directory writable; keep supervisor state outside their reach. Update `worktree.sh` and launcher code. | Protect the controller and primary checkout. Attempt writes to primary, policy, ledger and shared refs; assert denial rather than later detection. |
| **8** | Reserve budget atomically before each role invocation; reconcile actual usage and cap throttle retries. Change `runner.sh` and `delegate.sh` together. | Prevent competing lanes spending the same balance. Race reservations near the cap and inject repeated throttles; launches and charges must remain bounded. |
| **9** | Persist attempt phases, process identities and recovery decisions; distinguish goal success from stopped/incomplete. Fix `--once` in `runner.sh`. | Makes interruption survivable. Kill the supervisor after claim, commit and merge; restart without duplicate integration. Two ready cards with `--once` must process exactly one. |
| **10** | Retain verifier artifacts under durable run directories; validate evidence paths before acceptance. Update `P/verifier.md` and `runner.sh`. | Makes proof independently inspectable. Verify every referenced artifact still exists after cleanup and restart, and records the tested SHA. |

**What to cut**

Remove mandatory style rituals, principle citations, repeated playbook copying and automatic dual maintainability reviews from the overnight path. Do not import dyl-stack’s per-turn merge permission rule or Canvas’s interactive PR selection.

Replace the grep-for-“test” gate with executable acceptance requirements. Avoid adding more prose to compensate for missing enforcement.

Keep the morning report optional and concise. Keep approval boundaries for genuinely consequential actions, but stop routing ordinary environment recovery and merge repair to the sleeping human.
### Round 1 — grok

# Review — unattended night loop

**Verdict:** Keep apsolut-agents as the harness. Steal four scripted checks from the plugins. Do not adopt the plugins as the runtime. Orchestrate, advisor, and dyl-mode run only inside Cursor: `orchestrate/skills/orchestrate/SKILL.md` needs `CURSOR_API_KEY` and cloud agents, `advisor/hooks/stop-hook.sh` is a Cursor stop hook, and `dyl-mode/SKILL.md` will not start without pstack and cursor-team-kit. That stack cannot host Claude Code, Grok, Codex, and agy driving each other. apsolut already has what the plugins only say: `done_cmd` is a process exit code on a night branch, and `main` does not move. apsolut cannot stay up if the laptop sleeps. The plugins cannot enforce "the predicate never relaxes" (`pstack/docs/guide/07-overnight.md`); the model is the loop. Lifting the checks below into `runner.sh` is what can finish a product. Vendoring the plugin tree only buys Cursor UX.

## Gaps that matter overnight

1. **The script saves the handoff.** `orchestrate/scripts/core/failure-handoff.ts` (`hasStructuredHandoff`, `writeFailureHandoff`) stores the run's final message and treats a missing `## Status` as a failure. apsolut asks the model to write an absolute path in the primary checkout (`prompts/verifier.md` line 26; same in `worker.md` and `planner.md`). The worktree only gets a `.primary` pointer (`worktree.sh` 394–398). A sandbox that can write in cwd never produces the file the runner reads.

2. **Claims get re-run.** `orchestrate/scripts/core/agent-manager.ts` re-executes `measurements[]` on the worker branch. apsolut promotes the word under `## Verification` (`runner.sh` 806–813). `pathsAllowed` is not the missing lock: `orchestrate/scripts/core/prompts.ts` only pastes the globs into the prompt.

3. **A second look before the first done.** `advisor/hooks/stop-hook.sh` fires when files changed and the turn ended with no consult. apsolut's advisor runs only if a `.fail` already exists (`runner.sh` 681–684). The first symptom patch that passes `green_cmd` integrates.

4. **A real driver, not the word `live-verified`.** `pstack/skills/create-verification-skill/SKILL.md` builds launch, drive, and evidence, and will not ship a skill nobody executed. `agent-compatibility/skills/check-agent-compatibility/SKILL.md` separates "the app boots" from "a small change can be checked". The preflight is "reply ok" from an empty temp dir (`runner.sh` 239–261).

5. **Symptom lines, and one UI at a time.** `dyl-stack/skills/dyl-mode/SKILL.md` lists the patches (null guard, `as any`, `.skip`, snapshot, special case). That list is already in `worker.md`. `runner.sh` never scans the diff. dyl also serializes live UI. Two apsolut lanes share the window.

6. **Swarm on one SHA, risky cards only.** `poteto-mode/playbooks/autopilot-full.md` step 4: verifiers who did not write the code, a gap is not a pass, green CI does not authorize the merge. apsolut has one verifier. Do not take that playbook's merge to the default branch.

`principle-encode-lessons-in-structure`: if a check can be a script, another sentence in `prompts/` does not count.

## Defects a real model hits

`tests/fake-agent.sh` writes the exact path and the exact headings. A model does not.

**The finish line is editable.** `goal_met` runs `done_cmd` in the night worktree (`runner.sh` 322–334) after workers have committed. The canary hashes `GOAL.md`, `prompts/`, and `scripts/` only (`158–159`), not the spec `done_cmd` calls. A card that turns the e2e into `expect(true)` integrates and the night exits 0. `doctor.sh` 123 warns if the predicate is already green; the runner still boots, so an already-passing `pnpm test` and an empty board also exit 0.

**Stdout is not a handoff.** `h_status` and `h_level` need a line that is exactly `## Status` or `## Verification` (`179–188`). Models write `## Status: blocked`, or they put it only in the reply. A missing file becomes a synthetic handoff (`756–766`) whose status matches nothing. Exit 0 plus green (`775–783`) still integrates (`824–830`). `partial` is ignored. A parsed `blocked` skips the retry (`769`), so a reversible question kills the card. The planner will not re-plan `review` or blocked cards (`planner.md` rule 7). Accepted cards keep the model's `owner:` (`438`) and `after:` (`336–344`); `card_ok` (`363–372`) rejects neither.

**Retries see the tail, and a log line wipes a good tree.** The fail file puts the diff first and the output last (`547–553`). The retry and the advisor get `tail` (`709`, `686`), so a long diff is what disappears. `throttled` (`114–116`) runs on the whole transcript before green (`726–742`). A test that prints "too many requests" resets the branch, does not count an attempt, does not charge, and sleeps 900s until `stop_time`.

**The prompt is one argument, and `timeout` may be Windows `TIMEOUT.EXE`.** Lines 119–121 say values stay in files. `run_cli` passes `$(cat prompt)` as argv (`147`). Git Bash dies near 32KB, which is the retry and the planner. `doctor.sh` 39 accepts any `timeout` on `PATH`. `TIMEOUT.EXE` has no `-k`, so the probe fails opaquely, or every card dies in milliseconds and the breaker opens.

**Dirt after green undoes a good merge.** `integrate` rejects any non-ignored porcelain (`312–313`). Coverage or a `tsbuildinfo` that is not gitignored rolls the merge back and leaves the card in `review`, so it is never retried. `card_ok` is `grep -qi test` (`371`). The planner template already contains the word "test", and `spike: true` skips the gate.

## Top 10

Each one is a script. The test is what fails if it regresses.

1. **Pin the predicate.** Add `protect:` to `GOAL.md`. In `runner.sh`, `goal_met` and `integrate` refuse a night diff that touches those paths, and ignore a passing `done_cmd` if they moved. Test: a fake agent that rewrites the protected spec exits 6, not 0.
2. **Handoff in the worktree; stdout is the fallback.** Write `handoff.md` in the worktree, copy it out before any reset, and if it is missing scan `$OUT`. No parseable status is red (`756–784`), not a synthetic pass. Test: a CLI that only prints the handoff, and cannot write outside cwd, still honors `blocked`.
3. **Test-first is two runs.** For a non-spike card, run the new test at `PRE` and require failure, then at `HEAD` and require success, before integrate. The verifier's word cannot override that. Test: a test that passes on both commits stays red.
4. **Show the head of the diff. Keep throttle off test logs.** The retry packet is the start of the diff plus the green tail. Throttle matches only a short CLI envelope, and only when the exit is non-zero and there is no handoff. Test: stdout containing "rate limit" and a green tree still integrates.
5. **Normalize planner cards.** On accept, force `owner: any`, force `after: []`, reject `spike: true`. Test: a staged card with `owner: claude` and `after: [blocked-id]` is claimable by the other lane.
6. **Already-green predicate and a non-GNU timeout refuse the boot.** Make `doctor.sh` 123 a failure, and check both at `runner.sh` startup. `timeout --version` must say GNU. Test: `done_cmd` of `true` exits 4; a `timeout` that rejects `-k` exits 4 before any card.
7. **Diff lint, hard red, including the first attempt.** Added `.skip`, `eslint-disable`, `@ts-ignore`, `as any`, a deleted assertion, or an edit to the green script fails the card. Test: one added `it.skip` is red when `green_cmd` is `true`.
8. **The runner re-runs the card's proof.** `## Execution` must name that command, and the runner's own re-run must agree. A bare `test-verified` is `verifier-failed`. Test: the right word and an empty Execution stays off the night branch.
9. **Install outside the attempt clock.** `worktree.sh spawn` hardlink-copies `node_modules` or `.venv` from a seed worktree (`FUTURE.md`). The timer starts after that copy. Test: a one-minute budget still reaches the model when a sibling already has the deps.
10. **`blocked` ends the card only for a human gate.** Match the unblock line to `PROJECT.md` human gates or a missing credential. Anything else is a normal retry. Test: "not sure about the name" retries; "needs a production token" blocks at once.

## What to cut

Cut `review_agent` and `prompts/review.md` out of the night. It runs after the branch is frozen (`runner.sh` 518–534), spends the last dollars, and cannot change a commit. The fake reviewer always says merge. A script that lists blocked cards, unverified integrates, protect-path diffs, and lint hits is the Attention section.

Cut `spike: true` as a way past the test gate. After item 7, delete the symptom-patch essay from `advisor.md`, `review.md`, and the verifier. One example in `worker.md` is enough.

Keep thermos (`thermo-nuclear-code-quality-review/SKILL.md`) and the pr-review canvas out of the loop. A 1000-line file that passes `done_cmd` should land. A night that stops for "code judo" did not finish.

Do not import autopilot-full's merge to the default branch, Slack, or `/loop`. The Andon file plus a human clear is enough. "Plateau means pivot, not stop" assumes one agent that still holds the night. A fresh planner does not. Two empty rounds and exit 6 is the right stop. Bro voice, canvas grouping, and advisor slug selection do not move `done_cmd`.

### Round 1 — agy

**Verdict (Question 1: Approach).** Build a **hybrid on `apsolut-agents`'s substrate**: keep `apsolut-agents` as the local git-worktree + POSIX-sh execution engine, and port the missing mechanical enforcement from `cursor-plugins` into its scripts. Adopting `cursor-plugins` directly is impossible for local multi-CLI nights because they depend on Cursor's proprietary runtime: `orchestrate` spawns remote Cursor cloud VMs via `CURSOR_API_KEY` and `cursor-sdk` (`cursor-plugins/orchestrate/skills/orchestrate/SKILL.md:11-15`), `pstack` requires Cursor's `/loop` wake command, `Task` tool, and Cursor Projects (`cursor-plugins/pstack/docs/guide/07-overnight.md:35-38,96`), and `advisor` relies on Cursor IDE hooks (`cursor-plugins/advisor/hooks/hooks.json`). They cannot orchestrate local `claude`, `grok`, `codex`, and `agy` CLIs over local worktrees, and outside `orchestrate`'s TypeScript loop, `pstack`/`dyl-stack` rely on model prompt compliance rather than a host script resetting the git tree. Conversely, keeping `apsolut-agents` as-is fails on real projects: v0.9 copied the plugins' *prompt prose* (`template/prompts/README.md:24-46`) but omitted their *structural guarantees*—upstream handoff relay, quantitative measurement checks, cold-worktree bootstrap, conflict recovery on the night branch, and safe CLI prompt/throttle handling.

---

## 2. Gaps: Plugin Mechanisms Missing or Weaker in `apsolut-agents`

1. **Upstream handoff relay into worker prompts (`cursor-plugins/orchestrate/skills/orchestrate/scripts/core/prompts.ts:87-106`, `references/handoffs.md:73-84`).**
   `orchestrate` pastes every `dependsOn` task's handoff into downstream worker prompts. In `apsolut-agents`, `handoff_digest` (`template/scripts/runner.sh:380-390`) only feeds the *planner* (truncated to 8 lines). A worker on a card with `after: [T-01]` never sees T-01's `Notes` or invariants.
2. **Quantitative `measurements[]` verification & env scrubbing (`cursor-plugins/orchestrate/skills/orchestrate/scripts/measurements.ts:128-193,273-341`).**
   `orchestrate` parses `## Measurements` (`metric: before <op> after`), re-runs commands in an allowlisted env (`MEASUREMENT_ENV_ALLOW` + temp `HOME`), and flags >10% drift or unit mismatches. `apsolut-agents` has only binary `green_cmd`/`done_cmd` exit codes and leaks host env vars into checks.
3. **Failure taxonomy & `finished-no-handoff` output capture (`cursor-plugins/orchestrate/skills/orchestrate/scripts/core/failure-handoff.ts:25-53,102-123`).**
   `orchestrate` classifies `oom` (`exit 137`/`OOMKilled`), `cap-hit`, `network-drop`, and `tool-error` (switching models on `tool-error`), and attaches 2,000 chars of raw output when a worker omits a handoff. `apsolut-agents` (`runner.sh:756-766`) lumps `124|137` together and writes a synthetic handoff with *zero* raw output, blinding the planner.
4. **Merges as repairable agent tasks (`cursor-plugins/orchestrate/skills/orchestrate/references/handoffs.md:168-184`, `pstack/skills/poteto-mode/playbooks/autopilot-full.md:19`).**
   In `orchestrate` and `pstack`, branch conflicts trigger a rebase/merge repair round verified at the new head. In `apsolut-agents`, `integrate()` (`runner.sh:303-321`) aborts on conflict and strands the card.
5. **Path boundary enforcement (`pathsAllowed` / `pathsForbidden`) (`cursor-plugins/orchestrate/skills/orchestrate/prompts/worker.md:11-16`).**
   `NIGHTSHIFT.md:44` claims *"Cards touching PROJECT.md human-gate paths are never claimed,"* and cards declare `files:`, yet `runner.sh` has zero code checking either.
6. **Cold-start bootstrap vs. fast validation (`cursor-plugins/agent-compatibility/agents/startup-review.md:17-24`, `agents/validation-review.md:18-26`).**
   `agent-compatibility` separates cold-repo bootstrap from fast scoped validation. `apsolut-agents` runs `green_cmd` in unbootstrapped worktrees.
7. **Dual-rubric review & cognitive diff ordering (`cursor-plugins/thermos/skills/thermos/SKILL.md:15-19`, `cursor-plugins/pr-review-canvas/skills/pr-review-canvas/SKILL.md:26-49`).**
   `thermos` separates bug/security/devex-regression review from structural/1k-line code-quality review; `pr-review-canvas` orders diffs Core Logic → Wiring → Boilerplate with concrete input traces. `apsolut-agents` runs one end-of-night `review.md` capped at 7 lines.
8. **Live UI/server serialization (`cursor-plugins/dyl-stack/skills/dyl-mode/SKILL.md:83`).**
   `dyl-stack` serializes live control-surface verification so concurrent lanes do not collide on ports or browser state.

---

## 3. Defects: What Breaks in a Real Night (`runner.sh` & Prompts)

1. **`throttled()` greps the entire agent transcript, causing infinite unpaid reset loops (`template/scripts/runner.sh:114-116,726-745`).**
   `throttled "$OUT"` greps the *entire* output file `$OUT` for `rate.?limit|overloaded|internal server error|bad gateway|too many requests|...`. In any repo whose code or test output mentions `"Internal Server Error"` or `"rate limit"`, `throttled` false-positives. `runner.sh:726-743` runs `reset --hard $PRE`, leaves `.attempts-$ID` unchanged, skips `charge "$OUT"` (line 745 is *after* `if throttled`), sets `status: waiting`, sleeps 900s, and re-runs the card forever without charging `$SPENDF`.
2. **Failed `integrate()` strands verified cards in `status: review` and triggers a false plateau (`template/scripts/runner.sh:824-835,450-457` + `template/prompts/planner.md:29`).**
   `runner.sh:824` sets `status: review` *before* calling `integrate()`. If `integrate()` fails (merge conflict on `NIGHT_BR` or red post-merge `green_cmd`), `integrated:` stays `null` with no retry. When the board empties, `round_progressed()` (`runner.sh:450-457`) checks `integrated = $NIGHT_BR`, sees no progress, and calls the planner—while `planner.md:29` forbids re-planning `review` cards. Two rounds later the night dies with `exit 6 (plateau)`.
3. **Cold worktrees lack `node_modules`/`.venv`, breaking `BASELINE_OK`, `NIGHT_WT`, and `doctor.sh` (`template/scripts/runner.sh:290,310,325,661-672`, `template/scripts/doctor.sh:120,242`).**
   `runner.sh:661-672` runs `green_cmd` in the first card's fresh worktree *before* any agent installs dependencies, aborting at 12:01am with `exit 4 (harness)`. `NIGHT_WT` (`runner.sh:290`) also skips dependency install, so `integrate()` (`runner.sh:310`) and `goal_met()` (`runner.sh:325`) fail unless `green_cmd` runs `npm ci` every time.
4. **`run_cli` passes the entire prompt via `argv`, hitting `ARG_MAX` / Windows 32KB limits (`template/scripts/runner.sh:118-120,147`).**
   Despite line 118 (*"never argv or env"*), line 147 runs `sh -c "$c \"\$1\"" runner "$(cat "$4")"`. Once `PREVFAIL` (400-line diff + handoff + verdict + output tail), `HANDOFFS`, and `CARD` accumulate, `"$(cat "$4")"` exceeds Windows Git Bash's 32KB `CreateProcess` limit (or POSIX `ARG_MAX`), failing with exit `126/127` and tripping the breaker.
5. **Verifier `tree_state` check (`template/scripts/runner.sh:170-171,800-818`) blocks cards when tests create untracked files.**
   `tree_state` hashes `git status --porcelain`. If verification tests leave any untracked artifact (`.tsbuildinfo`, SQLite DB, coverage, log), `tree_state` changes (`runner.sh:800`), the verdict is discarded as `verifier-blocked`, and the card never integrates (`runner.sh:827`).
6. **`in_stop_window` hardcodes `< 1200`, breaking afternoon/evening `stop_time` (`template/scripts/runner.sh:97`).**
   `int(n)>=int(s) && int(n)<1200` is false for any `stop_time >= 12:00` (including `23:59` in `tests/goal-loop.sh:39`).
7. **Fragile `md_first` handoff parser (`template/scripts/runner.sh:179-188,806-808`).**
   `md_first` inspects only the first non-empty line under `## Verification` / `## Status`. A code fence, bullet, or comment on line 1 causes `h_level` to return empty and marks the card `verifier-blocked`.
8. **Unvalidated planner `after:` edges deadlock the goal loop (`template/scripts/runner.sh:363-373,430-445`).**
   `card_ok()` ignores `after:`. If the planner references a card dropped by `MAX_CARDS` (`line 433`), a typo, or a cycle, `deps_met` (`line 336`) stays false forever and burns all `max_plan_rounds`.
9. **Timed-out runs undercharge spend (`template/scripts/runner.sh:107-110,147`).**
   When `timeout` kills a 45-minute run (`RC=124`), the CLI never prints `total_cost_usd`, so `charge()` records `$2.00` (`FALLBACK_COST`) for a $15+ run.

---

## 4. Top 10 Changes (Ranked by Overnight Impact)

1. **Merge/rebase `NIGHT_BR` into card worktrees before `green_cmd`/verifier, and route `integrate()` failures to `red()` (`template/scripts/runner.sh:638-654,774-835`).**
   Tests code against latest `NIGHT_BR` and retries conflicts instead of stranding cards in `review`. *Test:* Two cards edit adjacent lines of `shared.txt`; assert card 2 retries with conflict context and both land on `NIGHT_BR`.
2. **Add `setup_cmd` / `seed_dirs` worktree bootstrap (`template/scripts/worktree.sh:388-393`, `template/HEARTBEAT.md:60`, `template/scripts/doctor.sh:120,242`).**
   Bootstraps dependencies (or hardlinks `node_modules`/`.venv`) on every worktree including `NIGHT-<date>`. *Test:* `run-tests.sh` requires a gitignored `.bootstrapped` file created by `setup_cmd`; assert `runner.sh` reaches `goal met`.
3. **Restrict `throttled()` to CLI error envelopes / last 15 lines and `charge` before backoff (`template/scripts/runner.sh:107-116,726-745`).**
   Stops test output containing `"500 Internal Server Error"` or `"rate limit"` from causing infinite unpaid reset loops; cap throttle backoffs to 3/card. *Test:* Card test prints `"HTTP 429 rate limit / 500 Internal Server Error"` and exits 0; assert card integrates on attempt 1.
4. **Pass prompts via stdin or file path instead of `argv` `"$(cat "$4")"` (`template/scripts/runner.sh:143-151`, `template/scripts/doctor.sh:285`).**
   Eliminates `E2BIG` / Windows 32KB `CreateProcess` failures on large retry prompts. *Test:* Inject a 100KB `PREVFAIL` file in `tests/goal-loop.sh`; assert `run_cli` succeeds.
5. **Validate planner `after:` DAG in `card_ok()` and relay upstream handoffs into `worker.md` (`template/scripts/runner.sh:363-373,430-445,706-715`, `template/prompts/worker.md:22`).**
   Rejects planner cards with broken/cyclic `after:` edges and injects dependency handoffs into worker prompts. *Test:* Stage card with `after: [MISSING]` (assert rejected); stage `B` `after: [A]` (assert `B-attempt1.prompt` contains `A`'s handoff).
6. **Enforce `files:` and `PROJECT.md` human-gate globs in `runner.sh`, and inject `PROJECT.md` into prompts (`template/scripts/runner.sh:625-635,774-785`, `template/prompts/worker.md`, `template/prompts/planner.md`).**
   Enforces `NIGHTSHIFT.md:44` pre-claim and post-diff, and gives workers `PROJECT.md` invariants. *Test:* Card modifies a path matching `human_gate_globs`; assert runner blocks the card and resets the tree.
7. **Harden handoff/verdict parsing (`md_first` → section scan) and ignore untracked test artifacts in verifier `tree_state` (`template/scripts/runner.sh:170-188,756-768,800-808`).**
   Scans the full section for enum tokens, includes `tail -40 "$OUT"` in synthetic handoffs, and checks only `HEAD` + tracked diffs (`git status -uno`) after verification before cleaning untracked files. *Test:* Verifier creates untracked `tmp.log` and puts `test-verified` on line 3 under `## Verification`; assert card integrates.
8. **Add quantitative `metrics_cmd` baseline-vs-after gate (`template/GOAL.md`, `template/scripts/runner.sh:303-334`).**
   Enforces non-regression on quantitative metrics during `integrate()`. *Test:* Metric counts `TODO` lines; assert a card adding a `TODO` fails `integrate()`.
9. **Fix `in_stop_window()` wraparound math and lock `night_setup()` / `add_spend()` (`template/scripts/runner.sh:97-106,286-302`).**
   Fixes `stop_time >= 12:00` and prevents concurrent lanes from colliding on `NIGHT-<date>` or `$SPENDF`. *Test:* Set `stop_time` to 1 minute ago at 15:00; assert `runner.sh` stops with `reason: stop_time`.
10. **Classify `RC=137` (OOM) vs `RC=124` (timeout) and charge elapsed-time fallback cost (`template/scripts/runner.sh:107-110,758-766`).**
    Prevents timed-out runs from undercharging spend and tells the planner to split oversized cards. *Test:* Fake CLI exits `124` without JSON cost; assert fallback spend scales and synthetic handoff instructs planner to split.

---

## 5. What to Cut

1. **Plain board mode vs. Goal mode split (`template/NIGHTSHIFT.md:47-52`, `runner.sh:58-66`).** Always integrate verified cards onto `agent/night/NIGHT-<date>`; if `done_cmd` is empty, stop when the board empties. Eliminates `after:` deadlocks and deletes dual-mode branching across `runner.sh`, `doctor.sh`, and `status.sh`.
2. **Hoarding integrated card worktree folders (`FUTURE.md:14-24`, `worktree.sh:510-564` `--jar`).** Once a card merges (`--no-ff`) onto `NIGHT-<date>` and its attempt is pinned under `refs/apsolut/attempts/`, git refs and `runs/` hold all evidence. Auto-remove the card's worktree on integration to save gigabytes of disk and drop `--jar` ceremony.
3. **Dual generated state files (`STATUS.md` + `state/PROJECT_STATE.md` in `template/scripts/status.sh:130-196`).** Generating identical git facts into two tracked files creates dirty-tree churn; keep one.
4. **Prose-only `INTENT:` log lines (`template/WORKTREES.md:153-159`) and `TICK:` spam in `agent-log.md` (`runner.sh:103`).** Replace unenforceable `INTENT:` prose with `files:` overlap checks in `pick_ready()`, and write `TICK:` events only to `runs/trail-<date>.tsv`.

### Round 2 — codex

1. **High — stdin mode can prevent the lane from starting.** `template/scripts/runner.sh:210` introduces `prompt_<agent>: stdin`, but the preflight at line 351 always appends the probe as an argument and never supplies it on stdin. With the documented `cmd_codex: codex exec -`, the probe becomes an extra positional argument; a stdin-only wrapper instead receives no probe. The lane fails before dispatch. **Fix:** send preflight prompts through the same delivery function as normal calls, with a short probe timeout. The fake CLI accepts either transport, masking this incompatibility.

2. **High — the frozen card is overwritten on retries.** `template/scripts/runner.sh:803` copies the live card over the snapshot every time the card is claimed; line 784 also reloads `check:` from the live card. If attempt 1 edits its shared card to weaken `verify:`, `check:`, or Done-when, then fails, attempt 2 adopts those edits. The CHANGELOG’s claim that worker edits “change nothing” therefore holds only within one attempt. **Fix:** retain the original contract snapshot across retries and read all acceptance fields from it; update operational fields separately.

3. **High — protected glob paths are expanded by the shell.** `template/scripts/runner.sh:286` passes unquoted `$PROTECT` to Git. For `protect: tests/*.sh`, launching from a primary checkout containing `tests/existing.sh` expands the pattern to existing primary files before Git sees it. A worker can add `tests/new.sh` without triggering either the card or night protection check. Results also depend on the runner’s launch directory. **Fix:** disable pathname expansion while splitting the configured pathspec list, then pass each literal pathspec as a quoted argument.

4. **Medium — restart persistence is broken on macOS and never closes normally.** `template/scripts/runner.sh:40` uses GNU `date -r FILE`; BSD/macOS `date -r` expects epoch seconds, so this falls back to zero and rejects the saved night after midnight. Separately, line 45 refreshes the timestamp on every launch, while `finish()` never removes or closes `.night-current`. Repeated launches less than 18 hours apart can keep reusing an old, completed night indefinitely, including its exhausted budget and planner rounds. **Fix:** store an explicit portable start timestamp and lifecycle state; close the shared night when its lanes have finished rather than refreshing its age on every launch.

5. **Medium — JSON final-message handoffs are not recovered.** `template/scripts/runner.sh:964` replaces escaped newlines, then requires `## Status` at the beginning of a physical line. With the shipped JSON-output configuration, a final message such as `{"result":"## Status\nblocked\n..."}` retains the JSON prefix before that heading. Recovery produces nothing; a blocked handoff becomes synthetic and loses its immediate-block behavior. I reproduced the empty extraction with that input. **Fix:** decode the CLI’s final-message JSON field before parsing Markdown. The new test emits raw Markdown and misses this case.

6. **Medium — a passing card check does not protect its integration result.** `template/scripts/runner.sh:1010` runs `check:` only on the card branch; `integrate()` at line 428 reruns only `green_cmd`. If another lane lands an incompatible but cleanly merging change, the combined tree can fail the card’s check while remaining green. In no-verifier mode, the card is nevertheless marked integrated and its dependents become eligible. **Fix:** rerun the frozen card check on the merge candidate under the integration lock; treat failure as an integration red.

7. **Medium — the delegate throttle-accounting claim is not implemented.** `template/scripts/delegate.sh:338` still rolls back every throttled round and exits before charging at line 355. It has no `max_backoffs_per_card` counter. Thus the CHANGELOG’s “Every call is charged,” capped-throttle behavior, and “same fix” in `delegate.sh` overstate this release. This is an unfulfilled release claim, rather than a newly introduced accounting defect. **Fix:** charge before the throttle branch and implement the cap, or narrow the CHANGELOG claim.

**Validation:** `sh tests/goal-loop.sh` could not start because the environment denied `mktemp` creation under `/tmp`. The JSON extraction reproduction was read-only; no files were modified.
### Round 2 — grok

# v0.10.0 diff review


## 1. A green merge that leaves untracked files is destroyed

`template/scripts/runner.sh:429` and `:1086`.

`integrate` still fails on any `git status --porcelain` line (no `-uno`). `tree_state` (`:255`) ignores untracked files; the merge does not. `green_cmd` that writes `coverage/`, a `.tsbuildinfo`, or a sqlite file prints `green_cmd changed the night tree` and returns failure.

v0.9 left that card in `review` with its commits and zeroed the breaker first. v0.10 calls `red()` (`:701`), resets the branch to `PRE`, and increments `FAILS`. The retry hits the same artifact and blocks. The third card trips the breaker (exit 2). The grep at `:1090` keeps only `MERGE CONFLICT` and `GREEN RED`, so the retry’s first line is empty.

Fix: use `status --porcelain -uno` in `integrate`. If the tracked tree is clean, keep the merge. Call `red()` only for a conflict or a red `green_cmd`.

## 2. The prompt pointer misses real CLIs

`runner.sh:209-224`. `HEARTBEAT.md:86-89` shows `prompt_claude: stdin` as a comment, so stock lanes stay on argv. `prompts/worker.md` is 3748 bytes; the goal plus the card crosses 6000 on the first attempt. Retries and planner rounds always do. The CLI then gets one sentence: read `$WS/runs/…prompt`.

That file is outside the worktree. On Git Bash the path is MSYS (`/c/Users/…`) inside a sentence, so it is not converted, and `claude.exe`, `grok.exe`, and `agy.exe` cannot open it. The planner writes nothing; two empty rounds plateau (exit 6). `tests/fake-agent.sh:20` hides this: a shell script can `cat` that path.

Fix: copy the prompt to `<worktree>/.apsolut-out/prompt.md` and point at that relative path. Set a real `prompt_<agent>: stdin` for `claude -p`.

## 3. The 18h night file does not match the changelog

`runner.sh:38-45`.

`date -r FILE` is GNU. On macOS `-r` means “print this epoch”; the path fails, `nft` is 0, and line 45 replaces `runs/.night-current` with today’s date. The restart opens `NIGHT-<today>` from `main` and a new spend file. The 18h claim is false on macOS.

Where `date -r` works, every boot rewrites the file and `finish()` never removes it, so restarts under 18h apart keep one budget and one `NIGHT-<first-date>` across days.

Fix: mtime via `stat -c %Y` or `stat -f %m`. Write the stamp once. Remove the file in `finish()`.

## 4. A handoff in CLI JSON is dropped

`runner.sh:962-968`. Shipped `cmd_claude`, `cmd_grok`, and `cmd_agy` use `--output-format json`. Recovery keeps a line only when it starts with `## Status`. In JSON the heading is mid-line (`"result":"## Status\nblocked\n…"`). `grep` matches, awk stores nothing, the file is removed, and the synthetic handoff is used. `Status: blocked` never reaches `:982`. A green tree integrates; otherwise the dead end burns attempts. Scenario 12 prints raw markdown, so that test stays green.

Fix: unescape `\n`, then take the text from the last `## Status` even mid-line.

## 5. Heading prose is a substring match

`runner.sh:267-281`, used at `:982` and `:1056`.

The parser pulls the rest of `## Status:` / `## Verification:` into the body, then `grep -oiE` with no word boundary. `## Status: not blocked` matches `blocked`: `red … block` drops the card and skips the retry. `## Verification: not live-verified` matches `live-verified` (rank 3) and the card merges. v0.9 required those headings to be exact, so this prose never reached the grep.

Fix: after stripping bullets and `*_`, accept a line only when it is exactly `success`, `partial`, `blocked`, or exactly one verdict token.

## 6. A timeout whose log quotes the suite is still a throttle

`runner.sh:171-174` and `:929-947`.

A non-zero exit whose last 40 lines contain `Internal Server Error` or `status 500` is a backoff: tree reset, attempt not counted, sleep 900. Exit 124 during a failing HTTP test does this. One-line JSON makes “last 40 lines” the whole result. `DID_ONE` is set at claim (`:799`), so after the sleep `--once` exits 0 at `:743` with the card still `waiting`.

`[ "$bo" -lt "$MAX_BACKOFF" ]` counts the 3rd throttle. The HEARTBEAT comment says up to 3 are free.

Fix: do not treat 124 or 137 as a throttle; require the phrase on a line that also contains `is_error`. Compare with `-le`. Set `DID_ONE` only when the card reaches review, blocked, or a counted red.

## Claims the code does not deliver

- “The same fix is in `delegate.sh`” and “every call is charged.” `delegate.sh:338-352` exits on throttle before `add_spend` (`:356`). No `max_backoffs_per_card`, no per-minute floor. A throttled delegate round is free and unbounded.
- `doctor.sh` “proves `setup_cmd`.” `doctor.sh:252-256` checks only the exit code. `setup_wt` (`runner.sh:415-417`) also rejects tracked edits and ends the night at `:813` (exit 4). A lockfile rewrite passes doctor and dies on the first worktree.
- Stdout handoffs, the 18h night, and “prompts always arrive” are findings 2–4.

`stop_time` at 12:00, anchored `CARD IS WRONG:`, the `latest` gate, the planner snapshot, and `-uno` on verifier verdicts match the diff.
