---
# apsolut-agents: tier=2 kind=doc
id: <ID e.g. FEAT-12 / T-01>   # this file's NAME must be exactly <id>.md — everything is keyed on it
status: waiting          # waiting | writing | need-feedback | review | done | hold | blocked | abandoned
owner: <agent>
title: <one line>
needs: []                # [<agent>] or [human] when status is need-feedback
after: []                # [T-01, T-02] — plain mode: ready once these are done (MERGED),
                         # so not the same night. Goal mode: ready once they are on the
                         # night branch, and this card starts from there (NIGHTSHIFT.md).
risk: []                 # [api-contract, schema, pii, money, ui] — see PLAYBOOK.md §4. A tag listed
                         # in HEARTBEAT risk_tags sends the card to the stronger verifier.
spike: false             # true = research/docs card; waives the night test-first gate
verify: test             # minimum independent verdict: live | test | typecheck (HEARTBEAT verify_level if absent)
check:                   # one command the RUNNER runs: must fail before the change, pass after (no # in it)
verified: null           # set by runner.sh: the verifier's verdict, self:<level>, blocked,
                         # unverified or risk-unverified
integrated: null         # set by runner.sh in goal mode: the night branch this card was merged into
files:                   # paths you expect to touch (declare INTENT on hot files)
  - <path/to/file>
branch: null             # agent/<agent>/<id> — set by worktree.sh spawn
worktree: null           # ../<repo>-wt-<agent>-<id> — set by worktree.sh spawn
budget: null             # minutes — Night Shift per-card timeout override (default in HEARTBEAT.md)
commit: null             # set to the hash when done
updated: <date>
---

# <ID> — <title>

## Goal
<what "done" means in one or two sentences>

## Done when
- [ ] A failing test exists that proves the goal (write it first — enforced for night cards)
- [ ] <criterion — checkable by a machine or a stranger, not a vibe>
- [ ] INTENT declared on hot files (see PROJECT.md) while writing
- [ ] Green per PROJECT.md (tests / typecheck / lint)

## Notes
<questions when need-feedback; decisions; links>
