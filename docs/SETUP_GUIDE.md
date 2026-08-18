# Setup Guide (zero assumed knowledge)

Do this together on a call the first time, even though you'll each do it
on your own computer -- it's much faster to unblock each other live than
over text. Budget ~45-60 minutes.

## 1. Install Roblox Studio

1. Go to https://create.roblox.com, sign in with your Roblox account
   (or create one).
2. Click "Create" / "Start Creating" -- this downloads and installs
   Roblox Studio if you don't have it.
3. Open Studio once and confirm it launches. Close it again for now.

## 2. Install Git

Git is what tracks and shares code changes between you two.

- **Windows:** download from https://git-scm.com/downloads and run the
  installer (default options are fine).
- **Mac:** open Terminal and run `git --version` -- if it's not
  installed, macOS will prompt you to install the Xcode Command Line
  Tools, which include Git.

Verify: open a terminal (Command Prompt/PowerShell on Windows, Terminal
on Mac) and run:
```
git --version
```
You should see a version number, not an error.

## 3. Create a GitHub account and a shared repo

1. One of you creates a free account at https://github.com if you don't
   have one, and creates a new **private** repository (e.g.
   `wildcard-tavern`).
2. Add the other person as a collaborator: repo page -> Settings ->
   Collaborators -> Add people.
3. Both of you clone it to your computer:
   ```
   git clone https://github.com/<your-username>/wildcard-tavern.git
   cd wildcard-tavern
   ```

## 4. Install VS Code

Download from https://code.visualstudio.com and install it. This is
where you'll edit the Lua code files (Roblox Studio's built-in script
editor also works, but Rojo is what keeps the two in sync).

## 5. Install Aftman (manages the Rojo version for you)

Aftman installs and pins tool versions so you both use the same Rojo
version.

- **Windows:** download the latest `aftman-*-windows-x86_64.zip` from
  https://github.com/LPGhatguy/aftman/releases, unzip it, and run the
  `aftman.exe` inside it once (it installs itself and adds itself to
  your PATH -- you may need to restart your terminal).
- **Mac:** run this in Terminal:
  ```
  curl -fsSL https://raw.githubusercontent.com/LPGhatguy/aftman/main/scripts/install.sh | bash
  ```
  Restart your terminal afterward.

Verify:
```
aftman --version
```

Then, from inside the project folder (where `aftman.toml` lives, which
we've already included), run:
```
aftman install
```
This installs the exact Rojo version pinned in `aftman.toml` for you.

Verify:
```
rojo --version
```

## 6. Install the Rojo plugin in Roblox Studio

1. Open Roblox Studio.
2. Go to the **Plugins** tab -> **Manage Plugins** (or the Toolbox on
   the right, depending on your Studio version) -> search "Rojo" in the
   plugin marketplace.
3. Install the plugin by "Rojo" (author: the Rojo project / Uplift
   Games). You should now see a Rojo icon in the Plugins ribbon.

## 7. First sync

1. Put the project files (the ones I sent you: `default.project.json`,
   `src/`, `aftman.toml`, `docs/`) inside your cloned `wildcard-tavern`
   folder.
2. From that folder in a terminal, run:
   ```
   rojo serve
   ```
   Leave this running -- it's a small local server that Studio connects
   to. You'll see something like `Rojo server listening on port 34872`.
3. In Roblox Studio, open a **new baseplate** place, click the Rojo
   plugin icon, and click **Connect** (default address
   `localhost:34872` is correct).
4. You should see the Explorer window in Studio populate with
   `ReplicatedStorage.Shared`, `ServerScriptService.Server`, etc. --
   that's Rojo syncing the files in.
5. Press **Play** in Studio. Check the **Output** window (View ->
   Output if it's not visible) -- you should see 26 `[PASS]` lines from
   the engine tests, then a playable card table.

If Play doesn't show a UI or the Output shows errors, stop and paste the
exact error into our chat (or send a screenshot) rather than guessing --
it's almost always one small thing (wrong Rojo version, plugin not
connected, etc.).

## 8. Day-to-day workflow (the simple version)

To avoid merge conflicts as beginners, the simplest safe workflow is:

1. **Before you start working**, run `git pull` to get the other
   person's latest changes.
2. Make your changes (in VS Code and/or by tweaking values and watching
   Rojo live-sync them into Studio).
3. When you're done for the session:
   ```
   git add .
   git commit -m "short description of what you changed"
   git push
   ```
4. Message each other when you push something, especially if you both
   might be editing the same file around the same time -- talking for
   10 seconds beats untangling a merge conflict for 30 minutes.

You do not need branches or pull requests for a 2-person, 1-week
project -- that's process overhead you don't need yet. Just communicate
and push often.
