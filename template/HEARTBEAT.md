<!-- apsolut-agents: tier=2 kind=instance -->
# HEARTBEAT — Night Shift + delegation policy (fill in per project)

Config for `scripts/runner.sh` (unattended nights) and `scripts/delegate.sh` (in-session
agent-drives-agent). Plain `key: value` lines — the scripts read them with grep, so keep
the format. Tune thresholds here, not in code.

## Limits

card_timeout_minutes: 45
max_attempts_per_card: 2
max_consecutive_failures_lane: 3
# night_budget_usd is a HARD stop but is checked BETWEEN cards — a night can overshoot
# by roughly one card's cost before it trips. (Keep comments on their own line: the
# scripts grep `key: value` and an inline comment would corrupt the value.)
night_budget_usd: 100
# cost_fallback_usd is charged per card when the CLI emits no cost output — exactly when
# you are flying blind. Field-observed real cards ran $6–10; tune this up, not down.
cost_fallback_usd: 2.00
stop_time: 07:00
idle_poll_seconds: 300
stale_claim_minutes: 5

## Delegation caps (scripts/delegate.sh — see DELEGATION.md §4)
delegate_max_depth: 2
delegate_max_concurrent: 2
delegate_max_rounds: 4
delegate_timeout_minutes: 45
delegate_budget_usd: 25

## Verification — what "green" means for a card's worktree
# green_cmd runs with cwd = the card's WORKTREE, which contains ONLY TRACKED files.
# No untracked helper scripts, no paths that exist only in the primary checkout —
# a green that passes on the primary but not on a fresh worktree blocks every card
# as if the work failed. `doctor.sh` proves green in a throwaway worktree.
green_cmd: echo "SET green_cmd IN HEARTBEAT.md" && false

## Notification (ntfy.sh topic URL, or leave empty for log-only)
notify_url:

## Agent commands — how each agent runs headless (prompt is appended as last arg)
## Used by BOTH runner.sh (night lanes) and delegate.sh (in-session delegation).
## This file is where the permission posture is decided: an agent cannot loosen its own,
## because agents never write this file. Bypass flags here are a deliberate human choice —
## delegates are contained by worktree isolation + a sealed pushurl, not by prompts (DELEGATION.md §3).
## Do not put --bare on a cmd_ line. claude --bare ignores the signed-in claude.ai
## account (no OAuth, no keychain) and the delegate exits "Not logged in" even though
## an interactive terminal on the same machine is signed in. Headless -p / exec is
## enough. doctor.sh fails a cmd_ line that contains --bare.
cmd_claude: claude -p --dangerously-skip-permissions --output-format json
cmd_grok: grok --always-approve --output-format json -p
cmd_agy: agy --dangerously-skip-permissions --output-format json -p

## Notes
- Runner and delegates inherit your user environment: provider API keys ARE available to
  them by design. The rule is "no project `.env` in worktrees", not "no secrets anywhere".
- `night_budget_usd` is a per-night HARD stop, enforced from CLI cost output when
  available, else `cost_fallback_usd` per card. Per-card time cap = `budget:` on the
  card, else `card_timeout_minutes`.
- `stale_claim_minutes` = grace before a claim whose runner PID is dead gets released.
- One runner per agent name — a second `runner.sh <agent>` refuses to start.
- `delegate_*` keys are optional: `delegate.sh` has the same values built in as defaults,
  so a workspace upgraded from before delegation existed (this file is `kind=instance` and
  is never overwritten) works unchanged. Add them only to override.
- `delegate_budget_usd` shares the daily ledger `runs/.spend-<date>` with `night_budget_usd`:
  daytime delegation and that night's run draw from the same pot.
