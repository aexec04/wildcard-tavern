#!/usr/bin/env bash
# One-time setup for parallel lanes. Run from the repo folder on your Mac:
#   bash tools/lanes-setup.sh
# Creates two extra working copies next to this folder, each on its own branch,
# each with its own claude/QUEUE.md. Run one watcher per copy (see the end).
set -euo pipefail
cd "$(dirname "$0")/.."
MAIN="$(pwd)"
PARENT="$(dirname "$MAIN")"
BASE="$(basename "$MAIN")"
for lane in shop menu; do
  dir="$PARENT/$BASE-$lane"
  if [ -d "$dir" ]; then echo "$dir already exists, skipping"; continue; fi
  git worktree add "$dir" -b "lane-$lane"
  mkdir -p "$dir/art-wip/logs"
  [ -f "$MAIN/tools/patron_art/.env" ] && cp "$MAIN/tools/patron_art/.env" "$dir/tools/patron_art/.env"
  printf '# Queue (%s lane)\n\nNothing queued\n' "$lane" > "$dir/claude/QUEUE.md"
  : > "$dir/claude/OUTBOX.md"
  # Lanes must not pull items from the shared backlog or edit STATUS.md (merge conflicts).
  git -C "$dir" update-index --skip-worktree claude/BACKLOG.md || true
  echo "# Backlog: empty in this lane. Only do tasks in claude/QUEUE.md." > "$dir/claude/BACKLOG.md"
  echo "created $dir on branch lane-$lane"
done
echo
echo "Now open TWO more Terminal tabs and run, one each:"
echo "  cd \"$PARENT/$BASE-shop\" && export PATH=\"/Library/Frameworks/Python.framework/Versions/3.13/bin:\$PATH\" && tools/watch-queue.sh"
echo "  cd \"$PARENT/$BASE-menu\" && export PATH=\"/Library/Frameworks/Python.framework/Versions/3.13/bin:\$PATH\" && tools/watch-queue.sh"
echo "Keep your existing watcher running in this folder (the Table lane)."
