# PRD — Night Shift v1 (synthesized)
_2026-07-29. Pipeline: Claude draft → blind parallel reviews by AGY/Gemini + Grok → this synthesis._
_Both reviewers: **build-changed**. No kill votes. This PRD supersedes `01-draft-claude.md`._

## Decision summary

Build an overnight runner for agent task cards — but **dumber and safer than the draft**.
Both blind reviews independently demanded the same four cuts, which makes them
non-negotiable:

1. **No LLM in the control plane.** Stage-2 haiku classifier is CUT. The heartbeat is
   pure rules (process liveness, transcript mtime, git progress, failure counters).
   Both reviewers: a cheap LLM judging WORKING-vs-LOOPING will confidently kill healthy
   long-running work. Rule-based first; revisit only with measured false-positive data.
2. **No overnight merging.** The `night/<date>` integration branch is CUT from v0–v1.
   Card branches survive unmerged until morning; the human merges selectively
   (each card = one clean `--no-ff` candidate, revert-free rejection). Overnight
   integration propagates one bad "green" into every later card.
3. **No automatic cross-model reassign.** Morning-human-only. Auto-reassign doubles
   token burn on cards that fail for card-quality reasons, and hides the real signal
   ("this card needs a human").
4. **Kill is terminal, not a nudge.** No `--resume`-with-hint recovery loop. Timeout →
   kill the process tree → mandatory cleanup (`git reset --hard` in the worktree, clear
   orphan `.git/*.lock`) → card back to `waiting` with attempt counter, or `blocked`
   after N attempts. Resume is a best-effort bonus where a vendor supports it, never
   load-bearing.

Additionally (Grok's steelman, accepted): **v0 runs ONE lane, supervised**, for long
enough to be boring — the two-lane night comes only after single-lane nights are clean.

## Phasing (each gate has pass/fail criteria — no vibes)

**v0 — one lane, supervised evening run (build first):**
- `after: []` dependency edges on cards; `status.sh` computes `ready`.
- Claim protocol (see below), single `runner.sh`, fixed 45-min timeout with optional
  per-card `budget:` override, Green per PROJECT.md decides done, branches left unmerged.
- TICK lines + circuit breaker (3 consecutive fails → stop) + per-night token/cost cap.
- **Gate to v1:** 3 supervised runs with: 0 double-claims, 0 touches of `main`,
  every card branch builds, budget respected, report matches reality.

**v1 — one lane, real overnight + morning report:**
- `runs/night-<date>.md`: done / blocked / attempts / wall-time vs budget / diffstat
  per branch. Idempotent (partial nights, restarts don't double-count).
- Boot recovery: on start, clear stale claims (by age + dead PID), adopt or remove
  orphan worktrees, never resume a half-written card silently.
- **Gate to v2:** 5 unattended nights, same criteria + zero human interventions needed
  before 07:00.

**v2 — second lane (grok) + heartbeat:**
- Two runners, file-overlap check at claim time (cards with intersecting `files:`
  globs are never concurrently claimable; cards missing `files:` are single-lane only).
- `heartbeat.sh` (10-min, pure sh): runner PID alive? transcript mtime < stall
  threshold? worktree commit/dirty progress? ready-cards-but-idle-runner? All green →
  `TICK: ok`; anomaly → kill/cleanup per rules + ntfy.sh phone ping; both lanes dead →
  global stop + incident file.
- **Gate to v3:** measured stage-1 false-positive rate ≈ 0 across 5 nights.

**v3 (only if data demands):** night integration branch with merge-only-after-clean-
rebase + conflict→blocked (no hero auto-resolve); smarter classification if rules
proved insufficient.

## Claim protocol (both reviewers flagged the draft's as racy)

Single source of truth = the card. One writer path:
1. `mkdir claims/<id>` — fast mutex (atomic on NTFS/Git Bash); fails → someone else has it.
2. Winner immediately rewrites card frontmatter: `owner`, `status: writing`,
   `claimed: <iso-time> pid:<pid>`.
3. Stale-claim recovery at runner start + each heartbeat: claim older than
   `stall_claim_minutes` AND pid dead → remove claim dir, card → `waiting`, log it.
`owner: any` allowed, but the claim step is identical — no free-for-all writes.

## HEARTBEAT.md policy (the minimum that matters — union of both reviews)

```
tick_interval: 10m
stall_transcript_minutes: 10
stall_no_commit_minutes: 30
max_attempts_per_card: 2
max_consecutive_failures_lane: 3
max_consecutive_failures_global: 5
stop_time: "07:00"
night_budget: <tokens or USD, hard, per-night; per-card soft cap>
min_free_disk_mb: 2048
notify_url: <ntfy.sh/...>
lanes: claude, grok   # + pid/log/worktree paths, written by runner
```

## Also adopted from reviews

- **Distinguish provider errors from test failures** (AGY): HTTP 429/5xx from the CLI
  must pause the lane with backoff, not trip the failure circuit breaker.
- **Env honesty** (Grok): document which env vars runners inherit; provider API keys
  ARE present by design — the rule is "no project `.env` in worktrees", not "no secrets".
- **Enforcement of `files:`** (Grok): overlap = glob intersection on declared paths;
  post-run, runner diffs the branch — edits outside declared `files:` +10% tolerance
  → flag in report (v2: → blocked).

## Rejected review points (with reasons)

- AGY's derived-complexity timeouts as default: adopted only as the optional
  `budget:` override (Grok's version) — we have no size model to derive from.
- Grok's "defer heartbeat entirely past v2": kept stage-1 TICK in v2 because two
  unattended lanes without liveness detection fails silent; it's 30 lines of sh.

## Open for the human (you)

1. Night budget number (tokens or € per night)?
2. v0 scratch project or a real repo for the supervised runs?
3. ntfy.sh vs Telegram vs email for the 03:00 ping?
