<!-- apsolut-agents: tier=1 kind=doc -->
# PROTOCOL — long runs (Tier 1)

_For weeks-long or large projects where no agent can hold the whole history in context._
_Delete this file (and `decisions/`, `runs/`, `archive/`) if the project is small/short._

The governing constraint: **every file an agent reads at session start must stay small
and current.** Facts that scripts can derive from git are generated, never hand-written —
hand-maintained state always drifts until it lies. Growth lives in git history and
`archive/`, not in the files you read every session.

---

## 1. Session protocol (every agent, every run)

**Start — read only, in order:** `PROJECT.md` → `state/PROJECT_STATE.md` → tail of
`agent-log.md` → `git log -12 --oneline` → your `agents/agent-<you>.md`. *(Tier 2 also:
run `sh .apsolut-agents/scripts/status.sh` and read the board it prints.)*

First session ever? Create `agents/agent-<you>.md` from the template and add your
roster row in `PROJECT.md` **before your first task** — an unfilled charter means other
agents can't route work to you.

**During:**
- Append to `agent-log.md` for anything another agent must see.
- **Publish asymmetrically.** A result, blocker, or question another agent or the
  human needs goes in the log or it doesn't exist. The converse holds mid-session:
  nothing new → no entry, and never an entry that is only an acknowledgement. The
  session-end token heading (End, below) is always required — it's the contract,
  not chatter.
- Cross-cutting decision → `decisions/DECISIONS.md` + a one-line pointer in the log.
- If another agent was active today, note in the log what you're about to edit.
  *(Tier 2: the full `INTENT:` convention — see `WORKTREES.md §5`.)*

**End — one heading token, then freeform prose:**
```markdown
### <Agent> — <date> — PUSHED | HOLD | FAILED
<what you did, what's next for whom — normal prose, keep it short>
```
Then run `sh .apsolut-agents/scripts/session-end.sh <you> <TOKEN>` — it verifies the
token, compacts the log if oversized, and regenerates the state facts. No other
ceremony: the token is the contract, the script does the bookkeeping.

## 2. State = save-game, not diary

`state/PROJECT_STATE.md` has two zones:

- **Facts block** (between `<!-- facts:begin -->` and `<!-- facts:end -->`) — branch,
  ahead/behind, dirty count, recent commits, last session token, worktrees. Written by
  `scripts/status.sh`. **Never hand-edit it**; it cannot go stale because it is derived.
- **Narrative** (everything else) — HOLD + why, ownership summary, blockers, top-3 next
  actions, do-not-undo. Hand-edit **when it changes**, not on a schedule. HOLD stays
  human-written: no script can know the human lifted it.

Delete narrative that is no longer true — git keeps history; the session that ships
an item (merged, decided, unblocked) is the session that deletes its line.

## 3. Compaction (automated)

`session-end.sh` archives the oldest entries to `archive/agent-log-YYYY-MM.md` once
`agent-log.md` exceeds ~400 lines, cutting at an entry boundary and leaving a pointer
line. `status.sh` warns when the log is oversized. No social rule, no owner — the
scripts do it, because a rule with a human owner never fired in practice.

## 4. Decisions

| Kind | Who decides | Recorded where |
|---|---|---|
| Local (naming, a module's internals) | The acting agent | optional one-liner in log |
| Cross-cutting (shared API/shape, schema, dependency, test strategy) | Negotiate in log ≤3 rounds → review backstop or human | `decisions/DECISIONS.md` |
| One-way / high-cost (see `PROJECT.md` human-gates) | **Human only** | `DECISIONS.md` |

Rules that keep the register honest:
- **Stable ids:** next id = highest existing + 1. Gaps are allowed; ids are never reused.
- **Close the loop:** every entry carries `Status: proposed | final | implemented (<commit>)`.
  When you implement a decision, update its `Status:` line in the same session — a
  register that says "not implemented" about shipped work is worse than no register.
- Mark superseded entries `~~superseded by D-0NN~~` at the top; don't delete them.

## 5. Subagent runs and delegated agents

The rule is the same for both, and it is the only rule that matters: **the agent that
spawned it owns everything it produced.** Spawned agents never touch this workspace —
the spawner translates their output into the record.

**Fan-outs** (a Claude Code Task/Workflow, a review swarm, any one-shot multi-agent
burst) leave exactly two artifacts here:

1. One log entry: N agents, duration, headline numbers, verdict.
2. One file `runs/<date>-<slug>.md` with the surviving output (findings, ranked plan,
   explicit rejects), linked from that entry.

**Delegated peers** *(Tier 2)* — another agent's CLI, driven by you through
`scripts/delegate.sh` — are the same contract with more at stake, because a delegate
commits code. `delegate.sh` writes the mechanical log entries (dispatch, result, spend);
you still owe the judgement: what you accepted, what you rejected, why, and the verdict
on every branch you leave behind. Full protocol and caps: **`DELEGATION.md`**.

Decisions arising from either go to `DECISIONS.md` as usual. See `runs/README.md`.

## 6. Push / ship (standing agreement)

- **Committed ≠ done.** Green (per `PROJECT.md`) → push **unless** the log or human says
  `HOLD`. Session end always states `PUSHED | HOLD | FAILED`. Agents never override a HOLD.
- **Green is a claim about a commit — state it as one.** The scripts stamp
  `green_cmd @ <commit>` in run output; for by-hand claims, quote the check and
  `git rev-parse HEAD` from the same shell. Scope negative claims ("no callers",
  "not found") to the places you actually searched.

## 7. What "good" looks like after 4 weeks

- A new session rehydrates from `PROJECT.md` + `PROJECT_STATE` + log tail + git log — nothing more.
- The facts block is always current because nobody maintains it — a script does.
- `agent-log.md` is this month's thread; older slices sit in `archive/`.
- `DECISIONS.md` is ≤1 page of *still-true* calls, each with an honest `Status:`.
- Every fan-out run left its plan in `runs/`, not in a vanished task output.

## 8. Don't build heavy machinery early

Markdown + git + three small scripts handle human-paced agents for a long time. True
same-day concurrency → add Tier 2 (`WORKTREES.md`): worktree isolation, not locks.
Inbox pollers / orchestrators / A2A: see `reference/multi-agent-cli-foundations.md` —
the someday-maybe architecture. Most projects never need it.
