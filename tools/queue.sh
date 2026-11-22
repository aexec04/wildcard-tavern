#!/usr/bin/env bash
# Usage: tools/queue.sh   (runs everything in claude/QUEUE.md; art generation only for tasks marked ALLOWED: generate)
set -euo pipefail
cd "$(dirname "$0")/.."
TOOLS='Read,Write,Edit,Grep,Glob,Bash(git add:*),Bash(git commit:*),Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(lua5.3:*),Bash(lua:*),Bash(python3:*),Bash(ls:*)'
mkdir -p art-wip/logs
# Keep lane branches current: before every run, bring in the main branch (Golden Gala and card set mechanism, tests,
# shared fixes) so a lane never builds on old code. Skipped on the main branch itself; a conflict is aborted and left
# for the chat check to resolve, and the run goes on with the lane as it is.
MAIN=concept-t-2d
CUR=$(git rev-parse --abbrev-ref HEAD)
if [ "$CUR" != "$MAIN" ] && git rev-parse --verify -q "$MAIN" >/dev/null; then
  if git diff --quiet && git diff --cached --quiet; then
    git -c user.name=queue -c user.email=queue@local merge --no-edit "$MAIN" >/dev/null 2>&1 \
      && echo "synced $CUR with $MAIN" || { git merge --abort >/dev/null 2>&1; echo "sync with $MAIN had conflicts, aborted"; }
  else
    echo "sync skipped: uncommitted changes in $CUR"
  fi
fi
LOG="art-wip/logs/queue-$(date +%Y%m%d-%H%M).log"
echo "== queue ==" | tee -a "$LOG"
claude -p "/queue" --model sonnet --allowedTools "$TOOLS" 2>&1 | tee -a "$LOG"
echo "== done, log: $LOG, results in claude/OUTBOX.md ==" | tee -a "$LOG"
