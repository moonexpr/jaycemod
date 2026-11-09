-- The one gate players spawn through (ws/sv_spawn_manager.lua runs it).
-- A lock holds everyone back: nobody picks a team, a player who would spawn
-- watches, the dead stay down, and a respawn wave brings nobody; each is
-- held, and lifting the last lock releases them all to spawn. Players are
-- opaque keys.
--
-- Shared: why a player is not spawning, as a status (the round's, or HELD
-- under a lock) and its words, TF2's own (tf_english.txt's
-- game_respawntime_*, TF_Arena_NoRespawning).
local ceil, format, ipairs, setmetatable = math.ceil, string.format, ipairs, setmetatable
local Sets = world.sets
module(...)

-- What holds spawning back.
LOCKS = Sets.Named("spawn lock", { "nav" })

local LOCK_MESSAGES = {
	nav = "No respawning permitted",
}

-- Why a player is not spawning: dead, waiting for a wave (at a time), in
-- sudden death or an arena round (never this round), or respawns stopped
-- until the next round; HELD by a lock; or watching, SPECTATING by choice
-- or yet to CHOOSE_TEAM.
NONE, WAVE, SUDDEN_DEATH, ARENA, NEXT_ROUND, HELD, SPECTATING, CHOOSE_TEAM = 0, 1, 2, 3, 4, 5, 6, 7

local WORDS = {
	[SUDDEN_DEATH] = "No respawning in Sudden Death",
	[ARENA] = "No respawning in Arena Mode",
	[NEXT_ROUND] = "Respawn in: Wait for next round",
	[SPECTATING] = "Spectator mode",
	[CHOOSE_TEAM] = "Choose a team",
}

-- The words for status: left, the seconds to a WAVE; lock, what HELD it.
-- nil when there is nothing to say.
function Message(status, left, lock)
	if status == HELD then return LOCK_MESSAGES[LOCKS:Check(lock)] end
	if status ~= WAVE then return WORDS[status] end
	local seconds = ceil(left)
	if seconds <= 0 then return "Prepare to respawn" end
	if seconds == 1 then return "Respawn in: 1 second" end
	return format("Respawn in: %d seconds", seconds)
end

-- Why a player is held out of play, as a status: a player is held only for
-- a reason they are told (Message), and with none (NONE) is free to spawn.
-- view: out (dead, or watching), locked (a lock holds spawning), teamPlay
-- (games.gameplay.teams' TeamPlay), spectator and playing (their team: the
-- spectators, RED or BLU; neither is teamless), alive, and status (the
-- round's, for the dead). Outside team play only a lock holds anyone.
function Reason(view)
	if not view.out then return NONE end
	if view.locked then return HELD end
	if not view.teamPlay then return NONE end
	if view.spectator then return SPECTATING end
	if not view.playing then return CHOOSE_TEAM end
	if view.alive then return NONE end
	return view.status
end

local Manager = {}
Manager.__index = Manager

function New()
	return setmetatable({ locks = {}, held = {}, heldOrder = {} }, Manager)
end

-- The lock holding spawning back (the first in LOCKS' order), or nil.
function Manager:LockedBy()
	for _, lock in ipairs(LOCKS:Members()) do
		if self.locks[lock] then return lock end
	end
	return nil
end

function Manager:Lock(lock)
	self.locks[LOCKS:Check(lock)] = true
end

-- Lifts lock; once none is left, the players held, in the order held, to
-- spawn (else none).
function Manager:Unlock(lock)
	self.locks[LOCKS:Check(lock)] = nil
	if self:LockedBy() then return {} end
	local released = self.heldOrder
	self.held, self.heldOrder = {}, {}
	return released
end

local function Hold(self, player)
	if self.held[player] then return end
	self.held[player] = true
	self.heldOrder[#self.heldOrder + 1] = player
end

-- Whether a player may pick a team.
function Manager:MayChooseTeam()
	return self:LockedBy() == nil
end

-- Whether a player about to spawn may; if not, they are held (and watch).
function Manager:Admit(player)
	if not self:LockedBy() then return true end
	Hold(self, player)
	return false
end

-- Whether a dead player may respawn as they ask; if not, they are held.
function Manager:MayRespawn(player)
	return self:Admit(player)
end

-- Of players due to spawn (a wave, a round's start), those who may: all,
-- or under a lock none, each held.
function Manager:Spawnable(players)
	if not self:LockedBy() then return players end
	for _, player in ipairs(players) do Hold(self, player) end
	return {}
end
