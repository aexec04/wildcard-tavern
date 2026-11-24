#!/usr/bin/env bash
# Usage: tools/sync-lanes.sh   (run from the main folder, on the Mac or from the cloud chat)
# Merges the main branch (concept-t-2d) into every lane worktree that sits next to this folder.
# Uses --git-dir/--work-tree so it also works where the worktree's .git file points at a path that does not exist
# (the cloud chat sees the folders under a different root). Lane watchers do not need to be stopped.
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd); PARENT=$(dirname "$ROOT"); BASE=$(basename "$ROOT")
MAIN=concept-t-2d
LANES="${LANES:-$BASE-menu $BASE-3}"   # lane-shop is stale and is never merged
for n in $LANES; do
  G="$ROOT/.git/worktrees/$n"; W="$PARENT/$n"
  [ -d "$G" ] && [ -d "$W" ] || { echo "$n: not found, skipped"; continue; }
  git --git-dir="$G" --work-tree="$W" -c user.name=sync -c user.email=sync@local merge --no-edit "$MAIN" >/dev/null 2>&1 \
    && echo "$n: at $(git --git-dir="$G" log -1 --format=%h)" \
    || { git --git-dir="$G" --work-tree="$W" merge --abort >/dev/null 2>&1; echo "$n: merge failed (conflict or a changed file in the way), left as is"; }
done
