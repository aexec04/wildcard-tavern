---
description: Work through claude/QUEUE.md in order and report to claude/OUTBOX.md
model: sonnet
---
Read CLAUDE.md and claude/STATUS.md first. Never read src/Client/init.client.lua in full; use grep and targeted line ranges. Never use the word "Balatro" in game text, assets or the Roblox page. Avoid em dashes in anything you write. Never push. Never write secrets (API keys, tokens) into any file or output.

1. Read claude/QUEUE.md. Do every task marked [ ] in order. Mark it [x] when finished. One local commit per task with a clear message. Do not commit claude/QUEUE.md or claude/OUTBOX.md.
2. Image generation and upload spend credits. Only run them for a task that says ALLOWED: generate. Otherwise code work only.
3. Run the Lua tests before and after code changes (lua5.3 tools/run_tests_local.lua, or lua if lua5.3 is not installed). Do not finish a task with failing tests.
4. After each task, append to claude/OUTBOX.md under a heading with the task title and the time: the commit hash and subject, the test result, any art id lines EXACTLY as "<category> <key> <decalId>" one per line, and anything blocked or that needs the user. Stop on any credit or auth error and say so in the OUTBOX.
5. If a task is ambiguous, pick the simplest option and note it in the OUTBOX. Do not ask questions; this runs unattended.
6. If QUEUE.md has no [ ] tasks, write "Nothing queued" in the OUTBOX and stop.
7. If you cannot do a task (missing ALLOWED line, missing or failing keys, an auth or credit error, or anything that needs the user), change its marker in claude/QUEUE.md from [ ] to [h] so it is not run again, write one OUTBOX entry that says exactly what the user must do, and move on to the next task. Never leave a blocked task as [ ]: every rerun of a blocked task costs credits and does nothing. Do not write the same OUTBOX note twice; if the last OUTBOX entry for this task already says the same thing, stop without writing.
8. Never hold a task for a prerequisite you can supply yourself. If the blocker is a missing art id, helper, constant, failing test or file that you can create or upload with what the task or the queue already allows (uploading an existing file in claude/reference/ or art-wip/ is always allowed and is not generation), do that prerequisite first inside the same run, commit it, then do the task. Only hold for things that truly need the user: missing keys, an auth or credit error, or a design decision.
9. Unattended loops must not go idle. When you finish the last [ ] task, read every [h] task. For each one whose blocker is now resolved (its prerequisite task is [x], the ids or files it needed now exist, or a test failure is fixed), change its marker back to [ ] and do it in this same run. Only stop when every remaining [h] truly needs the user, and say exactly what in the OUTBOX.
10. A task that says "Depends on <task>" is released by rule 9 as soon as that task is [x]. Do not wait for the user to release it.
11. When no [ ] or releasable [h] task remains, do not stop. Open claude/BACKLOG.md, take the first item without a DONE line, add it to claude/QUEUE.md as a [ ] task with concrete values, do it, and mark the item DONE. Keep going down the backlog until it is empty or you hit a user-only blocker.
