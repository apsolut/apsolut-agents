#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 Aleksandar Perisic (apsolut) — https://github.com/apsolut/apsolut-agents
# doctor.sh [agent ...] — preflight the workspace before trusting it with a night.
# Free checks always run: tools, HEARTBEAT sanity, card contract + after: graph,
# claims, green_cmd on the primary, rolling cost vs budget. Naming agents also
# live-probes each one's CLI (one tiny round per agent — costs a fraction of a cent).
# Everything the babysitter checked by hand, in one command (field report 2026-08-11).
# Exit 0 = no failures (warnings allowed), 1 = at least one FAIL.
set -eu

WS=$(cd "$(dirname "$0")/.." && pwd)
if [ -f "$WS/.primary" ]; then
  echo "error: run from the primary worktree ($(cat "$WS/.primary"))" >&2; exit 1
fi
HB="$WS/HEARTBEAT.md"
REPO=$(git -C "$WS" rev-parse --show-toplevel)
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

PASS=0; WARN=0; FAIL=0
# colour for a terminal only: off when piped or NO_COLOR is set, forced by CLICOLOR_FORCE=1
if [ -n "${NO_COLOR:-}" ]; then COLOR=no
elif [ "${CLICOLOR_FORCE:-0}" = 1 ] || [ -t 1 ]; then COLOR=yes
else COLOR=no; fi
if [ "$COLOR" = yes ]; then E=$(printf '\033'); CG="${E}[32m"; CY="${E}[33m"; CR="${E}[31m"; CC="${E}[36m"; CO="${E}[0m"
else CG=""; CY=""; CR=""; CC=""; CO=""; fi
ok()   { PASS=$((PASS+1)); printf '  %sok%s    %s\n' "$CG" "$CO" "$1"; }
warn() { WARN=$((WARN+1)); printf '  %sWARN%s  %s\n' "$CY" "$CO" "$1"; }
note() { printf '  %snote%s  %s
' "$CC" "$CO" "$1"; }   # a tip: not counted
fail() { FAIL=$((FAIL+1)); printf '  %sFAIL%s  %s\n' "$CR" "$CO" "$1"; }

cfg() { [ -f "$HB" ] && sed -n "s/^$1:[[:space:]]*//p" "$HB" | head -1 | tr -d '\r' || true; }
num_or() { case "$1" in ''|*[!0-9.]*|*.*.*) echo "$2";; *) echo "$1";; esac; }
fm_get() { awk -v k="$2" 'NR==1&&$0~/^---\r?$/{f=1;next} f&&$0~/^---\r?$/{exit}
  f&&index($0,k":")==1{sub("^" k ":[ \t]*","");sub("[ \t]*#.*$","");sub(/\r$/,"");print;exit}' "$1"; }
fm_list() { # $1=file $2=key — items of a frontmatter block list ("key:" then "- item" lines)
  awk -v k="$2" 'NR==1&&$0~/^---\r?$/{f=1;next} f&&$0~/^---\r?$/{exit}
    f&&index($0,k":")==1{l=1;next}
    l&&/^[ \t]*-[ \t]/{sub(/^[ \t]*-[ \t]*/,"");sub(/[ \t]*#.*$/,"");sub(/\r$/,"");print;next}
    l&&/^[A-Za-z_]/{l=0}' "$1"; }

echo "doctor — $WS"

# --- tools -------------------------------------------------------------------------
echo "[tools]"
for t in git curl awk sed grep mktemp timeout; do
  command -v "$t" >/dev/null 2>&1 && ok "$t" || fail "$t not found in PATH"
done
# runner.sh needs GNU timeout (-k, exit 124); Windows TIMEOUT.EXE first on PATH
# makes every call fail in milliseconds
timeout -k 1 5 true >/dev/null 2>&1 || fail "timeout is not GNU coreutils timeout ($(command -v timeout)) — put Git Bash/coreutils first on PATH" 

# --- heartbeat ---------------------------------------------------------------------
echo "[heartbeat]"
GREEN=""; CAPS=off
if [ ! -f "$HB" ]; then
  warn "no HEARTBEAT.md — nights/delegation (Tier 2) unavailable"
else
  GREEN=$(cfg green_cmd)
  case "$GREEN" in
    ''|*"SET green_cmd"*) fail "green_cmd unset — runner.sh refuses to start nights"; GREEN="";;
    *) ok "green_cmd set";;
  esac
  CMDS=$(sed -n 's/^cmd_\([A-Za-z0-9_]*\):.*/\1/p' "$HB" | tr '\n' ' ')
  [ -n "$CMDS" ] && ok "agent commands: $CMDS" || warn "no cmd_<agent>: lines — nothing can be dispatched"
  # claude --bare ignores the signed-in claude.ai session (OAuth and keychain).
  # A runner or delegate then exits "Not logged in" while an interactive terminal
  # on the same account is signed in. Headless -p / exec does not need --bare.
  bare_hit=$(grep -n '^cmd_.*--bare' "$HB" || true)
  if [ -n "$bare_hit" ]; then
    fail "a cmd_ line contains --bare — that drops the signed-in account when one agent calls another"
    printf '%s\n' "$bare_hit" | sed 's/^/        /'
  fi
  # A flag that takes a list (claude --disallowedTools/--allowedTools/--tools/
  # --add-dir/--mcp-config) swallows whatever follows it. In arg mode the prompt is
  # appended last, so such a flag at the end of the line eats the prompt.
  for a in $CMDS; do
    [ "$(cfg "prompt_$a")" = stdin ] && continue
    lastflag=$(cfg "cmd_$a" | tr ' ' '\n' | grep '^--' | command tail -1)
    lastword=$(cfg "cmd_$a" | awk '{print $NF}')
    case "$lastflag" in --disallowedTools|--disallowed-tools|--allowedTools|--allowed-tools|--tools|--add-dir|--mcp-config)
      case "$lastword" in --*) ;; *)
        fail "cmd_$a ends with $lastflag <list> — it would swallow the prompt; move it before another flag or set prompt_$a: stdin";;
      esac ;;
    esac
  done
  # spend caps are optional and off by default: on when one of the three keys is a
  # number above zero
  for k in night_budget_usd delegate_budget_usd call_budget_usd; do
    if awk -v b="$(num_or "$(cfg "$k")" 0)" 'BEGIN{exit !(b+0 > 0)}'; then CAPS=on; fi
  done
  # HEARTBEAT.md is yours and no upgrade rewrites it, so an older cmd_ line keeps
  # running without the caps newer CLIs need. Judged by the binary, not the lane name.
  for a in $CMDS; do
    cl=$(cfg "cmd_$a")
    # the binary is the first word that is not a VAR=value prefix
    case "$(printf '%s\n' "$cl" | tr ' ' '\n' | grep -vE '^[A-Za-z_][A-Za-z0-9_]*=' | head -1)" in
      claude)
        case "$cl" in *--disallowedTools*|*--disallowed-tools*) ;; *) warn "cmd_$a: no --disallowedTools Agent,Task — claude can spawn its own subagents, outside the card clock and the spend ledger";; esac
        # only a workspace with a spend cap needs the per-call flag
        if [ "$CAPS" = on ]; then
          case "$cl" in *--max-budget-usd*) ;; *) warn "cmd_$a: no --max-budget-usd \$APSOLUT_CALL_BUDGET_USD — a spend cap is set, and one card can overshoot it";; esac
        fi
        case "$cl" in *--strict-mcp-config*) ok "cmd_$a: locked down (--strict-mcp-config): the worker cannot reach the account's MCP servers and connectors" ;; *) note "cmd_$a: full access — the worker can use your account's MCP servers and connectors. To lock a night down, add --strict-mcp-config (see HEARTBEAT.md)";; esac ;;
      grok)
        case "$cl" in *--no-subagents*) ;; *) warn "cmd_$a: no --no-subagents — grok starts background subagents the runner neither waits for nor charges";; esac
        case "$cl" in *GROK_CLAUDE_MCPS_ENABLED=0*) ;; *) warn "cmd_$a: grok loads your Claude Code MCP servers, hooks and skills by default — put GROK_CLAUDE_MCPS_ENABLED=0 GROK_CLAUDE_HOOKS_ENABLED=0 (see template/HEARTBEAT.md) in front of the command";; esac ;;
      agy)
        case "$cl" in *--print-timeout*) ;; *) warn "cmd_$a: no --print-timeout \${APSOLUT_SOFT_TIMEOUT_MIN}m — a headless agy waits for its background tasks until the hard timeout kills it";; esac ;;
      codex)
        case "$cl" in *multi_agent*) ;; *) warn "cmd_$a: no --disable multi_agent — codex can spawn its own subagents";; esac ;;
    esac
  done
  # a cmd_ line can use the three values the scripts export (see HEARTBEAT.md)
  unk=$(grep '^cmd_' "$HB" | grep -o 'APSOLUT_[A-Z_]*' | sort -u | grep -vxE 'APSOLUT_(CALL_MINUTES|SOFT_TIMEOUT_MIN|CALL_BUDGET_USD|AGENT_DEPTH)' | tr '\n' ' ' || true)
  [ -z "$unk" ] || fail "a cmd_ line uses an unknown variable: $unk"
  for k in card_timeout_minutes max_attempts_per_card max_consecutive_failures_lane \
           night_budget_usd cost_fallback_usd idle_poll_seconds stale_claim_minutes \
           delegate_max_depth delegate_max_concurrent delegate_max_rounds \
           delegate_timeout_minutes delegate_budget_usd; do
    v=$(cfg "$k"); [ -n "$v" ] || continue
    [ "$(num_or "$v" X)" = X ] && fail "$k: '$v' not numeric (inline comment on the key line?)" || ok "$k: $v"
  done
  NTFY=$(cfg notify_url)
  if [ -n "$NTFY" ]; then
    curl -fsI -m 10 "$NTFY" >/dev/null 2>&1 && ok "notify_url reachable" || warn "notify_url set but not reachable"
  else
    warn "notify_url empty — nights run silent (log-only)"
  fi
fi

# --- goal loop (v0.9): roles, prompts, GOAL.md contract, Andon ---------------------
echo "[goal loop]"
GOALF="$WS/GOAL.md"; DONE_CMD=""
gcfg() { [ -f "$GOALF" ] && sed -n "s/^$1:[[:space:]]*//p" "$GOALF" | head -1 | tr -d '\r' || true; }
if [ -f "$WS/ANDON" ]; then
  fail "ANDON raised — every lane refuses to claim: $(sed -n 's/^reason: //p' "$WS/ANDON") (human: sh scripts/andon.sh clear)"
else
  ok "no Andon raised"
fi
for p in worker verifier planner advisor review; do
  [ -f "$WS/prompts/$p.md" ] || fail "prompts/$p.md missing — runner.sh refuses to start (run scripts/upgrade.sh)"
done
[ -f "$WS/prompts/worker.md" ] && ok "role prompts present (prompts/)"
if [ -f "$HB" ]; then
  for role in verifier_agent risk_verifier_agent advisor_agent review_agent; do
    a=$(cfg "$role"); [ -n "$a" ] || continue
    [ -n "$(cfg "cmd_$a")" ] && ok "$role: $a" || fail "$role: $a has no cmd_$a line — the runner refuses to start"
  done
  VA=$(cfg verifier_agent)
  [ -z "$VA" ] && warn "verifier_agent empty — green_cmd and each card's check: are the only gates; in goal mode a card without check: never integrates"
  for a in $CMDS; do
    [ -n "$VA" ] && [ "$a" = "$VA" ] && warn "verifier_agent '$VA' is also a worker lane — a lane it runs gets judged by its own model; prefer a different family"
  done
  # A judge weaker than the author rejects work it does not follow, and each wrong
  # rejection is a paid retry. Read from the cmd_ lines: a small-model name on the
  # verifier's line while another lane runs without one.
  SMALL='(^|[^[:alnum:]])(haiku|mini|nano|flash|lite|fast|small)([^[:alnum:]]|$)'
  strong=""
  for a in $CMDS; do
    cfg "cmd_$a" | grep -qiE "$SMALL" || strong="$strong$a "
  done
  for role in verifier_agent risk_verifier_agent; do
    a=$(cfg "$role"); [ -n "$a" ] || continue
    sm=$(cfg "cmd_$a" | grep -oiE "$SMALL" | head -1 | tr -cd '[:alnum:]' || true)
    [ -n "$sm" ] || continue
    others=$(printf '%s' "$strong" | tr ' ' '\n' | grep -vx "$a" | tr '\n' ' ' | sed 's/ *$//' || true)
    [ -z "$others" ] || warn "$role '$a' runs a small model ($sm) while $others does not — a verifier weaker than the worker rejects good work, and every wrong rejection is a paid retry"
  done
  # risk routing
  RT=$(cfg risk_tags | tr ',[]' '   ' | tr -s ' ' | sed 's/^ //; s/ $//'); RVA=$(cfg risk_verifier_agent)
  if [ -n "$RT" ]; then
    ok "risk_tags: $RT → judged by ${RVA:-${VA:-nobody}}"
    [ -n "$VA$RVA" ] || warn "risk_tags set but no verifier — in goal mode a card carrying one of them never integrates; it waits for you"
  elif [ -n "$RVA" ]; then
    warn "risk_verifier_agent set but risk_tags is empty — no card is ever routed to it"
  fi
fi
DONE_CMD=$(gcfg done_cmd)
if [ -z "$DONE_CMD" ]; then
  ok "GOAL.md done_cmd empty — plain board mode (the night ends when the board is empty)"
else
  ok "goal mode: done_cmd = $DONE_CMD"
  [ -n "$(gcfg goal)" ] || warn "GOAL.md goal: is empty — planner and workers get no one-line goal"
  for k in max_plan_rounds max_cards_per_round; do
    v=$(gcfg "$k"); [ -n "$v" ] || continue
    [ "$(num_or "$v" X)" = X ] && fail "GOAL.md $k: '$v' not numeric" || ok "GOAL.md $k: $v"
  done
  case "$(gcfg verify_level)" in ''|live|test|typecheck) ;; *) fail "GOAL.md verify_level: must be live, test or typecheck";; esac
  pa=$(gcfg planner_agent)
  [ -z "$pa" ] || [ -n "$(cfg "cmd_$pa")" ] || fail "GOAL.md planner_agent: $pa has no cmd_$pa line in HEARTBEAT.md"
  case "$DONE_CMD" in *sleep*|*"for "*h*) warn "done_cmd looks like a duration — it must be a predicate that can fail";; esac
  PROT="$(cfg protect) $(gcfg protect)"
  if [ -z "$(printf '%s' "$PROT" | tr -d ' ,')" ]; then
    warn "no protect: paths — a card can edit the predicate's tests or the green script and still integrate. List them in GOAL.md protect:"
  else
    ok "protected paths: $PROT"
  fi
  # the predicate runs in a worktree of tracked files, like green_cmd: prove it RUNS
  # there (red is expected before the night; "command not found" is not)
  DW="$TMPD/done-wt"
  if git -C "$REPO" worktree add -q --detach "$DW" HEAD >/dev/null 2>&1; then
    drc=0; ( cd "$DW" && timeout 600 sh -c "$DONE_CMD" ) > "$TMPD/done.out" 2>&1 || drc=$?
    case "$drc" in
      0) fail "done_cmd already PASSES on HEAD — the night would end at the first empty board with nothing done";;
      126|127) fail "done_cmd cannot run in a pristine worktree (exit $drc) — untracked script or missing tool?"
               command tail -5 "$TMPD/done.out" | sed 's/^/        /';;
      *) ok "done_cmd runs in a pristine worktree and is red now (exit $drc) — something to drive toward";;
    esac
    git -C "$REPO" worktree remove --force "$DW" >/dev/null 2>&1 || true
  else
    warn "could not create a temp worktree to test done_cmd"
  fi
fi

# --- cards: filename contract, statuses, test-first, after: graph ------------------
echo "[cards]"
IDS=" "
: > "$TMPD/edges"
if [ ! -d "$WS/work" ]; then
  warn "no work/ dir — card checks skipped"
else
  NCARDS=0
  for f in "$WS"/work/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in _TEMPLATE.md) continue;; esac
    NCARDS=$((NCARDS+1))
    i=$(fm_get "$f" id)
    if [ -z "$i" ]; then fail "work/$(basename "$f"): no id: in frontmatter"; continue; fi
    if [ "$(basename "$f")" = "$i.md" ]; then ok "work/$i.md"
    else fail "work/$(basename "$f") declares id: $i — rename the file to $i.md"; fi
    IDS="$IDS$i "
    st=$(fm_get "$f" status)
    case "$st" in waiting|writing|need-feedback|review|done|hold|blocked|abandoned) ;;
      *) warn "$i: unknown status '$st'";; esac
    for k in status owner branch worktree updated; do
      grep -q "^$k:" "$f" || warn "$i: frontmatter missing '$k:' — hand-written card? copy work/_TEMPLATE.md so scripts can record into it"
    done
    if [ -z "$(fm_get "$f" check)" ] && [ "$(fm_get "$f" spike)" != "true" ] && ! grep -qiwE 'tests?|specs?' "$f"; then
      warn "$i: no check:, names no test and spike is not true — the night runner will refuse it (PLAYBOOK §2)"
    fi
    # a worktree contains only TRACKED files: an untracked/gitignored card input is
    # invisible to the agent (field incident 2026-08-11 — lane spawned without inputs)
    for p in $(fm_list "$f" files); do
      case "$p" in "<path/to/file>"|"") continue;; esac
      if [ -e "$REPO/$p" ] && ! git -C "$REPO" ls-files --error-unmatch "$p" >/dev/null 2>&1; then
        warn "$i: files: '$p' exists but is UNTRACKED/gitignored — worktrees contain only tracked files; the agent will not see it"
      fi
    done
    for d in $(fm_get "$f" after | tr -d '[]' | tr ',' ' '); do
      printf '%s %s\n' "$i" "$d" >> "$TMPD/edges"
    done
  done
  [ "$NCARDS" -eq 0 ] && ok "no cards on the board"
  # missing deps + overnight reachability
  while read -r id dep; do
    case "$IDS" in
      *" $dep "*)
        dst=$(fm_get "$WS/work/$dep.md" status)
        if [ "$dst" != "done" ]; then
          if [ -n "$DONE_CMD" ]; then ok "$id waits on $dep — goal mode: clears when $dep integrates onto the night branch"
          else warn "$id waits on $dep (status: ${dst:-?}) — after: clears only on MERGE, unreachable overnight"; fi
        fi
        ;;
      *) fail "$id: after: names '$dep' but work/$dep.md does not exist";;
    esac
  done < "$TMPD/edges"
  # cycles: fixpoint — resolve cards whose existing deps are all resolved
  printf '%s\n' $IDS > "$TMPD/pending"
  : > "$TMPD/resolved"
  CH=1
  while [ "$CH" = 1 ]; do
    CH=0; : > "$TMPD/pending2"
    while read -r id; do
      [ -n "$id" ] || continue
      blocked=no
      while read -r e d; do
        [ "$e" = "$id" ] || continue
        grep -qx "$d" "$TMPD/resolved" && continue
        grep -qx "$d" "$TMPD/pending" || continue
        blocked=yes
      done < "$TMPD/edges"
      if [ "$blocked" = no ]; then echo "$id" >> "$TMPD/resolved"; CH=1
      else echo "$id" >> "$TMPD/pending2"; fi
    done < "$TMPD/pending"
    mv "$TMPD/pending2" "$TMPD/pending"
  done
  if [ -s "$TMPD/pending" ]; then
    fail "after: graph has a cycle involving: $(tr '\n' ' ' < "$TMPD/pending")"
  fi
fi

# --- claims ------------------------------------------------------------------------
echo "[claims]"
FOUND=no
for c in "$WS"/claims/*/; do
  [ -d "$c" ] || continue
  id=$(basename "$c")
  pid=$(cat "$c/pid" 2>/dev/null || echo "")
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    ok "claim $id: live (pid $pid)"
  else
    warn "claim $id: pid ${pid:-none} is dead — stale (runner boot recovery will release it)"
  fi
  FOUND=yes
done
[ "$FOUND" = no ] && ok "no active claims"

# --- green on the primary ----------------------------------------------------------
echo "[green]"
if [ -n "$GREEN" ]; then
  T0=$(date +%s)
  if ( cd "$REPO" && sh -c "$GREEN" ) > "$TMPD/green.out" 2>&1; then
    ok "green_cmd passed on primary in $(( $(date +%s) - T0 ))s @ $(git -C "$REPO" rev-parse --short HEAD)"
  else
    fail "green_cmd FAILED on the primary checkout — a night would block every card. Tail:"
    command tail -5 "$TMPD/green.out" | sed 's/^/        /'
  fi
  # the runner executes green_cmd with cwd = the card's WORKTREE, which contains only
  # tracked files — a green that passes on the primary but relies on untracked helpers
  # or primary-only paths fails on every lane and reads as the cards failing (field
  # incident 2026-08-11: cost 3 cards). Prove it in a real throwaway worktree.
  DWT="$TMPD/wt-doctor"
  if git -C "$REPO" worktree add --detach "$DWT" >/dev/null 2>&1; then
    SETUP=$(cfg setup_cmd)
    if [ -n "$SETUP" ]; then
      if ( cd "$DWT" && sh -c "$SETUP" ) > "$TMPD/setup-wt.out" 2>&1; then
        if [ -n "$(git -C "$DWT" status --porcelain -uno)" ]; then
          fail "setup_cmd changed TRACKED files in a pristine worktree (a lockfile rewrite?) — the runner refuses that as a harness failure"
        else ok "setup_cmd bootstraps a pristine worktree"; fi
      else fail "setup_cmd FAILED in a pristine worktree — every card would stop the night as a harness failure. Tail:"
           command tail -5 "$TMPD/setup-wt.out" | sed 's/^/        /'; fi
    fi
    if ( cd "$DWT" && sh -c "$GREEN" ) > "$TMPD/green-wt.out" 2>&1; then
      ok "green_cmd passed in a PRISTINE worktree (tracked files only)"
    else
      fail "green_cmd FAILED in a pristine worktree while cards run exactly there — it likely relies on untracked files or primary-only paths. Tail:"
      command tail -5 "$TMPD/green-wt.out" | sed 's/^/        /'
    fi
    git -C "$REPO" worktree remove --force "$DWT" >/dev/null 2>&1 || true
    git -C "$REPO" worktree prune >/dev/null 2>&1 || true
  else
    warn "could not create a temp worktree to test green_cmd where cards actually run"
  fi
else
  warn "green check skipped (green_cmd unset)"
fi

# --- rolling cost vs budget --------------------------------------------------------
echo "[unattended]"
# what a night cannot answer: a signing prompt, a login prompt
if [ "$(git -C "$REPO" config --bool commit.gpgsign 2>/dev/null || true)" = true ]; then
  sgo=$(mktemp)
  if sgt=$(git -C "$REPO" rev-parse 'HEAD^{tree}' 2>/dev/null) && \
     timeout -k 5 30 git -C "$REPO" commit-tree -S "$sgt" -p HEAD -m "apsolut-agents: signing probe" < /dev/null > /dev/null 2> "$sgo"; then
    ok "commits can be signed without a prompt (the runner checks again before every card)"
  else
    fail "a signed commit failed or waited for approval: $(grep -v '^$' "$sgo" | head -1 | cut -c1-120) — unlock the signing key or its agent; a night parks until it answers"
  fi
  rm -f "$sgo"
else
  ok "commit signing is off for this repo: no key to unlock"
fi
hw=$(cfg human_wait_minutes); ok "human_wait_minutes: ${hw:-60 (default)} — how long a parked lane waits for a key or a login to come back"
if command -v gh >/dev/null 2>&1; then
  if GH_PROMPT_DISABLED=1 gh auth status >/dev/null 2>&1; then ok "gh is signed in (intake.sh can read issues)"
  else warn "gh is not signed in — intake.sh will fail; workers and the runner do not need gh"; fi
fi

echo "[costs]"
# night_budget_usd empty, absent or 0 = no cap (the default)
BUDGET=$(num_or "$(cfg night_budget_usd)" 0)
if awk -v b="$BUDGET" 'BEGIN{exit !(b+0 > 0)}'; then NIGHT_CAP=on; else NIGHT_CAP=off; fi
FB=$(num_or "$(cfg cost_fallback_usd)" 2)
TOTAL=0; DAYS=0
for s in "$WS"/runs/.spend-*; do
  [ -f "$s" ] || continue
  TOTAL=$(awk "BEGIN{printf \"%.2f\", $TOTAL + $(num_or "$(cat "$s" 2>/dev/null || echo 0)" 0)}")
  DAYS=$((DAYS+1))
done
ATTEMPTS=$(ls "$WS"/runs/*-attempt*.out 2>/dev/null | grep -c . || true)
if [ "${ATTEMPTS:-0}" -gt 0 ] && [ "$DAYS" -gt 0 ]; then
  AVG=$(awk "BEGIN{printf \"%.2f\", $TOTAL / $ATTEMPTS}")
  if [ "$NIGHT_CAP" = on ]; then
    PER=$(awk "BEGIN{printf \"%.0f\", ($AVG > 0) ? $BUDGET / $AVG : 0}")
    ok "rolling avg \$$AVG/attempt ($ATTEMPTS attempts over $DAYS day(s)) — budget \$$BUDGET ≈ $PER attempts/night"
    awk "BEGIN{exit !($AVG > $FB * 2)}" && warn "avg \$$AVG is >2x cost_fallback_usd (\$$FB) — raise the fallback or budgets overshoot when cost output is missing"
  else
    ok "rolling avg \$$AVG/attempt ($ATTEMPTS attempts over $DAYS day(s))"
  fi
elif [ "$NIGHT_CAP" = on ]; then
  warn "no spend history yet — budgeting flies on cost_fallback_usd (\$$FB/card) until real cost data exists"
fi
# the cap is a choice, not a fault: say which way it is set, uncounted
if [ "$NIGHT_CAP" = off ]; then
  note "no night spend cap (night_budget_usd is empty or 0, the default): a night ends on stop_time, the breaker or an empty board. Paying per call? Set night_budget_usd in HEARTBEAT.md"
fi

# --- optional live probes ----------------------------------------------------------
if [ $# -gt 0 ]; then
  echo "[probe]"
  for AG in "$@"; do
    CMD=$(cfg "cmd_$AG")
    if [ -z "$CMD" ]; then fail "$AG: no cmd_$AG: in HEARTBEAT.md"; continue; fi
    PD=$(mktemp -d)
    # the values runner.sh and delegate.sh export to a cmd_ line
    APSOLUT_CALL_MINUTES=3; APSOLUT_SOFT_TIMEOUT_MIN=2; APSOLUT_CALL_BUDGET_USD=1.00
    export APSOLUT_CALL_MINUTES APSOLUT_SOFT_TIMEOUT_MIN APSOLUT_CALL_BUDGET_USD
    if [ "$(cfg "prompt_$AG")" = stdin ]; then
      PCMD() { printf 'Reply with the single word: ok\n' | timeout -k 10 180 sh -c "$CMD"; }
    else
      PCMD() { timeout -k 10 180 sh -c "$CMD \"\$1\"" doctor "Reply with the single word: ok" < /dev/null; }
    fi
    if OUTP=$( cd "$PD" && PCMD 2>&1 ); then
      rm -rf "$PD"
      if printf '%s' "$OUTP" | grep -q '"is_error"[[:space:]]*:[[:space:]]*true'; then
        fail "$AG: CLI answered but is_error:true (refusal/infra?) — a lane would burn the board"
      elif printf '%s' "$OUTP" | grep -qE '"stopReason"[[:space:]]*:[[:space:]]*"cancelled"|"denied_actions"[[:space:]]*:[[:space:]]*\[\{'; then
        fail "$AG: CLI exited 0 but ended the turn early (cancelled, or a tool was denied) — its permission flags do not cover headless runs"
      else
        case "$OUTP" in *[Oo][Kk]*) ok "$AG: CLI answered";; *) warn "$AG: answered but no 'ok' in reply";; esac
      fi
    else
      rm -rf "$PD"
      fail "$AG: probe exited non-zero — runner.sh would refuse this lane"
      printf '%s\n' "$OUTP" | command tail -3 | sed 's/^/        /'
    fi
  done
else
  echo "[probe]"
  echo "  (skipped — name agents to live-probe them: doctor.sh claude grok)"
fi

echo
echo "doctor: $PASS ok, $WARN warn, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
