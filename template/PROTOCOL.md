# PROTOCOL — long runs (Tier 1)

_For weeks-long or large projects where no agent can hold the whole history in context._
_Delete this file (and `decisions/`, `archive/`) if the project is small/short._

The governing constraint: **every file an agent reads at session start must stay small
and current.** We checkpoint and rotate rather than append forever. Growth lives in git
history and `archive/`, not in the files you read every session.

---

## 1. Session protocol (every agent, every run)

**Start — read only, in order:** `PROJECT.md` → `state/PROJECT_STATE.md` → tail of
`agent-log.md` → `git log -12 --oneline` → your `agents/agent-<you>.md`. *(Tier 2 also:
`STATUS.md` + `ls locks/`.)*

**During:**
- Append to `agent-log.md` for anything another agent must see.
- Cross-cutting decision → `decisions/DECISIONS.md` + a one-line pointer in the log.
- Before a large edit to a **hot file** (see `PROJECT.md`) → `INTENT: <agent> editing <path> for <why>` in the log.

**End — mandatory log block:**
```markdown
### <Agent> — <date> end
- Did: …
- PUSHED | HOLD | FAILED: …
- Next for <other>: …
- State file updated: yes/no
```
Then **rewrite** `state/PROJECT_STATE.md` (see §2).

## 2. State = save-game, not diary

`state/PROJECT_STATE.md` is **rewritten**, never appended forever. It holds only what's
true *now*: HEAD/remote delta, HOLD status, ownership/claims, blockers, top-3 next
actions, links to active plans. Delete anything no longer true — git keeps history.

**Only the session-ending agent rewrites it** (as the last action before the end block),
so two agents don't clobber the save-game. Treat it as a hot file.

## 3. Compaction (how you survive weeks)

Without this, `agent-log.md` becomes an unreadable novel and wastes everyone's context.

| Trigger | Action | Who |
|---|---|---|
| `agent-log.md` > ~150 lines, or month rolls over | Move settled/older entries to `archive/agent-log-YYYY-MM.md`; leave open threads + a 3-line recap | **The agent whose entry tips it over** does it in that same commit |
| A decision closes | One line in `DECISIONS.md`; drop the re-litigation from the live log | closer |
| `PROJECT_STATE` | Always a full rewrite | session-ender |

Compaction needs an **owner** or it never happens — hence "whoever tips it over."

## 4. Decisions

| Kind | Who decides | Recorded where |
|---|---|---|
| Local (naming, a module's internals) | The acting agent | optional one-liner in log |
| Cross-cutting (shared API/shape, schema, dependency, test strategy) | Negotiate in log ≤3 rounds → review backstop or human | `decisions/DECISIONS.md` |
| One-way / high-cost (see `PROJECT.md` human-gates) | **Human only** | `DECISIONS.md` |

Give each decision a **stable id** (`D-001`, `D-002`, …) so you can write "superseded by
D-0NN" when pruning. Template in `decisions/DECISIONS.md`.

## 5. Concurrency & INTENT

- One **owner** per open task at a time (Tier 2: `work/<id>.md`; else the `PROJECT_STATE`
  ownership list).
- **INTENT before large hot-file edits.** An INTENT is **released at your session end** —
  a dangling INTENT with no release is void after one session (so a crashed session never
  deadlocks a file forever).
- Shared docs (`PROTOCOL.md`, `README.md`, `PROJECT_STATE.md`) are hot files too — the
  same INTENT courtesy applies.
- If two agents want the same file → the second picks other work or asks in the log.
- Cap argument at 3 rounds → human.

## 6. Push / ship (standing agreement)

- **Committed ≠ done.** Green (per `PROJECT.md`) → push **unless** the log or human says
  `HOLD`. Session end always states `PUSHED | HOLD | FAILED`. Agents never override a HOLD.

## 7. What "good" looks like after 4 weeks

- A new session rehydrates from `PROJECT.md` + `PROJECT_STATE` + log tail + git log — nothing more.
- The backlog is scannable checkboxes, not a novel; `agent-log.md` is this week's thread, older months archived.
- `DECISIONS.md` is ≤1 page of *still-true* calls.
- No dual conversation venues; `HOLD`/`PUSHED` is never ambiguous.

## 8. Don't build heavy machinery early

Markdown + git handles human-paced agents for a long time. Add inbox pollers, a lock
protocol, or an orchestrator **only** when concurrent edits actually hurt — see
`CONCURRENCY.md` for the Tier-2 layer, and `multi-agent-cli-foundations.md` for the
someday-maybe architecture. Most projects never need them.
