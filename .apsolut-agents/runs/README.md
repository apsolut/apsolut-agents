<!-- apsolut-agents: tier=1 kind=doc -->
# runs/ — subagent fan-out results (Tier 1)

When an agent fans out to N subagents — a Claude Code Task/Workflow, a review swarm,
any one-shot multi-agent burst — the burst is invisible to this workspace unless its
output lands somewhere durable. Task outputs vanish with the session; a 40-finding
audit that lives only in "the task output" is a 40-finding audit you no longer have.

**The orchestrating agent owns the whole run.** Subagents never write to this
workspace — they report to their orchestrator, and the orchestrator files the result.

## Exactly two artifacts per run

1. **One entry in `agent-log.md`** — the headline: N agents, duration, key numbers,
   verdict, and a link to the run file.
2. **One file here: `runs/<date>-<slug>.md`** — the surviving output:
   - findings / results that matter (ranked if ranked)
   - what was explicitly rejected and why (so nobody re-litigates it)
   - anything needed to resume (script path, run id) if the tool supports it

Decisions arising from a run go to `decisions/DECISIONS.md` as usual, with a pointer
to the run file.

## Not here

- Raw subagent transcripts or full tool output — link, don't paste.
- Ongoing task tracking — that's `work/` (Tier 2) or `PROJECT_STATE`.
- One-subagent errands (a single search or review) — a log line is enough.
