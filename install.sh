#!/bin/sh
# install.sh <target-repo> [--refresh] — install or upgrade the .apsolut-agents/ workspace.
# Fresh install: copies template/ → <target>/.apsolut-agents/ (refuses if it exists).
# --refresh: overwrites files labeled kind=doc or kind=generated; NEVER touches
# kind=instance files (your log, state, PROJECT.md, decisions, charters, work files).
set -eu

usage() { echo "usage: sh install.sh <target-repo> [--refresh]" >&2; exit 2; }
[ $# -ge 1 ] || usage
TARGET=$1
REFRESH=no
[ "${2:-}" = "--refresh" ] && REFRESH=yes

SRC=$(cd "$(dirname "$0")/template" && pwd)
[ -d "$TARGET" ] || { echo "error: target '$TARGET' is not a directory" >&2; exit 1; }
DEST=$(cd "$TARGET" && pwd)/.apsolut-agents

kind_of() { # read the kind= from a file's first 5 lines; empty if unlabeled
  head -5 "$1" 2>/dev/null | sed -n 's/.*apsolut-agents: tier=[0-9ref]* kind=\([a-z]*\).*/\1/p' | head -1
}

if [ "$REFRESH" = no ]; then
  [ -e "$DEST" ] && { echo "error: $DEST already exists — use --refresh to upgrade" >&2; exit 1; }
  mkdir -p "$DEST"
  (cd "$SRC" && find . -type d -exec mkdir -p "$DEST/{}" \; )
  (cd "$SRC" && find . -type f | while read -r f; do cp "$f" "$DEST/$f"; done)
  echo "installed → $DEST"
  echo
  echo "Next (see $DEST/INSTALL.md):"
  echo "  1. Fill in .apsolut-agents/PROJECT.md (commands, hot files, human gates)"
  echo "  2. Delete the tiers you don't need (tier labels are on line 1 of every file)"
  echo "  3. Fill the narrative in state/PROJECT_STATE.md, then: sh .apsolut-agents/scripts/status.sh"
  echo "  4. Paste CLAUDE-SNIPPET.md into your CLAUDE.md / AGENTS.md"
else
  [ -d "$DEST" ] || { echo "error: $DEST does not exist — run without --refresh to install" >&2; exit 1; }
  UPDATED=0; SKIPPED=0; ADDED=0
  (cd "$SRC" && find . -type d -exec mkdir -p "$DEST/{}" \; )
  cd "$SRC"
  find . -type f | while read -r f; do
    rel=${f#./}
    if [ ! -e "$DEST/$rel" ]; then
      cp "$f" "$DEST/$rel"; echo "  added:   $rel"
    else
      k=$(kind_of "$f")
      case "$k" in
        doc|generated) cp "$f" "$DEST/$rel"; echo "  updated: $rel" ;;
        instance)      echo "  kept:    $rel (instance — yours)" ;;
        *)             echo "  kept:    $rel (unlabeled — not overwriting)" ;;
      esac
    fi
  done
  echo "refreshed → $DEST (instance files untouched)"
  echo "tip: re-run sh $DEST/scripts/status.sh to regenerate the board"
fi
