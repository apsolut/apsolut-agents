#!/bin/sh
# apsolut-agents: tier=0 kind=doc
# upgrade.sh [--tag vX.Y.Z] — self-upgrade this installed workspace from GitHub.
# No source clone needed: fetches the payload tarball and applies the refresh rules
# (kind=doc|generated overwritten, kind=instance NEVER touched). Run from the primary.
set -eu

REPO_URL=https://github.com/apsolut/apsolut-agents
TAG=main
[ "${1:-}" = "--tag" ] && TAG=${2:?--tag needs a value}

WS=$(cd "$(dirname "$0")/.." && pwd)
if [ -f "$WS/.primary" ]; then
  echo "error: run from the primary worktree ($(cat "$WS/.primary"))" >&2; exit 1
fi
CUR=$(cat "$WS/VERSION" 2>/dev/null | tr -d ' \r\n' || echo unknown)

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
case "$TAG" in main) REF=refs/heads/main ;; *) REF=refs/tags/$TAG ;; esac
echo "fetching payload ($TAG) from $REPO_URL ..."
curl -fsSL "$REPO_URL/archive/$REF.tar.gz" | tar xz -C "$TMP"
SRC=$(ls -d "$TMP"/apsolut-agents-*/template)
NEW=$(cat "$TMP"/apsolut-agents-*/VERSION 2>/dev/null | tr -d ' \r\n' || echo "$TAG")

kind_of() { head -5 "$1" 2>/dev/null | sed -n 's/.*apsolut-agents: tier=[0-9ref]* kind=\([a-z]*\).*/\1/p' | head -1; }

cd "$SRC"
find . -type d -exec mkdir -p "$WS/{}" \;
find . -type f | while read -r f; do
  rel=${f#./}
  if [ ! -e "$WS/$rel" ]; then
    cp "$f" "$WS/$rel"; echo "  added:   $rel"
  else
    case "$(kind_of "$f")" in
      doc|generated) cp "$f" "$WS/$rel"; echo "  updated: $rel" ;;
      instance)      echo "  kept:    $rel (instance — yours)" ;;
      *)             echo "  kept:    $rel (unlabeled — not overwriting)" ;;
    esac
  fi
done
printf '%s\n' "$NEW" > "$WS/VERSION"
echo "upgraded: ${CUR:-unknown} → $NEW"
echo "notes: if this project chose a lower tier, delete higher-tier additions (labels on"
echo "line 1); re-run sh $WS/scripts/status.sh to regenerate the board."
