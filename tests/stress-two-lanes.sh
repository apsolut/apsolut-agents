#!/bin/sh
# SPDX-License-Identifier: MIT — (c) 2026 Aleksandar Perisic (apsolut) — https://github.com/apsolut/apsolut-agents
# tests/stress-two-lanes.sh [rounds] — two fake lanes started in the same moment on one
# board of four cards, with the end-of-night state checked after every round. Odd
# rounds run the goal loop, even rounds a plain board. No model is called.
# It exists because races between lanes do not show in a scripted scenario: on
# v0.13.1 every goal round lost a lane, and tests/goal-loop.sh stayed green.
# Fixtures of failed rounds are kept and their paths printed.
# Run: sh tests/stress-two-lanes.sh 10   (CI runs four rounds)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd); N=${1:-8}
FAKE="$ROOT/tests/fake-agent.sh"
okn=0; badn=0

i=0
while [ "$i" -lt "$N" ]; do
  i=$((i+1))
  T=$(mktemp -d); R="$T/proj"; mkdir -p "$R"
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
cmd_fake2: sh $FAKE
cmd_fakev: sh $FAKE
verifier_agent: fakev
advisor_agent: fakev
review_agent: fakev
verify_level: test
EOF
  if [ $((i % 2)) -eq 1 ]; then
    mode=goal
    sed -i "s|^goal:.*|goal: a b c d exist|; s|^done_cmd:.*|done_cmd: test -f a.txt \\&\\& test -f b.txt \\&\\& test -f c.txt \\&\\& test -f d.txt|" "$W/GOAL.md"
  else
    mode=plain
    sed -i "s|^goal:.*|goal: |; s|^done_cmd:.*|done_cmd: |" "$W/GOAL.md"
  fi
  n=0
  for f in a b c d; do
    n=$((n+1))
    cat > "$W/work/T-0$n.md" <<EOF
---
id: T-0$n
status: waiting
owner: any
title: card T-0$n
after: []
risk: []
spike: false
verify: test
files:
  - $f.txt
branch: null
worktree: null
---

# T-0$n

## Goal
make the file

## Done when
- [ ] A failing test exists that proves the goal
- [ ] sh run-tests.sh passes

## Notes
make: $f.txt
EOF
  done
  git -C "$R" add -A && git -C "$R" commit -q -m init
  CL0=$(ls -A "$W/claims" 2>/dev/null | sort | tr '\n' ' ')
  D=$(date +%Y-%m-%d)

  ( cd "$R" && sh .apsolut-agents/scripts/runner.sh fake --drain ) > "$T/l1.out" 2>&1 &
  p1=$!
  ( cd "$R" && sh .apsolut-agents/scripts/runner.sh fake2 --drain ) > "$T/l2.out" 2>&1 &
  p2=$!
  r1=0; wait "$p1" || r1=$?
  r2=0; wait "$p2" || r2=$?

  RP="$W/runs/night-$D.md"; NBR="agent/night/NIGHT-$D"
  problems=""
  chk() { if ! eval "$2"; then problems="$problems
      - $1"; fi; }
  chk "lane exit codes are 0 (got $r1 and $r2)" '[ "$r1" -eq 0 ] && [ "$r2" -eq 0 ]'
  chk "the night was closed (.night-current removed)" '[ ! -f "$W/runs/.night-current" ]'
  chk "the report exists" '[ -s "$RP" ]'
  chk "the report names both lanes" 'grep -q "^# Night report .*(lanes: fake, fake2)" "$RP" && [ "$(grep -c "^Ended: " "$RP")" -eq 2 ]'
  chk "exactly one Attention section (found $(grep -c "^## Attention" "$RP" 2>/dev/null))" '[ "$(grep -c "^## Attention" "$RP")" -eq 1 ]'
  chk "no claim, lock or lane folder left (now: $(ls -A "$W/claims" 2>/dev/null | tr "\n" " "))" '[ "$(ls -A "$W/claims" 2>/dev/null | sort | tr "\n" " ")" = "$CL0" ]'
  chk "no temp file left in work/ or runs/" '[ -z "$(ls -A "$W/work" "$W/runs" 2>/dev/null | grep "\.tmp\." || true)" ]'
  chk "no snapshot worktree left" '[ "$(git -C "$R" worktree list | grep -c "/review\|/plan")" -eq 0 ]'
  chk "no claim was dropped on an abnormal exit" '! grep -q "released claim .* on exit" "$W/agent-log.md"'
  chk "main never moved" '[ "$(git -C "$R" log --format=%s -1 main)" = init ]'
  for n in 1 2 3 4; do
    c="$W/work/T-0$n.md"
    chk "T-0$n is verified" 'grep -q "^verified: test-verified" "$c"'
    chk "T-0$n ran exactly one attempt" '[ "$(cat "$W/runs/.attempts-$D-T-0$n" 2>/dev/null)" = 1 ]'
    if [ "$mode" = goal ]; then chk "T-0$n is integrated" 'grep -q "^integrated: $NBR" "$c"'
    else chk "T-0$n is in review" 'grep -q "^status: review" "$c"'; fi
  done
  if [ "$mode" = goal ]; then
    chk "the night branch holds all four files" 'for f in a b c d; do git -C "$R" cat-file -e "$NBR:$f.txt" 2>/dev/null || exit 1; done'
    chk "the report says goal met" 'grep -q "reason: goal met" "$RP"'
    chk "each card was merged once" '[ "$(git -C "$R" rev-list --merges --count "main..$NBR")" -ge 4 ]'
  fi
  both=$(cut -f2 "$W/runs/trail-$D.tsv" 2>/dev/null | sort -u | tr '\n' ' ')
  if [ -z "$problems" ]; then
    okn=$((okn+1)); echo "round $i ($mode): ok — lanes that worked: $both"
    rm -rf "$T" 2>/dev/null || true
  else
    badn=$((badn+1)); echo "round $i ($mode): PROBLEMS — fixture kept at $T$problems"
  fi
done
echo "stress: $okn rounds ok, $badn with problems"
[ "$badn" -eq 0 ]
