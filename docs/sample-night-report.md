# Sample night report

This is **real output** of `runner.sh` (only the heading levels are shifted), taken from the test suite
(`tests/goal-loop.sh`, scenario 2). The "agents" are the suite's scripted stand-ins
(`fake` as the worker, `fakev` as verifier, advisor and reviewer), so the task is a
toy and the spend is not real money. What it shows is the shape of what you read in
the morning, including a rejection and a retry. For a night run by real models, see
[`demo/night-report.md`](demo/night-report.md).

What happened in this night: the worker's first attempt passed `green_cmd`, the
independent verifier rejected it, an advisor read the failure, the second attempt was
verified and merged onto the night branch, and the goal's `done_cmd` turned green.

## `runs/night-2026-11-11.md`

### Night report — 2026-11-11 (lane: fake)

Ended: 2026-11-11 02:37 — reason: goal met — spend: $0.13 / $50

#### Goal

- goal: a.txt exists
- finish predicate: `test -f a.txt` — last result below
- plan rounds used: 0 / 4
- night branch: `agent/night/NIGHT-2026-11-11` (+2 commits) — land it with `sh .apsolut-agents/scripts/worktree.sh done NIGHT-2026-11-11 --merge`

```
done_cmd @ 0d5ae477064249a09e34df9bdf10ed0c68065367: test -f a.txt
```

#### Cards

| card | status | verified | integrated | attempts | branch | diffstat vs main |
|---|---|---|---|---|---|---|
| T-01 | review | test-verified | yes | 2 | agent/fake/T-01 |  2 files changed, 2 insertions(+) |

#### Waiting on you

(nothing)

Decision trail: runs/trail-2026-11-11.tsv (`column -s$'\t' -t runs/trail-2026-11-11.tsv`) · handoffs: runs/handoffs/

Nothing merged into `main` — `worktree.sh review`, then `done <id> --merge` for what you accept.

#### Attention
reviewed by fake
Call: 🟢 merge as is
- No flags

#### Waiting on the human
- (none)

## `runs/trail-2026-11-11.tsv`

One row per decision. The runner writes it; a wrong row is superseded, never edited.

| phase | decision | why | evidence | result |
|---|---|---|---|---|
| start | started the lane | goal mode yes, verifier fakev, advisor fakev | `pid 195299` | budget $50 |
| night | opened the night integration branch | goal mode: verified cards accumulate here | `NIGHT-2026-11-11` | open |
| harness | baseline green passed on a pristine worktree | a red harness must not read as red cards | `runs/.baseline-2026-11-11.out` | green |
| claim | started T-01 attempt 1 | card T-01 | `agent/fake/T-01 @ cfdfe4b` | running |
| card | green T-01 attempt 1 | green_cmd decides, not the agent's claim | `runs/T-01-attempt1.out @ a9983b4` | green (self: test-verified, handoff: success) |
| verify | fakev judged T-01: verifier-failed | needs test; - (high) a.txt does not hold the right content: cat a.txt -> wrong | `runs/handoffs/T-01-verify1.md` | no |
| card | red T-01 attempt 1, will retry with the failure in the prompt | task: independent verifier said verifier-failed (needs test) | `runs/T-01-attempt1.fail` | red |
| advise | advisor fakev read the failure of T-01 | retry gets a second model's diagnosis | `runs/handoffs/T-01-advice2.md` | advised |
| claim | started T-01 attempt 2 | card T-01 | `agent/fake/T-01 @ cfdfe4b` | running |
| card | green T-01 attempt 2 | green_cmd decides, not the agent's claim | `runs/T-01-attempt2.out @ 4467e56` | green (self: test-verified, handoff: success) |
| verify | fakev judged T-01: test-verified | needs test; - [x] a.txt exists with the right content: cat a.txt -> right | `runs/handoffs/T-01-verify2.md` | yes |
| integrate | merged T-01 into the night branch | green and verified (test-verified) | `agent/night/NIGHT-2026-11-11 @ 0d5ae47` | integrated |
| goal | checked the finish predicate | the board ran dry | `runs/.done-2026-11-11.out @ 0d5ae47` | met |
| stop | ended the night | goal met | `runs/night-2026-11-11.md` | spend $0.13 |
