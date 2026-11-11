# A real night: the report behind the demo

This is the night the README's recording replays. It ran on 2026-11-11 on a throwaway
repository (`todo-cli`: a Node command-line todo list with no dependencies), with real
models: **Claude Code** as the worker and planner, and **Codex** as the
verifier and the end-of-night reviewer.

The setup was a goal (`done_cmd: sh acceptance.sh`, red at the start) and two
hand-written cards, T-01 and T-02. Those two cards did not cover everything the
acceptance script asks for. When the board ran dry and the script was still red, the
planner wrote one more card (G1111r1-1: "rm <n>, --help usage line, and exit 2 for unknown commands (finishes acceptance.sh)"), and after it landed the script
passed. The night took about eight and a half minutes.

Three things to keep in mind when reading it:

- The task is small on purpose. It shows the pipeline, not what a long night costs.
- Every card passed on its first attempt, so this night shows no retry. For a
  rejection followed by a retry, see the scripted
  [sample report](../sample-night-report.md).
- The spend is what the CLIs reported or the runner estimated. Codex prints no cost,
  so its calls are charged at the configured fallback rate.

Below, the report is the runner's output as written (only the heading levels are
shifted). The trail is `runs/trail-2026-11-11.tsv` with the lane and evidence columns
left out.

---

## Night report — 2026-11-11 (lane: claude)

Ended: 2026-11-11 04:57 — reason: goal met — spend: $9.26 / $40

### Goal

- goal: a todo command-line tool that adds, lists, completes and removes items
- finish predicate: `sh acceptance.sh` — last result below
- plan rounds used: 1 / 4
- night branch: `agent/night/NIGHT-2026-11-11` (+6 commits) — land it with `sh .apsolut-agents/scripts/worktree.sh done NIGHT-2026-11-11 --merge`

```
done_cmd @ 9b25a80b45efd446a22dfb16fa82805f177e82bf: sh acceptance.sh
ACCEPTANCE: all journeys pass
```

### Cards

| card | status | verified | integrated | attempts | branch | diffstat vs main |
|---|---|---|---|---|---|---|
| G1111r1-1 | review | live-verified | yes | 1 | agent/claude/G1111r1-1 |  5 files changed, 341 insertions(+), 2 deletions(-) |
| T-01 | review | live-verified | yes | 1 | agent/claude/T-01 |  3 files changed, 109 insertions(+), 2 deletions(-) |
| T-02 | review | live-verified | yes | 1 | agent/claude/T-02 |  4 files changed, 200 insertions(+), 2 deletions(-) |

### Waiting on you

(nothing)

Decision trail: runs/trail-2026-11-11.tsv (`column -s$'\t' -t runs/trail-2026-11-11.tsv`) · handoffs: runs/handoffs/

Nothing merged into `main` — `worktree.sh review`, then `done <id> --merge` for what you accept.

### Attention
reviewed by codex
Call: 🟢 merge as is
- No flags

### Waiting on the human
- (none)

---

## The decision trail

| ts | phase | decision | why | result |
|---|---|---|---|---|
| 2026-11-11T03:49:20Z | start | started the lane | goal mode yes, verifier codex, advisor claude | budget $40 |
| 2026-11-11T03:49:21Z | night | opened the night integration branch | goal mode: verified cards accumulate here | open |
| 2026-11-11T03:49:22Z | harness | baseline green passed on a pristine worktree | a red harness must not read as red cards | green |
| 2026-11-11T03:49:23Z | claim | started T-01 attempt 1 | add and list items, stored as JSON | running |
| 2026-11-11T03:50:23Z | card | green T-01 attempt 1 | green_cmd and check: decide, not the agent's claim | green (self: test-verified, handoff: success) |
| 2026-11-11T03:51:34Z | verify | codex judged T-01: live-verified | needs test; - [x] A failing test exists that proves the goal: HEAD test fails against the base stub (5 failures), then passes against HEAD. It exercises the CLI through separate child processes, persistence, append order, open markers, numbering, and default storage. The historical “write it first” order is not independently observable from this single implementation commit; see Notes. | yes |
| 2026-11-11T03:51:36Z | integrate | merged T-01 into the night branch | green and verified (live-verified) | integrated |
| 2026-11-11T03:51:38Z | claim | started T-02 attempt 1 | mark an item done | running |
| 2026-11-11T03:52:29Z | card | green T-02 attempt 1 | green_cmd and check: decide, not the agent's claim | green (self: test-verified, handoff: success) |
| 2026-11-11T03:53:46Z | verify | codex judged T-02: live-verified | needs test; - [x] A failing test exists that proves the goal: test/done.test.js:24 exercises real child processes, marks the second item, and asserts exact numbered list output while preserving the first item. Verified red against base and green at HEAD. Historical "write it first" order cannot be independently established from the single implementation commit; see Notes. | yes |
| 2026-11-11T03:53:49Z | integrate | merged T-02 into the night branch | green and verified (live-verified) | integrated |
| 2026-11-11T03:53:51Z | goal | checked the finish predicate | the board ran dry | not met (rc=1) |
| 2026-11-11T03:54:40Z | plan | accepted card G1111r1-1 | rm <n>, --help usage line, and exit 2 for unknown commands (finishes acceptance.sh) | accepted |
| 2026-11-11T03:54:42Z | claim | started G1111r1-1 attempt 1 | rm <n>, --help usage line, and exit 2 for unknown commands (finishes acceptance.sh) | running |
| 2026-11-11T03:56:10Z | card | green G1111r1-1 attempt 1 | green_cmd and check: decide, not the agent's claim | green (self: live-verified, handoff: success) |
| 2026-11-11T03:57:43Z | verify | codex judged G1111r1-1: live-verified | needs test; risk tag api-contract; - [x] Failing regression test exists: all 16 tests fail on the archived base and pass at HEAD. Actual authoring order is not independently recoverable from the single implementation commit; the red/green requirement was reproduced. | yes |
| 2026-11-11T03:57:47Z | integrate | merged G1111r1-1 into the night branch | green and verified (live-verified) | integrated |
| 2026-11-11T03:57:49Z | goal | checked the finish predicate | the board ran dry | met |
| 2026-11-11T03:57:50Z | stop | ended the night | goal met | spend $9.26 |
