<!-- apsolut-agents: tier=2 kind=instance -->
# GOAL — the final product contract (Night Shift goal loop)

_Optional. While `done_cmd:` below is empty, the runner works the board and stops
when the board is empty, exactly as before. Set `done_cmd:` and the night becomes a
**goal loop**. Accepted cards integrate onto one night branch. When the board runs
dry, the runner checks the predicate. If the predicate fails, a planner writes the
next cards, and this repeats until the predicate passes, the planner reports that
it is stuck, the run plateaus, or a cap trips. The default branch never moves. See
`NIGHTSHIFT.md → Goal loop`._

Plain `key: value` lines. Scripts read them with grep, so keep comments on their
own lines.

## Contract

goal:
# done_cmd runs with cwd = the night integration worktree (tracked files only, like
# green_cmd). Exit 0 means the final product is reached. It must be a PREDICATE that
# can fail, not a duration ("work 4 hours" gives the loop nothing to check), and it
# must not edit files. Point it at a committed script: e2e journeys, an acceptance
# test suite, `test -z "$(grep -r TODO src)"`, a pixel diff, a coverage floor.
done_cmd:
# protect: pathspecs no card may change tonight: the files done_cmd and the
# acceptance tests live in. A card touching one is red, and a night whose diff
# touches one cannot meet the goal. The predicate never relaxes.
protect:
# minimum independent-verifier verdict for a card to integrate:
# live | test | typecheck  (a card's own `verify:` overrides it)
verify_level: test
max_plan_rounds: 4
max_cards_per_round: 5
# agent that plans (needs cmd_<agent> in HEARTBEAT.md). Empty = the lane's own agent.
planner_agent:

## Final product means

<!-- The human-readable version of done_cmd. Every line should be checkable.
     The planner reads this whole file, and so does every worker, as context. -->
- <a user can … and sees …>
- <`pnpm e2e journey` passes>

## Out of scope tonight

- <what the night must not attempt, even if it looks related>

## Must not change

- <load-bearing invariants (also PROJECT.md → Do-not-undo)>

## Decisions the human owns

<!-- The planner writes STUCK.md instead of guessing any of these. -->
- Anything listed under PROJECT.md → Human gates
