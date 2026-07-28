<!-- apsolut-agents: tier=1 kind=doc -->
> **REFERENCE ONLY — do not follow this document in this workspace.**
> It describes a heavier architecture (per-agent inboxes, an orchestrator, wrapper
> scripts, a different `locks/` scheme) that this workspace **deliberately does not
> use**. The live design is `README.md` + `PROTOCOL.md` + `WORKTREES.md`. This file
> is kept as the someday-maybe blueprint if a project ever truly outgrows
> markdown + git + worktrees. Where it contradicts the live docs, the live docs win.

# Multi-Agent CLI Orchestration — Foundations

_A working reference for coordinating Codex, Claude Code, and Grok CLI agents on a single long-running SaaS build._

---

## 1. Purpose

This document defines the foundational architecture for coordinating three independent AI coding CLI tools — Codex, Claude Code, and Grok — while building a large SaaS product over an extended, multi-week timeline. It covers how the agents communicate bi-directionally, how decisions get made and recorded, and how work persists across sessions that individually cannot hold the full project history in context.

The design deliberately favors plain markdown files and git over live sockets or a formal network protocol. Every message, decision, and state checkpoint is a file any of the three tools — or a human — can read directly, with nothing custom required to inspect what happened. It is meant to be cheap, transparent, and easy to debug, and to scale later into a formal protocol (such as A2A) only if it proves necessary.

---

## 2. Architecture Overview

Three components make up the system:

1. **Agent wrappers** — a thin script around each CLI tool (Codex, Claude Code, Grok) that watches its own inbox folder on a loop, invokes the underlying CLI with the pending task or question as a prompt, captures the output, and writes a response file back.
2. **Shared comms directory** — a folder checked into the repo (or kept alongside it) containing each agent's inbox/outbox, a shared project state file, and a decisions log.
3. **Orchestrator** — a small coordinator process (script, cron job, or a fourth lightweight agent) that assigns work, sequences tasks so two agents don't edit the same files at once, and escalates unresolved decisions to a human.

Agents do not need to run as persistent servers. Each wrapper can simply poll its inbox folder every N seconds and shell out to the CLI tool when there's new work — this matches how Codex, Claude Code, and Grok's CLI already operate (prompt in, result out).

---

## 3. Agent Roles & Specialization

Assign each agent a lane based on its strengths, and let the orchestrator route tasks accordingly. Suggested starting split (adjust to taste):

| Agent       | Suggested focus                                                              | Owns                                 |
| ----------- | ---------------------------------------------------------------------------- | ------------------------------------ |
| Claude Code | Careful refactors, test-writing, cross-file consistency, architecture review | `decisions/`, `docs/`, core services |
| Codex       | Boilerplate generation, scaffolding, repetitive CRUD/endpoint code           | feature modules assigned per task    |
| Grok        | Fast iteration, brainstorming alternative approaches, quick prototypes       | experimental/spike branches          |

Ownership matters more than specialization labels: each in-progress feature or module should have exactly one agent actively writing to it at a time to avoid merge conflicts and duplicated edits.

---

## 4. Communication Protocol (Bi-Directional Messaging)

### 4.1 Folder structure

```
/agent-comms/
  inbox/
    codex/
    claude-code/
    grok/
    orchestrator/
  state/
    PROJECT_STATE.md
  decisions/
    DECISIONS.md
  locks/
    <file-or-module>.lock
```

Each agent only ever reads its own `inbox/<agent>/` folder and writes into other agents' inbox folders (or the orchestrator's). Nobody polls a folder that isn't addressed to them.

### 4.2 Message file schema

Every message is a single markdown file with YAML frontmatter:

```markdown
---
id: req-0042
type: question # task | question | answer | status | decision-request
from: claude-code
to: codex
reply_to: null # set on responses, points at the id being answered
status: open # open | answered | blocked | done
created_at: 2026-07-16T10:32:00Z
---

What response shape does the /users endpoint return? Need it to wire up
the profile page types.
```

A response uses the same schema with `type: answer`, `reply_to: req-0042`, and lands in the _requester's_ inbox, not the responder's own.

### 4.3 Message lifecycle

1. Orchestrator (or an agent) drops a `task` or `question` file into the target agent's inbox.
2. The target agent's wrapper loop notices the new file, feeds it to the CLI as a prompt (plus any referenced context), and writes a `status` or `answer` file back into the sender's inbox.
3. The sender's loop picks up the reply on its next pass and continues its own task.
4. Once a task is fully resolved, both files are marked `status: done` and archived (moved to `inbox/<agent>/done/`) rather than deleted, so the exchange stays auditable.

This gives you real bi-directional conversation — clarifying questions, negotiation, follow-ups — without any agent needing to be a live server.

---

## 5. Decision-Making & Conflict Resolution

`decisions/DECISIONS.md` is the single source of truth for anything that affects more than one agent's work (shared interfaces, schema changes, architectural direction). Rules:

- **Local decisions** (naming, internal structure of a module an agent owns) — the agent decides and appends a one-line entry to the log. No escalation needed.
- **Cross-cutting decisions** (shared API shape, schema change, dependency choice) — the agent writes a `decision-request` message instead of just acting, describing the options considered.
- **Tiebreaker** — designate one agent (commonly Claude Code, given its strength at review) as the default authority for cross-cutting calls, or route to a human checkpoint for anything with real cost (schema migrations, third-party service choices, security-relevant calls).
- **Loop guard** — cap decision back-and-forth at 3 rounds between agents; beyond that, auto-escalate to a human rather than letting them argue indefinitely.

Every recorded decision should capture: what was decided, why, what alternatives were considered and rejected, and the date. Prune superseded entries over time — git history preserves the "why not" even after the live log is cleaned up.

---

## 6. Long-Running State & Memory

No CLI agent can hold 20+ days of transcript in context, so long-running memory is handled in two layers:

- **Git itself** is the durable record. Commits, branch names, and PR/commit descriptions already capture what happened and why — all three tools understand git natively, so this costs nothing extra to maintain.
- **`state/PROJECT_STATE.md`** is a compact, hand- (or agent-) maintained rollup updated at the end of each work session: what's done, what's in progress, open questions, known issues. New sessions read this file plus recent git log instead of full history.

Treat `PROJECT_STATE.md` like a save-game checkpoint: small, current, and rewritten rather than appended forever. Anything no longer relevant gets pruned, not archived inline.

---

## 7. Concurrency & Locking

To avoid two agents editing the same files simultaneously:

- Before starting a task that touches specific files/modules, an agent (or the orchestrator) creates a lock file in `locks/` named after the file or module.
- Other agents check for a lock before claiming overlapping work; if present, they wait, pick a different task, or ask the lock holder a question instead of editing directly.
- Locks are released (file deleted) when the task's changes are committed.
- The orchestrator is responsible for sequencing tasks that are known in advance to overlap, so locking is a safety net, not the primary scheduling mechanism.

---

## 8. Cost Model (Recap)

The coordination layer itself (markdown message files) is cheap relative to actual coding work — typically a rounding error (roughly tens of dollars at most across a multi-week build under metered API pricing), since markdown carries less overhead than formats like JSON-RPC. The dominant cost driver is the volume of actual code-generation and reasoning tokens each agent produces, not how they hand off tasks. If the CLIs are used under flat-rate subscriptions rather than metered API keys, the coordination overhead adds effectively nothing to the bill.

---

## 9. Failure Modes & Guardrails

- **Infinite back-and-forth** between agents on a decision — capped by the 3-round escalation rule in Section 5.
- **Simultaneous edits** to the same file — prevented by the locking convention in Section 7.
- **Context bloat** — agents should only read messages addressed to them and referenced files, never the entire comms directory (mirrors the "don't pollute context" discipline used in single-agent setups).
- **Silent stalls** — messages sitting in `status: open` past a reasonable timeout (e.g., a few hours) should trigger an orchestrator alert rather than being discovered days later.
- **Human checkpoint** — keep a manual review gate before merging cross-cutting or high-risk changes (schema migrations, auth, billing), regardless of how confident the agents are.

---

## 10. Path to Standardization (Optional)

This file-based approach is intentionally the simplest viable version. If the project grows to the point where agents need to run concurrently rather than in sequence, or need to be distributed across machines, the same message schema maps cleanly onto the open A2A (Agent2Agent) protocol: each agent becomes a small local A2A server with an Agent Card describing its skills, and JSON-RPC messages replace the markdown files. Nothing about the decision log, state rollup, or locking convention needs to change — only the transport.

---

## 11. Getting Started Checklist

1. Create the `/agent-comms/` folder structure above in the project repo.
2. Write a thin wrapper script per CLI tool that polls its inbox and shells out to the tool.
3. Seed `PROJECT_STATE.md` and `DECISIONS.md` with the current state of the project.
4. Define each agent's ownership area (Section 3) so task routing has a default answer.
5. Start with sequential task handoff before enabling any concurrent/locking behavior — add complexity only once the simple version is proven out.
