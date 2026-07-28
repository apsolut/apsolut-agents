<!-- apsolut-agents: tier=2 kind=doc -->
# NIGHTSHIFT — unattended overnight runs (Tier 2)

_Runs task cards through the night with no human in the loop. Design reviewed blind
by three models (Claude draft, Gemini + Grok reviews); the cuts they agreed on are
law here: rule-based control only, no overnight merges, kill is terminal, no
automatic cross-model reassignment._

## The deal

Evening: you write task cards. Night: one runner per agent works the board in
isolated worktrees. Morning: you review **unmerged branches** — each card is one
clean `--no-ff` merge candidate; rejecting one card = simply not merging its branch.

```
sh .apsolut-agents/scripts/runner.sh claude        # terminal 1 (whole night)
sh .apsolut-agents/scripts/runner.sh grok          # terminal 2 (v2 — after solo nights are boring)
sh .apsolut-agents/scripts/runner.sh claude --once # supervised single pass (v0 gate runs)
```

Config lives in `HEARTBEAT.md` (instance file — yours): timeouts, budget, breaker
thresholds, `green_cmd`, per-agent headless commands, ntfy.sh URL.

## What a card needs to be night-runnable

- Concrete **Goal** + **Done when** (vague cards produce confident garbage at 3am).
- `files:` declared; cards touching `PROJECT.md` human-gate paths are never claimed.
- Optional `after: [T-01]` dependency edges and `budget: 30` (minutes) override.

**`after:` is sequencing, NOT code visibility.** Branches stay unmerged overnight, so
a dependent card branches from the default branch and **cannot see its dependency's
code**. If card B needs card A's code, they are one card — or B waits for the morning
merge. (Found the hard way in the v0 acceptance test.)

## The loop (per card)

claim (`mkdir claims/<id>` mutex → card rewrite with owner/status) → spawn worktree →
run the agent's headless CLI with the card as prompt, hard timeout → salvage-commit
any uncommitted work → run `green_cmd`; **the green check decides, never the LLM's
own claim** → green: `status: review`, branch waits for morning · red: reset the
worktree, retry once, then `status: blocked` + phone ping.

## Safety rails (structural)

- Runner cannot push and never merges — branches only. HOLD stays human.
- Per-night **hard budget cap** (`night_budget_usd`), per-card time cap, lane circuit
  breaker (N consecutive failures → stop), provider 429/quota → backoff, not failure.
- Boot recovery: stale claims (dead pid + old) are released on every start.
- Kill cleanup: process-tree kill via `timeout -k`, then `index.lock` removal and
  `reset --hard` on failure — a wedged attempt never poisons the next one.

## Morning ritual

Read `runs/night-<date>.md` (what finished, what blocked, spend, per-branch
diffstat) → `worktree.sh done <id> --merge` for the branches you accept → delete the
rest. Reassigning a blocked card to the other model is a **human** decision, made
here, with the attempt output in front of you.

## Phase gates (don't skip)

v0: 3 supervised `--once` runs — zero double-claims, zero touches of the default
branch, every green branch builds, budget respected. v1: 5 clean unattended solo
nights. v2: add the second lane + `heartbeat.sh`. Full rationale: the night-shift
PRD in `runs/` (or `ideas/` while drafting).
