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
# per-call cap for the read-only roles below (verifier, advisor, planner, reviewer)
helper_timeout_minutes: 20
# hard cap for every check the runner runs itself: setup_cmd, green_cmd, a card's
# check:, done_cmd. A hung e2e must not eat the night.
check_timeout_minutes: 30
# with no cost in the CLI output (a timeout, a CLI that prints none), charge the larger
# of cost_fallback_usd and minutes x this rate
cost_per_minute_usd: 0.15
# a provider throttle is not an attempt, up to this many per card per night
max_backoffs_per_card: 3

## Roles (v0.9) — each names an agent that has a cmd_<agent> line below; empty = off
# verifier_agent runs every green card for real and returns a verdict
# (live-verified | test-verified | typecheck-only | verifier-blocked | verifier-failed).
# Below verify_level, the attempt counts as red. Pick a DIFFERENT model family from the
# worker lanes: an author checks what it meant to build, not what it built.
verifier_agent:
# advisor_agent reads a failed attempt before the retry and writes a diagnosis into
# the retry prompt (the "stuck" checkpoint). One call per retried card.
advisor_agent:
# review_agent audits the decision trail at night end and appends "Attention" to the
# night report. Read it first in the morning.
review_agent:
# minimum verifier verdict: live | test | typecheck. A card's `verify:` overrides it,
# and GOAL.md verify_level overrides it in goal mode.
verify_level: test

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
# done --merge runs this same command inside the agent's EXISTING worktree, on a
# detached merge into the primary commit, before the primary branch moves. It does
# not use a fresh worktree: that checkout has no node_modules or virtualenv.
# green_cmd must not edit, stage, or commit. done --merge refuses when this
# command changes that merge. Ignored output is allowed. A fixer (lint --fix,
# prettier --write) belongs in the agent worktree before --merge.
green_cmd: echo "SET green_cmd IN HEARTBEAT.md" && false
# setup_cmd runs ONCE in every fresh worktree (cards and the night branch), outside
# the attempt clock: install deps, or link a seeded node_modules/.venv. It may write
# ignored files only. Empty = none (then green_cmd has to install for itself).
#   setup_cmd: pnpm install --frozen-lockfile --prefer-offline
setup_cmd:
# protect: git pathspecs no card may change, on every night (GOAL.md protect: adds
# the goal's own). A card diff touching one is red. Put the judge here: the green
# script, test config, CI config.   protect: run-tests.sh .github/ vitest.config.ts
protect:
# added lines matching this extended regex turn an attempt red (symptom patches).
# Delete the line to use the default; leave the value empty to switch it off.
forbid_added: \.skip\(|\.only\(|(^|[^[:alnum:]_])x(it|describe)\(|@ts-ignore|@ts-nocheck|eslint-disable

## Notification (ntfy.sh topic URL, or leave empty for log-only)
notify_url:

## Agent commands — how each agent runs headless (prompt is appended as last arg)
## prompt_<agent>: stdin sends the prompt on stdin instead (claude -p and `codex exec -`
## read it there). With the default (arg), a prompt bigger than prompt_arg_max_bytes
## (6000) is replaced by a one-line pointer to the prompt file, because Windows caps a
## command line near 8-32 KB.   prompt_claude: stdin
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
