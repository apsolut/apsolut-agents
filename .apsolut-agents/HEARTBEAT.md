<!-- apsolut-agents: tier=2 kind=instance -->
# HEARTBEAT — Night Shift policy (fill in per project)

Config for `scripts/runner.sh` (and later `heartbeat.sh`). Plain `key: value` lines —
the scripts read them with grep, so keep the format. Tune thresholds here, not in code.

## Limits

card_timeout_minutes: 45
max_attempts_per_card: 2
max_consecutive_failures_lane: 3
night_budget_usd: 25
cost_fallback_usd: 2.00
stop_time: 07:00
idle_poll_seconds: 300
stale_claim_minutes: 5

## Verification — what "green" means for a card's worktree
green_cmd: echo "SET green_cmd IN HEARTBEAT.md" && false

## Notification (ntfy.sh topic URL, or leave empty for log-only)
notify_url:

## Lane commands — how each agent runs headless (prompt is appended as last arg)
cmd_claude: claude -p --permission-mode acceptEdits --output-format json
cmd_grok: grok --always-approve --output-format json -p
cmd_agy: agy --dangerously-skip-permissions --output-format json -p

## Notes
- Runner inherits your user environment: provider API keys ARE available to lanes by
  design. The rule is "no project `.env` in worktrees", not "no secrets anywhere".
- `night_budget_usd` is a per-night HARD stop, enforced from CLI cost output when
  available, else `cost_fallback_usd` per card. Per-card time cap = `budget:` on the
  card, else `card_timeout_minutes`.
