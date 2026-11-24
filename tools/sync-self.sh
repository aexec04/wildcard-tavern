#!/usr/bin/env bash
# Brings the main branch (concept-t-2d) into the current lane branch. Safe to run any time:
# - does nothing on the main branch itself or when main does not exist here
# - uncommitted changes are fine: git only refuses when the merge would overwrite a file you changed,
#   and then the merge is aborted and the lane is left as it is
# - untracked files that main now tracks are parked in art-wip/aside first so they cannot block the merge
# Used by tools/queue.sh (before each run), tools/watch-queue.sh (while idle) and tools/sync-lanes.sh.
cd "$(dirname "$0")/.." || exit 0
MAIN=concept-t-2d
CUR=$(git rev-parse --abbrev-ref HEAD)
[ "$CUR" = "$MAIN" ] && exit 0
git rev-parse --verify -q "$MAIN" >/dev/null || exit 0
if [ "$(git rev-list --count HEAD.."$MAIN" 2>/dev/null)" = "0" ]; then exit 0; fi
mkdir -p art-wip/aside
for f in $(git ls-tree -r --name-only "$MAIN" 2>/dev/null | grep -v ' '); do
  if [ -e "$f" ] && ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    mkdir -p "art-wip/aside/$(dirname "$f")"; mv "$f" "art-wip/aside/$f"; echo "parked untracked $f in art-wip/aside"
  fi
done
if git -c user.name=queue -c user.email=queue@local merge --no-edit "$MAIN" >/dev/null 2>&1; then
  echo "synced $CUR with $MAIN"
else
  git merge --abort >/dev/null 2>&1 || true
  echo "sync of $CUR with $MAIN failed (a file you changed is touched by main), left as is"
fi
exit 0
