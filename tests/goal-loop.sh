#!/bin/sh
# SPDX-License-Identifier: MIT — (c) 2026 apsolut — https://github.com/apsolut/apsolut-agents
# tests/goal-loop.sh — end-to-end Night Shift goal loop against a fake agent CLI.
# Each scenario: a throwaway repo, a fresh install, a board, `runner.sh fake --once`,
# then asserts on exit code, branches, cards, trail and report. No model is called.
# Run: sh tests/goal-loop.sh   (CI runs it; needs git, awk, sed, timeout)
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAKE="$ROOT/tests/fake-agent.sh"
PASSN=0; FAILN=0
TMPS=""
# KEEP=1 keeps the fixture repos for inspection (paths printed at the end)
[ -n "${KEEP:-}" ] || trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT

ok()   { PASSN=$((PASSN+1)); echo "  ok    $1"; }
bad()  { FAILN=$((FAILN+1)); echo "  FAIL  $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# fixture repo: tracked run-tests.sh is the green check; the test repo signs nothing
# (it is a throwaway fixture with no key; real commits stay signed)
setup() { # $1 goal text, $2 done_cmd
  T=$(mktemp -d); TMPS="$TMPS $T"
  R="$T/proj"; mkdir -p "$R"
  git init -q -b main "$R"
  git -C "$R" config user.email test@example.invalid
  git -C "$R" config user.name test
  git -C "$R" config commit.gpgsign false
  printf 'for t in t_*.sh; do [ -f "$t" ] || continue; sh "$t" || exit 1; done\n' > "$R/run-tests.sh"
  sh "$ROOT/install.sh" "$R" >/dev/null
  W="$R/.apsolut-agents"
  cat > "$W/HEARTBEAT.md" <<EOF
card_timeout_minutes: 2
helper_timeout_minutes: 2
max_attempts_per_card: 2
max_consecutive_failures_lane: 3
night_budget_usd: 50
cost_fallback_usd: 0.10
stop_time: 23:59
idle_poll_seconds: 1
stale_claim_minutes: 5
green_cmd: sh run-tests.sh
cmd_fake: sh $FAKE
cmd_fakev: sh $FAKE
verifier_agent: fakev
advisor_agent: fakev
review_agent: fakev
verify_level: test
EOF
  sed -i "s|^goal:.*|goal: $1|; s|^done_cmd:.*|done_cmd: $2|" "$W/GOAL.md"
  git -C "$R" add -A && git -C "$R" commit -q -m init
  MAIN0=$(git -C "$R" rev-parse main)
}
card() { # $1 id, $2 notes line(s)
  cat > "$W/work/$1.md" <<EOF
---
id: $1
status: waiting
owner: any
title: card $1
after: []
risk: []
spike: false
verify: test
files:
  - x
branch: null
worktree: null
---

# $1

## Goal
make the file

## Done when
- [ ] A failing test exists that proves the goal
- [ ] sh run-tests.sh passes

## Notes
$2
EOF
}
run() { RC=0; ( cd "$R" && sh .apsolut-agents/scripts/runner.sh fake --once ) > "$T/runner.out" 2>&1 || RC=$?; }
NB() { echo "agent/night/NIGHT-$(date +%Y-%m-%d)"; }

echo "[1] goal loop: card, verifier, integration, planner, goal met"
setup "a.txt and b.txt exist" 'test -f a.txt \&\& test -f b.txt'
card T-01 "make: a.txt"
run
check "exit 0 (goal met)" '[ "$RC" -eq 0 ]'
check "report says goal met" 'grep -q "reason: goal met" "$W/runs/night-$(date +%Y-%m-%d).md"'
check "default branch never moved" '[ "$(git -C "$R" rev-parse main)" = "$MAIN0" ]'
check "night branch holds a.txt and b.txt" 'git -C "$R" cat-file -e "$(NB):a.txt" && git -C "$R" cat-file -e "$(NB):b.txt"'
check "T-01 integrated and test-verified" '[ "$(sed -n "s/^verified: //p" "$W/work/T-01.md")" = test-verified ] && grep -q "^integrated: $(NB)" "$W/work/T-01.md"'
check "planner card accepted and integrated" 'ls "$W"/work/G*r1-1.md >/dev/null 2>&1 && grep -q "^integrated: $(NB)" "$W"/work/G*r1-1.md'
check "one merge commit per card on the night branch" '[ "$(git -C "$R" rev-list --merges --count "main..$(NB)")" -eq 2 ]'
check "NIGHT card left in review" 'grep -q "^status: review" "$W/work/NIGHT-$(date +%Y-%m-%d).md"'
check "trail has verify, integrate, plan and goal rows" 'for p in verify integrate plan goal; do cut -f3 "$W/runs/trail-$(date +%Y-%m-%d).tsv" | grep -qx "$p" || exit 1; done'
check "reviewer attention appended to the report" 'grep -q "^## Attention" "$W/runs/night-$(date +%Y-%m-%d).md"'
check "morning merge lands the night" '( cd "$R" && sh .apsolut-agents/scripts/worktree.sh done "NIGHT-$(date +%Y-%m-%d)" --merge ) >/dev/null 2>&1 && git -C "$R" cat-file -e main:b.txt'

echo "[2] verifier rejects attempt 1, advisor feeds attempt 2"
setup "a.txt exists" 'test -f a.txt'
card T-01 "make: a.txt
flaky: yes"
run
check "exit 0 (goal met)" '[ "$RC" -eq 0 ]'
check "two attempts" '[ "$(cat "$W/runs/.attempts-T-01")" = 2 ]'
check "attempt 1 pinned under refs/apsolut/attempts" 'git -C "$R" rev-parse -q --verify refs/apsolut/attempts/T-01-1 >/dev/null'
check "verifier verdict was in the failure context" 'grep -q verifier-failed "$W/runs/T-01-attempt1.fail"'
check "advisor wrote advice and the retry prompt carried it" '[ -s "$W/runs/handoffs/T-01-advice2.md" ] && grep -q "ADVISOR" "$W/runs/T-01-attempt2.prompt"'
check "night branch has the right content" '[ "$(git -C "$R" show "$(NB):a.txt")" = right ]'

echo "[3] Andon stops the line before any claim"
setup "a.txt exists" 'test -f a.txt'
card T-01 "make: a.txt"
( cd "$R" && sh .apsolut-agents/scripts/andon.sh raise "harness broken: test" ) >/dev/null
run
check "exit 5" '[ "$RC" -eq 5 ]'
check "card never claimed" 'grep -q "^status: waiting" "$W/work/T-01.md"'

echo "[4] tamper canary: a worker editing HEARTBEAT.md ends the night"
setup "a.txt exists" 'test -f a.txt'
card T-01 "make: a.txt
tamper: yes"
run
check "exit 5" '[ "$RC" -eq 5 ]'
check "Andon raised naming HEARTBEAT.md" 'grep -q "HEARTBEAT.md" "$W/ANDON"'
check "nothing integrated" '! git -C "$R" cat-file -e "$(NB):a.txt" 2>/dev/null'

echo "[5] planner STUCK ends the night for a human"
setup "stuck-please" 'test -f never.txt'
run
check "exit 6" '[ "$RC" -eq 6 ]'
check "STUCK writeup filed and in the report" '[ -s "$W/runs/STUCK-$(date +%Y-%m-%d).md" ] && grep -q "Planner is stuck" "$W/runs/night-$(date +%Y-%m-%d).md"'

echo "[6] agent-declared dead end blocks without a retry"
setup "" ''
card T-01 "make: a.txt
blocked: yes"
run
check "card blocked after one attempt" 'grep -q "^status: blocked" "$W/work/T-01.md" && [ "$(cat "$W/runs/.attempts-T-01")" = 1 ]'
check "blocked note carries the agent's reason" 'grep -q "Would unblock: - needs a credential" "$W/work/T-01.md"'

echo "[7] plain board mode (no done_cmd) is unchanged: no night branch"
setup "" ''
card T-01 "make: a.txt"
run
check "exit 0 (board empty)" '[ "$RC" -eq 0 ] && grep -q "reason: board empty" "$W/runs/night-$(date +%Y-%m-%d).md"'
check "card in review on its own branch, no night branch" 'grep -q "^status: review" "$W/work/T-01.md" && ! git -C "$R" rev-parse -q --verify "$(NB)" >/dev/null'

echo
echo "goal-loop: $PASSN ok, $FAILN failed"
[ -z "${KEEP:-}" ] || echo "kept fixtures:$TMPS"
[ "$FAILN" -eq 0 ] || { echo "last runner output:"; tail -30 "$T/runner.out"; exit 1; }
