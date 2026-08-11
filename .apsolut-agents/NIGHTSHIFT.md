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

**Attended sibling:** `DELEGATION.md` / `scripts/delegate.sh` runs the same agents on the
same cards *while you're present* — you dispatch, watch, and send correction rounds. Same
claim mutex and same daily spend ledger, so the two can't collide over a card. Rule of
thumb: rule-based and destructive-on-red at 3am (`runner.sh`), judgement-based and
non-destructive when a foreman is reading the output (`delegate.sh`).

## What a card needs to be night-runnable

- **Filename = `<id>.md`, exactly.** Claims, deps and reports all construct
  `work/<id>.md` from the `id:` field; the runner refuses to start the lane if any
  card's filename disagrees with its `id:` (a mismatch used to half-work, then
  silently miss everything downstream).
- Concrete **Goal** + **Done when** (vague cards produce confident garbage at 3am) —
  stating what must be true, not which commands to run, and no constraints the task
  doesn't actually have: the 3am agent treats every word on the card as law.
- `files:` declared; cards touching `PROJECT.md` human-gate paths are never claimed.
- Optional `after: [T-01]` dependency edges and `budget: 30` (minutes) override.

**`after:` is sequencing, NOT code visibility.** Branches stay unmerged overnight, so
a dependent card branches from the default branch and **cannot see its dependency's
code**. The runner therefore only treats `after:` deps as satisfied once the dep is
`done` (i.e. **merged**) — `review` is not enough. If card B needs card A's code the
same night, they are one card. (Found the hard way in the v0 acceptance test.)

## The loop (per card)

claim (`mkdir claims/<id>` mutex → card rewrite with owner/status) → spawn worktree →
run the agent's headless CLI with the card as prompt, hard timeout → salvage-commit
any uncommitted work → run `green_cmd`; **the green check decides, never the LLM's
own claim** → green: `status: review`, branch waits for morning · red: the attempt
is pinned under `refs/apsolut/attempts/<id>-<n>` and its diff + output tail saved
as `runs/<id>-attempt<n>.fail`, the worktree reset, and the next attempt gets that
failure context in its prompt (a blind retry repeats the same dead end); retry
once, then `status: blocked` + phone ping. Backoff resets salvage + pin the same
way — a 429 never destroys work.

## Safety rails (structural)

- Lane preflight: on boot the runner sends the CLI one "reply ok" probe from an empty
  temp dir and refuses to start the lane if it fails — bad auth or a refusing account
  costs one probe, not a whole board of burned attempts.
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

Before any run: `sh .apsolut-agents/scripts/doctor.sh <agent>` — tools, HEARTBEAT
sanity, card contract + `after:` graph, green on the primary, rolling cost vs
budget, and a live CLI probe, in one command. Exit 1 = do not start the night.

v0: 3 supervised `--once` runs — zero double-claims, zero touches of the default
branch, every green branch builds, budget respected. v1: 5 clean unattended solo
nights. v2: add the second lane + `heartbeat.sh` (future — not shipped yet). Full rationale: the night-shift
PRD in `runs/` (or `ideas/` while drafting).
