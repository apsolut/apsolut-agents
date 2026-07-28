---
# apsolut-agents: tier=2 kind=doc
id: <ID e.g. FEAT-12 / T-01>
status: waiting          # waiting | writing | need-feedback | review | done | hold | blocked | abandoned
owner: <agent>
title: <one line>
needs: []                # [<agent>] or [human] when status is need-feedback
files:                   # paths you expect to touch (declare INTENT on hot files)
  - <path/to/file>
branch: null             # agent/<agent>/<id> — set by worktree.sh spawn
worktree: null           # ../<repo>-wt-<agent>-<id> — set by worktree.sh spawn
commit: null             # set to the hash when done
updated: <date>
---

# <ID> — <title>

## Goal
<what "done" means in one or two sentences>

## Done when
- [ ] <criterion>
- [ ] INTENT declared on hot files (see PROJECT.md) while writing
- [ ] Green per PROJECT.md (tests / typecheck / lint)

## Notes
<questions when need-feedback; decisions; links>
