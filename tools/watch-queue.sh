#!/usr/bin/env bash
# Leave this running in one terminal tab. It checks claude/QUEUE.md every 20s
# and runs tools/queue.sh when there is an unchecked task "- [ ]".
# Stop with Ctrl+C. Do not run it while an interactive Claude Code session is
# editing this repo (both would write the same working tree).
#
# Credit guard: if a run makes NO new commit and QUEUE.md did not change, the
# queue is stalled (a task is blocked). It will not run again until QUEUE.md
# changes, so a blocked task can never burn credits in a loop. Hard cap: 3 runs
# in a row without a new commit, even if QUEUE.md keeps changing.
cd "$(dirname "$0")/.." || exit 1
echo "Watching claude/QUEUE.md for new tasks (Ctrl+C to stop)..."
hash_q() { shasum claude/QUEUE.md 2>/dev/null | cut -d' ' -f1; }
stalled_hash=""
no_progress=0
while true; do
  if grep -q '^- \[ \]' claude/QUEUE.md 2>/dev/null; then
    now_hash=$(hash_q)
    if [ "$now_hash" = "$stalled_hash" ]; then
      sleep 20; continue
    fi
    if [ "$no_progress" -ge 3 ]; then
      echo "[$(date +%H:%M:%S)] 3 runs in a row made no commit. Stopped to save credits. Read claude/OUTBOX.md, fix or hold the blocked task ([h]), then restart this script."
      exit 1
    fi
    before=$(git rev-parse HEAD 2>/dev/null)
    echo "[$(date +%H:%M:%S)] New task found, running queue..."
    tools/queue.sh
    echo "[$(date +%H:%M:%S)] Queue run finished."
    after=$(git rev-parse HEAD 2>/dev/null)
    if [ "$before" = "$after" ]; then
      no_progress=$((no_progress + 1))
      if [ "$(hash_q)" = "$now_hash" ]; then
        stalled_hash="$now_hash"
        echo "[$(date +%H:%M:%S)] No progress and QUEUE.md unchanged: waiting for an edit to QUEUE.md before running again."
      fi
    else
      no_progress=0
      stalled_hash=""
    fi
  fi
  sleep 20
done
