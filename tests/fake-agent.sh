#!/bin/sh
# SPDX-License-Identifier: MIT — (c) 2026 apsolut — https://github.com/apsolut/apsolut-agents
# fake-agent.sh "<prompt>" — a scripted stand-in for an agent CLI, used by
# tests/goal-loop.sh. It recognises the role from the rendered prompt and acts like
# a cooperative (or, when the card or goal asks, misbehaving) agent, so the whole
# night loop can run in CI without a model. Cards steer it with Notes lines:
#   make: <file>   create <file> and t_<file>.sh, which tests for it
#   flaky: yes     the first attempt writes the wrong content (the verifier catches it)
#   tamper: yes    edit HEARTBEAT.md through the .primary pointer
#   blocked: yes   report a dead end
# and the goal steers the planner: "stuck-please" → STUCK.md.
set -eu
P=$1
after() { printf '%s\n' "$P" | sed -n "s/.*$1[[:space:]]*//p" | head -1; }

case "$P" in
  "Reply with the single word: ok") echo ok; exit 0 ;;
esac

case "$P" in
*"the independent verifier"*)
  out=$(after 'nothing else in the repo:')
  f=$(printf '%s\n' "$P" | sed -n 's/^make: //p' | head -1)
  if [ -n "$f" ] && [ "$(cat "$f" 2>/dev/null)" = "right" ]; then
    lvl=test-verified; why="- [x] $f exists with the right content: cat $f -> right"
  else
    lvl=verifier-failed; why="- (high) $f does not hold the right content: cat $f -> $(cat "$f" 2>/dev/null || echo missing)"
  fi
  printf '## Verification\n%s\n\n## Execution\n- cat %s -> %s\n\n## Findings\n%s\n\n## Notes\n- fake verifier\n' \
    "$lvl" "$f" "$(cat "$f" 2>/dev/null || echo missing)" "$why" > "$out"
  echo '{"total_cost_usd": 0.01}'
  ;;
*"the night planner"*)
  stage=$(printf '%s\n' "$P" | sed -n 's/.*as its own file in \(.*\)\/ named exactly.*/\1/p' | head -1)
  next=$(printf '%s\n' "$P" | sed -n 's/.*with ids continuing from \([^ ]*\) (.*/\1/p' | head -1)
  mkdir -p "$stage"
  case "$P" in *stuck-please*)
    printf 'The goal needs a product decision: which colour.\nWould unblock: the human picks one.\n' > "$stage/STUCK.md"
    echo '{"total_cost_usd": 0.01}'; exit 0;;
  esac
  if [ ! -f b.txt ]; then
    cat > "$stage/$next.md" <<EOF
---
id: $next
status: waiting
owner: any
title: add b.txt
after: []
risk: []
spike: false
verify: test
files:
  - b.txt
---

# $next — add b.txt

## Goal
Close the gap the predicate shows: b.txt is missing.

## Done when
- [ ] A failing test exists that proves the goal (write it first)
- [ ] \`sh run-tests.sh\` passes

## Notes
make: b.txt
EOF
  fi
  echo '{"total_cost_usd": 0.02}'
  ;;
*"a read-only advisor"*)
  out=$(after 'nowhere else:')
  printf 'The first attempt wrote "wrong". Write "right" instead.\n' > "$out"
  echo '{"total_cost_usd": 0.01}'
  ;;
*"the morning reviewer"*)
  out=$(printf '%s\n' "$P" | sed -n 's/^Write exactly this to \(.*\), and nowhere else:$/\1/p' | head -1)
  printf '## Attention\nreviewed by fake\nCall: 🟢 merge as is\n- No flags\n\n## Waiting on the human\n- (none)\n' > "$out"
  echo '{"total_cost_usd": 0.01}'
  ;;
*"working alone and headless"*)
  hf=$(after 'with exactly these headings:')
  f=$(printf '%s\n' "$P" | sed -n 's/^make: //p' | head -1)
  case "$P" in *"tamper: yes"*)
    echo "tampered: yes" >> "$(cat .apsolut-agents/.primary)/HEARTBEAT.md";;
  esac
  case "$P" in *"blocked: yes"*)
    printf '## Status\nblocked\n\n## Notes\n- needs a credential nobody gave me\n' > "$hf"; exit 0;;
  esac
  content=right
  case "$P" in *"flaky: yes"*)
    case "$P" in *"PREVIOUS ATTEMPT FAILED"*) ;; *) content=wrong;; esac;;
  esac
  printf '%s\n' "$content" > "$f"
  printf 'test -f %s\n' "$f" > "t_$f.sh"
  git add -A -- ':!.apsolut-agents' && git commit -q -m "add $f"
  printf '## Status\nsuccess\n\n## Root cause\nn/a (new behaviour)\n\n## What I did\n- added %s\n\n## Verification\ntest-verified\n- sh run-tests.sh -> pass\n\n## Notes\n- fake worker\n\n## Suggested follow-ups\n- (none)\n' "$f" > "$hf"
  echo '{"total_cost_usd": 0.05}'
  ;;
*) echo "fake-agent: unknown role" >&2; exit 3 ;;
esac
