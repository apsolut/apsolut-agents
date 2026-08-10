#!/bin/sh
# apsolut-agents: tier=0 kind=doc
# upgrade.sh [--tag vX.Y.Z] [--dry-run] — self-upgrade this installed workspace from GitHub.
# No source clone needed: fetches the payload tarball and applies the refresh rules
# (kind=doc|generated overwritten, kind=instance NEVER touched). Run from the primary.
# --dry-run prints what it would add/update/keep and writes nothing.
set -eu

# --- run from a temp copy of this file ---------------------------------------------
# The refresh loop below cp's scripts/upgrade.sh — this very file — while the shell
# is still reading it incrementally: executing the on-disk copy during a real upgrade
# splices the new file's bytes into the running script at the old offset. Re-exec a
# temp copy first; $0 moves, so the workspace path travels via env.
if [ -z "${APSOLUT_UPGRADE_REEXEC:-}" ]; then
  APSOLUT_UPGRADE_WS=$(cd "$(dirname "$0")/.." && pwd)
  APSOLUT_UPGRADE_SELF=$(mktemp)
  cp "$0" "$APSOLUT_UPGRADE_SELF"
  export APSOLUT_UPGRADE_WS APSOLUT_UPGRADE_SELF APSOLUT_UPGRADE_REEXEC=1
  exec sh "$APSOLUT_UPGRADE_SELF" "$@"
fi
# from here on we ARE the temp copy — remove it on any exit, even a usage error
# (the trap below is replaced by the wider TMP+SELF trap once TMP exists)
trap 'rm -f "$APSOLUT_UPGRADE_SELF"' EXIT

REPO_URL=https://github.com/apsolut/apsolut-agents
TAG=main; DRY=no
while [ $# -gt 0 ]; do
  case "$1" in
    --tag)     shift; TAG=${1:?--tag needs a value} ;;
    --dry-run) DRY=yes ;;
    *)         echo "usage: upgrade.sh [--tag vX.Y.Z] [--dry-run]" >&2; exit 2 ;;
  esac
  shift
done

WS=$APSOLUT_UPGRADE_WS
if [ -f "$WS/.primary" ]; then
  echo "error: run from the primary worktree ($(cat "$WS/.primary"))" >&2; exit 1
fi
CUR=$(cat "$WS/VERSION" 2>/dev/null) || CUR=""
CUR=$(printf '%s' "$CUR" | tr -d ' \r\n')
[ -n "$CUR" ] || CUR=unknown

TMP=$(mktemp -d); trap 'rm -rf "$TMP" "$APSOLUT_UPGRADE_SELF"' EXIT
case "$TAG" in main) REF=refs/heads/main ;; *) REF=refs/tags/$TAG ;; esac
echo "fetching payload ($TAG) from $REPO_URL ..."
# fetch to a file rather than piping into tar, so a 404 reports as itself
curl -fsSL "$REPO_URL/archive/$REF.tar.gz" -o "$TMP/payload.tar.gz" \
  || { echo "error: could not fetch '$TAG' from $REPO_URL — check the tag name" >&2; exit 1; }
tar xzf "$TMP/payload.tar.gz" -C "$TMP"
SRC=$(ls -d "$TMP"/apsolut-agents-*/template)
# fallback must be its own step: `cat f | tr ... || echo x` never fires, because ||
# binds to tr, which succeeds on empty input — that would write an empty VERSION.
NEW=$(cat "$TMP"/apsolut-agents-*/VERSION 2>/dev/null) || NEW=""
NEW=$(printf '%s' "$NEW" | tr -d ' \r\n')
[ -n "$NEW" ] || NEW=$TAG

kind_of() { head -5 "$1" 2>/dev/null | sed -n 's/.*apsolut-agents: tier=[0-9ref]* kind=\([a-z]*\).*/\1/p' | head -1; }

put_file() { # put_file <src-path> <dest-rel> <verb>
  if [ "$DRY" = yes ]; then
    printf '  would %s: %s\n' "$3" "$2"
  else
    cp "$1" "$WS/$2"
    printf '  %s: %s\n' "$3" "$2"
  fi
}

[ "$DRY" = yes ] && echo "dry-run: would upgrade $WS ($CUR → $NEW)"

cd "$SRC"
# `find -type d -exec mkdir -p "$WS/{}" \;` is unspecified by POSIX — {} is only
# guaranteed to be substituted when it is a standalone argument.
if [ "$DRY" = no ]; then
  find . -type d | while read -r d; do mkdir -p "$WS/$d"; done
fi
find . -type f | while read -r f; do
  rel=${f#./}
  if [ ! -e "$WS/$rel" ]; then
    put_file "$f" "$rel" add
  else
    case "$(kind_of "$f")" in
      doc|generated) put_file "$f" "$rel" update ;;
      instance)      echo "  keep:   $rel (instance — yours)" ;;
      *)             echo "  keep:   $rel (unlabeled — not overwriting)" ;;
    esac
  fi
done

if [ "$DRY" = yes ]; then
  echo "  would write: VERSION ($NEW)"
  echo "dry-run: nothing was changed."
else
  printf '%s\n' "$NEW" > "$WS/VERSION"
  echo "upgraded: $CUR → $NEW"
  echo "notes: if this project chose a lower tier, delete higher-tier additions (labels on"
  echo "line 1); re-run sh $WS/scripts/status.sh to regenerate the board."
fi

exit 0
