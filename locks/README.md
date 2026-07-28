# locks/ — advisory exclusive-write markers (Tier 2)

One file per path being written **right now**. Filename = the path with `/` → `--`
(e.g. `src/lib/db.ts` → `src--lib--db.ts.md`). Copy `_TEMPLATE.md`.

## Lifecycle
1. Before editing: set the task `work/<id>.md` status to `writing`, then create the lock file.
2. Edit.
3. On commit (or abandon): **delete** the lock file.

## Rules
- One lock per path. Only files you will actually change — never lock half the repo.
- If a path is locked by someone else → **don't open it for edit**, and don't base work on
  a dirty working-tree read of it. Use the committed version (`git show HEAD:<path>`).
- **Session-scoped:** clear your own locks at session end. Anyone may reclaim a lock whose
  owner's session has ended, after a one-line note in `agent-log.md`.
- **Advisory, not a mutex** — see `CONCURRENCY.md §4–§5`. For true isolation, prefer a
  per-agent `git worktree` over locks.
