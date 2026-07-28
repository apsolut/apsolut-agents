<!-- GENERATED — do not hand-edit. Source of truth: work/*.md + locks/*.md + git.
     Regenerate with your status script, or read work/ and locks/ directly.
     (Tier 2 only — delete if you're not running concurrent agents.) -->

# STATUS board

_Last generated: <date> — by <script/agent>_

## Work units

| id | status | owner | title | needs | updated |
|----|--------|-------|-------|-------|---------|
| _(none yet)_ | — | — | — | — | — |

Status set: `waiting` · `writing` · `need-feedback` · `review` · `done` · `hold` · `blocked` · `abandoned`

## Locks (advisory exclusive-write)

| path | owner | work | since |
|------|-------|------|-------|
| _(none)_ | — | — | — |

While a path is locked, other agents read the **committed** version (`git show HEAD:path`),
not the working tree. Locks are session-scoped and advisory — see `CONCURRENCY.md`.

## Ship

| | |
|--|--|
| Local vs remote | `<git ahead/behind>` |
| HOLD | `<yes/no — who/why>` |
