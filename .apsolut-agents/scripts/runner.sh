#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 Aleksandar Perisic (apsolut) — https://github.com/apsolut/apsolut-agents
# runner.sh <agent> [--once|--drain] — Night Shift: overnight task runner, one lane per agent.
#   --once   one card through the whole pipeline, then stop (the supervised v0 gate)
#   --drain  work until the board is empty (or the goal is met), then stop; no idle wait
# Rule-based control only. The default branch never moves overnight, kill is
# terminal, and a claim is a mkdir mutex plus a card rewrite. Provider errors back
# off instead of tripping the breaker. See NIGHTSHIFT.md.
# v0.9 goal loop: with GOAL.md done_cmd set, cards whose verification passes
# integrate onto one night branch. When the board is empty, the runner checks the
# predicate there and a planner writes the next cards, until the predicate passes.
# Role prompts live in prompts/*.md. Every decision goes to runs/trail-<date>.tsv.
set -eu

# Nothing in a night may sit at a prompt nobody will answer. A git credential
# prompt, a credential-manager window or a gh login prompt fails at once instead,
# for every worker, role and check this runner starts.
GIT_TERMINAL_PROMPT=0; GCM_INTERACTIVE=never; GH_PROMPT_DISABLED=1
export GIT_TERMINAL_PROMPT GCM_INTERACTIVE GH_PROMPT_DISABLED

AGENT=${1:?usage: runner.sh <agent> [--once|--drain]}
ONCE=no; DRAIN=no
case "${2:-}" in
  --once) ONCE=yes; DRAIN=yes ;;
  --drain) DRAIN=yes ;;
  "") ;;
  *) echo "usage: runner.sh <agent> [--once|--drain]" >&2; exit 1 ;;
esac
DID_ONE=no

WS=$(cd "$(dirname "$0")/.." && pwd)
if [ -f "$WS/.primary" ]; then
  echo "error: run from the primary worktree" >&2; exit 1
fi
REPO=$(git -C "$WS" rev-parse --show-toplevel)
HB="$WS/HEARTBEAT.md"; LOG="$WS/agent-log.md"; GOALF="$WS/GOAL.md"
mkdir -p "$WS/claims" "$WS/runs"
# The night's identity outlives a crash: a runner restarted after midnight keeps the
# night that is still open (same branch, same spend ledger, same round count) instead
# of opening a fresh night from the default branch. finish() closes it.
# File format: "<date> <start epoch>". The age counts from the night's START, not the
# last launch, and finish() removes the file once no other lane is still running.
NIGHTF="$WS/runs/.night-current"
DATE=$(date +%Y-%m-%d); NOW=$(date +%s); REUSED=no
if [ -f "$NIGHTF" ]; then
  nd=$(awk 'NR==1{print $1}' "$NIGHTF" | tr -d '\r'); ne=$(awk 'NR==1{print $2}' "$NIGHTF" | tr -d '\r')
  case "$ne" in ''|*[!0-9]*) ne=0;; esac
  case "$nd" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    [ $(( NOW - ne )) -lt 64800 ] && { DATE=$nd; REUSED=yes; } ;;
  esac
fi
# a new night starts with no lane results; a lane joining an open night keeps the others'
[ "$REUSED" = yes ] || { echo "$DATE $NOW" > "$NIGHTF"; rm -f "$WS/runs/.lane-end-$DATE-"*; }
REPORT="$WS/runs/night-$DATE.md"; SPENDF="$WS/runs/.spend-$DATE"
# written before a merge into the night branch, removed once the merge is rolled back
# or the card is marked integrated: "<night branch> <tip before the merge> <card id>"
INTEGJ="$WS/runs/.integrating-$DATE"
HO="$WS/runs/handoffs"; EVD="$WS/runs/evidence"
mkdir -p "$HO" "$EVD"
# Role output is written INSIDE the worktree (a sandboxed CLI may not be able to
# write anywhere else) under this git-excluded folder, then copied into runs/.
OUTD=.apsolut-out

cfg() { sed -n "s/^$1:[[:space:]]*//p" "$HB" | head -1 | tr -d '\r'; }
gcfg() { if [ -f "$GOALF" ]; then sed -n "s/^$1:[[:space:]]*//p" "$GOALF" | head -1 | tr -d '\r'; fi; }
fm_get() { awk -v k="$2" 'NR==1&&$0~/^---\r?$/{f=1;next} f&&$0~/^---\r?$/{exit}
  f&&index($0,k":")==1{sub("^" k ":[ \t]*","");sub("[ \t]*#.*$","");sub(/\r$/,"");print;exit}' "$1"; }
fm_set() { awk -v k="$2" -v v="$3" 'NR==1&&$0~/^---\r?$/{f=1;print;next}
  f&&$0~/^---\r?$/{if(!done)print k": "v;f=0;print;next}
  f&&index($0,k":")==1{print k": "v;done=1;next}{print}' \
  "$1" > "$1.tmp.$$" && mv -f "$1.tmp.$$" "$1"; }
num_or() { case "$1" in ''|*[!0-9.]*|*.*.*) echo "$2";; *) echo "$1";; esac; }
# a time limit must be a whole number above zero: `timeout 0` means "no limit", and
# nobody who wrote 0 meant a call that may run forever
pos_int_or() { case "$1" in ''|*[!0-9]*) echo "$2";; *) if [ "$1" -gt 0 ]; then echo "$1"; else echo "$2"; fi;; esac; }

TIMEOUT_MIN=$(pos_int_or "$(cfg card_timeout_minutes)" 45)
HELPER_MIN=$(pos_int_or "$(cfg helper_timeout_minutes)" 20)
MAX_ATTEMPTS=$(num_or "$(cfg max_attempts_per_card)" 2)
MAX_FAILS=$(num_or "$(cfg max_consecutive_failures_lane)" 3)
# waiting on a human (v0.13): how long a parked lane waits for a signing key or a
# CLI login to come back, and how often it looks. 0 minutes = end the lane at once.
HUMAN_WAIT=$(num_or "$(cfg human_wait_minutes)" 60); HUMAN_WAIT=${HUMAN_WAIT%%.*}
PARK_POLL=$(num_or "$(cfg park_poll_seconds)" 300); PARK_POLL=${PARK_POLL%%.*}
[ "${PARK_POLL:-0}" -ge 1 ] || PARK_POLL=1
# the spend cap is optional and off by default: night_budget_usd empty, absent or 0 =
# no cap. A number above zero is a hard stop, checked between cards.
BUDGET=$(num_or "$(cfg night_budget_usd)" "$(num_or "$(cfg night_budget)" 0)")
# what $APSOLUT_CALL_BUDGET_USD holds when nothing caps a call: a cmd_ line that
# passes it on (claude --max-budget-usd) needs a number, and this one is never reached
NO_CAP_USD=1000000
FALLBACK_COST=$(num_or "$(cfg cost_fallback_usd)" 2)
STOP=$(cfg stop_time | tr -d ':'); STOP=${STOP:-0700}
POLL=$(num_or "$(cfg idle_poll_seconds)" 300)
STALE_MIN=$(num_or "$(cfg stale_claim_minutes)" "$(num_or "$(cfg stall_claim_minutes)" 5)")
GREEN=$(cfg green_cmd)
NTFY=$(cfg notify_url)
CMD=$(cfg "cmd_$AGENT")
VERIFIER=$(cfg verifier_agent); ADVISOR=$(cfg advisor_agent); REVIEWER=$(cfg review_agent)
VERIFY_LEVEL=$(cfg verify_level); VERIFY_LEVEL=${VERIFY_LEVEL:-test}
# risk routing: a card whose risk: list holds one of risk_tags is judged by
# risk_verifier_agent (else verifier_agent), and in goal mode it never integrates on
# its check: alone. Empty risk_tags = off.
RISK_TAGS=$(cfg risk_tags | tr ',[]' '   '); RISK_VERIFIER=$(cfg risk_verifier_agent)
CHECK_MIN=$(pos_int_or "$(cfg check_timeout_minutes)" 30)
# the runner's own commits and merges are signed: a signing program that waits for a
# human (a locked key manager) must not hold the lane for ever
GIT_MAX=$(pos_int_or "$(cfg git_timeout_seconds)" 300)
SETUP=$(cfg setup_cmd)
PER_MIN=$(num_or "$(cfg cost_per_minute_usd)" 0.15)
MAX_BACKOFF=$(num_or "$(cfg max_backoffs_per_card)" 3)
ARG_MAX_B=$(num_or "$(cfg prompt_arg_max_bytes)" 6000)
CALL_BUDGET=$(num_or "$(cfg call_budget_usd)" 0)
# added lines matching this ERE turn an attempt red (symptom patches). Empty = off.
if grep -q '^forbid_added:' "$HB"; then FORBID=$(cfg forbid_added)
else FORBID='\.skip\(|\.only\(|(^|[^[:alnum:]_])x(it|describe)\(|@ts-ignore|@ts-nocheck|eslint-disable'; fi
[ -n "$CMD" ] || { echo "error: no cmd_$AGENT in HEARTBEAT.md" >&2; exit 1; }
# GNU timeout is load-bearing (-k, exit 124). Windows' TIMEOUT.EXE earlier on PATH
# would make every call fail in milliseconds and read as red cards.
timeout -k 1 5 true >/dev/null 2>&1 || {
  echo "error: 'timeout' is not GNU coreutils timeout ($(command -v timeout)) — fix PATH" >&2; exit 1; }
case "$GREEN" in ''|*"SET green_cmd"*)
  echo "error: green_cmd in HEARTBEAT.md is unset — define what green means before running nights" >&2; exit 1;;
esac

# --- goal loop config (GOAL.md; absent or empty done_cmd = plain board mode) -------
DONE_CMD=$(gcfg done_cmd)
GOAL_MODE=no; [ -n "$DONE_CMD" ] && GOAL_MODE=yes
if [ "$GOAL_MODE" = yes ]; then
  v=$(gcfg verify_level); [ -n "$v" ] && VERIFY_LEVEL=$v
fi
MAX_ROUNDS=$(num_or "$(gcfg max_plan_rounds)" 4)
MAX_CARDS=$(num_or "$(gcfg max_cards_per_round)" 5)
PLANNER=$(gcfg planner_agent); PLANNER=${PLANNER:-$AGENT}
# protect: git pathspecs no card may change (the judge: the predicate's script, the
# acceptance tests, the green script, CI config). HEARTBEAT applies to every night,
# GOAL.md adds goal-specific ones. A card diff touching one is red.
PROTECT=$(printf '%s %s' "$(cfg protect)" "$(gcfg protect)" | tr ',\t' '  ' | tr -s ' ' | sed 's/^ //; s/ $//')
NIGHT_ID="NIGHT-$DATE"; NIGHT_CARD="$WS/work/$NIGHT_ID.md"; NIGHT_BR=""; NIGHT_WT=""; NIGHT_BASE=""
# keep role output folders out of git in every worktree (info/exclude is shared)
EXCL="$(git -C "$REPO" rev-parse --git-common-dir)/info/exclude"
case "$EXCL" in /*|?:*) ;; *) EXCL="$REPO/$EXCL";; esac
mkdir -p "$(dirname "$EXCL")"; grep -qx "/$OUTD/" "$EXCL" 2>/dev/null || echo "/$OUTD/" >> "$EXCL"

ROLES="$AGENT"
for r in "$VERIFIER" "$RISK_VERIFIER" "$ADVISOR" "$REVIEWER"; do [ -n "$r" ] && ROLES="$ROLES $r"; done
[ "$GOAL_MODE" = yes ] && ROLES="$ROLES $PLANNER"
ROLES=$(printf '%s\n' $ROLES | awk '!s[$0]++' | tr '\n' ' ')
for r in $ROLES; do
  [ -n "$(cfg "cmd_$r")" ] || { echo "error: role agent '$r' has no cmd_$r in HEARTBEAT.md" >&2; exit 1; }
done
for p in worker verifier planner advisor review; do
  [ -f "$WS/prompts/$p.md" ] || { echo "error: prompts/$p.md missing — run scripts/upgrade.sh" >&2; exit 1; }
done

# --- card contract: filename must be exactly <id>.md ------------------------------
# pick_ready discovers cards by frontmatter id:, but claims, deps and reports all
# construct work/<id>.md from that id — a mismatched filename half-works, then every
# downstream step silently misses (cost a full night in the field, 2026-08-11).
CARD_ERRS=0
for f in "$WS"/work/*.md; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in _TEMPLATE.md) continue;; esac
  i=$(fm_get "$f" id)
  if [ -z "$i" ]; then
    echo "error: work/$(basename "$f") has no 'id:' in its frontmatter" >&2; CARD_ERRS=$((CARD_ERRS+1))
  elif [ "$(basename "$f")" != "$i.md" ]; then
    echo "error: work/$(basename "$f") declares 'id: $i' — rename the file to $i.md" >&2; CARD_ERRS=$((CARD_ERRS+1))
  fi
done
[ "$CARD_ERRS" -eq 0 ] || { echo "error: $CARD_ERRS bad card(s) — refusing to start the lane" >&2; exit 1; }

now_hhmm() { date +%H%M; }
# morning stop (s < 12:00): the window is [s, 12:00). evening stop: [s, midnight).
in_stop_window() { awk -v n="$(now_hhmm)" -v s="$STOP" 'BEGIN{n=int(n);s=int(s); exit !(s<1200 ? (n>=s && n<1200) : n>=s)}'; }
# started during the morning window (e.g. a supervised 08:00 run) → don't stop instantly;
# the stop gate re-arms once the clock leaves the window (past noon or past midnight).
ARMED=yes; in_stop_window && ARMED=no

notify() { [ -n "$NTFY" ] && curl -s --connect-timeout 10 --max-time 20 -d "night-shift[$AGENT]: $1" "$NTFY" >/dev/null 2>&1 || true; }
tick() { printf 'TICK: %s %s %s\n' "$AGENT" "$(date '+%m-%d %H:%M')" "$1" >> "$LOG"; }
trail() { TRAIL_LANE=$AGENT TRAIL_DATE=$DATE sh "$WS/scripts/trail.sh" "$@" 2>/dev/null || true; }
spent() { num_or "$(cat "$SPENDF" 2>/dev/null || echo 0)" 0; }
# capped: the night has a spend cap. over_budget: it has one, and the ledger reached it.
capped() { awk -v b="$BUDGET" 'BEGIN{exit !(b+0 > 0)}'; }
over_budget() { capped && awk -v s="$(spent)" -v b="$BUDGET" 'BEGIN{exit !(s+0 >= b+0)}'; }
# how the spend reads in a report ("$4.20 / $100", "$4.20 (no cap)") and the cap in a
# start line ("$100", "off")
spend_txt() { if capped; then echo "\$$(spent) / \$$BUDGET"; else echo "\$$(spent) (no cap)"; fi; }
if capped; then BUDGET_TXT="\$$BUDGET"; else BUDGET_TXT=off; fi
add_spend() { # lanes share the ledger: read-modify-write under a mutex
  # best effort: after ~10s take the mutex by force, after ~20s write without it. A
  # ledger that is off by one card beats a lane stuck on a lock it cannot remove.
  n=0
  until mkdir "$SPENDF.lock" 2>/dev/null; do
    n=$((n+1))
    if [ "$n" -eq 50 ]; then rm -rf "$SPENDF.lock" 2>/dev/null || true; fi
    [ "$n" -ge 100 ] && break
    sleep 0.2
  done
  awk "BEGIN{printf \"%.2f\", $(spent) + $(num_or "$1" 0)}" > "$SPENDF.tmp.$$" && mv -f "$SPENDF.tmp.$$" "$SPENDF" || true
  rm -rf "$SPENDF.lock" 2>/dev/null || true
}
# $1 = CLI output file, $2 = minutes the call ran → its reported cost; with none (a
# timeout, a CLI that prints no cost) the larger of cost_fallback_usd and
# minutes × cost_per_minute_usd, so a 45-minute timeout is not booked as $2.
# $3 = the agent that ran: cost_fallback_usd_<agent> and cost_per_minute_usd_<agent>
# override the two rates for a CLI that never prints a cost (codex --json, agy).
charge() {
  c=$(grep -oE '"(total_cost_usd|costUSD|total_cost)"[: ]*[0-9.]+' "$1" 2>/dev/null | tail -1 | grep -o '[0-9.]*$' || true)
  if [ -z "$c" ]; then
    cf=$FALLBACK_COST; cr=$PER_MIN
    if [ -n "${3:-}" ]; then
      cf=$(num_or "$(cfg "cost_fallback_usd_$3")" "$cf"); cr=$(num_or "$(cfg "cost_per_minute_usd_$3")" "$cr")
    fi
    c=$(awk -v f="$cf" -v m="$(num_or "${2:-0}" 0)" -v r="$cr" 'BEGIN{x=m*r; printf "%.2f", (x>f?x:f)}')
  fi
  add_spend "$c"
}
# What one CLI call may spend: call_budget_usd, and never more than what is left of
# the night when the night has a cap. night_budget_usd is only checked between cards,
# so without a per-call cap one card can overshoot it. A cmd_ line passes it on to a
# CLI that has a spend flag (claude --max-budget-usd $APSOLUT_CALL_BUDGET_USD). With
# neither cap set the value is NO_CAP_USD, so that line still gets a number.
call_budget() {
  awk -v b="$BUDGET" -v s="$(spent)" -v c="$CALL_BUDGET" -v big="$NO_CAP_USD" 'BEGIN{r=(b+0>0)?b-s:big; if(c>0&&c<r)r=c; if(r<0.01)r=0.01; printf "%.2f", r}'
}
# Exported to every cmd_ line (it runs through sh -c, so it can use them):
#   APSOLUT_CALL_MINUTES      the hard cap `timeout` enforces on this call
#   APSOLUT_SOFT_TIMEOUT_MIN  one minute less, for a CLI that can stop itself and
#                             still print its JSON (agy --print-timeout)
#   APSOLUT_CALL_BUDGET_USD   call_budget() above
call_env() { # $1 minutes
  APSOLUT_CALL_MINUTES=$1
  APSOLUT_SOFT_TIMEOUT_MIN=$(( $1 > 1 ? $1 - 1 : 1 ))
  APSOLUT_CALL_BUDGET_USD=$(call_budget)
  export APSOLUT_CALL_MINUTES APSOLUT_SOFT_TIMEOUT_MIN APSOLUT_CALL_BUDGET_USD
}
# Why a CLI stopped by its own hand, read from its JSON: budget | turns | timeout |
# cancelled | error, or nothing. A CLI can exit 0 without finishing the turn: grok
# with a tool it could not get approved ("stopReason":"cancelled"), agy with
# "denied_actions". Exit codes alone read those as a normal run. Only the last lines
# count, and the keys are matched unescaped, so a copy quoted inside a model's
# answer (escaped there) never matches.
cli_stop() { # $1 output file
  t=$(command tail -40 "$1" 2>/dev/null || true)
  case "$t" in
    *'"subtype":"error_max_budget_usd"'*|*'"subtype": "error_max_budget_usd"'*) echo budget ;;
    *'"subtype":"error_max_turns"'*|*'"subtype": "error_max_turns"'*) echo turns ;;
    *'"finished_reason":"print_timeout"'*|*'"finished_reason": "print_timeout"'*) echo timeout ;;
    *'"stopReason":"cancelled"'*|*'"stopReason": "cancelled"'*|*'"denied_actions":[{'*|*'"denied_actions": [{'*) echo cancelled ;;
    *) if printf '%s' "$t" | grep -q '"is_error"[[:space:]]*:[[:space:]]*true'; then echo error; fi ;;
  esac
}
T0=0; t_start() { T0=$(date +%s); }
t_min() { echo $(( ( $(date +%s) - T0 + 59 ) / 60 )); }
# provider trouble (429/5xx/quota) = backoff, not a failure, not an attempt. Only a
# call that FAILED (rc != 0 or is_error) can be throttled, and only its last lines
# count: a card about rate limiting, or a test log that prints "Internal Server
# Error", must never read as provider trouble (that reset good work in a loop).
throttled() { # $1 output file, $2 rc
  case "${2:-0}" in 124|137) return 1;; esac   # our own timeout kill, not the provider
  [ "${2:-0}" -ne 0 ] || grep -q '"is_error"[[:space:]]*:[[:space:]]*true' "$1" 2>/dev/null || return 1
  command tail -40 "$1" 2>/dev/null | grep -qiE 'rate.?limit|quota exceeded|overloaded|too many requests|service.{0,15}unavailable|internal server error|bad gateway|gateway time.?out|(http|status( code)?|api.?error|error.?code)[^0-9A-Za-z]{0,4}(429|50[0-4]|529)([^0-9]|$)'
}
# run a check command in a worktree with a hard cap; $1 dir, $2 cmd, $3 out (append)
run_check() { ( cd "$1" && timeout -k 30 $(( CHECK_MIN * 60 )) sh -c "$2" ) >> "$3" 2>&1; }

# --- prompt rendering: prompts/<role>.md with {{KEY}} filled from files -----------
# Values travel through files, never argv or env, so cards and diffs of any size or
# byte content survive. Marker lines (apsolut-agents: tier=) are stripped.
P_DIR=""
p_begin() { P_DIR=$(mktemp -d); : > "$P_DIR/.spec"; }
pv()  { printf '%s\n' "$2" > "$P_DIR/$1"; printf '%s\t%s\n' "$1" "$P_DIR/$1" >> "$P_DIR/.spec"; }
pvf() { if [ -f "$2" ]; then cp "$2" "$P_DIR/$1"; else : > "$P_DIR/$1"; fi
        printf '%s\t%s\n' "$1" "$P_DIR/$1" >> "$P_DIR/.spec"; }
p_render() { # $1 role, $2 output file
  awk -v spec="$P_DIR/.spec" '
    BEGIN { while ((getline line < spec) > 0) {
              t = index(line, "\t"); k = substr(line, 1, t-1); p = substr(line, t+1)
              v = ""; first = 1
              while ((getline l < p) > 0) { v = first ? l : v "\n" l; first = 0 }
              close(p); val[k] = v }
            close(spec) }
    /apsolut-agents: tier=/ { next }
    { s = $0; out = ""
      while (match(s, /[{][{][A-Z_]+[}][}]/)) {
        k = substr(s, RSTART+2, RLENGTH-4)
        out = out substr(s, 1, RSTART-1) ((k in val) ? val[k] : substr(s, RSTART, RLENGTH))
        s = substr(s, RSTART+RLENGTH) }
      print out s }' "$WS/prompts/$1.md" > "$2"
  rm -rf "$P_DIR"; P_DIR=""
}
# How the prompt reaches the CLI (HEARTBEAT prompt_<agent>: arg | stdin):
#   stdin  the whole prompt on stdin, nothing on argv (claude -p, codex exec -, …)
#   arg    the prompt as the last argument, while it fits prompt_arg_max_bytes.
#          A bigger one (retries, planner rounds) becomes a one-line pointer to the
#          prompt file: Windows caps a command line near 8–32 KB, and a prompt that
#          does not fit would fail every retry before the model ever ran.
run_cli() { # $1 agent, $2 cwd, $3 minutes, $4 prompt file, $5 output file → CLI exit code
  c=$(cfg "cmd_$1"); mode=$(cfg "prompt_$1")
  arg=""
  if [ "$mode" != stdin ]; then
    if [ "$(wc -c < "$4")" -le "$ARG_MAX_B" ]; then arg=$(cat "$4")
    else
      # a RELATIVE path inside the cwd: a native Windows CLI cannot open an MSYS
      # /c/... path written into a sentence, and a sandboxed one may not read outside
      mkdir -p "$2/$OUTD"; cp "$4" "$2/$OUTD/prompt.md"
      arg="Your complete instructions are in the file $OUTD/prompt.md (relative to your current directory) — read the whole file now and follow it exactly. It is long on purpose; do not skip any part."
    fi
  fi
  t_start
  set +e
  if [ "$mode" = stdin ]; then
    ( cd "$2" && APSOLUT_AGENT_DEPTH=1 && export APSOLUT_AGENT_DEPTH && call_env "$3" && \
      timeout -k 30 $(( $3 * 60 )) sh -c "$c" ) < "$4" > "$5" 2>&1
  else
    ( cd "$2" && APSOLUT_AGENT_DEPTH=1 && export APSOLUT_AGENT_DEPTH && call_env "$3" && \
      timeout -k 30 $(( $3 * 60 )) sh -c "$c \"\$1\"" runner "$arg" ) < /dev/null > "$5" 2>&1
  fi
  rc=$?
  set -e
  return $rc
}
# where a role writes its output inside a worktree, and how the runner collects it
out_path() { mkdir -p "$1/$OUTD"; rm -rf "${1:?}/$OUTD/$2"; echo "$1/$OUTD/$2"; }
collect() { # $1 in-worktree file, $2 runs/ destination — copy if the role wrote it
  # never fatal: a file a lingering child still holds (Windows) must not end the lane
  if [ -s "$1" ] && cp "$1" "$2" 2>/dev/null; then rm -f "$1" 2>/dev/null || true; fi
}

# --- tamper canary: no agent may edit the rules it runs under --------------------
# Every agent runs with a bypass permission posture, and the .primary pointer leads
# back here. Checksum the files no lane writes at night around every agent run. A
# mismatch raises the Andon and ends the night, because the caps are no longer the
# caps. Prevention needs Docker (FUTURE.md). This is detection.
ws_sum() { ( cd "$WS" && for f in HEARTBEAT.md GOAL.md prompts/*.md scripts/*.sh; do
               [ -f "$f" ] && cksum "$f"; done ) 2>/dev/null || true; }
SUM0=""
guard_begin() { SUM0=$(ws_sum); }
guard_end() { # $1 who → 0 clean, 1 tampered (Andon raised)
  s1=$(ws_sum)
  [ "$SUM0" = "$s1" ] && return 0
  what=$(printf '%s\n%s\n' "$SUM0" "$s1" | sort | uniq -u | awk '{print $3}' | sort -u | tr '\n' ' ')
  TRAIL_LANE=$AGENT sh "$WS/scripts/andon.sh" raise "tamper: $1 changed ${what}during its run" >/dev/null 2>&1 || true
  trail tamper "stopped the night" "$1 changed rule files" "$what" ANDON
  return 1
}
# HEAD + tracked changes. Untracked files are left out on purpose: a test run that
# drops coverage/, a .tsbuildinfo or a sqlite file is not a read-only role editing
# the code. restore_tree() still cleans them away.
tree_state() { printf '%s %s' "$(git -C "$1" rev-parse HEAD 2>/dev/null)" \
  "$(git -C "$1" status --porcelain -uno 2>/dev/null | grep -v '\.apsolut-agents' | cksum)"; }
restore_tree() { # $1 worktree, $2 commit, $3 stray-diff file — undo a read-only role's writes
  { git -C "$1" status --porcelain; git -C "$1" diff HEAD; } > "$3" 2>/dev/null || true
  git -C "$1" reset --hard -q "$2" 2>/dev/null || true
  git -C "$1" clean -fdq -e .apsolut-agents 2>/dev/null || true
}

# --- handoff parsing ----------------------------------------------------------------
# Models drift from the template: "## Status: blocked", "**success**", a bullet, a
# code fence. A heading matches case-insensitively by prefix, the text after it on
# the heading line counts as the first body line, and fences are skipped.
md_section() { # $1 file, $2 heading, $3 max lines → section body
  [ -f "$1" ] || return 0
  awk -v h="$2" -v m="$3" 'BEGIN{h=tolower(h)}
    {sub(/\r$/,"")}
    /^#{2,3}[ \t]/ { t=tolower($0); sub(/^#+[ \t]*/,"",t)
      if (f) exit
      if (index(t,h)==1) { f=1; rest=substr($0, index(tolower($0),h)+length(h)); sub(/^[ \t:*-]*/,"",rest)
        if (rest!="" && n<m) { print rest; n++ }; next } }
    f && /^```/ {next}
    f && NF && n<m { print; n++ }' "$1"
}
md_first() { md_section "$1" "$2" 1; }
md_body() { md_section "$1" "$2" "$3"; }
# the token must be the FIRST word of a line ("blocked — needs a key" counts,
# "not blocked" does not), after list markers, emphasis and backticks are stripped
first_token() { # $1 = ERE of allowed tokens; stdin = section lines
  awk -v re="^($1)\$" '{ l = tolower($0); gsub(/[`*_]/, "", l); sub(/^[ \t>-]*/, "", l)
    split(l, w, /[^a-z-]+/); if (w[1] ~ re) { print w[1]; exit } }'
}
h_status() { md_section "$1" Status 3 | first_token 'success|partial|blocked' || true; }
h_level() { md_section "$1" Verification 3 | first_token 'live-verified|test-verified|typecheck-only|verifier-blocked|verifier-failed|not-verified' || true; }
# protected paths a diff touched (empty = none); $1 dir, $2 from, $3 to
protected_hits() {
  [ -n "$PROTECT" ] || return 0
  # set -f: `protect: tests/*.sh` must reach git as a pathspec, not be expanded by
  # the shell against whatever files the runner's cwd happens to hold
  set -f
  # shellcheck disable=SC2086
  git -C "$1" diff --name-only "$2" "$3" -- $PROTECT 2>/dev/null | head -5 | tr '\n' ' '
  set +f
}
forbidden_hits() { # symptom patches on added lines; $1 dir, $2 from, $3 to
  [ -n "$FORBID" ] || return 0
  git -C "$1" diff -U0 "$2" "$3" 2>/dev/null | grep '^+' | grep -v '^+++' | grep -E "$FORBID" | head -3 || true
}
# $1 card -> its first risk: tag that is listed in risk_tags (nothing = not risky)
risky_tag() {
  for rt in $(fm_get "$1" risk | tr -d '[]' | tr ',' ' '); do
    case " $RISK_TAGS " in *" $rt "*) echo "$rt"; return 0;; esac
  done
  return 0
}
rank() { case "$1" in live-verified) echo 3;; test-verified) echo 2;; typecheck-only) echo 1;; *) echo 0;; esac; }
need_rank() { case "$1" in live) echo 3;; typecheck) echo 1;; *) echo 2;; esac; }
goal_text() {
  if [ "$GOAL_MODE" = yes ]; then
    printf 'goal: %s\nfinish predicate: %s\n\n' "$(gcfg goal)" "$DONE_CMD"
    awk '/^## Final product means/{f=1} f&&!/^<!--|-->$/' "$GOALF"
  else
    echo "(no GOAL.md contract tonight — the card below is the whole goal)"
  fi
}

# --- lane singleton: one runner per agent name -----------------------------------
LANE="$WS/claims/.lane-$AGENT"
if ! mkdir "$LANE" 2>/dev/null; then
  lp=$(cat "$LANE/pid" 2>/dev/null || echo "")
  if [ -n "$lp" ] && kill -0 "$lp" 2>/dev/null; then
    echo "error: runner for '$AGENT' already active (pid $lp)" >&2; exit 1
  fi
  rm -rf "$LANE"; mkdir "$LANE"
fi
echo $$ > "$LANE/pid"

CURRENT_ID=""; FINISHED=no
cleanup() {
  crc=$?
  # every step is attempted whatever the one before it did, and nothing runs twice
  set +e
  trap - EXIT INT TERM
  if [ -n "$CURRENT_ID" ] && [ -d "$WS/claims/$CURRENT_ID" ]; then
    # the card first, then its claim: a card left "writing" with no claim is found by
    # nobody, a claim left on a waiting card is recovered at the next start
    c="$WS/work/$CURRENT_ID.md"
    [ -f "$c" ] && [ "$(fm_get "$c" status)" = "writing" ] && fm_set "$c" status waiting
    rm -rf "$WS/claims/$CURRENT_ID"
    tick "released claim $CURRENT_ID on exit"
  fi
  for l in .planning .integrate .report; do
    [ "$(cat "$WS/claims/$l/pid" 2>/dev/null)" = "$$" ] && rm -rf "${WS:?}/claims/$l"
  done
  [ -n "$P_DIR" ] && rm -rf "$P_DIR"
  # Only finish() writes a report. A runner that stops any other way (a signal, a
  # command that failed under set -e) says so where the human looks, and leaves its
  # ending for the report another lane may still write: a dead lane must never look
  # like a quiet one.
  if [ "$FINISHED" != yes ]; then
    tick "DIED: the runner stopped without a report (exit $crc) — this log and runs/trail-$DATE.tsv hold the night so far"
    echo "$(date '+%Y-%m-%d %H:%M') — reason: the runner stopped without a report (exit $crc) — spend: $(spend_txt)" > "$WS/runs/.lane-end-$DATE-$AGENT"
    notify "DIED: the runner stopped without a report (exit $crc)"
  fi
  rm -rf "$LANE"
}
# INT and TERM end the runner. With cleanup as their handler the shell released the
# claims and then carried on with the night, so a stopped lane kept working.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

lock() { # $1 name → spin up to ~10 min for a cross-lane mutex
  n=0; nopid=0
  until mkdir "$WS/claims/$1" 2>/dev/null; do
    n=$((n+1)); [ "$n" -ge 120 ] && return 1
    lp=$(cat "$WS/claims/$1/pid" 2>/dev/null || true)
    # a holder that died: its pid is gone, or it never got to write one (seen three
    # times in a row, so a lock taken this instant is not mistaken for a dead one)
    if [ -z "$lp" ]; then nopid=$((nopid+1)); else nopid=0; fi
    if { [ -n "$lp" ] && ! kill -0 "$lp" 2>/dev/null; } || [ "$nopid" -ge 3 ]; then
      rm -rf "${WS:?}/claims/$1" 2>/dev/null || true
      nopid=0; sleep 1; continue
    fi
    sleep 5
  done
  echo $$ > "$WS/claims/$1/pid"
}
unlock() { rm -rf "${WS:?}/claims/$1"; }

# --- lane preflight: prove every role CLI can answer before burning cards ----------
# One probe from an empty temp cwd (never the repo — the CLI runs with a bypassed
# permission posture). A lane whose CLI cannot answer at all — bad auth, refused
# account, dead binary — would otherwise march the whole board, charging an attempt
# plus fallback cost per card (cost a full night in the field, 2026-08-11). A dead
# verifier would make every card unverified, so roles are probed too.
probe_role() { # $1 agent → 0 when its CLI answers; else PROBE_WHY and PROBE_OUT say why not
  PROBE_DIR=$(mktemp -d); PROBE_OUT=""; pbrc=0; PROBE_WHY=""
  rcmd=$(cfg "cmd_$1")
  # the answer goes to a file, not a pipe: a child the CLI leaves behind would keep a
  # pipe open, and the probe would wait for it long after its 180 seconds
  pbf="$WS/runs/.probe-$AGENT-$1.out"
  if [ "$(cfg "prompt_$1")" = stdin ]; then
    ( cd "$PROBE_DIR" && call_env 3 && printf 'Reply with the single word: ok\n' | timeout -k 10 180 sh -c "$rcmd" ) > "$pbf" 2>&1 || pbrc=$?
  else
    ( cd "$PROBE_DIR" && call_env 3 && timeout -k 10 180 sh -c "$rcmd \"\$1\"" runner "Reply with the single word: ok" ) < /dev/null > "$pbf" 2>&1 || pbrc=$?
  fi
  PROBE_OUT=$(cat "$pbf" 2>/dev/null || true)
  rm -rf "$PROBE_DIR" 2>/dev/null || true
  [ "$pbrc" -ne 0 ] && PROBE_WHY="exited non-zero"
  [ -z "$PROBE_WHY" ] && printf '%s' "$PROBE_OUT" | grep -q '"is_error"[[:space:]]*:[[:space:]]*true' && PROBE_WHY="returned is_error:true"
  [ -z "$PROBE_WHY" ] && printf '%s' "$PROBE_OUT" | grep -qE '"stopReason"[[:space:]]*:[[:space:]]*"cancelled"|"denied_actions"[[:space:]]*:[[:space:]]*\[\{' && PROBE_WHY="ended the turn early (cancelled, or a tool was denied)"
  [ -z "$PROBE_WHY" ] && { printf '%s' "$PROBE_OUT" | grep -qiw 'ok' || PROBE_WHY="returned no 'ok'"; }
  [ -z "$PROBE_WHY" ]
}
for r in $ROLES; do
  probe_role "$r" && continue
  why=$PROBE_WHY
  if [ -n "$why" ]; then
    echo "error: preflight probe for '$r' $why — refusing to start the lane" >&2
    printf '%s\n' "$PROBE_OUT" | command tail -5 >&2
    tick "preflight probe FAILED ($r): $why — lane refused"
    notify "preflight probe for $r failed ($why) — lane refused"
    FINISHED=yes; exit 1
  fi
done
tick "preflight probe ok ($ROLES)"

# --- boot recovery: release claims whose runner is dead ---------------------------
for c in "$WS"/claims/*/; do
  [ -d "$c" ] || continue
  id=$(basename "$c")
  case "$id" in .*) continue;; esac   # lanes and mutexes, not card claims
  pid=$(cat "$c/pid" 2>/dev/null || echo "")
  ft=$(date -r "$c" +%s 2>/dev/null || echo 0)
  age=$(( ( $(date +%s) - ft ) / 60 ))
  if { [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; } && [ "$age" -ge "$STALE_MIN" ]; then
    # the card first, then its claim. A card the dead runner had already marked
    # review or blocked keeps that result.
    [ -f "$WS/work/$id.md" ] && [ "$(fm_get "$WS/work/$id.md" status)" = writing ] && fm_set "$WS/work/$id.md" status waiting
    rm -rf "$c" 2>/dev/null || true
    tick "recovered stale claim $id (pid ${pid:-none} dead, ${age}m old)"
  fi
done

# --- night integration branch (goal mode) ------------------------------------------
# One card-shaped worktree per night: agent/night/NIGHT-<date>. Cards that pass
# green and verification are merged here with --no-ff, one merge commit per card, so
# a single card can be reverted. Later cards spawn FROM this branch, so a dependent
# card sees its dependency's code the same night. The default branch never moves.
# In the morning, `worktree.sh done NIGHT-<date> --merge` lands the night as one
# proven merge.
night_setup() {
  # All of it under the lock. Lanes started together each see "no night yet": the
  # one that waits must look again once it holds the lock, and must not read or
  # write the night card while the first lane is still filling it in. The wait is
  # long because the first lane may be running setup_cmd.
  lock .integrate || lock .integrate || { echo "error: could not take the integration lock" >&2; exit 1; }
  NIGHT_WT=""; [ -f "$NIGHT_CARD" ] && NIGHT_WT=$(fm_get "$NIGHT_CARD" worktree)
  if [ -z "$NIGHT_WT" ] || [ "$NIGHT_WT" = null ] || [ ! -d "$NIGHT_WT" ]; then
    sh "$WS/scripts/worktree.sh" spawn night "$NIGHT_ID" >/dev/null
    setup_wt "$(fm_get "$NIGHT_CARD" worktree)" || { unlock .integrate; finish "harness: setup_cmd failed in the night worktree (runs/.setup-$NIGHT_ID.out)" 4; }
    fm_set "$NIGHT_CARD" title "Night integration $DATE — $(gcfg goal | cut -c1-60)"
    fm_set "$NIGHT_CARD" spike true
    fm_set "$NIGHT_CARD" owner night
    fm_set "$NIGHT_CARD" base "$(git -C "$REPO" rev-parse HEAD)"
    printf '\n## Night integration\nCards verified tonight are merged here (--no-ff, one merge per card).\nFinish predicate: `%s`\nMorning: `sh .apsolut-agents/scripts/worktree.sh done %s --merge`\n' \
      "$DONE_CMD" "$NIGHT_ID" >> "$NIGHT_CARD"
    trail night "opened the night integration branch" "goal mode: verified cards accumulate here" "$NIGHT_ID" open
  fi
  fm_set "$NIGHT_CARD" status writing
  NIGHT_WT=$(fm_get "$NIGHT_CARD" worktree); NIGHT_BR=$(fm_get "$NIGHT_CARD" branch)
  NIGHT_BASE=$(fm_get "$NIGHT_CARD" base)
  heal_night
  unlock .integrate
}
# Put the night branch back on a known tip. A refused merge must never stay on it:
# every later card starts from that branch. → 0 when the tip is where it should be
roll_night_back() { # $1 commit
  git -C "$NIGHT_WT" merge --abort >/dev/null 2>&1 || true
  for rw in 0 3 10; do
    [ "$rw" -eq 0 ] || sleep "$rw"
    git -C "$NIGHT_WT" reset --hard -q "$1" 2>/dev/null && break
  done
  git -C "$NIGHT_WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
  if [ "$(git -C "$NIGHT_WT" rev-parse HEAD 2>/dev/null)" = "$1" ] && \
     [ -z "$(git -C "$NIGHT_WT" status --porcelain -uno 2>/dev/null | grep -v '\.apsolut-agents' || true)" ]; then
    return 0
  fi
  # the files could not be put back (something holds one open). Take the branch off
  # the refused merge at least, so nothing that reads the branch gets that code; the
  # caller still treats this as a failed rollback.
  git -C "$NIGHT_WT" reset --soft -q "$1" 2>/dev/null || true
  return 1
}
# Call with the .integrate lock held. A runner that died between a merge and its
# checks left the journal behind: undo that merge before anything builds on it.
heal_night() {
  [ -f "$INTEGJ" ] || return 0
  hb=$(awk 'NR==1{print $1}' "$INTEGJ" 2>/dev/null || true); hp=$(awk 'NR==1{print $2}' "$INTEGJ" 2>/dev/null || true)
  hc=$(awk 'NR==1{print $3}' "$INTEGJ" 2>/dev/null || true)
  if [ -z "$hp" ] || [ "$hb" != "$NIGHT_BR" ]; then rm -f "$INTEGJ" 2>/dev/null || true; return 0; fi
  # the card is marked integrated before the journal is removed: a journal whose card
  # carries the mark is left over from a merge that was accepted, and stays merged
  if [ -n "$hc" ] && [ "$(fm_get "$WS/work/$hc.md" integrated 2>/dev/null || true)" = "$NIGHT_BR" ]; then
    rm -f "$INTEGJ" 2>/dev/null || true; return 0
  fi
  if roll_night_back "$hp"; then
    tick "rolled the night branch back to $(printf '%.7s' "$hp"): a runner stopped in the middle of a merge"
    trail integrate "rolled the night branch back" "a runner stopped in the middle of a merge" "$NIGHT_BR @ $(printf '%.7s' "$hp")" healed
    rm -f "$INTEGJ" 2>/dev/null || true
  else
    # keep the journal: the next start tries again. Nothing may build on this branch.
    tick "andon: the night branch could not be rolled back to $(printf '%.7s' "$hp") after an interrupted merge"
    TRAIL_LANE=$AGENT sh "$WS/scripts/andon.sh" raise "the night branch could not be rolled back after an interrupted merge — it may hold code nobody accepted" >/dev/null 2>&1 || true
  fi
}
# setup_cmd (HEARTBEAT): bootstrap a fresh worktree (install deps, link a seeded
# node_modules or .venv) once, outside every attempt's clock and outside green_cmd.
setup_wt() { # $1 worktree → 0 ok
  [ -n "$SETUP" ] || return 0
  sf="$WS/runs/.setup-$(basename "$1").out"
  echo "setup_cmd @ $(git -C "$1" rev-parse --short HEAD): $SETUP" > "$sf"
  run_check "$1" "$SETUP" "$sf" || return 1
  # setup may write ignored files only; tracked edits mean it is not a setup step
  [ -z "$(git -C "$1" status --porcelain -uno | grep -v '\.apsolut-agents' || true)" ] || {
    echo "setup_cmd changed tracked files — refusing" >> "$sf"; return 1; }
}
integrate() { # $1 id, $2 branch, $3 log, $4 card check (optional) → 0 merged, green (and checked) on the night branch
  lock .integrate || return 1
  heal_night
  if [ -f "$WS/ANDON" ]; then unlock .integrate; return 1; fi
  pre=$(git -C "$NIGHT_WT" rev-parse HEAD); ok=yes
  echo "$NIGHT_BR $pre $1" > "$INTEGJ"
  echo "=== integrate $1 into $NIGHT_BR @ $pre ===" >> "$3"
  timeout -k 10 "$GIT_MAX" git -C "$NIGHT_WT" merge --no-ff --no-edit -q -m "night: integrate $1 ($2)" "$2" >> "$3" 2>&1 || ok=no
  [ "$ok" = no ] && echo "MERGE CONFLICT with the night branch: $(git -C "$NIGHT_WT" diff --name-only --diff-filter=U | tr '\n' ' ')" >> "$3"
  if [ "$ok" = yes ]; then
    echo "green_cmd @ $(git -C "$NIGHT_WT" rev-parse HEAD) (night)" >> "$3"
    run_check "$NIGHT_WT" "$GREEN" "$3" || { ok=no; echo "GREEN RED on the night branch after the merge" >> "$3"; }
  fi
  # another lane may have landed something that merges cleanly but breaks this card
  if [ "$ok" = yes ] && [ -n "${4:-}" ]; then
    echo "check @ merge candidate: $4" >> "$3"
    run_check "$NIGHT_WT" "$4" "$3" || { ok=no; echo "GREEN RED on the night branch: the card's check fails after the merge" >> "$3"; }
  fi
  # untracked output (coverage/, .tsbuildinfo, a sqlite file) is fine; edits to
  # tracked files mean green is not a pure check
  [ "$ok" = yes ] && [ -n "$(git -C "$NIGHT_WT" status --porcelain -uno | grep -v '\.apsolut-agents' || true)" ] && {
    echo "GREEN RED on the night branch: green_cmd changed tracked files" >> "$3"; ok=no; }
  [ "$ok" = yes ] && git -C "$NIGHT_WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
  if [ "$ok" = yes ]; then
    # Accepted. The card says so first, the journal goes second, both under the
    # lock: whatever stops the runner in between, the next one reads it correctly
    # (mark present: the merge stays; mark absent: the merge is rolled back).
    fm_set "$WS/work/$1.md" integrated "$NIGHT_BR"
    fm_set "$WS/work/$1.md" status review
    [ "$(fm_get "$WS/work/$1.md" integrated 2>/dev/null || true)" = "$NIGHT_BR" ] && rm -f "$INTEGJ" 2>/dev/null
  elif roll_night_back "$pre"; then
    rm -f "$INTEGJ" 2>/dev/null || true
  else
    # the refused merge is still on the night branch: stop every lane before
    # another card builds on code nobody accepted. The journal stays for the next start.
    echo "could not roll the night branch back to $pre" >> "$3"
    TRAIL_LANE=$AGENT sh "$WS/scripts/andon.sh" raise "the night branch could not be rolled back after a refused merge of $1 — it may hold code nobody accepted" >/dev/null 2>&1 || true
  fi
  unlock .integrate
  [ "$ok" = yes ]
}
goal_met() { # 0 = the finish predicate passes on the night branch
  lock .integrate || return 1
  heal_night
  if [ -f "$WS/ANDON" ]; then unlock .integrate; return 1; fi
  at=$(git -C "$NIGHT_WT" rev-parse HEAD); rc=0
  echo "done_cmd @ $at: $DONE_CMD" > "$WS/runs/.done-$DATE.out"
  run_check "$NIGHT_WT" "$DONE_CMD" "$WS/runs/.done-$DATE.out" || rc=$?
  # the predicate never relaxes: a night whose diff moved the judge cannot meet it
  ph=$(protected_hits "$NIGHT_WT" "${NIGHT_BASE:-$at}" "$at")
  if [ -n "$ph" ]; then
    echo "protected paths changed on the night branch ($ph) — a pass would not count" >> "$WS/runs/.done-$DATE.out"
    [ "$rc" -eq 0 ] && rc=98
  fi
  if [ "$(tree_state "$NIGHT_WT")" != "$at $(printf '' | cksum)" ]; then
    restore_tree "$NIGHT_WT" "$at" "$WS/runs/.done-$DATE.stray.diff"
    echo "done_cmd changed the night tree — result ignored (see runs/.done-$DATE.stray.diff)" >> "$WS/runs/.done-$DATE.out"
    rc=99
  fi
  unlock .integrate
  trail goal "checked the finish predicate" "the board ran dry" "runs/.done-$DATE.out @ $(printf '%.7s' "$at")" "$( [ "$rc" -eq 0 ] && echo met || echo "not met (rc=$rc)")"
  [ "$rc" -eq 0 ]
}

deps_met() { # $1 = card file → 0 if every id in after: is done (merged) or integrated tonight
  a=$(fm_get "$1" after | tr -d '[]' | tr ',' ' ')
  for d in $a; do
    df="$WS/work/$d.md"; [ -f "$df" ] || return 1
    [ "$(fm_get "$df" status)" = "done" ] && continue
    [ -n "$NIGHT_BR" ] && [ "$(fm_get "$df" integrated)" = "$NIGHT_BR" ] && continue
    return 1
  done
  return 0
}

is_card() { [ -f "$1" ] || return 1; case "$(basename "$1")" in _TEMPLATE.md) return 1;; esac; }

pick_ready() { # print first claimable card id, or nothing
  for f in "$WS"/work/*.md; do is_card "$f" || continue;
    i=$(fm_get "$f" id); [ -n "$i" ] || continue
    [ "$(fm_get "$f" status)" = "waiting" ] || continue
    o=$(fm_get "$f" owner)
    case "$o" in "$AGENT"|any|"<agent>"|"") ;; *) continue;; esac
    deps_met "$f" || continue
    echo "$i"; return 0
  done
  return 1
}

# --- planner round (goal mode, board dry, predicate red) ---------------------------
ROUND_FILE="$WS/runs/.plan-rounds-$DATE"
card_ok() { # $1 staged card → prints why not, returns 1; silent 0 when acceptable
  id=$(fm_get "$1" id)
  [ -n "$id" ] || { echo "no id:"; return 1; }
  [ "$(basename "$1")" = "$id.md" ] || { echo "filename is not $id.md"; return 1; }
  case "$id" in *[!A-Za-z0-9._-]*|NIGHT-*) echo "bad id '$id'"; return 1;; esac
  [ ! -e "$WS/work/$id.md" ] || { echo "id $id already on the board"; return 1; }
  [ "$(fm_get "$1" status)" = waiting ] || { echo "status is not waiting"; return 1; }
  grep -q '^## Goal' "$1" && grep -q '^## Done when' "$1" || { echo "missing ## Goal or ## Done when"; return 1; }
  [ "$(fm_get "$1" spike)" != true ] || { echo "planner cards cannot be spikes (spike: true skips the test gate)"; return 1; }
  [ -n "$(fm_get "$1" check)" ] || { echo "no check: command (the runner runs it: red before the change, green after)"; return 1; }
  for d in $(fm_get "$1" after | tr -d '[]' | tr ',' ' '); do
    [ "$d" != "$id" ] || { echo "after: names itself"; return 1; }
    [ -f "$WS/work/$d.md" ] || [ -f "$(dirname "$1")/$d.md" ] || { echo "after: names unknown card $d"; return 1; }
  done
  return 0
}
board_table() {
  for f in "$WS"/work/*.md; do is_card "$f" || continue;
    [ "$(fm_get "$f" id)" = "$NIGHT_ID" ] && continue
    printf '%s | %s | verified: %s | integrated: %s | %s\n' "$(fm_get "$f" id)" "$(fm_get "$f" status)" \
      "$(fm_get "$f" verified)" "$( [ -n "$NIGHT_BR" ] && [ "$(fm_get "$f" integrated)" = "$NIGHT_BR" ] && echo yes || echo no)" "$(fm_get "$f" title)"
  done
}
handoff_digest() { # latest handoff per card touched tonight: notes, follow-ups, blocks
  for f in "$WS"/work/*.md; do is_card "$f" || continue;
    id=$(fm_get "$f" id)
    h=$(ls -t "$HO/$id"-attempt*.md 2>/dev/null | head -1 || true)
    [ -n "$h" ] || continue
    echo "### $id ($(fm_get "$f" status), handoff status: $(h_status "$h"))"
    md_body "$h" Notes 8
    md_body "$h" "Suggested follow-ups" 8
    sed -n 's/^Would unblock: /would unblock: /p' "$f" | tail -1
  done | head -200
}
LAST_ROUND_IDS=""; NOPROG=0
plan_round() { # 0 = cards accepted, 1 = STUCK, 2 = no usable cards, 3 = rounds exhausted, 4 = throttled
  R=$(( $(num_or "$(cat "$ROUND_FILE" 2>/dev/null || echo 0)" 0) + 1 ))
  [ "$R" -le "$MAX_ROUNDS" ] || return 3
  echo "$R" > "$ROUND_FILE"
  STAGE="$WS/runs/plan-$DATE-r$R"; mkdir -p "$STAGE"
  if [ -n "$LAST_ROUND_IDS" ]; then
    lr=$(for i in $LAST_ROUND_IDS; do f="$WS/work/$i.md"; [ -f "$f" ] || continue
      printf '%s -> %s%s\n' "$i" "$(fm_get "$f" status)" \
        "$(sed -n 's/^Failed because: / — failed because: /p' "$f" | tail -1)"; done)
    [ "$NOPROG" -gt 0 ] && lr="$lr
NONE of these reached the night branch. Attack the premise the last round shared before planning again."
  else lr="(first round tonight)"; fi
  p_begin
  pv AGENT "$PLANNER"; pv WT "$NIGHT_WT"; pv BRANCH "$NIGHT_BR"; pv GOAL "$(goal_text)"
  pv DONE_CMD "$DONE_CMD"; pv DONE_OUT "$(command tail -40 "$WS/runs/.done-$DATE.out" 2>/dev/null)"
  pv BOARD "$(board_table)"; pv HANDOFFS "$(handoff_digest)"; pv LAST_ROUND "$lr"
  # The planner reads a detached snapshot of the night tip, never the night worktree:
  # another lane may integrate while it plans, and nothing the planner does can
  # touch that branch. Its cards come back through the snapshot's output folder.
  at=$(git -C "$NIGHT_WT" rev-parse HEAD); PSNAP=$(mktemp -d)/plan
  git -C "$NIGHT_WT" worktree add -q --detach "$PSNAP" "$at" >/dev/null 2>&1 || PSNAP=""
  [ -n "$PSNAP" ] || { trail plan "could not snapshot the night branch" "git worktree add failed" "$NIGHT_WT" error; return 2; }
  PSTAGE=$(out_path "$PSNAP" plan); mkdir -p "$PSTAGE"
  pv MAX_CARDS "$MAX_CARDS"; pv STAGE "$PSTAGE"; pv NEXT_ID "G$(date +%m%d)r$R-1"
  PF="$STAGE/.prompt.md"; p_render planner "$PF"
  guard_begin; tick "plan round $R ($PLANNER)"
  prc=0; run_cli "$PLANNER" "$PSNAP" "$HELPER_MIN" "$PF" "$STAGE/.out" || prc=$?
  charge "$STAGE/.out" "$(t_min)" "$PLANNER"
  guard_end "planner $PLANNER" || finish "andon: tamper by the planner" 5
  for f in "$PSTAGE"/*.md; do [ -f "$f" ] && cp "$f" "$STAGE/"; done
  [ -n "$(git -C "$PSNAP" status --porcelain -uno 2>/dev/null)" ] && \
    trail plan "discarded planner edits to its snapshot" "the planner may only write cards" "$STAGE" discarded
  git -C "$NIGHT_WT" worktree remove --force "$PSNAP" >/dev/null 2>&1 || rm -rf "${PSNAP:?}" 2>/dev/null || true
  git -C "$NIGHT_WT" worktree prune >/dev/null 2>&1 || true
  if throttled "$STAGE/.out" "$prc" && ! ls "$STAGE"/*.md >/dev/null 2>&1; then
    echo $(( R - 1 )) > "$ROUND_FILE"
    trail plan "backed off the planner" "provider throttle; the round is not counted" "$STAGE/.out" backoff
    return 4
  fi
  if [ -f "$STAGE/STUCK.md" ]; then
    cp "$STAGE/STUCK.md" "$WS/runs/STUCK-$DATE.md"
    trail plan "planner says the goal needs a human" "$(head -c 200 "$STAGE/STUCK.md")" "runs/STUCK-$DATE.md" stuck
    return 1
  fi
  ACC=""; n=0
  for f in "$STAGE"/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in STUCK.md|.*) continue;; esac
    [ "$n" -lt "$MAX_CARDS" ] || { trail plan "dropped $(basename "$f")" "over max_cards_per_round" "$f" dropped; continue; }
    if why=$(card_ok "$f"); then
      id=$(fm_get "$f" id)
      # finish the staged copy, then publish it in one step: another lane must never
      # see, and claim, a card that is still being rewritten
      fm_set "$f" planned_by "$PLANNER r$R"
      fm_set "$f" updated "$DATE"
      # a planner does not pick lanes or pin branches: any lane may claim its cards
      fm_set "$f" owner any
      fm_set "$f" branch null; fm_set "$f" worktree null
      if cp "$f" "$WS/work/.$id.md.new" 2>/dev/null && mv -f "$WS/work/.$id.md.new" "$WS/work/$id.md" 2>/dev/null; then
        ACC="$ACC $id"; n=$((n+1))
        trail plan "accepted card $id" "$(fm_get "$f" title)" "work/$id.md" accepted
      else
        trail plan "could not publish $id" "copying the card into work/ failed" "$f" error
      fi
    else
      trail plan "rejected $(basename "$f")" "$why" "$f" rejected
    fi
  done
  [ -n "$ACC" ] || { LAST_ROUND_IDS=""; return 2; }
  LAST_ROUND_IDS=$ACC
  printf '\n### %s — %s (night shift)\n- plan round %s (%s): %s\n' "$AGENT" "$DATE" "$R" "$PLANNER" "$ACC" >> "$LOG"
  return 0
}
round_progressed() { # did any card from the last round reach the night branch?
  for i in $LAST_ROUND_IDS; do
    f="$WS/work/$i.md"; [ -f "$f" ] || continue
    [ "$(fm_get "$f" integrated)" = "$NIGHT_BR" ] && return 0
    [ "$(fm_get "$f" status)" = "done" ] && return 0
  done
  return 1
}

# --- morning packet -----------------------------------------------------------------
finish() { # $1 reason, $2 exit code
  BASEBR=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
  GOALSTATE=""
  if [ "$GOAL_MODE" = yes ] && [ -n "$NIGHT_BR" ]; then
    ahead=$(git -C "$REPO" rev-list --count "HEAD..$NIGHT_BR" 2>/dev/null || echo 0)
    if [ "$ahead" -gt 0 ]; then fm_set "$NIGHT_CARD" status review
    else fm_set "$NIGHT_CARD" status abandoned; fi
    GOALSTATE=$(command tail -15 "$WS/runs/.done-$DATE.out" 2>/dev/null || echo "(predicate never checked)")
  fi
  # The report is one file for the whole night. Each lane leaves its own result in
  # runs/.lane-end-<date>-<agent> (line 1: how it ended, line 2: what it waits on),
  # and whichever lane finishes rebuilds the report from all of them, so a second
  # lane never erases the first one's ending.
  LEND="$WS/runs/.lane-end-$DATE-$AGENT"
  {
    echo "$(date '+%Y-%m-%d %H:%M') — reason: $1 — spend: $(spend_txt)"
    case "$1" in "waiting on a human"*) echo "- **Lane parked, $1.** Unfinished cards are still \`waiting\` with their attempts returned: fix it, then start the runner again.";; esac
  } > "$LEND"
  # Inside the lock this lane marks itself as ending and looks for lanes that are
  # alive and not ending. Exactly one of several lanes finishing together sees none:
  # that one runs the reviewer and closes the night.
  RLOCK=no; if lock .report; then RLOCK=yes; fi
  : > "$LANE/ending" 2>/dev/null || true
  others=no
  for l in "$WS"/claims/.lane-*; do
    [ -d "$l" ] && [ "$l" != "$LANE" ] && [ ! -f "$l/ending" ] && kill -0 "$(cat "$l/pid" 2>/dev/null || echo 0)" 2>/dev/null && others=yes
  done
  LANES=""
  for l in "$WS/runs/.lane-end-$DATE-"*; do [ -f "$l" ] && LANES="$LANES ${l##*/.lane-end-"$DATE"-}"; done
  LANES=${LANES# }
  case "$LANES" in *" "*) MULTI=yes;; *) MULTI=no;; esac
  {
    if [ "$MULTI" = yes ]; then
      echo "# Night report — $DATE (lanes: $(printf '%s' "$LANES" | sed 's/ /, /g'))"
      for a in $LANES; do echo; echo "Ended: $(sed -n 1p "$WS/runs/.lane-end-$DATE-$a") — lane: $a"; done
    else
      echo "# Night report — $DATE (lane: $AGENT)"
      echo
      echo "Ended: $(sed -n 1p "$LEND")"
    fi
    echo
    if [ "$GOAL_MODE" = yes ]; then
      echo "## Goal"
      echo
      echo "- goal: $(gcfg goal)"
      echo "- finish predicate: \`$DONE_CMD\` — last result below"
      echo "- plan rounds used: $(cat "$ROUND_FILE" 2>/dev/null || echo 0) / $MAX_ROUNDS"
      [ -n "$NIGHT_BR" ] && echo "- night branch: \`$NIGHT_BR\` (+$(git -C "$REPO" rev-list --count "HEAD..$NIGHT_BR" 2>/dev/null || echo 0) commits) — land it with \`sh .apsolut-agents/scripts/worktree.sh done $NIGHT_ID --merge\`"
      echo
      echo '```'; printf '%s\n' "$GOALSTATE"; echo '```'
      echo
    fi
    echo "## Cards"
    echo
    echo "| card | status | verified | integrated | attempts | branch | diffstat vs $BASEBR |"
    echo "|---|---|---|---|---|---|---|"
    for f in "$WS"/work/*.md; do is_card "$f" || continue;
      id=$(fm_get "$f" id); [ "$id" = "$NIGHT_ID" ] && continue
      st=$(fm_get "$f" status); br=$(fm_get "$f" branch)
      at=$(cat "$WS/runs/.attempts-$DATE-$id" 2>/dev/null || echo 0)
      ds="—"
      [ -n "$br" ] && [ "$br" != "null" ] && \
        ds=$(git -C "$REPO" diff --stat "$BASEBR...$br" 2>/dev/null | tail -1 || echo "—")
      echo "| $id | $st | $(fm_get "$f" verified) | $( [ -n "$NIGHT_BR" ] && [ "$(fm_get "$f" integrated)" = "$NIGHT_BR" ] && echo yes || echo —) | $at | $br | ${ds:-—} |"
    done
    echo
    echo "## Waiting on you"
    echo
    w=0
    [ -f "$WS/ANDON" ] && { echo "- **Andon raised:** $(sed -n 's/^reason: //p' "$WS/ANDON") — clear with \`sh .apsolut-agents/scripts/andon.sh clear\`"; w=1; }
    for a in $LANES; do
      pl=$(sed -n 2p "$WS/runs/.lane-end-$DATE-$a")
      [ -n "$pl" ] || continue
      if [ "$MULTI" = yes ]; then echo "$pl (lane: $a)"; else echo "$pl"; fi
      w=1
    done
    [ -f "$WS/runs/STUCK-$DATE.md" ] && { echo "- **Planner is stuck:** runs/STUCK-$DATE.md — $(head -c 300 "$WS/runs/STUCK-$DATE.md" | tr '\n' ' ')"; w=1; }
    for f in "$WS"/work/*.md; do is_card "$f" || continue;
      id=$(fm_get "$f" id); st=$(fm_get "$f" status); vf=$(fm_get "$f" verified)
      [ "$st" = blocked ] && [ "$(fm_get "$f" updated)" = "$DATE" ] && {
        by=$(sed -n 's/^Blocked by: //p' "$f" | tail -1)
        echo "- $id blocked${by:+ (by: $by)} — $(sed -n 's/^Would unblock: //p' "$f" | tail -1)"; w=1; }
      [ "$st" = review ] && [ "$vf" = blocked ] && { echo "- $id green but UNVERIFIED (verifier blocked) — runs/handoffs/$id-verify*.md"; w=1; }
      [ "$st" = review ] && [ "$vf" = unverified ] && { echo "- $id green but UNVERIFIED (no verifier and no check:) — not integrated"; w=1; }
      [ "$st" = review ] && [ "$vf" = risk-unverified ] && { echo "- $id green, but it carries a risk tag and no verifier judged it — not integrated; yours to review"; w=1; }
    done
    [ "$w" -eq 0 ] && echo "(nothing)"
    echo
    echo "Decision trail: runs/trail-$DATE.tsv (\`column -s\$'\\t' -t runs/trail-$DATE.tsv\`) · handoffs: runs/handoffs/"
    echo
    echo "Nothing merged into \`$BASEBR\` — \`worktree.sh review\`, then \`done <id> --merge\` for what you accept."
  } > "$REPORT.tmp.$$"
  if ! mv -f "$REPORT.tmp.$$" "$REPORT" 2>/dev/null; then
    if cp "$REPORT.tmp.$$" "$REPORT" 2>/dev/null; then rm -f "$REPORT.tmp.$$" 2>/dev/null || true
    else
      # the old file cannot be replaced (open in another program?): this night's
      # report is the new file, and everything below names that one
      tick "could not replace runs/$(basename "$REPORT") — this night's report is runs/$(basename "$REPORT").tmp.$$"
      REPORT="$REPORT.tmp.$$"
    fi
  fi
  if [ "$RLOCK" = yes ]; then unlock .report; fi
  trail stop "ended the night" "$1" "runs/$(basename "$REPORT")" "spend \$$(spent)"
  # cross-model morning audit of the trail (show-me-your-work's "Attention" section).
  # Only the last lane standing runs it: it then sees the whole night, and two lanes
  # never write the same review files at once.
  if [ -n "$REVIEWER" ] && [ "$others" = no ] && ! over_budget && [ -s "$WS/runs/trail-$DATE.tsv" ]; then
    AP="$WS/runs/night-$DATE-attention.md"; rm -f "$AP"
    p_begin
    pv AGENT "$REVIEWER"; pv REPORT "$REPORT"; pv TRAIL "$WS/runs/trail-$DATE.tsv"; pv HANDOFFS_DIR "$HO"
    # Like the planner, the reviewer reads a detached snapshot of the night tip: a
    # lane that joins and integrates while it reads is never undone by its clean-up,
    # and nothing it leaves behind stays in the night worktree.
    RSNAP=""
    if [ -n "$NIGHT_WT" ]; then
      RSNAP=$(mktemp -d)/review
      git -C "$NIGHT_WT" worktree add -q --detach "$RSNAP" "$(git -C "$NIGHT_WT" rev-parse HEAD)" >/dev/null 2>&1 || RSNAP=""
    fi
    RD=${RSNAP:-$(mktemp -d)}; APW=$(out_path "$RD" attention.md)
    pv NIGHT_BRANCH "${NIGHT_BR:-(none — plain board night)}"; pv BASE "$BASEBR"; pv REPO "$REPO"; pv OUT_PATH "$APW"
    p_render review "$WS/runs/.review-$DATE.prompt"
    st0=$(tree_state "$RD"); at=$(git -C "$RD" rev-parse HEAD 2>/dev/null || true)
    guard_begin
    run_cli "$REVIEWER" "$RD" "$HELPER_MIN" "$WS/runs/.review-$DATE.prompt" "$WS/runs/.review-$DATE.out" || true
    charge "$WS/runs/.review-$DATE.out" "$(t_min)" "$REVIEWER"
    guard_end "reviewer $REVIEWER" || true
    collect "$APW" "$AP"
    [ -n "$at" ] && [ "$(tree_state "$RD")" != "$st0" ] && restore_tree "$RD" "$at" "$WS/runs/.review-$DATE.stray.diff"
    if [ -n "$RSNAP" ]; then git -C "$NIGHT_WT" worktree remove --force "$RSNAP" >/dev/null 2>&1 || rm -rf "${RSNAP:?}" 2>/dev/null || true; fi
    if [ -s "$AP" ]; then
      { echo; cat "$AP" 2>/dev/null || true; } >> "$REPORT"
    else
      printf '\n## Attention\nreviewer %s produced no attention file — see runs/.review-%s.out\n' "$REVIEWER" "$DATE" >> "$REPORT"
    fi
  fi
  [ "$others" = no ] && rm -f "$NIGHTF"
  tick "night end: $1 (report: runs/$(basename "$REPORT"))"
  notify "ended: $1 — spend \$$(spent). Report ready."
  sh "$WS/scripts/status.sh" >/dev/null 2>&1 || true
  FINISHED=yes
  exit "${2:-0}"
}

# --- one red attempt: pin the evidence, reset, decide retry or block ----------------
# $1 reason (one line), $2 "block" to skip the retry (agent or advisor says dead end)
# BY says what stopped it, so the morning reader knows whether the WORK failed:
#   task  the work itself (tests red, verifier said no, a dead end, a conflict)
#   rule  a runner rule refused it; the change may be fine (protect:, forbid_added,
#         the call budget, the test-first gate)
#   cli   the agent CLI failed or was cut off; nothing was learned about the task
# Set BY before calling red; it falls back to task after every call.
BY=task
red() {
  FAILS=$(( FAILS + 1 ))
  [ "$(git -C "$WT" rev-parse HEAD)" != "$PRE" ] && git -C "$WT" update-ref "refs/apsolut/attempts/$ID-$N" HEAD 2>/dev/null || true
  # most useful first: the retry and the advisor read the HEAD of this file, so a
  # long diff must never push the reason and the evidence out of their view
  {
    echo "attempt $N failed: $1 (rc=$RC)"
    [ -n "${VP:-}" ] && [ -f "$VP" ] && { echo; echo "The independent verifier's verdict:"; head -60 "$VP"; }
    [ -f "$HF" ] && { echo; echo "Its handoff:"; head -40 "$HF"; }
    echo; echo "Last output (incl. checks):"
    command tail -50 "$OUT"
    echo; echo "Diff it tried (vs $PRE), files first:"
    git -C "$WT" diff --stat "$PRE" HEAD 2>/dev/null | tail -30
    git -C "$WT" diff "$PRE" HEAD 2>/dev/null | head -300
  } > "$WS/runs/$ID-attempt$N.fail" 2>/dev/null || true
  git -C "$WT" reset --hard -q "$PRE" 2>/dev/null || true
  git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
  if [ "${2:-}" = block ] || [ "$N" -ge "$MAX_ATTEMPTS" ]; then
    rm -f "$CARDSNAP"   # unblocking means a human edits the card: judge the new one
    fm_set "$CARD" status blocked
    fm_set "$CARD" updated "$DATE"
    # the agent's Notes say what would unblock only when the agent itself stopped
    unb=""; [ "${2:-}" = block ] && unb=$(md_body "$HF" Notes 1)
    printf '\nAttempted: %s attempt(s) by %s, night %s (runs/%s)\nFailed because: %s\nBlocked by: %s\nWould unblock: %s\n' \
      "$N" "$AGENT" "$DATE" "$(basename "$OUT")" "$1" "$BY" "${unb:-a human reading runs/$ID-attempt$N.fail}" >> "$CARD"
    printf '\n### %s — %s (night shift)\n- %s BLOCKED (%s) after %s attempt(s): %s. See runs/%s\n' \
      "$AGENT" "$DATE" "$ID" "$BY" "$N" "$1" "$ID-attempt$N.fail" >> "$LOG"
    notify "$ID blocked ($BY): $1"
    tick "blocked $ID ($BY)"
    trail card "blocked $ID" "$BY: $1" "runs/$ID-attempt$N.fail" blocked
  else
    fm_set "$CARD" status waiting
    tick "red $ID attempt $N ($1) — will retry"
    trail card "red $ID attempt $N, will retry with the failure in the prompt" "$BY: $1" "runs/$ID-attempt$N.fail" red
  fi
  BY=task
}

echo "runner[$AGENT]: timeout=${TIMEOUT_MIN}m attempts=$MAX_ATTEMPTS breaker=$MAX_FAILS budget=$BUDGET_TXT stop=$STOP goal=$GOAL_MODE verifier=${VERIFIER:-none}"
tick "night start (budget $BUDGET_TXT, stop $STOP, goal mode $GOAL_MODE)"
trail start "started the lane" "goal mode $GOAL_MODE, verifier ${VERIFIER:-none}, advisor ${ADVISOR:-none}" "pid $$" "budget $BUDGET_TXT"
# --- waiting on a human (v0.13) ----------------------------------------------------
# Two things a card cannot fix and a retry cannot fix: the key that signs commits is
# locked, or a CLI lost its login. Marching the board through either blocks every
# card and trips the breaker. So the lane parks: the card goes back to waiting with
# its attempt returned, and the runner waits for the condition to clear.
SIGN=no; [ "$(git -C "$REPO" config --bool commit.gpgsign 2>/dev/null || true)" = true ] && SIGN=yes
sign_ok() { # can a commit be signed right now, without anyone approving a prompt?
  [ "$SIGN" = yes ] || return 0
  sgt=$(git -C "$REPO" rev-parse 'HEAD^{tree}' 2>/dev/null) || return 0
  timeout -k 5 30 git -C "$REPO" commit-tree -S "$sgt" -p HEAD -m "apsolut-agents: signing probe" \
    < /dev/null > /dev/null 2> "$WS/runs/.sign-probe.out"
}
sign_why() { sgw=$(grep -v '^$' "$WS/runs/.sign-probe.out" 2>/dev/null | head -1 | cut -c1-120)
  echo "commits cannot be signed (${sgw:-the signing key did not answer in 30s}) — unlock the key or its agent"; }
unattempt() { # the failure is not the card's: keep what it did, give the attempt back, free the card
  [ "$(git -C "$WT" rev-parse HEAD)" != "$PRE" ] && git -C "$WT" update-ref "refs/apsolut/attempts/$ID-$N" HEAD 2>/dev/null || true
  git -C "$WT" reset --hard -q "$PRE" 2>/dev/null || true
  git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
  echo $(( N - 1 )) > "$WS/runs/.attempts-$DATE-$ID"
  fm_set "$CARD" status waiting
  release; DID_ONE=no
}
park() { # $1 reason; the rest = a command that succeeds once a human has fixed it
  pkwhy=$1; shift
  tick "PARKED, waiting on a human: $pkwhy"
  notify "lane parked, waiting on a human: $pkwhy"
  trail lane "parked the lane" "$pkwhy" "" parked
  if [ "$ONCE" = yes ] || [ "$HUMAN_WAIT" -le 0 ]; then finish "waiting on a human: $pkwhy" 7; fi
  pkw=0
  while :; do
    sleep "$PARK_POLL"; pkw=$(( pkw + PARK_POLL ))
    [ -f "$WS/ANDON" ] && finish "andon: $(sed -n 's/^reason: //p' "$WS/ANDON")" 5
    if [ "$ARMED" = yes ] && in_stop_window; then finish "waiting on a human: $pkwhy" 7; fi
    if "$@"; then
      tick "resumed after $(( pkw / 60 ))m: no longer waiting on a human"
      trail lane "resumed the lane" "cleared: $pkwhy" "" resumed
      return 0
    fi
    [ "$pkw" -ge $(( HUMAN_WAIT * 60 )) ] && finish "waiting on a human: $pkwhy (gave up after ${HUMAN_WAIT}m)" 7
  done
}


FAILS=0
BASELINE_OK=no
# the night branch needs a signed commit too: do not open a night that cannot commit
sign_ok || park "$(sign_why)" sign_ok
[ "$GOAL_MODE" = yes ] && night_setup

deps_digest() { # $1 card → what its after: cards did (latest handoff), for the worker
  for d in $(fm_get "$1" after | tr -d '[]' | tr ',' ' '); do
    h=$(ls -t "$HO/$d"-attempt*.md 2>/dev/null | head -1 || true)
    [ -n "$h" ] || continue
    echo "### $d ($(fm_get "$WS/work/$d.md" status 2>/dev/null))"
    md_body "$h" "What I did" 10
    md_body "$h" Notes 10
  done | head -80
}
# the attempt reached an end the runner decided: drop its start marker with the claim
release() { rm -f "$WS/runs/.pre-$DATE-$ID" 2>/dev/null || true; rm -rf "$WS/claims/$ID"; CURRENT_ID=""; }
VBLOCKS=0

while :; do
  [ -f "$WS/ANDON" ] && finish "andon: $(sed -n 's/^reason: //p' "$WS/ANDON")" 5
  [ "$ONCE" = yes ] && [ "$DID_ONE" = yes ] && finish "once: one card through the pipeline" 0
  if [ "$ARMED" = no ]; then in_stop_window || ARMED=yes
  elif in_stop_window; then finish "stop_time" 0; fi
  over_budget && { notify "BUDGET CAP hit (\$$(spent))"; finish "budget" 3; }
  [ "$FAILS" -ge "$MAX_FAILS" ] && { notify "CIRCUIT BREAKER: $FAILS consecutive failures"; finish "breaker" 2; }
  sign_ok || park "$(sign_why)" sign_ok

  ID=$(pick_ready || true)
  if [ -z "$ID" ]; then
    if [ "$GOAL_MODE" = yes ]; then
      busy=no
      for f in "$WS"/work/*.md; do is_card "$f" || continue; [ "$(fm_get "$f" status)" = writing ] && [ "$(fm_get "$f" id)" != "$NIGHT_ID" ] && busy=yes; done
      if [ "$busy" = no ]; then
        if goal_met; then notify "GOAL MET on $NIGHT_BR"; finish "goal met" 0; fi
        if [ -n "$LAST_ROUND_IDS" ]; then
          if round_progressed; then NOPROG=0; else NOPROG=$((NOPROG+1)); fi
          [ "$NOPROG" -ge 2 ] && { notify "PLATEAU: two plan rounds landed nothing"; finish "plateau: two plan rounds in a row landed nothing" 6; }
        fi
        if lock .planning; then
          prc=0; plan_round || prc=$?
          unlock .planning
          case "$prc" in
            0) continue ;;
            1) notify "goal needs a human (STUCK)"; finish "planner: goal needs a human (runs/STUCK-$DATE.md)" 6 ;;
            2) trail plan "planner produced no usable card" "see the rejected rows above" "runs/plan-$DATE-r$(cat "$ROUND_FILE")/" empty
               NOPROG=$((NOPROG+1))
               [ "$NOPROG" -ge 2 ] && finish "plateau: planner produced no usable cards" 6
               continue ;;
            3) finish "plan rounds exhausted ($MAX_ROUNDS) — goal not met" 6 ;;
            4) sleep 900; continue ;;
          esac
        fi
      fi
    fi
    [ "$DRAIN" = yes ] && finish "board empty" 0
    tick "idle — no ready cards"; sleep "$POLL"; continue
  fi

  mkdir "$WS/claims/$ID" 2>/dev/null || { sleep 5; continue; }
  CURRENT_ID=$ID
  echo $$ > "$WS/claims/$ID/pid"
  CARD="$WS/work/$ID.md"
  # The card as FIRST claimed tonight is what gets judged, on every attempt. A worker
  # that edits its own card (a lower verify:, a softer check: or Done-when) changes
  # nothing: verify:, check: and the text the verifier reads all come from here.
  CARDSNAP="$WS/runs/.card-$DATE-$ID.md"
  [ -f "$CARDSNAP" ] || cp "$CARD" "$CARDSNAP"
  CHK=$(fm_get "$CARDSNAP" check)

  # test-first gate (PLAYBOOK §2): a check: command the runner runs, or a test named
  # on the card, or spike: true. (A word match, so "latest" no longer counts.)
  if [ -z "$CHK" ] && [ "$(fm_get "$CARDSNAP" spike)" != "true" ] && ! grep -qiwE 'tests?|specs?' "$CARDSNAP"; then
    fm_set "$CARD" status blocked
    printf '\nAttempted: claim by runner\nFailed because: no check: command, no test named on the card, and spike is not true (PLAYBOOK §2)\nBlocked by: rule\nWould unblock: add check: <command that fails now and passes when done>, or a failing-test criterion in Done-when\n' >> "$CARD"
    tick "refused $ID: test-first gate (PLAYBOOK §2)"
    trail claim "refused $ID" "test-first gate: no check, no test named, not a spike" "work/$ID.md" blocked
    rm -f "$CARDSNAP"; release; continue
  fi
  fm_set "$CARD" owner "$AGENT"
  fm_set "$CARD" status writing
  fm_set "$CARD" claimed "$(date -u +%Y-%m-%dT%H:%M:%SZ) pid:$$"
  fm_set "$CARD" updated "$DATE"
  DID_ONE=yes

  BR=$(fm_get "$CARD" branch); WT=$(fm_get "$CARD" worktree)
  if [ -z "$BR" ] || [ "$BR" = "null" ] || [ ! -d "${WT:-/nonexistent}" ]; then
    rm -f "$WS/runs/.pre-$DATE-$ID" 2>/dev/null || true   # a fresh worktree holds nothing interrupted
    if [ -n "$NIGHT_BR" ]; then
      sh "$WS/scripts/worktree.sh" spawn "$AGENT" "$ID" --base "$NIGHT_BR" >/dev/null
    else
      sh "$WS/scripts/worktree.sh" spawn "$AGENT" "$ID" >/dev/null
    fi
    WT=$(fm_get "$CARD" worktree); BR=$(fm_get "$CARD" branch)
    if ! setup_wt "$WT"; then
      fm_set "$CARD" status waiting; release
      notify "HARNESS: setup_cmd failed in a fresh worktree"
      finish "harness: setup_cmd failed in a fresh worktree (runs/.setup-$(basename "$WT").out)" 4
    fi
  fi
  # never run destructive git ops anywhere but a spawned worktree
  case "$(basename "$WT")" in
    *-wt-*) ;;
    *) tick "SKIP $ID: worktree path '$WT' is not a spawned worktree — refusing"
       fm_set "$CARD" status blocked
       release; FAILS=$((FAILS+1)); continue;;
  esac
  # A start marker that is still here belongs to an attempt whose runner stopped
  # half-way: its commits and files are still in the worktree. Keep them under a ref
  # and go back to where that attempt started, so check: is judged on a clean tree
  # and this attempt is a real one.
  PJ="$WS/runs/.pre-$DATE-$ID"
  if [ -f "$PJ" ]; then
    jp=$(cat "$PJ" 2>/dev/null || true)
    if [ -n "$jp" ] && git -C "$WT" cat-file -e "$jp^{commit}" 2>/dev/null; then
      jdirty=$(git -C "$WT" status --porcelain | grep -v '\.apsolut-agents' || true)
      if [ "$(git -C "$WT" rev-parse HEAD)" != "$jp" ] || [ -n "$jdirty" ]; then
        # keep all of it: commits under a ref, files not yet committed as a patch
        [ "$(git -C "$WT" rev-parse HEAD)" != "$jp" ] && git -C "$WT" update-ref "refs/apsolut/attempts/$ID-interrupted" HEAD 2>/dev/null || true
        if [ -n "$jdirty" ]; then
          git -C "$WT" add -A -- ':!.apsolut-agents' 2>/dev/null || true
          git -C "$WT" diff --cached --binary HEAD > "$WS/runs/$ID-interrupted.diff" 2>/dev/null || true
        fi
        git -C "$WT" reset --hard -q "$jp" 2>/dev/null || true
        git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
        if [ "$(git -C "$WT" rev-parse HEAD)" != "$jp" ] || [ -n "$(git -C "$WT" status --porcelain -uno | grep -v '\.apsolut-agents' || true)" ]; then
          # not clean: an attempt started here would be judged on the wrong tree. The
          # marker stays, so the card restarts properly once it is set to waiting.
          tick "blocked $ID (harness): its worktree could not be put back after an interrupted attempt"
          fm_set "$CARD" status blocked; fm_set "$CARD" updated "$DATE"
          printf '\nAttempted: restart after an interrupted attempt, night %s\nFailed because: the worktree could not be reset to where that attempt started\nBlocked by: harness\nWould unblock: close whatever still has a file open in %s, then set status: waiting\n' "$DATE" "$WT" >> "$CARD"
          rm -rf "$WS/claims/$ID"; CURRENT_ID=""
          continue
        fi
        tick "reset $ID to where its interrupted attempt started (what it had done is kept: refs/apsolut/attempts/$ID-interrupted, runs/$ID-interrupted.diff)"
      fi
    fi
  fi
  # goal mode: every attempt starts from the current night tip. A retry after a
  # merge conflict, or a card whose dependency landed meanwhile, builds on what is
  # integrated now. (After a red reset the card branch has no commits of its own,
  # so this is a fast-forward.)
  if [ -n "$NIGHT_BR" ] && git -C "$WT" merge-base --is-ancestor HEAD "$NIGHT_BR" 2>/dev/null; then
    git -C "$WT" merge --ff-only -q "$NIGHT_BR" >/dev/null 2>&1 || true
  fi
  PRE=$(git -C "$WT" rev-parse HEAD)
  echo "$PRE" > "$PJ"

  # harness-vs-card attribution: green must pass on the PRISTINE worktree before any
  # agent runs. A worktree contains only TRACKED files and green_cmd runs with cwd
  # set to it — a relative path or untracked helper makes every card read as "card
  # failed" while the harness is broken, blocking good work and tripping the breaker
  # (field incident 2026-08-11: cost 3 cards). Checked once per night, first worktree.
  if [ "$BASELINE_OK" != yes ]; then
    : > "$WS/runs/.baseline-$DATE.out"
    if run_check "$WT" "$GREEN" "$WS/runs/.baseline-$DATE.out"; then
      BASELINE_OK=yes
      tick "baseline green ok on pristine worktree"
      trail harness "baseline green passed on a pristine worktree" "a red harness must not read as red cards" "runs/.baseline-$DATE.out" green
    else
      fm_set "$CARD" status waiting
      release
      notify "HARNESS: green_cmd fails on a pristine worktree — night refused, no cards charged"
      tick "HARNESS FAILURE: green_cmd red on pristine worktree $WT (not a card failure) — runs/.baseline-$DATE.out"
      finish "harness: green_cmd red on pristine worktree" 4
    fi
  fi

  # check: is proved red BEFORE the change. A check that already passes means the
  # card is done or the check proves nothing; either way no model should run.
  if [ -n "$CHK" ]; then
    echo "check @ $PRE (must FAIL before the change): $CHK" > "$WS/runs/$ID-check-pre.out"
    if run_check "$WT" "$CHK" "$WS/runs/$ID-check-pre.out"; then
      git -C "$WT" reset --hard -q "$PRE"; git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
      fm_set "$CARD" status blocked; fm_set "$CARD" updated "$DATE"; rm -f "$CARDSNAP"
      printf '\nAttempted: claim by runner, night %s\nFailed because: check: already passes before any change (runs/%s-check-pre.out)\nBlocked by: rule\nWould unblock: a check that fails until the card is done, or close the card\n' "$DATE" "$ID" >> "$CARD"
      trail claim "refused $ID" "its check: passes before any change, so it proves nothing" "runs/$ID-check-pre.out" blocked
      release; continue
    fi
    git -C "$WT" reset --hard -q "$PRE"; git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
  fi

  N=$(( $(cat "$WS/runs/.attempts-$DATE-$ID" 2>/dev/null || echo 0) + 1 ))
  CB=$(pos_int_or "$(fm_get "$CARD" budget | tr -dc '0-9')" "$TIMEOUT_MIN")
  OUT="$WS/runs/$ID-attempt$N.out"
  HF="$HO/$ID-attempt$N.md"; rm -f "$HF"; VP=""
  PREVFAIL="$WS/runs/$ID-attempt$(( N - 1 )).fail"

  # advisor checkpoint ("stuck"): a different model reads the failure before the retry
  ADVICE=""
  if [ -f "$PREVFAIL" ] && [ -n "$ADVISOR" ]; then
    AP="$HO/$ID-advice$N.md"; rm -f "$AP"; APW=$(out_path "$WT" advice.md)
    p_begin; pv AGENT "$ADVISOR"; pv ID "$ID"; pv WT "$WT"; pvf CARD "$CARDSNAP"
    pv PREVFAIL "$(head -150 "$PREVFAIL")"; pv ADVICE_PATH "$APW"
    p_render advisor "$WS/runs/$ID-advice$N.prompt"
    st0=$(tree_state "$WT"); guard_begin
    run_cli "$ADVISOR" "$WT" "$HELPER_MIN" "$WS/runs/$ID-advice$N.prompt" "$WS/runs/$ID-advice$N.out" || true
    charge "$WS/runs/$ID-advice$N.out" "$(t_min)" "$ADVISOR"
    guard_end "advisor $ADVISOR" || finish "andon: tamper by the advisor" 5
    collect "$APW" "$AP"
    [ "$(tree_state "$WT")" != "$st0" ] && restore_tree "$WT" "$PRE" "$WS/runs/$ID-advice$N.stray.diff"
    if [ -s "$AP" ]; then
      ADVICE=$(head -60 "$AP")
      trail advise "advisor $ADVISOR read the failure of $ID" "retry gets a second model's diagnosis" "runs/handoffs/$ID-advice$N.md" advised
      if grep -qE '^[[:space:]*_>-]*CARD IS WRONG:' "$AP"; then
        fm_set "$CARD" status blocked; fm_set "$CARD" updated "$DATE"; rm -f "$CARDSNAP"
        printf '\nAttempted: %s attempt(s), then advisor %s\nFailed because: advisor says the card is wrong — %s\nBlocked by: task\nWould unblock: a human rewrites the card (runs/handoffs/%s)\n' \
          "$(( N - 1 ))" "$ADVISOR" "$(grep -m1 'CARD IS WRONG:' "$AP" | sed 's/.*CARD IS WRONG:[[:space:]]*//')" "$ID-advice$N.md" >> "$CARD"
        trail card "blocked $ID without a retry" "the advisor says the card itself is wrong" "runs/handoffs/$ID-advice$N.md" blocked
        release; continue
      fi
    fi
  fi

  HFW=$(out_path "$WT" handoff.md)
  p_begin
  pv AGENT "$AGENT"; pv WT "$WT"; pv BRANCH "$BR"; pv GOAL "$(goal_text)"; pv GREEN "$GREEN"
  pv HANDOFF_PATH "$HFW"; pvf CARD "$CARDSNAP"
  pv CHECK "${CHK:-(none on this card: name and write the failing test yourself)}"
  dd=$(deps_digest "$CARDSNAP")
  if [ -n "$dd" ]; then
    pv DEPS "$(printf '\n=== WHAT THE CARDS THIS ONE BUILDS ON DID (their handoffs; their code is in your tree) ===\n%s\n' "$dd")"
  else pv DEPS ""; fi
  if [ -f "$PREVFAIL" ]; then
    pv PREVFAIL "$(printf '\n=== PREVIOUS ATTEMPT FAILED — read this, do NOT repeat the same approach ===\n%s\n' "$(head -150 "$PREVFAIL")")"
  else pv PREVFAIL ""; fi
  if [ -n "$ADVICE" ]; then
    pv ADVICE "$(printf '\n=== ADVISOR (%s read that failure; weigh it, you are accountable) ===\n%s\n' "$ADVISOR" "$ADVICE")"
  else pv ADVICE ""; fi
  p_render worker "$WS/runs/$ID-attempt$N.prompt"

  tick "start $ID attempt $N (cap ${CB}m)"
  trail claim "started $ID attempt $N" "$(fm_get "$CARD" title)" "$BR @ $(printf '%.7s' "$PRE")" running
  guard_begin
  RC=0; run_cli "$AGENT" "$WT" "$CB" "$WS/runs/$ID-attempt$N.prompt" "$OUT" || RC=$?
  guard_end "worker $AGENT on $ID" || { RC=96; fm_set "$CARD" status blocked; finish "andon: tamper by the worker on $ID" 5; }
  charge "$OUT" "$(t_min)" "$AGENT"
  collect "$HFW" "$HF"

  GD=$(git -C "$WT" rev-parse --git-dir 2>/dev/null || true)
  [ -n "$GD" ] && rm -f "$GD/index.lock" 2>/dev/null || true

  if throttled "$OUT" "$RC"; then
    BOF="$WS/runs/.backoff-$DATE-$ID"; bo=$(( $(cat "$BOF" 2>/dev/null || echo 0) + 1 )); echo "$bo" > "$BOF"
    if [ "$bo" -le "$MAX_BACKOFF" ]; then
      tick "provider backoff on $ID ($bo/$MAX_BACKOFF, not an attempt)"
      trail card "backed off $ID ($bo/$MAX_BACKOFF)" "provider throttle, not the agent's failure" "runs/$(basename "$OUT")" backoff
      # salvage + pin BEFORE the reset: a throttle is not the agent's failure, and
      # destroying its uncommitted work on a 429 was pure evidence loss. The pinned
      # ref is gc-proof and invisible to branch listings; humans list/delete
      # refs/apsolut/* manually, same posture as worktree folders.
      if [ -n "$(git -C "$WT" status --porcelain | grep -v '\.apsolut-agents' || true)" ]; then
        git -C "$WT" add -A -- ':!.apsolut-agents' 2>/dev/null || git -C "$WT" add -A
        timeout -k 10 "$GIT_MAX" git -C "$WT" commit -q -m "$ID: salvaged before throttle backoff (attempt $N)" || true
      fi
      [ "$(git -C "$WT" rev-parse HEAD)" != "$PRE" ] && git -C "$WT" update-ref "refs/apsolut/attempts/$ID-$N-backoff-$bo" HEAD 2>/dev/null || true
      git -C "$WT" reset --hard -q "$PRE" 2>/dev/null || true
      git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
      fm_set "$CARD" status waiting
      release; DID_ONE=no   # --once means one card with an outcome, not one backoff
      sleep 900; continue
    fi
    echo "runner: provider throttled $bo times on this card tonight — counting it as a failed attempt" >> "$OUT"
  fi
  echo "$N" > "$WS/runs/.attempts-$DATE-$ID"

  # a CLI that stopped itself: its own timeout is a timeout whatever it exited with,
  # and "exit 0, turn never finished" is a failure, never a green candidate
  STOPWHY=$(cli_stop "$OUT")
  case "$STOPWHY" in
    timeout) case "$RC" in 124|137) ;; *) RC=124;; esac ;;
    cancelled|error|turns) [ "$RC" -ne 0 ] || RC=98 ;;
  esac

  # agent must still be on its card branch — anything else is a hard fail
  NOWBR=$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  [ "$NOWBR" = "$BR" ] || { RC=97; echo "runner: branch assert failed ($NOWBR != $BR)" >> "$OUT"; }

  if [ -n "$(git -C "$WT" status --porcelain | grep -v '\.apsolut-agents' || true)" ]; then
    git -C "$WT" add -A -- ':!.apsolut-agents' 2>/dev/null || git -C "$WT" add -A
    timeout -k 10 "$GIT_MAX" git -C "$WT" commit -q -m "$ID: uncommitted work salvaged by runner (attempt $N)" >> "$OUT" 2>&1 || { sign_ok || SIGNLOST=yes; }
  fi
  if [ "${SIGNLOST:-no}" = yes ]; then
    SIGNLOST=no
    git -C "$WT" diff --cached "$PRE" > "$WS/runs/$ID-attempt$N.parked.diff" 2>/dev/null || true
    unattempt
    park "$(sign_why); $ID's uncommitted work is kept in runs/$ID-attempt$N.parked.diff" sign_ok
    continue
  fi

  # the handoff: the file the agent wrote, else the handoff it printed as its final
  # message (JSON-escaped newlines undone), else a synthetic one naming the failure
  if [ ! -s "$HF" ] && grep -qE '#+ *Status' "$OUT" 2>/dev/null; then
    sed 's/\\n/\
/g; s/\\"/"/g; s/\\t/	/g' "$OUT" | awk '
      match($0, /#+ *[Ss]tatus/) { buf = substr($0, RSTART) "\n"; f = 1; next }
      f { buf = buf $0 "\n" } END { printf "%s", buf }' | sed '$ s/"[,}].*$//' | head -80 > "$HF"
    [ -n "$(h_status "$HF")" ] || rm -f "$HF"
  fi
  if [ ! -s "$HF" ]; then
    case "$RC" in
      124|137) fm="timeout after ${CB}m — the card is probably too big; split it" ;;
      97) fm="left its branch" ;;
      0) fm="finished without writing a handoff" ;;
      *) fm="CLI exited $RC" ;;
    esac
    case "$STOPWHY" in
      error) fm="CLI reported is_error:true" ;;
      cancelled) fm="the CLI ended the turn early (cancelled, or a tool it needed was denied) with no completed answer" ;;
      turns) fm="the CLI hit its own turn limit before finishing" ;;
      budget) fm="hit the per-call budget cap" ;;
    esac
    { printf '## Status\n(none — synthetic handoff written by runner.sh)\n\n## Failure mode\n%s\n\n## Notes\n- output: runs/%s\n\n## Output tail\n' "$fm" "$(basename "$OUT")"
      command tail -40 "$OUT"; } > "$HF"
  fi
  HSTAT=$(h_status "$HF"); VSELF=$(h_level "$HF")

  if [ "$HSTAT" = blocked ]; then
    red "the agent reported a dead end: $(md_body "$HF" Notes 1)" block
    release; continue
  fi

  # a card that used up a whole call budget is too big for one call: a retry at the
  # same size pays the cap a second time, so it goes to the human instead
  if [ "$STOPWHY" = budget ]; then
    BY=rule; red "hit the per-call budget cap — split the card or raise call_budget_usd" block
    release; continue
  fi

  echo "green_cmd @ $(git -C "$WT" rev-parse HEAD)" >> "$OUT"
  if [ "$RC" -ne 0 ]; then
    if ! probe_role "$AGENT"; then
      unattempt
      park "the $AGENT CLI stopped answering ($PROBE_WHY) — sign it in again" probe_role "$AGENT"
      continue
    fi
    fmode=$(md_first "$HF" "Failure mode")
    BY=cli; red "${fmode:-the agent CLI exited $RC}"
    release; continue
  fi
  if ! run_check "$WT" "$GREEN" "$OUT"; then
    red "green_cmd red at $(git -C "$WT" rev-parse --short HEAD)"
    release; continue
  fi
  # the judge is not the worker's to edit, and symptom patches are not fixes
  ph=$(protected_hits "$WT" "$PRE" HEAD)
  if [ -n "$ph" ]; then
    BY=rule; red "changed protected path(s): $ph — the checks are not the worker's to edit"
    release; continue
  fi
  fh=$(forbidden_hits "$WT" "$PRE" HEAD)
  if [ -n "$fh" ]; then
    BY=rule; red "added a forbidden symptom patch (forbid_added): $(printf '%s' "$fh" | head -1 | cut -c1-140)"
    release; continue
  fi
  # check: must pass AFTER the change — the runner runs it, the worker's word is a claim
  CHECKED=no
  if [ -n "$CHK" ]; then
    echo "check @ $(git -C "$WT" rev-parse HEAD) (must PASS after the change): $CHK" >> "$OUT"
    if ! run_check "$WT" "$CHK" "$OUT"; then
      red "check: still red after the change ($CHK)"
      release; continue
    fi
    [ -z "$(git -C "$WT" status --porcelain -uno | grep -v '\.apsolut-agents' || true)" ] || {
      BY=rule; red "check: changed tracked files — a check must not edit"; release; continue; }
    CHECKED=yes
  fi
  trail card "green $ID attempt $N" "$( [ "$CHECKED" = yes ] && echo "green_cmd and check: decide" || echo "green_cmd decides"), not the agent's claim" "runs/$(basename "$OUT") @ $(git -C "$WT" rev-parse --short HEAD)" "green (self: ${VSELF:-none}, handoff: ${HSTAT:-none})"

  # independent verification: a different agent runs the change; the author's word is a claim
  VLEVEL="self:${VSELF:-none}"; PASS=yes
  [ "$CHECKED" = yes ] && VLEVEL="check-passed"
  NEED=$(fm_get "$CARDSNAP" verify); NEED=${NEED:-$VERIFY_LEVEL}
  # risk routing: the card's risk: tags pick who judges it. Read from the snapshot,
  # so a worker cannot drop its own tag.
  RTAG=$(risky_tag "$CARDSNAP"); VAG=$VERIFIER
  [ -n "$RTAG" ] && [ -n "$RISK_VERIFIER" ] && VAG=$RISK_VERIFIER
  if [ -n "$VAG" ]; then
    VP="$HO/$ID-verify$N.md"; rm -f "$VP"; VPW=$(out_path "$WT" verdict.md)
    SCRW=$(out_path "$WT" "scratch-$N"); mkdir -p "$SCRW"
    HEADC=$(git -C "$WT" rev-parse HEAD)
    p_begin
    pv AGENT "$VAG"; pv ID "$ID"; pv WT "$WT"; pv BRANCH "$BR"; pv BASE "$PRE"; pv SCRATCH "$SCRW"
    pv GREEN "$GREEN"; pv CHECK "${CHK:-(none on this card)}"; pvf CARD "$CARDSNAP"; pvf HANDOFF "$HF"; pv VERDICT_PATH "$VPW"
    p_render verifier "$WS/runs/$ID-verify$N.prompt"
    st0=$(tree_state "$WT"); guard_begin
    rcv=0; run_cli "$VAG" "$WT" "$HELPER_MIN" "$WS/runs/$ID-verify$N.prompt" "$WS/runs/$ID-verify$N.out" || rcv=$?
    charge "$WS/runs/$ID-verify$N.out" "$(t_min)" "$VAG"
    guard_end "verifier $VAG on $ID" || finish "andon: tamper by the verifier on $ID" 5
    collect "$VPW" "$VP"
    # evidence outlives the worktree cleanup: screenshots, logs, repro scripts
    if [ -n "$(ls -A "$SCRW" 2>/dev/null)" ]; then
      rm -rf "${EVD:?}/$ID-verify$N" 2>/dev/null || true
      # the scratch folder goes only once its content is safe under runs/evidence
      if mv "$SCRW" "$EVD/$ID-verify$N" 2>/dev/null || cp -r "$SCRW" "$EVD/$ID-verify$N" 2>/dev/null; then
        rm -rf "$SCRW" 2>/dev/null || true
      fi
    else
      rm -rf "$SCRW" 2>/dev/null || true
    fi
    if [ "$(tree_state "$WT")" != "$st0" ]; then
      restore_tree "$WT" "$HEADC" "$WS/runs/$ID-verify$N.stray.diff"
      VLEVEL=verifier-blocked; why="the verifier edited tracked files; its verdict was thrown away"
    elif [ "$rcv" -ne 0 ]; then
      VLEVEL=verifier-blocked; why="the verifier CLI exited $rcv$(throttled "$WS/runs/$ID-verify$N.out" "$rcv" && echo " (provider throttle)" || true)"
      throttled "$WS/runs/$ID-verify$N.out" "$rcv" || probe_role "$VAG" || VPARK="the verifier CLI ($VAG) stopped answering ($PROBE_WHY) — sign it in again"
    else
      VLEVEL=$(h_level "$VP"); why=$(md_body "$VP" Findings 1)
      [ -n "$VLEVEL" ] || { VLEVEL=verifier-blocked; vs=$(cli_stop "$WS/runs/$ID-verify$N.out")
        why="the verifier wrote no verdict${vs:+ (its CLI stopped: $vs)}"; }
    fi
    git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
    if [ -n "${VPARK:-}" ]; then
      pkv=$VPARK; VPARK=""
      unattempt
      park "$pkv" probe_role "$VAG"
      continue
    fi
    if [ "$VLEVEL" = verifier-blocked ]; then
      PASS=blocked; VBLOCKS=$((VBLOCKS+1))
    elif [ "$VLEVEL" = verifier-failed ] || [ "$(rank "$VLEVEL")" -lt "$(need_rank "$NEED")" ]; then
      PASS=no; VBLOCKS=0
    else VBLOCKS=0; fi
    trail verify "$VAG judged $ID: $VLEVEL" "needs $NEED${RTAG:+; risk tag $RTAG}; ${why:-}" "runs/handoffs/$ID-verify$N.md" "$PASS"
    if [ "$VBLOCKS" -ge 2 ]; then
      TRAIL_LANE=$AGENT sh "$WS/scripts/andon.sh" raise "verifier $VAG blocked on two cards in a row (last: $why) — its harness is broken, every card would land unverified" >/dev/null 2>&1 || true
      trail andon "stopped the night" "two verifier-blocked verdicts in a row" "runs/handoffs/$ID-verify$N.md" ANDON
    fi
  elif [ "$GOAL_MODE" = yes ] && [ "$CHECKED" != yes ]; then
    # goal mode never integrates on the author's word alone: something other than
    # the author (the runner's check: or a verifier) has to prove each card
    PASS=unverified
  elif [ "$GOAL_MODE" = yes ] && [ -n "$RTAG" ]; then
    # a risk-tagged card needs a second pair of eyes: its own check: is not enough
    PASS=riskhold
    trail verify "kept $ID off the night branch" "risk tag $RTAG and no verifier is configured" "work/$ID.md" risk-unverified
  fi
  case "$PASS" in
    blocked) fm_set "$CARD" verified blocked ;;
    unverified) fm_set "$CARD" verified unverified ;;
    riskhold) fm_set "$CARD" verified risk-unverified ;;
    *) fm_set "$CARD" verified "$VLEVEL" ;;
  esac

  if [ "$PASS" = no ]; then
    red "independent verifier said $VLEVEL (needs $NEED)"
    release; continue
  fi

  # the card stays "writing" until its merge is decided: a runner that stops during
  # the merge leaves a card the next start puts back on the board, not one that
  # reads as finished and never lands
  INTEG=""
  if [ -n "$NIGHT_BR" ] && [ "$PASS" = yes ]; then
    if integrate "$ID" "$BR" "$OUT" "$CHK"; then
      fm_set "$CARD" integrated "$NIGHT_BR"; fm_set "$CARD" status review; INTEG=", integrated into $NIGHT_BR"
      trail integrate "merged $ID into the night branch" "green and verified ($VLEVEL)" "$NIGHT_BR @ $(git -C "$NIGHT_WT" rev-parse --short HEAD)" integrated
    else
      # the merge commit is signed: a key that locked after the worker's commit is
      # not the card's failure
      if ! sign_ok; then
        trail integrate "kept $ID off the night branch" "the merge could not be signed" "runs/$(basename "$OUT")" parked
        unattempt
        park "$(sign_why); $ID was green and is redone once signing works" sign_ok
        continue
      fi
      # merges are tasks: a card that cannot land is red, and its retry starts
      # from the current night tip with the conflict or the red output in its prompt
      trail integrate "kept $ID off the night branch" "merge conflict or green red after the merge" "runs/$(basename "$OUT")" refused
      red "could not land on the night branch ($(grep -E '^(MERGE CONFLICT|GREEN RED)' "$OUT" | tail -1 | cut -c1-160 || echo 'see the output')) — retry from the current night tip"
      release; continue
    fi
  fi
  fm_set "$CARD" status review
  FAILS=0
  printf '\n### %s — %s (night shift)\n- %s done (attempt %s): green, verified %s%s. Output: runs/%s\n' \
    "$AGENT" "$DATE" "$ID" "$N" "$VLEVEL" "$INTEG" "$(basename "$OUT")" >> "$LOG"
  tick "green $ID ($VLEVEL)"
  release
done
