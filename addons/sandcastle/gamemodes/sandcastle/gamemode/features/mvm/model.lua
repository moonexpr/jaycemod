-- The Mann vs. Machine mode: a tf_logic_mann_vs_machine makes the game
-- MvM (CTFGameRules::IsMannVsMachineMode) over the game types its maps also
-- carry: their bombs are item_teamflags (CTF) and mvm_mannhattan's gates
-- control points. BLU's robots carry their own bomb, a delivery fires the
-- capture zone's outputs and scores nothing (the map's relays end the
-- round), and owning every gate wins nothing.
--
-- Sandcastle has no population manager: one wave, with setup standing in
-- for the ready-up. Setup's end starts the wave (the popfile's
-- StartWaveOutput), the bomb at home goes to an invader in its spawn room
-- (CTFBotFetchFlag's "we just spawned - give us the flag"), and invaders in
-- their spawn room cannot be hurt (CTFBotMainAction::Update).
local ipairs = ipairs
local Rounds = require("games.gameplay.rounds")
local Teams = require("games.gameplay.teams")
local Players = require("games.gameplay.players")
local Geometry = require("foundation.math.geometry")
module(...)

local C = Players.COND

Mode = Rounds.Mode:Extend("mvm")
Mode.OBJECTIVE = true
-- Over every other mode a map can carry.
Mode.PRIORITY = 5
Mode.FLAG_OWNERS_CARRY = true
-- TF_TEAM_PVE_INVADERS: their spawn rooms drop no bomb.
Mode.FLAG_INVADERS = Teams.BLUE
-- No bomb is taken before the wave starts.
Mode.FLAG_WAITS_FOR_WAVE = true

function Mode:MayWinByPoints(team, q) return false end

-- An MvM game begins with at least MIN_DEFENDERS players and NPCs on RED;
-- BLU's robots are the wave's.
MIN_DEFENDERS = 6
Mode.PLAYERS_NEEDED = { team = Teams.RED, count = MIN_DEFENDERS }

-- ws_mvm_setup_time's default: the ready-up's stand-in.
SETUP_SECONDS = 30

-- The popfiles' StartWaveOutput, the same on every map that has one.
WAVE_START_OUTPUTS = {
	{
		target = "wave_start_relay",
		input = "Trigger",
	},
}

-- candidates: { pos }s, the invaders in their spawn room. The one nearest
-- the bomb's home, or nil.
function BombCarrier(candidates, home)
	local best, bestRange
	for _, c in ipairs(candidates) do
		local range = Geometry.Distance(c.pos, home)
		if not best or range < bestRange then best, bestRange = c, range end
	end
	return best
end

-- What an invader in its spawn room gets, renewed while it stays.
SPAWN_PROTECTION = {
	{ cond = C.INVULNERABLE, seconds = 0.5 },
	{ cond = C.INVULNERABLE_HIDE_UNLESS_DAMAGED, seconds = 0.5 },
	{ cond = C.INVULNERABLE_WEARINGOFF, seconds = 0.5 },
	{ cond = C.IMMUNE_TO_PUSHBACK, seconds = 1.0 },
}

-- Whether one of team standing in a spawn room of roomTeam is protected.
function Protected(team, roomTeam, invaders)
	return team == invaders and roomTeam == invaders
end
