<!-- apsolut-agents: tier=1 kind=instance -->
# DECISIONS — cross-cutting only

Durable record of choices that affect more than one agent's work (shared shapes, schema,
dependencies, test strategy, architecture). **Append-only. Grep it for a topic — never
read it whole.** Stable ids: next = highest existing + 1; gaps allowed, never reuse.

**Close the loop:** when you implement a decision, update its `Status:` line in the same
session. Mark a superseded entry `~~superseded by D-0NN~~` at its top; don't delete it.

Template:
```markdown
### D-0NN — <title>  (<date>)
- **Decision:** …
- **Why:** …
- **Rejected:** …
- **Status:** proposed | final | implemented (<commit>)
- **Owners / applies to:** …
```

---

### D-001 — <example: STATUS.md is generated, never hand-edited>  (<date>)
- **Decision:** `STATUS.md` and the state facts block are rendered by `scripts/status.sh` from `work/*.md` + git; agents write only their own atom files.
- **Why:** a hand-maintained shared board is itself a collision point and drifts until it lies.
- **Rejected:** each agent hand-updating the board (dual source of truth).
- **Status:** final
- **Owners / applies to:** all agents. _Delete this example once you have real decisions._
