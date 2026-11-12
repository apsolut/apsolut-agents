#!/bin/sh
# SPDX-License-Identifier: MIT — (c) 2026 Aleksandar Perisic (apsolut) — https://github.com/apsolut/apsolut-agents
# fake-agent.sh ["<prompt>"] — a scripted stand-in for an agent CLI, used by
# tests/goal-loop.sh. It recognises the role from the rendered prompt and acts like
# a cooperative (or, when the card or goal asks, misbehaving) agent, so the whole
# night loop can run in CI without a model. The prompt arrives as $1, on stdin (no
# $1), or as a one-line pointer to a prompt file — the three ways runner.sh sends it.
# Cards steer it with Notes lines:
#   make: <file>         create <file> and t_<file>.sh, which tests for it
#   flaky: yes           the first attempt writes the wrong content (the verifier catches it)
#   tamper: yes          edit HEARTBEAT.md through the .primary pointer
#   blocked: yes         report a dead end
#   chatty: yes          print provider-error words in a successful run
#   cheat: yes           make the green script always pass (a protected path)
#   skip: yes            add a skipped test (a forbidden symptom patch)
#   stdout-handoff: yes  print the handoff instead of writing the file
#   budget-stop: yes     stop like claude at --max-budget-usd (is_error, exit 1)
#   cancelled: yes       stop like grok on a denied tool (stopReason cancelled, exit 0)
#   print-timeout: yes   stop like agy at --print-timeout (finished_reason, exit 3)
#   logout: yes          the worker's CLI loses its login (once), probe included
#   verifier-logout: yes the verifier's CLI loses its login (once)
#   verifier-crash: yes  the verifier's CLI exits 1 with no verdict, login intact
# A "login" is the absence of the file named by $FAKE_LOGOUT: while it exists every
# call, the probe included, fails like a signed-out CLI.
# and the goal steers the planner: "stuck-please" → STUCK.md.
set -eu
if [ $# -ge 1 ]; then P=$1; else P=$(cat); fi
case "$P" in "Your complete instructions are in the file "*)
  f=$(printf '%s\n' "$P" | sed -n 's/^Your complete instructions are in the file \([^ ]*\) .*/\1/p')
  case "$f" in /*) echo "fake-agent: pointer must be relative to the cwd: $f" >&2; exit 3;; esac
  P=$(cat "$f");;
esac
after() { printf '%s\n' "$P" | sed -n "s/.*$1[[:space:]]*//p" | head -1; }
has() { case "$P" in *"$1"*) return 0;; esac; return 1; }

if [ -n "${FAKE_LOGOUT:-}" ]; then
  case "$P" in
    *"the independent verifier"*)
      if has "verifier-logout: yes" && [ ! -f "$FAKE_LOGOUT.vdone" ]; then : > "$FAKE_LOGOUT.vdone"; : > "$FAKE_LOGOUT"; fi ;;
    *) if printf '%s\n' "$P" | grep -q '^logout: yes' && [ ! -f "$FAKE_LOGOUT.done" ]; then : > "$FAKE_LOGOUT.done"; : > "$FAKE_LOGOUT"; fi ;;
  esac
  if [ -f "$FAKE_LOGOUT" ]; then echo "Not logged in · Please run /login"; exit 1; fi
fi
case "$P" in
  "Reply with the single word: ok") echo ok; exit 0 ;;
esac

case "$P" in
*"the independent verifier"*)
  if has "verifier-crash: yes"; then echo "fake verifier: crashed"; exit 1; fi
  # "verifier-locks-key: <file>": the signing key locks while the verifier works (once)
  k=$(printf '%s\n' "$P" | sed -n 's/^verifier-locks-key: //p' | head -1)
  if [ -n "$k" ] && [ -f "$k" ] && [ ! -f "$k.vlocked" ]; then mv "$k" "$k.vlocked"; fi
  out=$(after 'nothing else in the repo:')
  f=$(printf '%s\n' "$P" | sed -n 's/^make: //p' | head -1)
  if [ -n "$f" ] && [ "$(cat "$f" 2>/dev/null)" = "right" ]; then
    lvl=test-verified; why="- [x] $f exists with the right content: cat $f -> right"
  else
    lvl=verifier-failed; why="- (high) $f does not hold the right content: cat $f -> $(cat "$f" 2>/dev/null || echo missing)"
  fi
  scr=$(printf '%s\n' "$P" | sed -n 's/.*go under \(.*\) only\..*/\1/p' | head -1)
  [ -n "$scr" ] && echo "evidence for $f" > "$scr/proof.log"
  printf '## Verification\n%s\n\n## Execution\n- cat %s -> %s\n\n## Findings\n%s\n\n## Notes\n- fake verifier\n' \
    "$lvl" "$f" "$(cat "$f" 2>/dev/null || echo missing)" "$why" > "$out"
  echo '{"total_cost_usd": 0.01}'
  ;;
*"the night planner"*)
  stage=$(printf '%s\n' "$P" | sed -n 's/.*as its own file in \(.*\)\/ named exactly.*/\1/p' | head -1)
  next=$(printf '%s\n' "$P" | sed -n 's/.*with ids continuing from \([^ ]*\) (.*/\1/p' | head -1)
  mkdir -p "$stage"
  if has stuck-please; then
    printf 'The goal needs a product decision: which colour.\nWould unblock: the human picks one.\n' > "$stage/STUCK.md"
    echo '{"total_cost_usd": 0.01}'; exit 0
  fi
  if [ ! -f b.txt ]; then
    cat > "$stage/$next.md" <<EOF
---
id: $next
status: waiting
owner: claude
title: add b.txt
after: []
risk: []
spike: false
verify: test
check: test -f b.txt
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
  hf=$(printf '%s\n' "$P" | sed -n 's/.*do not commit it): //p' | head -1)
  f=$(printf '%s\n' "$P" | sed -n 's/^make: //p' | head -1)
  has "tamper: yes" && echo "tampered: yes" >> "$(cat .apsolut-agents/.primary)/HEARTBEAT.md"
  echo "env: budget=${APSOLUT_CALL_BUDGET_USD:-unset} soft=${APSOLUT_SOFT_TIMEOUT_MIN:-unset} cap=${APSOLUT_CALL_MINUTES:-unset}"
  # the three ways a real CLI stops itself (shapes captured from claude, grok, agy)
  if has "budget-stop: yes"; then
    echo '{"type":"result","subtype":"error_max_budget_usd","is_error":true,"total_cost_usd":0.50}'; exit 1
  fi
  if has "cancelled: yes"; then echo '{"text":"","stopReason":"cancelled","num_turns":1}'; exit 0; fi
  if has "print-timeout: yes"; then
    echo '{"status":"ERROR","response":"","finished_reason":"print_timeout"}'; exit 3
  fi
  if has "blocked: yes"; then
    printf '## Status\nblocked\n\n## Notes\n- needs a credential nobody gave me\n' > "$hf"; exit 0
  fi
  content=right
  if has "flaky: yes" && ! has "PREVIOUS ATTEMPT FAILED"; then content=wrong; fi
  printf '%s\n' "$content" > "$f"
  printf 'test -f %s\n' "$f" > "t_$f.sh"
  has "cheat: yes" && printf 'exit 0\n' > run-tests.sh
  has "skip: yes" && printf 'it.skip("later", () => {})\n' > "skipped.test.js"
  git add -A -- ':!.apsolut-agents' && git commit -q -m "add $f"
  H=$(printf '## Status\nsuccess\n\n## Root cause\nn/a (new behaviour)\n\n## What I did\n- added %s\n\n## Verification\ntest-verified\n- sh run-tests.sh -> pass\n\n## Notes\n- fake worker made %s\n\n## Suggested follow-ups\n- (none)\n' "$f" "$f")
  if has "stdout-handoff: yes"; then
    # the way a JSON-output CLI prints it: one line, escaped newlines, in an envelope
    printf '{"type":"result","result":"%s","total_cost_usd":0.05}\n' \
      "$(printf '%s\n' "$H" | sed 's/^success$/blocked/' | awk '{printf "%s\n", $0}')"
    exit 0
  else
    printf '%s\n' "$H" > "$hf"
  fi
  has "chatty: yes" && echo "tests: HTTP 429 rate limit exceeded / 500 Internal Server Error (expected in this suite)"
  echo '{"total_cost_usd": 0.05}'
  ;;
*) echo "fake-agent: unknown role" >&2; exit 3 ;;
esac
