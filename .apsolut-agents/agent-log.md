<!-- apsolut-agents: tier=0 kind=instance -->
# agent-log.md — the live thread

The one place agents talk: questions, answers, handoffs, "editing X now", "found Y".
**Append-only, newest at the bottom. Never rewrite someone else's entry — reply below it.**
Map + rules live in `README.md` / `PROTOCOL.md`; this file is just the conversation.

Entry shape (keep it short — link to commits/files for detail):
```markdown
### <Agent> — <date> <optional topic>
- <what you did / are asking / decided>
- INTENT: <agent> editing <path> for <why>        # Tier 2 — before a large hot-file edit
- SPAWN: <agent> → <branch> at <path>             # written by worktree.sh spawn
- MERGED: <branch> → <default> (<hash>)           # written by worktree.sh done

### <Agent> — <date> — PUSHED | HOLD | FAILED     # session end: token in the heading
<freeform prose: what you did, what's next for whom>
```

Oversized log? `scripts/session-end.sh` auto-archives old entries to
`archive/agent-log-YYYY-MM.md` past ~400 lines.

---

## Log

### Claude — 2026-07-28 overhaul
- Rebuilt the repo from the 15-file markdown-only draft: payload moved to `template/`,
  locks + CONCURRENCY.md deleted (worktrees are Tier 2 now — D-001), scripts added
  (`status.sh`, `session-end.sh`, `worktree.sh`, `install.sh`), protocol pruned against
  evidence from the joyci run (end block → one token heading; compaction automated at
  400 lines; INTENT moved to Tier 2; `runs/` added for subagent fan-outs).
- Full acceptance test passed in scratchpad: fresh install → spawn grok worktree →
  agent-B log write via `.primary` → merge-back via `done --merge` → compaction at
  529→179 lines → `--refresh` kept instance files. Zero coordination files on the
  agent branch, as designed.
- This workspace is the live dogfood instance of `template/` — see D-002.
- Dogfood catch #1: the roster table lived in `README.md` (kind=doc) — a `--refresh`
  would have wiped it. Moved the roster to `PROJECT.md` (kind=instance) in the template
  and all references; refreshed this instance to prove the flow.

<!-- next entry below -->

### claude — 2026-07-28 — HOLD
Overhaul complete: worktrees Tier 2, scripts, dogfood. HOLD until human decides on a remote.
