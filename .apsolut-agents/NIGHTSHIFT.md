<!-- apsolut-agents: tier=2 kind=doc -->
# NIGHTSHIFT — unattended overnight runs (Tier 2)

_Runs task cards through the night with no human in the loop. Design reviewed blind
by three models (Claude draft, Gemini + Grok reviews); the cuts they agreed on are
law here: rule-based control only, no overnight merges into the default branch,
kill is terminal, no automatic cross-model reassignment. The v0.9 goal loop (below)
merges onto a separate night branch only. The default branch still moves only when a
human runs `done --merge`._

## The deal

Evening: you write task cards. Night: one runner per agent works the board in
isolated worktrees. Morning: you review **unmerged branches** — each card is one
clean `--no-ff` merge candidate; rejecting one card = simply not merging its branch.

```
sh .apsolut-agents/scripts/runner.sh claude        # terminal 1 (whole night)
sh .apsolut-agents/scripts/runner.sh grok          # terminal 2 (v2 — after solo nights are boring)
sh .apsolut-agents/scripts/runner.sh claude --once # ONE card through the pipeline, then stop (v0 gate)
sh .apsolut-agents/scripts/runner.sh claude --drain # until the board is empty / goal met, no idle wait
```

Config lives in `HEARTBEAT.md` (instance file — yours): timeouts, budget, breaker
thresholds, `green_cmd`, per-agent headless commands, ntfy.sh URL.

**Attended sibling:** `DELEGATION.md` / `scripts/delegate.sh` runs the same agents on the
same cards *while you're present* — you dispatch, watch, and send correction rounds. Same
claim mutex and same daily spend ledger, so the two can't collide over a card. Rule of
thumb: rule-based and destructive-on-red at 3am (`runner.sh`), judgement-based and
non-destructive when a foreman is reading the output (`delegate.sh`).

## What a card needs to be night-runnable

- **Filename = `<id>.md`, exactly.** Claims, deps and reports all construct
  `work/<id>.md` from the `id:` field; the runner refuses to start the lane if any
  card's filename disagrees with its `id:` (a mismatch used to half-work, then
  silently miss everything downstream).
- **`check:`** — one command the runner itself runs: it must FAIL before the change
  (else the card is refused: it is done already, or the check proves nothing) and
  PASS after. This is test-first enforced by a script, not asked of a model. Cards
  without `check:` must name a test in Done-when, or be `spike: true`. Planner cards
  always carry one.
- Concrete **Goal** + **Done when** (vague cards produce confident garbage at 3am) —
  stating what must be true, not which commands to run, and no constraints the task
  doesn't actually have: the 3am agent treats every word on the card as law.
- `files:` declared **and tracked** — a worktree contains only tracked files, so a
  gitignored input (or an untracked helper `green_cmd` relies on) is invisible to
  the agent; `doctor.sh` flags both. Cards touching `PROJECT.md` human-gate paths
  are never claimed.
- Optional `after: [T-01]` dependency edges and `budget: 30` (minutes) override.

**`after:` without a goal is sequencing, NOT code visibility.** In plain board mode
branches stay unmerged overnight, so a dependent card branches from the default
branch and **cannot see its dependency's code**. The runner only treats the dep as
satisfied once it is `done` (merged). **In goal mode it is code visibility:** a dep
clears when it is integrated onto the night branch, every attempt starts from the
night tip, and the worker's prompt carries the dep's handoff.

## The loop (per card)

claim (`mkdir claims/<id>` mutex → card rewrite with owner/status) → spawn worktree →
run the agent's headless CLI with the card as prompt, hard timeout → salvage-commit
any uncommitted work → run `green_cmd`; **the green check decides, never the LLM's
own claim** → green: `status: review`, branch waits for morning · red: the attempt
is pinned under `refs/apsolut/attempts/<id>-<n>` and its diff + output tail saved
as `runs/<id>-attempt<n>.fail`, the worktree reset, and the next attempt gets that
failure context in its prompt (a blind retry repeats the same dead end); retry
once, then `status: blocked` + phone ping. Backoff resets salvage + pin the same
way — a 429 never destroys work.

## What the runner enforces, not asks (v0.10)

Distilled from a blind four-model review (Claude, Codex, Grok, agy) of v0.9 against
the Cursor plugins: every rule a script can check moved out of the prompts.

| rule | how |
|---|---|
| the judge is not the worker's | `protect:` pathspecs (HEARTBEAT + GOAL.md): a card diff touching one is red; a night diff touching one cannot meet the goal. The card is snapshotted at claim, so a worker editing its own `verify:` or Done-when changes nothing. |
| test first | `check:` runs before (must fail) and after (must pass) |
| no symptom patches | `forbid_added:` regex over added lines (`.skip(`, `.only(`, `@ts-ignore`, `eslint-disable`, …) → red |
| one call cannot outspend the night (v0.11) | `$APSOLUT_CALL_BUDGET_USD` (`call_budget_usd`, never more than what is left of the night) goes to a CLI with a spend flag; a worker that hits it is blocked, not retried |
| exit 0 is not "finished" (v0.11) | a CLI that reports `is_error`, a cancelled turn, a denied tool or its own turn limit is red whatever it exited with; its own timeout reads as a timeout |
| lanes do not fan out by themselves (v0.11) | the `cmd_` lines switch off each CLI's native subagents; `doctor.sh` warns about a line that does not |
| a throttle is a failed call | only a non-zero exit or `is_error`, judged on the last 40 lines; every call is charged; `max_backoffs_per_card` then it counts as an attempt |
| nothing hangs the night | `check_timeout_minutes` caps setup, green, check and done_cmd |
| fresh worktrees are usable | `setup_cmd` runs once per worktree, outside the attempt clock |
| prompts always arrive | `prompt_<agent>: stdin`, or argv up to `prompt_arg_max_bytes`, then a pointer to the prompt file |
| sandboxed CLIs can report | roles write into `<worktree>/.apsolut-out/` (git-excluded); the runner collects into `runs/`. A handoff printed as the final message counts too. |
| merges are tasks | a card that conflicts or goes red on the night branch is a red attempt; its retry starts from the night tip |
| proof is kept | verifier scratch moves to `runs/evidence/<id>-verify<n>/` |
| a broken verifier is loud | two `verifier-blocked` in a row raise the Andon |
| goal mode needs a second opinion | with no verifier, only cards whose `check:` passed integrate; the rest wait as `unverified` |
| risk picks the judge (v0.12) | a card whose `risk:` holds one of `risk_tags` is judged by `risk_verifier_agent` (else `verifier_agent`); with no verifier it never integrates on its `check:` alone and waits as `risk-unverified`. Read from the card snapshot, so a worker cannot drop its own tag |
| a block says what blocked it (v0.12) | every blocked card carries `Blocked by: task \| rule \| cli`: the work failed, a runner rule refused it, or the CLI never finished. The night report repeats it |
| a crash does not reset the night | `runs/.night-current` keeps the night (branch, spend, rounds) across a restart within 18 h |
| cost is honest | no cost in the output → `max(cost_fallback_usd, minutes × cost_per_minute_usd)`; the spend ledger is locked across lanes |

## Roles and the per-card pipeline (v0.9)

Each role is a plain prompt in `prompts/<role>.md`, rendered with the card, the goal,
and the evidence. Each optional role is an agent name in `HEARTBEAT.md` (`verifier_agent:`,
`advisor_agent:`, `review_agent:`; `planner_agent:` lives in `GOAL.md`).

```
claim → snapshot card → [setup_cmd, new worktree] → check: must FAIL → [advisor, retries only]
  → worker → handoff → green_cmd → protect: + forbid_added: → check: must PASS → [verifier] → review
                                                                       └─ goal mode: integrate → night branch
```

- **Worker** (`prompts/worker.md`): carries the rules agents keep breaking. Prove it on
  the real artifact. Write the test first. Write `Root cause: X because Y` before any
  fix (a null guard, a retry, or a `.skip` is a symptom patch until that line
  justifies it). Make the smallest change. After two failed fixes, attack the
  premise. Never weaken the check. A dead end is a `blocked` handoff. It ends with a
  structured **handoff** in `runs/handoffs/<id>-attempt<n>.md` (Status, Root cause,
  What I did, Verification, Notes, Suggested follow-ups). No handoff gets a synthetic
  one that names the failure mode: timeout ("split the card"), left its branch, or
  CLI error. `Status: blocked` blocks the card at once, with no retry burned.
- **Verifier** (`prompts/verifier.md`): a *different* agent runs the change. It is
  read-only, and the runner checks HEAD and `git status` and resets any edit. It
  returns `live-verified | test-verified | typecheck-only | verifier-blocked |
  verifier-failed`. Below the card's `verify:` level (default `test`), the attempt is
  red, and the verdict goes into the retry's failure context. `verifier-blocked` means
  the environment, not the work, so the card waits in `review` as **unverified** and
  never integrates. Do not give this role a weaker model than the workers: a judge
  that cannot follow the code rejects good work, and each wrong rejection is a paid
  retry. `risk_verifier_agent` sends the cards tagged with a `risk_tags` entry to
  your strongest model and leaves the rest with the usual one.
- **Advisor** (`prompts/advisor.md`): before a retry, a different agent reads the
  failed diff and output, then names the mechanism, the wrong premise, and the next
  steps. That diagnosis goes into the retry prompt. `CARD IS WRONG:` blocks the card
  instead of burning the attempt.
- **Reviewer** (`prompts/review.md`): at night end, it audits the decision trail and
  handoffs against the evidence. It appends `## Attention` (🟢/🟡/🔴, at most 7 lines)
  and `## Waiting on the human` to the night report. Read it first.

Every decision is a row in `runs/trail-<date>.tsv`: claim, green or red, verdict,
integrate, plan, goal check, stop. The trail plus the diff is what lets the morning
trust the night.

## Goal loop: run until the final product (v0.9)

Fill in `GOAL.md` (goal, `done_cmd:`, and what "final product" means) and the night
stops working a *list* and starts working toward a *predicate*:

```
board has a ready card? ── yes → run it (pipeline above); verified → merge onto the night branch
        │ no
        ▼
done_cmd on the night branch ── exit 0 → GOAL MET, stop
        │ red
        ▼
planner (prompts/planner.md) reads GOAL.md, the predicate's output, the board, and
the handoffs' follow-ups → writes ≤ max_cards_per_round cards → runner validates
them (filename = id, Goal + Done when, test-first) → work/ → loop
```

- **One night branch** (`agent/night/NIGHT-<date>`, a card-shaped worktree). Each
  verified card merges onto it with `--no-ff`, one merge commit per card, so a single
  card reverts cleanly. Green runs again after each merge, and a red merge is undone.
  Later cards **spawn from the night branch**, so `after:` clears on integration and a
  three-card chain finishes in one night.
- **Stops**, each with an exit code and a line in the report:

  | exit | reason |
  |---|---|
  | 0 | goal met (the predicate passed on the night branch) |
  | 6 | planner wrote `STUCK.md` (needs a human decision), plateau (two plan rounds in a row landed nothing), or `max_plan_rounds` used up |
  | 5 | Andon raised, or the tamper canary fired |
  | 2 / 3 / 4 | breaker / budget / harness, as before |

- **A plateau means pivot, and the predicate never relaxes.** When a round lands
  nothing, the next planner prompt says so and orders it to attack the shared premise
  before planning again. A second empty round stops the night instead of spinning.
- **Morning:** `worktree.sh review NIGHT-<date>`, then `worktree.sh done NIGHT-<date>
  --merge`. That is the usual proven merge (green in the worktree, primary moves only
  on pass). The per-card branches are already contained in it. Remove their worktrees
  with plain `done <id>`.
- **Write `done_cmd` as a predicate, never a duration.** Good ones are an e2e journey,
  an acceptance suite, `! grep -rq TODO src`, a coverage floor, or a pixel diff. "Work
  for 4 hours" gives the loop nothing to check. `doctor.sh` proves `done_cmd` *runs*
  in a pristine worktree (red is expected, "command not found" is not).

## Andon and the tamper canary (v0.9)

- `scripts/andon.sh raise "<reason>"`: any agent stops the line for every lane. Use
  it when there is evidence that continuing produces garbage: upstream output is
  wrong, the harness is broken, or auth is dead. One card's dead end is a `blocked`
  handoff, not an Andon. Runners exit 5 before their next claim. **Only the human
  clears it** (`andon.sh clear`, which is refused from a worktree or a delegate).
- **Tamper canary:** the runner checksums `HEARTBEAT.md`, `GOAL.md`, `prompts/` and
  `scripts/` around every agent call. An agent that edits the rules it runs under
  (they are reachable through `.primary`) raises the Andon and ends the night. This is
  detection, not prevention. Prevention needs Docker lanes (FUTURE.md).

## Safety rails (structural)

- Lane preflight: on boot the runner sends the CLI one "reply ok" probe from an empty
  temp dir and refuses to start the lane if it fails — bad auth or a refusing account
  costs one probe, not a whole board of burned attempts.
- Baseline green: before the first dispatch the runner runs `green_cmd` on the
  pristine worktree; if it fails there, the night refuses as a **harness** failure
  (exit 4) instead of blocking good cards and tripping the breaker.
- Runner cannot push (spawn seals that worktree's pushurl) and never merges — branches only. HOLD stays human.
- Per-night **hard budget cap** (`night_budget_usd`), per-card time cap, lane circuit
  breaker (N consecutive failures → stop), provider 429/quota → backoff, not failure.
- Boot recovery: stale claims (dead pid + old) are released on every start.
- Kill cleanup: process-tree kill via `timeout -k`, then `index.lock` removal and
  `reset --hard` on failure — a wedged attempt never poisons the next one.

## Morning ritual

Read `runs/night-<date>.md`. Start with **Attention** and **Waiting on you**, then
the goal state, the card table (status, verdict, integrated), and spend. Follow the
trail rows Attention points at. Then run `worktree.sh review`, and `worktree.sh done
<id> --merge` for the branches you accept. In goal mode that is usually just
`done NIGHT-<date> --merge`. `--merge` runs `green_cmd` in the agent worktree and moves the primary
branch only if that passes and leaves the merge commit unchanged. A dirty folder stays until you run `done <id> --jar` (branch already
in `HEAD`) or `done <id> --reject "<why>"`. Nothing prunes worktrees for you.
Reassigning a blocked card to the other model is a **human** decision, made
here, with the attempt output in front of you. Read `Blocked by:` first. `task`
means the work failed: fix or split the card. `rule` means a runner rule refused a
change that may be fine: decide whether the rule or the card is wrong. `cli` means
the agent never finished: nothing was learned about the card, so rerun it.

## Cards from GitHub issues (v0.12)

`sh scripts/intake.sh` turns every open issue that carries the label `agents`
(`intake_label:` in `HEARTBEAT.md`, or `--label`) into `work/GH-<number>.md`. The
label is your approval: on a public repo anyone can open an issue, and its text
reaches a worker that runs with approvals bypassed. Naming issue numbers narrows the
list and never waives the label.

Cards arrive as `status: hold`. Read each one, add a `check:` and `risk:` tags, then
set `status: waiting`. `--ready` writes `waiting` directly, for a board you trust to
run unread. The issue text is quoted into the card as data, with a note to the worker
that it is a request and not instructions. A card is a snapshot, an issue that
already has a card is skipped, and `--dry-run` writes nothing. Needs `gh`, signed in.
Anything that can open a labelled issue (an alert, a failed deploy, a teammate) can
now feed the board.

## Phase gates (don't skip)

Before any run: `sh .apsolut-agents/scripts/doctor.sh <agent>` — tools, HEARTBEAT
sanity, card contract + `after:` graph, green on the primary, rolling cost vs
budget, and a live CLI probe, in one command. Exit 1 = do not start the night.

v0: 3 supervised `--once` runs — zero double-claims, zero touches of the default
branch, every green branch builds, budget respected. v1: 5 clean unattended solo
nights. v2: add the second lane + `heartbeat.sh` (future — not shipped yet). Full rationale: the night-shift
PRD in `runs/` (or `ideas/` while drafting).
