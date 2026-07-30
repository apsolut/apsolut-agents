#!/bin/sh
# install.sh — install or upgrade the .apsolut-agents/ workspace.
#
# Local (from a clone):
#   sh install.sh <target-repo> [--refresh] [--wire] [--tag vX.Y.Z] [--dry-run]
# Remote (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/apsolut/apsolut-agents/main/install.sh | sh -s -- . [--wire]
#
# Fresh install copies the payload to <target>/.apsolut-agents/ (refuses if it exists).
# --refresh overwrites files labeled kind=doc|generated and NEVER touches kind=instance
# (your log, state, PROJECT.md, decisions, charters, work files).
# --wire APPENDS the bootstrap block to CLAUDE.md/AGENTS.md between two HTML-comment
# markers — never rewrites existing content, skipped if the begin marker is present.
# --tag pins a release; default is main.
# --dry-run prints every file it would write and the exact CLAUDE.md block, and
# changes nothing under <target>. (On the curl path it still fetches to a temp dir.)
#
# Sandboxed/permission-restricted agents that cannot execute this script: the manual
# equivalent is documented in template/INSTALL.md §1 — three steps, plus a diff command
# that proves the result matches this installer byte-for-byte.
set -eu

REPO_URL=https://github.com/apsolut/apsolut-agents
TARGET=""; REFRESH=no; WIRE=no; TAG=main; DRY=no
while [ $# -gt 0 ]; do
  case "$1" in
    --refresh) REFRESH=yes ;;
    --wire)    WIRE=yes ;;
    --dry-run) DRY=yes ;;
    --tag)     shift; TAG=${1:?--tag needs a value} ;;
    -*)        echo "unknown flag: $1" >&2; exit 2 ;;
    *)         TARGET=$1 ;;
  esac
  shift
done
[ -n "$TARGET" ] || { echo "usage: install.sh <target-repo> [--refresh] [--wire] [--tag vX.Y.Z] [--dry-run]" >&2; exit 2; }
[ -d "$TARGET" ] || { echo "error: target '$TARGET' is not a directory" >&2; exit 1; }
TB=$(cd "$TARGET" && pwd)
DEST="$TB/.apsolut-agents"

# --- locate the payload: local template/ next to this script, else fetch from GitHub
CLEANUP=""
trap 'if [ -n "$CLEANUP" ]; then rm -rf "$CLEANUP"; fi' EXIT
SCRIPTDIR=$(cd "$(dirname "$0" 2>/dev/null || echo .)" 2>/dev/null && pwd || echo "")
if [ -n "$SCRIPTDIR" ] && [ -d "$SCRIPTDIR/template" ]; then
  SRC="$SCRIPTDIR/template"
  VERFILE="$SCRIPTDIR/VERSION"; VERFALLBACK=dev
else
  CLEANUP=$(mktemp -d)
  case "$TAG" in main) REF=refs/heads/main ;; *) REF=refs/tags/$TAG ;; esac
  echo "fetching payload ($TAG) from $REPO_URL ..."
  # fetch to a file rather than piping into tar, so a 404 reports as itself
  # instead of "gzip: stdin: unexpected end of file"
  curl -fsSL "$REPO_URL/archive/$REF.tar.gz" -o "$CLEANUP/payload.tar.gz" \
    || { echo "error: could not fetch '$TAG' from $REPO_URL — check the tag name" >&2; exit 1; }
  tar xzf "$CLEANUP/payload.tar.gz" -C "$CLEANUP"
  SRC=$(ls -d "$CLEANUP"/apsolut-agents-*/template)
  VERFILE=$(ls "$CLEANUP"/apsolut-agents-*/VERSION 2>/dev/null | head -1)
  VERFALLBACK=$TAG
fi
# read VERSION; the fallback must be a separate step — `cat f | tr ... || echo x`
# never fires the fallback, because || binds to tr, which succeeds on empty input.
VER=$(cat "$VERFILE" 2>/dev/null) || VER=""
VER=$(printf '%s' "$VER" | tr -d ' \r\n')
[ -n "$VER" ] || VER=$VERFALLBACK

kind_of() { # read the kind= from a file's first 5 lines; empty if unlabeled
  head -5 "$1" 2>/dev/null | sed -n 's/.*apsolut-agents: tier=[0-9ref]* kind=\([a-z]*\).*/\1/p' | head -1
}

mkdirs() { # mirror the payload's directory tree into $DEST
  [ "$DRY" = yes ] && return 0
  (cd "$SRC" && find . -type d | while read -r d; do mkdir -p "$DEST/$d"; done)
}

put_file() { # put_file <src-path> <dest-rel> <verb>
  if [ "$DRY" = yes ]; then
    printf '  would %s: %s\n' "$3" "$2"
  else
    cp "$1" "$DEST/$2"
    printf '  %s: %s\n' "$3" "$2"
  fi
}

put_version() {
  if [ "$DRY" = yes ]; then
    echo "  would write: VERSION ($VER)"
  else
    printf '%s\n' "$VER" > "$DEST/VERSION"
  fi
}

if [ "$REFRESH" = no ]; then
  [ -e "$DEST" ] && { echo "error: $DEST already exists — use --refresh to upgrade" >&2; exit 1; }
  [ "$DRY" = yes ] && echo "dry-run: would install v$VER → $DEST"
  [ "$DRY" = no ] && mkdir -p "$DEST"
  mkdirs
  (cd "$SRC" && find . -type f | while read -r f; do put_file "$f" "${f#./}" add; done)
  put_version
  if [ "$DRY" = no ]; then
    echo "installed v$VER → $DEST"
    echo
    echo "Next (see $DEST/INSTALL.md):"
    echo "  1. Fill in .apsolut-agents/PROJECT.md (commands, hot files, human gates, roster)"
    echo "  2. Delete the tiers you don't need (tier labels are on line 1 of every file)"
    echo "  3. Fill the narrative in state/PROJECT_STATE.md, then: sh .apsolut-agents/scripts/status.sh"
    [ "$WIRE" = yes ] || echo "  4. Paste CLAUDE-SNIPPET.md into your CLAUDE.md / AGENTS.md (or rerun with --wire)"
  fi
else
  [ -d "$DEST" ] || { echo "error: $DEST does not exist — run without --refresh to install" >&2; exit 1; }
  OLD=$(cat "$DEST/VERSION" 2>/dev/null) || OLD=""
  OLD=$(printf '%s' "$OLD" | tr -d ' \r\n')
  [ -n "$OLD" ] || OLD=unknown
  [ "$DRY" = yes ] && echo "dry-run: would refresh $DEST ($OLD → $VER)"
  mkdirs
  cd "$SRC"
  find . -type f | while read -r f; do
    rel=${f#./}
    if [ ! -e "$DEST/$rel" ]; then
      put_file "$f" "$rel" add
    else
      case "$(kind_of "$f")" in
        doc|generated) put_file "$f" "$rel" update ;;
        instance)      echo "  keep:   $rel (instance — yours)" ;;
        *)             echo "  keep:   $rel (unlabeled — not overwriting)" ;;
      esac
    fi
  done
  put_version
  if [ "$DRY" = no ]; then
    echo "refreshed → $DEST ($OLD → $VER; instance files untouched)"
    echo "tip: re-run sh $DEST/scripts/status.sh to regenerate the board"
  fi
fi

# --- --wire: append the bootstrap block to CLAUDE.md / AGENTS.md (idempotent)
if [ "$WIRE" = yes ]; then
  MARK_B="<!-- apsolut-agents:begin -->"
  MARK_E="<!-- apsolut-agents:end -->"
  # read the block from the payload, not $DEST — $DEST may not exist yet under --dry-run
  snippet() { sed -n '/^```markdown$/,/^```$/p' "$SRC/CLAUDE-SNIPPET.md" | sed '1d;$d'; }
  wire_file() {
    if [ -f "$1" ] && grep -qF "$MARK_B" "$1"; then
      echo "  wired:  $(basename "$1") (marker already present — skipped)"
      return 0
    fi
    if [ "$DRY" = yes ]; then
      echo "  would wire: $(basename "$1") — appends only, between markers:"
      { echo ""; echo "$MARK_B"; snippet; echo "$MARK_E"; } | sed 's/^/    + /'
      return 0
    fi
    {
      echo ""
      echo "$MARK_B"
      snippet
      echo "$MARK_E"
    } >> "$1"
    echo "  wired:  $(basename "$1")"
  }
  DID=no
  for f in CLAUDE.md AGENTS.md; do
    if [ -f "$TB/$f" ]; then wire_file "$TB/$f"; DID=yes; fi
  done
  if [ "$DID" = no ]; then
    if [ "$DRY" = yes ]; then
      echo "  would create: CLAUDE.md (neither CLAUDE.md nor AGENTS.md exists)"
    fi
    wire_file "$TB/CLAUDE.md"
    if [ "$DRY" = no ]; then echo "  (created CLAUDE.md)"; fi
  fi
fi

# explicit success: a trailing conditional that evaluates false is the script's last
# command, so without this a fully successful --wire run can exit 1.
exit 0
