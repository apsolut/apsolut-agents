# CONCURRENCY — status board + locks (Tier 2)

_Only add this layer when 2–3 agents actually edit the **same day / same files**._
_A solo or sequential project does not need it — delete `CONCURRENCY.md`, `STATUS.md`,
`work/`, `locks/` and rely on `agent-log.md` + `PROJECT_STATE`._

Think **air-traffic control, not group chat**: a glanceable board + advisory locks so an
agent can answer "is anyone mid-write on this?" in seconds without reading the whole log.

---

## 1. The atoms (single source of truth)

Everything derives from two kinds of small, single-owner files. **Agents only ever write
files they own** — that's what stops the coordination files from becoming a collision
point themselves.

- **`work/<id>.md`** — one task, one owner, one status. YAML frontmatter is the truth.
- **`locks/<slug>.md`** — one per path being written right now.

## 2. `STATUS.md` is GENERATED — never hand-edited

The board is a *rendering* of the atoms + git, not a second copy you maintain by hand.
Hand-maintaining a shared board means every agent writes the same file (collision) and the
board drifts until it lies. So:

> `STATUS.md` header says `<!-- GENERATED — do not hand-edit -->`. It is produced from
> `work/*.md` frontmatter + `locks/*` + `git`. If you have a generator script
> (`<your build tool> run status`), run it; if not, treat `STATUS.md` as optional and read
> the `work/` and `locks/` files directly.

Optional tiny generator (pseudocode — implement in your stack):
```
read all work/*.md frontmatter  → task rows (id, status, owner, needs)
list locks/*.md frontmatter     → lock rows (path, owner, since)
read git branch/ahead-behind    → ship status
render STATUS.md (with the GENERATED header)
```

## 3. Work status state machine

`waiting → writing → (need-feedback ⇄ writing) → review → done`
plus side states `hold | blocked | abandoned`.

| status | Owner does | Others do |
|---|---|---|
| `waiting` | Claimed, prep, no locks yet | Don't start the same id |
| `writing` | Coding; holds locks | **Skip locked paths**; don't "help" unasked |
| `need-feedback` | Lists questions in the work file + pings log | Answer → owner returns to `writing` |
| `review` | Lists files + what to check | Review **committed** code only, if unlocked |
| `done` | Sets `commit:` in the work file | Leave alone |
| `hold` / `blocked` / `abandoned` | Stop / note dep / free the id | Respect / unblock / may re-claim |

## 4. Locks — "don't read what I'm writing"

If agent A is mid-refactor of a shared file, agent B reading the **working-tree** file sees
half a change and builds on the wrong world. So while a path is locked, others read the
**last commit** instead:

```
<read the committed version, e.g.>  git show HEAD:path/to/file
```

**Lifecycle:** before editing → `work` status `writing` + create `locks/<slug>.md` →
edit → on commit/abandon → delete the lock. **A lock lives for your session**; you clear
your locks at session end. Anyone may reclaim a lock whose owner's session has ended, after
a one-line note in the log.

**Honesty:** a lock file is **advisory**, not a real mutex — on one shared working tree two
agents can both "create" the same lock and both think they hold it. For 2–3 cooperative
agents that's fine (social + file). If you need true exclusion, use an atomic primitive
(e.g. `mkdir locks/<slug>/`, which fails if it already exists) or — better — see §5.

## 5. The real fix for true concurrency: git worktrees

The dirty-read problem exists *only* because agents share one working directory. If agents
genuinely run at the same time, give each its **own `git worktree` / branch**:

```
git worktree add ../<project>-agentB feature/agentB
```

Now agent B never sees agent A's uncommitted buffer, no locks are needed, and work merges
through commits/PRs. Keep the generated board for coordination; let worktrees provide the
isolation. Reach for this before building a heavier lock protocol.

## 6. Feedback loop (faster than prose)

Need another agent? Set the work file `status: need-feedback`, `needs: [<agent>]`, bullet
the questions **in the work file**, and drop one line in `agent-log.md`. The answerer
replies in the log or under the work file's Notes; the owner sets status back to `writing`
or `done`. Don't spin up parallel chat threads.

## 7. Session checklist (Tier 2)

```
[ ] STATUS.md (or work/ + locks/) — anything writing / need-feedback for me?
[ ] ls locks/ — avoid those paths (read HEAD if you need them)
[ ] work/<my-ids>.md — my status
[ ] PROJECT_STATE — HOLD?
[ ] agent-log.md tail — human words only when needed
```

## 8. Deliberately NOT built (until pain is real)

Realtime sockets / A2A servers; perfect distributed locks; auto-status from git hooks. On
a single machine + single repo with human-paced agents, good faith + advisory files +
worktrees are enough. If agents lie about status, the human enforces — it's social + file,
not crypto.
