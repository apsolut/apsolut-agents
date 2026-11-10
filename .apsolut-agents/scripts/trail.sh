#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 apsolut — https://github.com/apsolut/apsolut-agents
# trail.sh <phase> <decision> <why> <evidence> <result> — append one row to tonight's
# decision trail, runs/trail-<date>.tsv (one row per decision, append-only).
# runner.sh writes a row at every claim, verdict, integration, plan round and stop;
# a human or an interactive agent may add rows the same way. Evidence is a pointer
# (commit, file:line, runs/ path), never prose. A wrong row is superseded by a new
# row, never edited. Pattern credit: pstack show-me-your-work (cursor/plugins, MIT).
# Env: TRAIL_LANE (default: $USER or "human"), TRAIL_DATE (default: today).
set -eu

[ $# -eq 5 ] || { echo "usage: trail.sh <phase> <decision> <why> <evidence> <result>" >&2; exit 2; }

WS=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$WS/.primary" ] && WS=$(cat "$WS/.primary")
DATE=${TRAIL_DATE:-$(date +%Y-%m-%d)}
F="$WS/runs/trail-$DATE.tsv"
mkdir -p "$WS/runs"

# one line per cell; a leading = + - @ is quoted so a spreadsheet never evaluates it
cell() { printf '%s' "$1" | tr '\t\r\n' '   ' | sed "s/^\([=+@-]\)/'\1/"; }

[ -f "$F" ] || printf 'ts\tlane\tphase\tdecision\twhy\tevidence\tresult\n' > "$F"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(cell "${TRAIL_LANE:-${USER:-human}}")" \
  "$(cell "$1")" "$(cell "$2")" "$(cell "$3")" "$(cell "$4")" "$(cell "$5")" >> "$F"
