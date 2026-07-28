# DECISIONS — cross-cutting only

Durable record of choices that affect more than one agent's work (shared shapes, schema,
dependencies, test strategy, architecture). **Append-only. Grep it for a topic — never
read it whole.** Give each a stable id so you can mark supersession.

Mark a superseded entry `~~superseded by D-0NN~~` at its top; don't delete it.

Template:
```markdown
### D-0NN — <title>  (<date>)
- **Decision:** …
- **Why:** …
- **Rejected:** …
- **Owners / applies to:** …
```

---

### D-001 — <example: STATUS.md is generated, never hand-edited>  (<date>)
- **Decision:** `STATUS.md` is rendered from `work/*.md` + `locks/*` + git; agents write only their own atom files.
- **Why:** a hand-maintained shared board is itself a collision point and drifts until it lies.
- **Rejected:** each agent hand-updating the board (dual source of truth).
- **Owners / applies to:** all agents (Tier 2). _Delete this example once you have real decisions._
