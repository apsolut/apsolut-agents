#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 apsolut — https://github.com/apsolut/apsolut-agents
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
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
warn() { WARN=$((WARN+1)); printf '  WARN  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }

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

# --- heartbeat ---------------------------------------------------------------------
echo "[heartbeat]"
GREEN=""
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
    if [ "$(fm_get "$f" spike)" != "true" ] && ! grep -qi "test" "$f"; then
      warn "$i: names no test and spike is not true — the night runner will refuse it (PLAYBOOK §2)"
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
        [ "$dst" = "done" ] || warn "$id waits on $dep (status: ${dst:-?}) — after: clears only on MERGE, unreachable overnight"
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
echo "[costs]"
BUDGET=$(num_or "$(cfg night_budget_usd)" 100)
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
  PER=$(awk "BEGIN{printf \"%.0f\", ($AVG > 0) ? $BUDGET / $AVG : 0}")
  ok "rolling avg \$$AVG/attempt ($ATTEMPTS attempts over $DAYS day(s)) — budget \$$BUDGET ≈ $PER attempts/night"
  awk "BEGIN{exit !($AVG > $FB * 2)}" && warn "avg \$$AVG is >2x cost_fallback_usd (\$$FB) — raise the fallback or budgets overshoot when cost output is missing"
else
  warn "no spend history yet — budgeting flies on cost_fallback_usd (\$$FB/card) until real cost data exists"
fi

# --- optional live probes ----------------------------------------------------------
if [ $# -gt 0 ]; then
  echo "[probe]"
  for AG in "$@"; do
    CMD=$(cfg "cmd_$AG")
    if [ -z "$CMD" ]; then fail "$AG: no cmd_$AG: in HEARTBEAT.md"; continue; fi
    PD=$(mktemp -d)
    if OUTP=$( cd "$PD" && timeout -k 10 180 sh -c "$CMD \"\$1\"" doctor "Reply with the single word: ok" 2>&1 ); then
      rm -rf "$PD"
      if printf '%s' "$OUTP" | grep -q '"is_error"[[:space:]]*:[[:space:]]*true'; then
        fail "$AG: CLI answered but is_error:true (refusal/infra?) — a lane would burn the board"
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
