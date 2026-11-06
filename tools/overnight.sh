#!/usr/bin/env bash
# Usage: tools/overnight.sh            (code work only, spends no credits)
#        tools/overnight.sh --generate (also generates and uploads new art)
set -euo pipefail
cd "$(dirname "$0")/.."
TOOLS='Read,Write,Edit,Grep,Glob,Bash(git add:*),Bash(git commit:*),Bash(git status:*),Bash(git diff:*),Bash(lua5.3:*),Bash(python3:*),Bash(ls:*)'
mkdir -p art-wip/logs
LOG="art-wip/logs/overnight-$(date +%Y%m%d-%H%M).log"

echo "== next-batch ==" | tee -a "$LOG"
claude -p "/next-batch" --model sonnet --allowedTools "$TOOLS" 2>&1 | tee -a "$LOG"

if [ "${1:-}" = "--generate" ]; then
  echo "== art generation (spends credits) ==" | tee -a "$LOG"
  claude -p "/patron-art Generate, upload, resolve Image ids and write the lua maps for categories: bossrounds, recipes, housepasses, titles, in that order. Use --workers 2 if you see rate-limit errors. Stop immediately on any credit or auth error and report it." \
    --model haiku --allowedTools "$TOOLS" 2>&1 | tee -a "$LOG"
fi

echo "== done, log: $LOG ==" | tee -a "$LOG"
