<!-- apsolut-agents: tier=1 kind=instance -->
# 2026-08-11 — Field incident #2: green passed on primary, failed in every lane

Reported by the human from a real night run (an n8n project, budget $150):

- `green_cmd: sh .apsolut-agents/green.sh` — relative path, and the helper was
  untracked. runner.sh runs green with **cwd = the card's worktree**, and a
  worktree contains **only tracked files** — so every lane died on "No such file
  or directory", which read as the *cards* failing. Two cards blocked after good
  work, breaker tripped at 04:44, three cards never ran. Spend $7.42.
- Second bug found while fixing: card inputs lived under a wholesale-gitignored
  path (`.apsolut/09-workflows/*`) — the first lane spawned without the very
  files its card told it to read.
- **Nothing was lost**: `refs/apsolut/attempts/` pins (shipped earlier the same
  day) held both attempts; the human restored both branches from them. First
  field validation of the evidence-refs feature.

## Root class

Harness failure misattributed as work failure. Green was only ever proven where
cards do NOT run (the primary), and the tracked-files-only property of worktrees
was documented nowhere near where it bites.

## Shipped in v0.7.1

1. **runner.sh baseline green**: before the first dispatch of the night, green
   runs once on the pristine worktree; failure = "harness: green_cmd red on
   pristine worktree", exit 4, no cards charged, no breaker trip.
2. **doctor.sh**: green is now also proven inside a throwaway `git worktree
   add --detach` (FAIL when primary-only), and every card's `files:` entries are
   checked for existence-but-untracked (WARN: "the agent will not see it").
3. **doctor.sh**: cards missing required frontmatter keys (status/owner/branch/
   worktree/updated) are flagged — and **worktree.sh `fm_set` now inserts
   missing keys instead of silently dropping the value** (replace-only fm_set
   made spawn record nothing on a hand-written card; found by the test board
   while reproducing this incident).
4. **Docs**: the cwd-is-worktree / tracked-files-only contract now sits directly
   above `green_cmd:` in HEARTBEAT.md and in NIGHTSHIFT's card requirements.

Verified end-to-end on a scratch repo with a fake CLI lane: broken green →
harness exit 4 with the card back to `waiting`; fixed green → baseline ok,
dispatch, green, card → `review`, branch recorded. Doctor catches both planted
incident bugs (untracked green helper, untracked card input).
