<!-- apsolut-agents: tier=2 kind=instance -->
# HEARTBEAT — Night Shift + delegation policy (fill in per project)

Config for `scripts/runner.sh` (unattended nights) and `scripts/delegate.sh` (in-session
agent-drives-agent). Plain `key: value` lines — the scripts read them with grep, so keep
the format. Tune thresholds here, not in code.

## Limits

card_timeout_minutes: 45
max_attempts_per_card: 2
max_consecutive_failures_lane: 3
# SPEND CAPS ARE OFF BY DEFAULT: night_budget_usd, call_budget_usd and
# delegate_budget_usd are empty. On a subscription plan nothing is charged per call,
# so a dollar cap protects nothing there. Spend is still recorded in
# runs/.spend-<date> and printed in the night report.
# Paying per call (an API key)? Switch the cap on:   night_budget_usd: 100
# It is then a HARD stop, checked BETWEEN cards — a night can overshoot by roughly one
# card's cost before it trips. Empty or 0 = no cap. (Keep comments on their own line:
# the scripts grep `key: value` and an inline comment would corrupt the value.)
night_budget_usd:
# call_budget_usd caps ONE CLI call. The scripts export the smaller of this and what is
# left of the night as $APSOLUT_CALL_BUDGET_USD, and a cmd_ line hands it to a CLI that
# has a spend flag (claude --max-budget-usd). A worker that hits it is blocked, not
# retried: a retry at the same size pays the cap twice. Empty = what is left of the
# night. With no night cap either, the variable holds 1000000: a number the flag
# accepts and a call never reaches.
call_budget_usd:
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
# Both rates can be set per agent for a CLI that never prints a cost (codex --json and
# agy print token counts only): cost_fallback_usd_<agent>, cost_per_minute_usd_<agent>.
#   cost_per_minute_usd_codex: 0.25
# Waiting on a human (v0.13). When the key that signs commits is locked, or a CLI has
# lost its login, no card can succeed and a retry cannot help. The lane parks: the
# card goes back to waiting with its attempt returned, and the runner looks again
# every park_poll_seconds for up to human_wait_minutes (or until stop_time). After
# that it ends the night with exit 7 and says so in the report. 0 = end at once.
human_wait_minutes: 60
park_poll_seconds: 300
# How long one of the runner's own signed commits or merges may take. A signing
# program that waits for a human (a locked key manager) then fails the step and the
# lane parks, where it used to wait for ever.
git_timeout_seconds: 300
# a provider throttle (a FAILED call whose last lines say 429/quota/overloaded; never
# our own timeout) is not an attempt, up to this many per card per night
max_backoffs_per_card: 3

## Roles (v0.9) — each names an agent that has a cmd_<agent> line below; empty = off
# verifier_agent runs every green card for real and returns a verdict
# (live-verified | test-verified | typecheck-only | verifier-blocked | verifier-failed).
# Below verify_level, the attempt counts as red. Pick a DIFFERENT model family from the
# worker lanes: an author checks what it meant to build, not what it built. Never a
# weaker model than the workers: a judge that cannot follow the code rejects good
# work, and every wrong rejection is a paid retry. doctor.sh warns about a small one.
verifier_agent:
# Risk routing. A card whose `risk:` list holds one of risk_tags is judged by
# risk_verifier_agent (your strongest model) when that is set, else by verifier_agent.
# In goal mode such a card never integrates on its check: alone: with no verifier it
# stays in review for you. The tags are the PLAYBOOK §4 ones. Empty risk_tags = off.
risk_tags: api-contract schema pii money
risk_verifier_agent:
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
# daily spend cap for delegation, off by default. Empty = night_budget_usd, and no cap
# when that is empty too. 0 = no cap for delegation even when the night has one.
delegate_budget_usd:

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
# Optional: add .claude/ (and .codex/, .cursor/) if no card should change the hooks
# and settings the CLIs load from the repo. Off by default: some cards are about
# exactly those files.
protect:
# added lines matching this extended regex turn an attempt red (symptom patches).
# Delete the line to use the default; leave the value empty to switch it off.
forbid_added: \.skip\(|\.only\(|(^|[^[:alnum:]_])x(it|describe)\(|@ts-ignore|@ts-nocheck|eslint-disable

## Issue intake (scripts/intake.sh)
# Only open GitHub issues carrying this label become cards. The label is your "I read
# this, the agents may work on it". Empty = agents.
intake_label: agents

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
##
## A cmd_ line runs through `sh -c`, with three values exported for it:
##   $APSOLUT_CALL_BUDGET_USD    call_budget_usd, never more than what is left of the night
##                               (1000000 while no spend cap is set)
##   $APSOLUT_CALL_MINUTES       the hard time cap `timeout` enforces on this call
##   $APSOLUT_SOFT_TIMEOUT_MIN   one minute less, for a CLI that can stop itself in time
## What the flags below are for (checked against claude 2.1.322, codex 0.167.0,
## grok 1.0.70, agy 1.5.5; `doctor.sh <agent>` proves a line still answers):
## - No native subagents. Every CLI can now fan out by itself, and that work is outside
##   the depth cap, the card clock and the spend ledger. claude --disallowedTools
##   Agent,Task · grok --no-subagents · codex --disable multi_agent. agy has no flag.
## - claude --max-budget-usd stops one call at the per-call budget. It does nothing
##   while no spend cap is set, and is already in place the day you set one.
## - agy --print-timeout makes agy stop itself and still print its JSON
##   ("finished_reason":"print_timeout"), which the runner reads as a timeout. Without
##   it a headless agy waits for its background tasks until `timeout` kills it.
## - A list flag (claude --disallowedTools, --allowedTools, --tools, --add-dir,
##   --mcp-config) swallows the next word. Never leave one last on an arg-mode line:
##   it would eat the prompt. doctor.sh fails such a line.
## - Workers run with everything your CLI has. A headless claude loads the MCP servers
##   and claude.ai connectors of the signed-in account (mail, chat, CRM, ...), and a
##   worker may use them to get a card done. That is the default on purpose.
##   Optional lock-down: add --strict-mcp-config to the claude line and the worker
##   keeps only the code and the shell. It cannot reach your mail or CRM, and each
##   call starts lighter (measured on claude 2.1.322, one-word prompt: 42,000 tokens
##   of start-up context without the flag, 33,600 with it). The flag also drops a
##   project .mcp.json; add `--mcp-config .mcp.json` to keep that one server.
##   Adding --disable-slash-commands (no skills, no commands) measured 28,800.
## - grok reads your Claude Code and Cursor setup by default: MCP servers, hooks,
##   skills, rules, agents. The GROK_CLAUDE_*_ENABLED=0 variables in front of the grok
##   line switch that off, so a Grok worker runs on its own configuration and its
##   start-up context is about a tenth smaller (21,200 to 18,800 tokens on 1.0.70).
## - codex --ignore-user-config and agy --disable-slash-commands were measured too and
##   changed nothing in start-up tokens or time, so they are not on the lines below.
## - codex prints no cost and no is_error: a failed call is its exit code, and its
##   spend is cost_fallback_usd / cost_per_minute_usd (settable per agent, see Limits).
prompt_claude: stdin
cmd_claude: claude -p --dangerously-skip-permissions --disallowedTools Agent,Task --max-budget-usd $APSOLUT_CALL_BUDGET_USD --output-format json
cmd_grok: GROK_CLAUDE_MCPS_ENABLED=0 GROK_CLAUDE_HOOKS_ENABLED=0 GROK_CLAUDE_SKILLS_ENABLED=0 GROK_CLAUDE_RULES_ENABLED=0 GROK_CLAUDE_AGENTS_ENABLED=0 grok --always-approve --no-subagents --output-format json -p
cmd_agy: agy --dangerously-skip-permissions --output-format json --print-timeout ${APSOLUT_SOFT_TIMEOUT_MIN}m -p
prompt_codex: stdin
cmd_codex: codex exec --dangerously-bypass-approvals-and-sandbox --disable multi_agent --json -

## Notes
- Runner and delegates inherit your user environment: provider API keys ARE available to
  them by design. The rule is "no project `.env` in worktrees", not "no secrets anywhere".
- `night_budget_usd`, when set, is a per-night HARD stop, enforced from CLI cost output
  when available, else `cost_fallback_usd` per card. Empty or 0 = no cap (the default).
  Per-card time cap = `budget:` on the card, else `card_timeout_minutes`.
- `stale_claim_minutes` = grace before a claim whose runner PID is dead gets released.
- One runner per agent name — a second `runner.sh <agent>` refuses to start.
- `delegate_*` keys are optional: `delegate.sh` has the same values built in as defaults,
  so a workspace upgraded from before delegation existed (this file is `kind=instance` and
  is never overwritten) works unchanged. Add them only to override.
- `delegate_budget_usd` shares the daily ledger `runs/.spend-<date>` with `night_budget_usd`:
  with a cap set, daytime delegation and that night's run draw from the same pot.
