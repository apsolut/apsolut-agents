<!-- apsolut-agents: tier=2 kind=doc -->
# WORKTREES — true concurrency (Tier 2)

_Only add this layer when 2–3 agents actually edit the **same day / same files**._
_A solo or sequential project does not need it — delete `WORKTREES.md`, `STATUS.md`,
`work/`, `scripts/worktree.sh` and rely on `agent-log.md` + `PROJECT_STATE`._

Think **air-traffic control, not group chat**: each concurrent agent gets its own
isolated checkout (a `git worktree`), while all coordination stays in ONE place.
No locks — isolation comes from git, not from advisory marker files.

---

## 1. The model

- The clone where `.apsolut-agents/` was installed is the **primary worktree**.
  All coordination files (log, state, work files, decisions) live **only there**.
- Each concurrent agent works in a **secondary worktree**: an isolated checkout on
  its own branch. It never sees another agent's uncommitted buffer, so the whole
  dirty-read problem locks tried to paper over simply doesn't exist.
- Work merges back through normal git merges (or PRs), from the primary worktree.

### The one rule: follow `.primary`

A secondary worktree contains a checked-out *copy* of `.apsolut-agents/` — but that
copy is a read-only snapshot of the docs, **not** your workspace. The spawn script
drops an untracked pointer file in it:

```
<worktree>/.apsolut-agents/.primary   → absolute path of the primary workspace
```

**If `.primary` exists, the path inside it IS your `.apsolut-agents/` for every read
and write** — log appends, state, work files, decisions, everything. The scripts
resolve it automatically. Consequence: agent branches carry **zero** coordination-file
changes, the log stays physically single, and merges never conflict on coordination.

## 2. The ownership atom: `work/<id>.md`

One task, one owner, one status. YAML frontmatter is the truth (the status script
reads it). Copy `work/_TEMPLATE.md`. State machine:

`waiting → writing → (need-feedback ⇄ writing) → review → done`
plus side states `hold | blocked | abandoned`.

| status | Owner does | Others do |
|---|---|---|
| `waiting` | Claimed, prep | Don't start the same id |
| `writing` | Coding in own worktree | Don't "help" unasked |
| `need-feedback` | Lists questions in the work file + pings log | Answer → owner returns to `writing` |
| `review` | Lists files + what to check | Review the **branch**, comment in log |
| `done` | Sets `commit:` in the work file | Leave alone |
| `hold` / `blocked` / `abandoned` | Stop / note dep / free the id | Respect / unblock / may re-claim |

## 3. Spawn / work / merge / cleanup

**Spawn** (from the primary worktree):

```
sh .apsolut-agents/scripts/worktree.sh spawn <agent> <task-id>
```

which does: create `work/<task-id>.md` if absent (owner, `status: writing`, branch,
worktree filled) → `git worktree add ../<repo>-wt-<agent>-<id> -b agent/<agent>/<id>`
→ write the `.primary` pointer → `SPAWN:` line in the log → print the bootstrap
prompt to paste into the new agent's session.

- **Branch naming:** `agent/<agent>/<task-id>` (e.g. `agent/grok/T-014`).
- **Worktree location:** sibling dir `../<repo>-wt-<agent>-<id>` — outside the repo,
  so no gitignore games and no recursion.

**While working** (secondary agent): code + commit on your branch; talk in the
**primary** log (via `.primary`); update your own `work/<id>.md` status there too.

**Merge:** when the card is in `review`, a person runs `worktree.sh done <id> --merge`.
That command does not merge onto the primary branch first. It detaches the **agent**
worktree (the one that already has `node_modules` / `.venv`) at the primary commit,
merges the agent branch there, and runs `green_cmd` in that directory. Only a passing
check fast-forwards the primary branch to that commit. A red check leaves the primary
branch where it was, puts the agent worktree back on its branch, and keeps the merge
commit at `refs/apsolut/merges/<id>`. A brand-new worktree is the wrong place to run
this check: it has no installs, so green fails for setup reasons.

If the project has a remote + PR flow, open a PR instead. Merge conflicts on hot
files → normal 3-round log negotiation → human.

**Spawn also seals push.** After `git worktree add`, spawn sets
`extensions.worktreeConfig` (shared; it only allows a per-worktree config file)
and then `git config --worktree remote.<name>.pushurl no_push://refused` for every
remote. A push from inside that sibling fails at the transport. The primary
checkout is untouched — a plain `git config remote.origin.pushurl` without
`--worktree` would have blocked it, so the script never does that.

**Morning review** (read-only, deletes nothing):

```
sh .apsolut-agents/scripts/worktree.sh review          # every sibling
sh .apsolut-agents/scripts/worktree.sh review <task-id>
```

One block per sibling: ahead/behind, whether the branch is already in `HEAD`,
dirty-file count, size, and the exact `done` command to run if you accept it.
`session-end.sh` prints this when any secondary worktree is still open.

**Cleanup** is a human command. The runner and delegate never call it.

```
sh .apsolut-agents/scripts/worktree.sh done <task-id> [--merge]
sh .apsolut-agents/scripts/worktree.sh done <task-id> --jar
sh .apsolut-agents/scripts/worktree.sh done <task-id> --reject "<why>"
```

Plain `done` refuses a dirty tree and prints the paths. `--merge` runs the check
above, then removes the worktree and deletes the branch only if the primary branch
actually moved. Without `--merge` the branch stays.

`--jar` and `--reject` are how a dirty folder is removed without pretending the
dirt was committed. Both write `runs/evidence/<id>/` first (`status.txt`,
`diff.patch`, untracked files up to 1 MB each). `--reject "<why>"` also appends a
line to `runs/verdicts-YYYY-MM.md` and sets the card to `abandoned`. `--jar` is
the one `review` suggests when the branch is already contained in `HEAD` and only
uncommitted files are holding the folder. Neither merges, and neither deletes the
branch. Every `done` records a verdict line (`merged`, `removed`, `jar`, or
`rejected`) and the log line is `MERGED` only when a merge happened.

## 3b. What a worktree does not isolate

A new worktree is a checkout of tracked files. `node_modules`, virtualenvs, and
build directories do not come with it, so each agent installs before its own tests
mean anything. Two agents still share one machine: the same port, the same local
database. Git will not notice that collision.

Some files are touched by almost every task even when the plan never names them.
Put these on the hot-files list in `PROJECT.md` and declare `INTENT` before editing
them: the route table, `.env.example`, the migrations directory, and the dependency
manifest (`package.json`, `pyproject.toml`, `Cargo.toml`, or whatever this repo uses).

## 4. Coordination commits

Secondary agents' coordination writes land as working-tree changes in the **primary**
worktree. They are committed only from there, on the default branch — typically by
`session-end.sh --commit` of whoever ends last. Git's index lock serializes
concurrent commits; simultaneous appends to the log remain the same social-trust
deal as always (fine at 2–3 cooperative agents).

## 5. INTENT (lives here, Tier 2 only)

Before a large edit to a **hot file** (see `PROJECT.md`), drop one line in the log:
`INTENT: <agent> editing <path> for <why>`. Release it at session end. A dangling
INTENT is void once its session ends. With worktrees this is a courtesy heads-up to
reduce merge conflicts — not a lock; nothing enforces it but each other.

## 6. Feedback loop (faster than prose)

Need another agent? Set your work file `status: need-feedback`, `needs: [<agent>]`,
bullet the questions **in the work file**, and drop one line in `agent-log.md`. The
answerer replies in the log or under the work file's Notes; the owner sets status
back to `writing` or `done`. Don't spin up parallel chat threads.

## 7. `STATUS.md` is GENERATED

Run `sh .apsolut-agents/scripts/status.sh` — it renders `work/*.md` frontmatter +
`git worktree list` + git facts into `STATUS.md` and refreshes the facts block of
`state/PROJECT_STATE.md`. Never hand-edit either generated region: a hand-maintained
board drifts until it lies. A work file claiming `writing` with no live worktree gets
flagged stale by the script.

## 8. Session checklist (Tier 2)

```
[ ] sh scripts/status.sh — anything writing / need-feedback for me? stale flags?
[ ] work/<my-ids>.md — my status current?
[ ] PROJECT_STATE — HOLD?
[ ] agent-log.md tail — anything addressed to me?
```

## 9. Deliberately NOT built (until pain is real)

Realtime sockets / A2A servers; distributed locks (deleted — worktrees made them
moot); auto-status from git hooks; an orchestrator. On a single machine + single
repo with human-paced agents, good faith + worktrees + one shared log are enough.
If agents lie about status, the human enforces — it's social + git, not crypto.
