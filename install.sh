#!/bin/sh
# install.sh — install or upgrade the .apsolut-agents/ workspace.
#
# Local (from a clone):
#   sh install.sh <target-repo> [--refresh] [--wire] [--tag vX.Y.Z]
# Remote (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/apsolut/apsolut-agents/main/install.sh | sh -s -- . [--wire]
#
# Fresh install copies the payload to <target>/.apsolut-agents/ (refuses if it exists).
# --refresh overwrites files labeled kind=doc|generated and NEVER touches kind=instance
# (your log, state, PROJECT.md, decisions, charters, work files).
# --wire inserts the bootstrap block into CLAUDE.md/AGENTS.md between markers (idempotent).
# --tag pins a release; default is main.
set -eu

REPO_URL=https://github.com/apsolut/apsolut-agents
TARGET=""; REFRESH=no; WIRE=no; TAG=main
while [ $# -gt 0 ]; do
  case "$1" in
    --refresh) REFRESH=yes ;;
    --wire)    WIRE=yes ;;
    --tag)     shift; TAG=${1:?--tag needs a value} ;;
    -*)        echo "unknown flag: $1" >&2; exit 2 ;;
    *)         TARGET=$1 ;;
  esac
  shift
done
[ -n "$TARGET" ] || { echo "usage: install.sh <target-repo> [--refresh] [--wire] [--tag vX.Y.Z]" >&2; exit 2; }
[ -d "$TARGET" ] || { echo "error: target '$TARGET' is not a directory" >&2; exit 1; }
TB=$(cd "$TARGET" && pwd)
DEST="$TB/.apsolut-agents"

# --- locate the payload: local template/ next to this script, else fetch from GitHub
CLEANUP=""
trap '[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"' EXIT
SCRIPTDIR=$(cd "$(dirname "$0" 2>/dev/null || echo .)" 2>/dev/null && pwd || echo "")
if [ -n "$SCRIPTDIR" ] && [ -d "$SCRIPTDIR/template" ]; then
  SRC="$SCRIPTDIR/template"
  VER=$(cat "$SCRIPTDIR/VERSION" 2>/dev/null | tr -d ' \r\n' || echo dev)
else
  CLEANUP=$(mktemp -d)
  case "$TAG" in main) REF=refs/heads/main ;; *) REF=refs/tags/$TAG ;; esac
  echo "fetching payload ($TAG) from $REPO_URL ..."
  curl -fsSL "$REPO_URL/archive/$REF.tar.gz" | tar xz -C "$CLEANUP"
  SRC=$(ls -d "$CLEANUP"/apsolut-agents-*/template)
  VER=$(cat "$CLEANUP"/apsolut-agents-*/VERSION 2>/dev/null | tr -d ' \r\n' || echo "$TAG")
fi
[ -n "${VER:-}" ] || VER=dev

kind_of() { # read the kind= from a file's first 5 lines; empty if unlabeled
  head -5 "$1" 2>/dev/null | sed -n 's/.*apsolut-agents: tier=[0-9ref]* kind=\([a-z]*\).*/\1/p' | head -1
}

if [ "$REFRESH" = no ]; then
  [ -e "$DEST" ] && { echo "error: $DEST already exists — use --refresh to upgrade" >&2; exit 1; }
  mkdir -p "$DEST"
  (cd "$SRC" && find . -type d -exec mkdir -p "$DEST/{}" \; )
  (cd "$SRC" && find . -type f | while read -r f; do cp "$f" "$DEST/$f"; done)
  printf '%s\n' "$VER" > "$DEST/VERSION"
  echo "installed v$VER → $DEST"
  echo
  echo "Next (see $DEST/INSTALL.md):"
  echo "  1. Fill in .apsolut-agents/PROJECT.md (commands, hot files, human gates, roster)"
  echo "  2. Delete the tiers you don't need (tier labels are on line 1 of every file)"
  echo "  3. Fill the narrative in state/PROJECT_STATE.md, then: sh .apsolut-agents/scripts/status.sh"
  [ "$WIRE" = yes ] || echo "  4. Paste CLAUDE-SNIPPET.md into your CLAUDE.md / AGENTS.md (or rerun with --wire)"
else
  [ -d "$DEST" ] || { echo "error: $DEST does not exist — run without --refresh to install" >&2; exit 1; }
  OLD=$(cat "$DEST/VERSION" 2>/dev/null | tr -d ' \r\n' || echo unknown)
  (cd "$SRC" && find . -type d -exec mkdir -p "$DEST/{}" \; )
  cd "$SRC"
  find . -type f | while read -r f; do
    rel=${f#./}
    if [ ! -e "$DEST/$rel" ]; then
      cp "$f" "$DEST/$rel"; echo "  added:   $rel"
    else
      case "$(kind_of "$f")" in
        doc|generated) cp "$f" "$DEST/$rel"; echo "  updated: $rel" ;;
        instance)      echo "  kept:    $rel (instance — yours)" ;;
        *)             echo "  kept:    $rel (unlabeled — not overwriting)" ;;
      esac
    fi
  done
  printf '%s\n' "$VER" > "$DEST/VERSION"
  echo "refreshed → $DEST (${OLD:-unknown} → $VER; instance files untouched)"
  echo "tip: re-run sh $DEST/scripts/status.sh to regenerate the board"
fi

# --- --wire: insert the bootstrap block into CLAUDE.md / AGENTS.md (idempotent)
if [ "$WIRE" = yes ]; then
  MARK_B="<!-- apsolut-agents:begin -->"
  MARK_E="<!-- apsolut-agents:end -->"
  wire_file() {
    if [ -f "$1" ] && grep -qF "$MARK_B" "$1"; then
      echo "  wired:   $(basename "$1") (marker already present — skipped)"
      return 0
    fi
    {
      echo ""
      echo "$MARK_B"
      sed -n '/^```markdown$/,/^```$/p' "$DEST/CLAUDE-SNIPPET.md" | sed '1d;$d'
      echo "$MARK_E"
    } >> "$1"
    echo "  wired:   $(basename "$1")"
  }
  DID=no
  for f in CLAUDE.md AGENTS.md; do
    [ -f "$TB/$f" ] && { wire_file "$TB/$f"; DID=yes; }
  done
  [ "$DID" = no ] && { wire_file "$TB/CLAUDE.md"; echo "  (created CLAUDE.md)"; }
fi
