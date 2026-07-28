---
id: <ID e.g. FEAT-12 / P2-01>
status: waiting          # waiting | writing | need-feedback | review | done | hold | blocked | abandoned
owner: <agent>
title: <one line>
needs: []                # [<agent>] or [human] when status is need-feedback
files:                   # paths you expect to touch (lock these while writing)
  - <path/to/file>
commit: null             # set to the hash when done
updated: <date>
---

# <ID> — <title>

## Goal
<what "done" means in one or two sentences>

## Done when
- [ ] <criterion>
- [ ] Lock/INTENT on hot files while writing
- [ ] Green per PROJECT.md (tests / typecheck / lint)

## Notes
<questions when need-feedback; decisions; links>
