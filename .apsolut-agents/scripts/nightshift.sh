#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 Aleksandar Perisic (apsolut) — https://github.com/apsolut/apsolut-agents
# nightshift.sh <agent> [--once|--drain] — start a night and watch it, in colour.
#
# A thin front for runner.sh: the same arguments, the same exit code, nothing decided
# here. While the runner works it shows this lane's TICK lines from agent-log.md as
# they are written, and at the end it prints how the night ended and what waits on
# you. Use runner.sh directly when nothing should watch (cron, a service).
#
# Colour: on for a terminal, off when the output is piped or NO_COLOR is set, forced
# with CLICOLOR_FORCE=1. Green = landed, yellow = waiting or retrying, red = blocked.
set -eu

WS=$(cd "$(dirname "$0")/.." && pwd)
LOG="$WS/agent-log.md"
AGENT=${1:?usage: nightshift.sh <agent> [--once|--drain]}

if [ -n "${NO_COLOR:-}" ]; then COLOR=no
elif [ "${CLICOLOR_FORCE:-0}" = 1 ] || [ -t 1 ]; then COLOR=yes
else COLOR=no; fi
E=$(printf '\033')
if [ "$COLOR" = yes ]; then
  RED="${E}[31m"; GRN="${E}[32m"; YEL="${E}[33m"; MAG="${E}[1;35m"; DIM="${E}[2m"; BLD="${E}[1m"; OFF="${E}[0m"
else RED=""; GRN=""; YEL=""; MAG=""; DIM=""; BLD=""; OFF=""; fi

# one TICK line in, one coloured line out: "HH:MM  what happened"
paint() {
  awk -v a="$AGENT" -v red="$RED" -v grn="$GRN" -v yel="$YEL" -v dim="$DIM" -v off="$OFF" '
    { line = $0; sub("^TICK: " a " [0-9][0-9]-[0-9][0-9] ", "", line)
      t = substr(line, 1, 5); msg = substr(line, 7); c = ""
      if (msg ~ /^(blocked|red )|BLOCKED|FAILED|BREAKER|BUDGET CAP|andon|Andon|tamper|DIED/) c = red
      else if (msg ~ /PARKED|backoff|will retry|waiting on a human|unverified|SKIP|rolled the night branch back|interrupted attempt/) c = yel
      else if (msg ~ /^(green|integrated|resumed|night end)|goal met|verified|merged/) c = grn
      printf "%s%s%s  %s%s%s\n", dim, t, off, c, msg, (c == "" ? "" : off); fflush() }'
}

printf '%s  NIGHT SHIFT  %s lane %s%s%s  %s\n' "$MAG" "$OFF" "$BLD" "$AGENT" "$OFF" "${2:-until stop_time}"

# follow the log by polling: portable, and it stops when we say so
STOPF=$(mktemp); rm -f "$STOPF"
seen=$(wc -l < "$LOG" 2>/dev/null || echo 0)
(
  while :; do
    total=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    if [ "$total" -gt "$seen" ]; then
      sed -n "$(( seen + 1 )),${total}p" "$LOG" | grep "^TICK: $AGENT " | paint || true
      seen=$total
    fi
    [ -f "$STOPF" ] && break
    sleep 1
  done
) &
FOLLOW=$!
trap 'touch "$STOPF"; wait "$FOLLOW" 2>/dev/null || true; rm -f "$STOPF"' EXIT INT TERM

rc=0
sh "$WS/scripts/runner.sh" "$@" || rc=$?
touch "$STOPF"; wait "$FOLLOW" 2>/dev/null || true

# a runner that wrote no "night end" line wrote no report either: the newest report
# on disk is an older night's, so do not show it as this one
if ! sed -n "$(( seen + 1 )),\$p" "$LOG" 2>/dev/null | grep -q "^TICK: $AGENT .* night end: "; then
  echo
  printf '%sThe runner stopped without a report (exit %s).%s agent-log.md and runs/trail-*.tsv hold the night so far.\n' "$RED" "$rc" "$OFF"
  exit "$rc"
fi

# the runner names its report in its last line; the newest on disk is the fallback
rname=$(sed -n "$(( seen + 1 )),\$p" "$LOG" 2>/dev/null | sed -n "s/^TICK: $AGENT .* night end: .*(report: \(runs\/[^)]*\))\$/\1/p" | tail -1)
REPORT=""
if [ -n "$rname" ] && [ -f "$WS/$rname" ]; then REPORT="$WS/$rname"; fi
[ -n "$REPORT" ] || REPORT=$(ls -t "$WS"/runs/night-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md 2>/dev/null | head -1 || true)
if [ -n "$REPORT" ]; then
  case "$rc" in 0) c=$GRN ;; 7|6) c=$YEL ;; *) c=$RED ;; esac
  echo
  # with several lanes the report has one "Ended:" line each: show this lane's
  ended=$(sed -n 's/^Ended: //p' "$REPORT" | grep " — lane: $AGENT\$" | head -1 || true)
  [ -n "$ended" ] || ended=$(sed -n 's/^Ended: //p' "$REPORT" | head -1)
  printf '%s%s%s\n' "$c" "$ended" "$OFF"
  wait_on=$(awk '/^## Waiting on you/{f=1;next} /^## |^Decision trail:/{f=0} f&&NF' "$REPORT")
  if [ -n "$wait_on" ] && [ "$wait_on" != "(nothing)" ]; then
    printf '%sWaiting on you:%s\n%s\n' "$BLD" "$OFF" "$wait_on"
  else
    printf '%sNothing is waiting on you.%s\n' "$DIM" "$OFF"
  fi
  printf '%sreport: %s%s\n' "$DIM" "${REPORT#"$WS"/}" "$OFF"
fi
exit "$rc"
