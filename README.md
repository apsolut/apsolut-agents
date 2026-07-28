# `.apsolut-agents/` — multi-agent workspace

**All agent-to-agent talk happens in this folder.** Not in scattered TODO chat blocks,
not in commit messages as the primary channel, not in random doc paragraphs meant for
another agent. One place a human — or any agent — can open and see the whole picture.

New here? Read **`INSTALL.md`** once. Working the project? Read on.

---

## Start of every session (read in order)

1. **`PROJECT.md`** — this project's stack, commands, hot files, and human-gates.
2. **`state/PROJECT_STATE.md`** — the save-game: what's done, in progress, blocked, who owns what.
3. **tail of `agent-log.md`** — the recent conversation (not the whole archive).
4. `git log -12 --oneline` — what actually landed.
5. *(Tier 2)* `STATUS.md` + `ls locks/` — who's mid-write, which paths are locked.
6. Your own `agents/agent-<you>.md` — your working style, if you need the refresher.

If getting oriented takes more than these, a file has grown past its size discipline —
fix that (compact it) before anything else.

## Where does what I write go?

| I want to… | Put it in |
|---|---|
| Say something to another agent (question, answer, handoff, "editing X now") | `agent-log.md` (append, newest at bottom) |
| Record the project's current state changed | rewrite the relevant part of `state/PROJECT_STATE.md` |
| Record a cross-cutting decision others must respect | `decisions/DECISIONS.md` + one-line ping in the log |
| Track a task | `work/<id>.md` *(Tier 2)*, else a line in `PROJECT_STATE` |
| Describe how I (an agent) work | `agents/agent-<me>.md` |

**Don't cross the streams.** A message to an agent is never a backlog item, and the
backlog is never a chat thread.

## The rules that matter (memorize)

1. **Append** to `agent-log.md`; never rewrite someone else's entry — reply below it.
2. **Committed ≠ done.** Not done until pushed to the remote, or the log says `HOLD`.
3. **HOLD** = do not push/ship. Only the human lifts a HOLD.
4. **INTENT before hot-file edits.** Before a large edit to a file listed in
   `PROJECT.md → Hot files`, drop a one-liner in the log: `INTENT: <agent> editing <path> for <why>`.
   Release it at your session end.
5. **Human-gate** the one-way doors in `PROJECT.md` (migrations, auth, billing, spend, prod push).
6. **End every session** with a log line: `PUSHED | HOLD | FAILED` + what's next for whom.
7. Cap agent↔agent debate at ~3 rounds, then escalate to the human.

## Roster

Fill in as agents join. One agent writes a given module at a time — check
`PROJECT_STATE` ownership (or `work/*` in Tier 2) before claiming overlapping work.

| Agent | Default lane |
|---|---|
| *(e.g. Claude)* | *(e.g. root-cause fixes, migration/schema safety, review, tests)* |
| *(e.g. Grok)* | *(e.g. fast iteration, spikes, shipping mechanics)* |
| *(e.g. Codex)* | *(e.g. scaffolding, repetitive modules)* |
| Human | push/deploy, tiebreak, legal/billing, one-way doors |
