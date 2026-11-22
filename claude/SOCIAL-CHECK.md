# Social check: free text between players

Result: no player typed text reaches another player.

| Place | What is sent | Why it is safe |
| --- | --- | --- |
| Names on boards, friends, spectate | Roblox display name | Roblox filters display names itself. Fixed in this pass: boards used the username, now `Spec.name` and `Spec.nameFor` return the display name. |
| Tags, titles, flair | Registry ids only | `Flair.cleanPublicTag` accepts only a known name aura id, anything else becomes nil. |
| Spectate | `watch` with a user id number and fixed action words | No text field exists. Only the watched player's run state is streamed. |
| Seed Run code | Text box, 6 characters | `SeededRng.validateCode` accepts only the code alphabet, so no free text travels. |
| Share boxes (Game Over, Win card, Ledger, Sidebar) | Read-only text the game made | The player copies it out; nothing is sent to other players. |
| Rooms, chat, invites | Nothing typed | Invites use Roblox's own invite prompt and a DataStore inbox holding user ids and numbers. |

No code path calls TextService filtering because no free typed text is relayed. If a typed name, message or room title is ever added, it must go through `TextService:FilterStringAsync` on the server first. A test (`Social check`) fails if a leaderboard path goes back to usernames.
