import re

p = "src/Server/init.server.lua"
s = open(p, encoding="utf-8").read()

# 1. new remotes live in one table `Rem` (the server main chunk is near Lua's 200 local limit)
remotes = {
    "SpectateActionRemote": "SpectateAction",
    "EquipFlairRemote": "EquipFlair",
    "ClaimCollectionRewardRemote": "ClaimCollectionReward",
    "StoreOpenedRemote": "StoreOpened",
    "HintSeenRemote": "HintSeen",
    "ResetHintsRemote": "ResetHints",
    "SpectateStreamRemote": "SpectateStream",
}
for old, name in remotes.items():
    pattern = re.compile(r"^local " + old + r" = newRemote\(\"" + name + r"\"\)", re.M)
    assert pattern.search(s), old
    s = pattern.sub("Rem." + name + " = newRemote(\"" + name + "\")", s, count=1)
    s = re.sub(r"\b" + old + r"\b", "Rem." + name, s)

# declare Rem right after newRemote's definition (before the first use)
marker = "local PlayHandRemote = newRemote(\"PlayHand\")"
assert marker in s
s = s.replace(marker, "local Rem = {} -- remotes added late (a table keeps the main chunk under 200 locals)\n" + marker, 1)

# 2. spectate helpers in one table `Spec`
s = s.replace("local SpectateModule = require(Engine.Spectate)\nlocal spectateState = SpectateModule.new()",
              "local Spec = { M = require(Engine.Spectate) } -- one table: the main chunk is near Lua's 200 local limit\nSpec.state = Spec.M.new()")
for fn, field in [("spectateName", "name"), ("spectateSend", "send"), ("spectateNotifyCount", "notifyCount"),
                  ("spectateSnapshotFor", "snapshotFor"), ("spectatePushed", "pushed"), ("spectateRelease", "release")]:
    s = s.replace("local function " + fn + "(", "function Spec." + field + "(")
    s = re.sub(r"\b" + fn + r"\b", "Spec." + field, s)
s = re.sub(r"\bSpectateModule\b", "Spec.M", s)
s = re.sub(r"\bspectateState\b", "Spec.state", s)
open(p, "w", encoding="utf-8").write(s)
print("done")
