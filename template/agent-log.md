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
- MERGED: <branch> → <default> (<hash>)           # done --merge only
- REMOVED / JAR / REJECTED: <branch> …            # done without a merge

### <Agent> — <date> — PUSHED | HOLD | FAILED     # session end: token in the heading
<freeform prose: what you did, what's next for whom>
```

Oversized log? `scripts/session-end.sh` auto-archives old entries to
`archive/agent-log-YYYY-MM.md` past ~400 lines.

---

## Log

### <Agent> — <date> (example — delete me)
- Set up the workspace; filled in `PROJECT.md`; filled the narrative in `PROJECT_STATE`.
- Taking: <task>. Next for <other>: <thing>.

### <Agent> — <date> — HOLD (example — delete me)
Nothing to push yet; workspace scaffolded.

<!-- next entry below -->
