# PROJECT — stack facts (fill this in)

**The only file with project-specific details.** Everything else in `.apsolut-agents/`
is generic and points here. Fill in the blanks for your repo; keep it current when the
stack changes. Delete rows that don't apply; add rows you need.

_Tier: 0 (core). Last updated: <date> by <agent/human>._

---

## Identity

| | |
|---|---|
| **Project** | `<name — one line what it is>` |
| **Repo / remote** | `<git remote + default branch, e.g. origin/main>` |
| **Stack** | `<languages, framework(s), runtime, DB, hosting>` |
| **Deploy target** | `<where it runs, how it's deployed>` |

## Commands (how agents verify their work)

Replace with your project's real commands. Agents run these before claiming "green."

| Purpose | Command |
|---|---|
| Install deps | `<e.g. npm ci / pnpm i / pip install -r requirements.txt>` |
| Build | `<e.g. npm run build>` |
| Unit / smoke tests | `<e.g. npm test>` |
| Typecheck | `<e.g. npm run typecheck / tsc --noEmit / mypy>` |
| Lint | `<e.g. npm run lint>` |
| Format | `<e.g. npm run format — name the ACTUAL formatter; don't guess>` |
| Run locally | `<e.g. npm run dev>` |
| **"Green" = ** | `<which of the above must pass before a change is done, e.g. tests + typecheck>` |

> Agents: **read this table before running any tool.** Don't run a formatter/linter the
> project doesn't use — it will churn the whole codebase in the wrong style.

## Hot files (declare INTENT before large edits)

Shared, high-collision files. Before a big edit to any of these, drop an `INTENT:` line
in `agent-log.md` (Tier 2: also take a lock).

- `<e.g. src/lib/db.ts — everything imports it>`
- `<e.g. config / schema / migrations>`
- `<e.g. shared types / the main router>`

## Human gates (never auto-decide these)

One-way or high-cost doors. An agent proposes; the **human** decides.

- `<e.g. schema migrations — and back up the DB first>`
- `<e.g. auth / security changes>`
- `<e.g. billing / anything that spends money>`
- `<e.g. pushing to prod / deploy>`
- `<e.g. destructive data ops, force-push, dependency mass-upgrade>`

## Deploy (the ship sequence)

`<Fill the real steps, e.g.: push → CI → migrate → build → restart. Or "N/A / manual".>`

## Do-not-undo (load-bearing invariants)

Decisions that look wrong out of context but are deliberate. Don't "clean these up."

- `<e.g. X is intentionally dynamic/uncached because …>`
- `<link to decisions/DECISIONS.md for the why>`
