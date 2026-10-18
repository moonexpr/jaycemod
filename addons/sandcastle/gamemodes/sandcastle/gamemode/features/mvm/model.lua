-- The Mann vs. Machine mode: a tf_logic_mann_vs_machine makes the game
-- MvM (CTFGameRules::IsMannVsMachineMode) over the game types its maps also
-- carry: their bombs are item_teamflags (CTF) and mvm_mannhattan's gates
-- control points. BLU's robots carry their own bomb, a delivery fires the
-- capture zone's outputs and scores nothing (the map's relays end the
-- round), and owning every gate wins nothing.
local Rounds = require("foundation.rounds")
module(...)

Mode = Rounds.Mode:Extend("mvm")
Mode.OBJECTIVE = true
-- Over every other mode a map can carry.
Mode.PRIORITY = 5
Mode.FLAG_OWNERS_CARRY = true

function Mode:MayWinByPoints(team, q) return false end
