<!-- apsolut-agents: tier=2 kind=doc -->
# DELEGATION — an agent driving another agent's CLI (Tier 2)

**Any agent in the roster may run any other agent's CLI as a subordinate worker, in
session, and stay in charge of it.** Claude can spin Grok; Grok can spin Claude; either
can spin Codex, Gemini, or a local model. The agent doing the spawning is the
**foreman** — it dispatches, watches, corrects, and decides. The spawned agent is a
**delegate**: it writes code in an isolated worktree and nothing else.

This is the attended sibling of `NIGHTSHIFT.md`. Same cards, same claims, same spend
ledger — the difference is that here somebody is reading the output and can course-correct
mid-flight, so `delegate.sh` **reports** a red green-check instead of resetting the work.

```
sh .apsolut-agents/scripts/delegate.sh run grok T-014 --detach
sh .apsolut-agents/scripts/delegate.sh status
sh .apsolut-agents/scripts/delegate.sh tail T-014
sh .apsolut-agents/scripts/delegate.sh run grok T-014 --note "keep the public API; fix the failing case only"
sh .apsolut-agents/scripts/delegate.sh stop T-014
```

---

## 1. When to delegate (and when not to)

Delegate when the work is **separable and verifiable**: a card with a concrete Goal, a
`Done when`, declared `files:`, and a green check that decides the outcome. Good fits —
a self-contained refactor, a test suite to fill in, a migration with a clear shape, a
port of a known pattern, anything you'd hand a competent contractor with a spec.

Don't delegate: exploration with no success criterion (you'll get confident garbage),
anything on a `PROJECT.md` human-gate path, or work you can't verify. **If you cannot
state how you'll know it worked, you cannot delegate it** — a delegate optimizes for
looking done.

Also don't delegate what's cheaper to do yourself. A round costs real money and 10–45
minutes of wall clock; a 20-line edit does not need a foreman.

## 2. The loop

1. **Write the card.** `work/<id>.md` from `work/_TEMPLATE.md`. `delegate.sh` refuses
   without one — a delegation with no card has nothing to verify against.
2. **Dispatch.** `delegate.sh run <agent> <id> --detach`. A worktree is spawned on round
   1 and reused after; the delegate lands on `agent/<agent>/<id>`.
3. **Track.** `delegate.sh status` for the board (who's running, which round, spend so
   far, which cards are waiting on your judgement). `delegate.sh tail <id>` for live
   output. Poll on your own rhythm — don't sit in a tight loop burning context; do other
   work between checks. Status you put in the log is facts off the board — running,
   exited (code), green/red, timed out — never a guess about what the delegate is
   "probably" doing; timers are backstops, facts decide.
4. **Decide.** On green: read the diff, then `worktree.sh done <id> --merge`. On red:
   read the output and choose — one more round with a correction, take it yourself, or
   escalate. `delegate.sh stop <id>` kills a delegate that's off the rails; it
   salvage-commits so nothing is lost, and keeps the branch for inspection.
5. **Correct, don't restart.** A follow-up round is `run` again on the same id with
   `--note "<instruction>"`. Same worktree, same branch, and the delegate is told to read
   its previous output first. That's how you "give it commands".
6. **Log it, then end your session normally.** One log entry per dispatch and per result
   is written for you. What is *not* automatic is the judgement: before your session-end
   token, say in `agent-log.md` what you delegated, what you accepted, what you rejected
   and why. A branch nobody can explain is worse than no branch.

Rounds are capped (`delegate_max_rounds`, default 4) and counted at **dispatch**, so
stopping and re-dispatching doesn't reset the budget. Hitting the cap is a signal, not an
obstacle to route around: **the card is wrong, not the delegate.** Re-scope it, split it,
or do it yourself. One thing deliberately doesn't count: a round the provider rate-limited
or errored out (verdict `THROTTLED` — the counter is rolled back, nothing is charged).
A round you `stop` **does** count, and is charged the fallback cost — it consumed tokens,
and a stop that refunded itself would make the cap meaningless.

## 3. Permission posture — bypass is the human's call, in the human's file

Each agent's headless invocation lives in `HEARTBEAT.md` as `cmd_<agent>:`, including
whatever permission posture the human chose:

```
cmd_claude: claude -p --dangerously-skip-permissions --output-format json
cmd_grok:   grok --always-approve --output-format json -p
cmd_codex:  codex exec --dangerously-bypass-approvals-and-sandbox --json
```

`HEARTBEAT.md` is `kind=instance` — yours, never overwritten by an upgrade. **That file
being the only place the flags live is the opt-in.** An agent cannot grant itself a
looser posture, because it does not write `HEARTBEAT.md`; if `cmd_<agent>:` is missing,
`delegate.sh` refuses and tells you to ask the human. Nothing here nags you about the
flags once they're there — that decision is made and recorded.

Running delegates with approvals bypassed is what makes unattended rounds work at all;
a delegate that stops to ask permission in a headless pipe just burns its timeout. Be
clear-eyed about the trade, though: **a foreman running inside a restrictive harness that
spawns a bypass-permission delegate has routed around its own harness's permission
model.** That is a legitimate thing to do deliberately in your own repo, and a bad thing
to do by accident. The containment is structural, not advisory:

| Rail | Enforced by |
|---|---|
| Delegates run only in a spawned worktree (`*-wt-*`), never the primary | `delegate.sh` refuses otherwise |
| Never push, never merge | prompt contract + `worktree.sh done --merge` is the only merge path, run by you |
| Never write under `.apsolut-agents/` | prompt contract + `git add` pathspec excludes it |
| Cannot spawn its own delegates | `APSOLUT_AGENT_DEPTH` + `delegate_max_depth` |
| Bounded blast radius | one branch per card, unmerged until a human-or-foreman reads the diff |
| Bounded spend | shared `runs/.spend-<date>` ledger + `delegate_budget_usd` hard stop |
| Bounded fan-out | `delegate_max_concurrent` counted from live claims |

Everything a delegate does is one `git diff` away from being seen, and one unmerged
branch away from being discarded. That's the whole design.

## 4. Caps (all defaulted — no config needed to start)

`HEARTBEAT.md` keys, with the built-in default `delegate.sh` uses when the key is absent
(it will be absent on any workspace installed before delegation existed — that's fine):

| Key | Default | What it stops |
|---|---|---|
| `delegate_max_depth` | 2 | Recursion. A delegate is spawned at depth 1 and refuses to delegate further, so Claude→Grok→Claude→… cannot run away. |
| `delegate_max_concurrent` | 2 | Fan-out. Counted from live claims, so it holds even if the depth env var doesn't propagate through a CLI. |
| `delegate_max_rounds` | 4 | Infinite correction loops on a card that's wrong. |
| `delegate_timeout_minutes` | `card_timeout_minutes`, else 45 | A wedged delegate. Per-card override: `budget:` on the card, or `--budget <min>`. |
| `delegate_budget_usd` | `night_budget_usd`, else 25 | Runaway spend. Shared ledger with Night Shift: the same daily cap covers both. |

Two caps deserve their reasoning stated, because they look like friction:

- **Depth.** Mutual spawning is the point of this file (Grok spinning Claude is a
  first-class case) — but *transitive* spawning has no natural floor, and every level
  multiplies cost and shrinks accountability. One level of delegation keeps exactly one
  agent answerable for each branch.
- **Concurrency.** Not a performance limit — a comprehension limit. Three delegates
  editing three branches produce more diff than a foreman can honestly review, and an
  unreviewed accept is the failure this whole workspace exists to prevent.

An agent never raises a cap. Ask the human, in the log.

## 5. What the foreman owes the workspace

`delegate.sh` writes the mechanical entries (dispatch, result, spend, ticks). You owe the
judgement, and you own everything your delegates did — the same rule as `PROTOCOL.md §5`
for subagent fan-outs, and for the same reason:

- **Delegates never touch this workspace.** They don't log, don't update state, don't
  write cards. You translate their output into the record.
- **One `runs/` artifact per non-trivial delegation** if the output is worth keeping
  (a review, a plan, an investigation) — `runs/<date>-<slug>.md`, linked from the log.
  Raw CLI transcripts already land in `runs/<id>-delegate<N>.out`; those are evidence,
  not documentation.
- **State the verdict on every branch you leave behind.** Merged, kept-for-later with a
  reason, or deleted. `delegate.sh status` lists cards sitting in `review` precisely so
  the next session can see what you left undecided.
- **`Committed ≠ done` applies to your delegates' work too.** A delegate cannot push, so
  its work is *by construction* not done until you merge and push it.
- **Prefer fresh eyes for judgement verdicts.** `green_cmd` decides mechanically;
  where only judgement can verdict (a design, a review, a doc), route the read to an
  agent that didn't produce it when the roster allows — after three correction rounds
  you aren't one. Solo roster: say so in the log and review it yourself.

## 6. Interaction with Night Shift

Same claim mutex (`claims/<id>`), same card fields, same spend file — so an in-session
delegation and an overnight `runner.sh` lane **cannot double-claim a card**, in either
order. Whichever gets `mkdir claims/<id>` first owns it; the other refuses and says so.

If you delegate during the day and leave the branch in `review`, the night runner will
not touch that card (it only claims `status: waiting`). Conversely, a card a runner
blocked overnight is a perfectly good thing to delegate a corrective round to in the
morning — with the failure output from `runs/` in your `--note`.

## 7. Failure modes seen in practice

| Symptom | Cause | Fix |
|---|---|---|
| Delegate reports success, green fails | It optimized for the claim, not the check | Never trust the delegate's own verdict — `delegate.sh` already ignores it and runs `green_cmd`. Set `green_cmd` in `HEARTBEAT.md`; `unverified` is not `green`. |
| Round 3+ on the same card | Card is under-specified | Stop. Re-scope or take it yourself. More rounds make it worse. |
| `THROTTLED` verdict | Provider rate limit / 5xx / quota — not the delegate's fault | Nothing to fix. It did **not** consume a round (the counter is rolled back) and nothing was charged to the ledger. Wait and re-dispatch. |
| Delegate wandered outside its worktree | Weak card, wide `files:` | Branch assert catches it (`rc=97`); tighten `files:` and re-dispatch. |
| Nothing in the output, immediate exit | Wrong `cmd_<agent>` — usually a missing `-p`/`exec` or a prompt-position mismatch | The prompt is appended as the last argument; check the CLI's headless invocation. |
| `already claimed` | A runner lane or another delegation owns the card | `delegate.sh status`, then wait, stop it, or pick another card. |
| Spend cap hit mid-afternoon | Delegating work that wasn't separable | The cap did its job. Ask the human before raising it. |
