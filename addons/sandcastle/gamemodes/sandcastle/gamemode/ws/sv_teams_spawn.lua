-- Where players spawn. info_player_teamspawn is an engine entity in GMod that
-- keeps none of TF2's state, so each one's state lives here as a record built
-- from the keyvalues the map gave it (sv_world.lua records them): its team,
-- whether it is disabled, and its links to a control point or a mini-round.
-- The records are set up per round as TF2 does before it respawns players
-- (games/gameplay/spawn.lua), map inputs change them during the round, and a
-- spawning player takes the next valid spot.
local S = gameplay.spawn

local records = setmetatable({}, { __mode = "k" })

-- The spawn's TF2 state (see games/gameplay/spawn.lua for the fields).
function WS.SpawnState(ent)
	local s = records[ent]
	if not s then
		s = S.FromKeyValues(WS.KeyValues(ent))
		records[ent] = s
	end
	return s
end

-- CTFTeamSpawn's inputs. The engine entity ignores them, so they change the
-- record; RoundSpawn only re-finds names, which the setup here does itself.
local SPAWN_INPUTS = {
	enable = function(s) s.disabled = false end,
	disable = function(s) s.disabled = true end,
	setteam = function(s, value) s.team = tonumber(value) or WS.TEAM_UNASSIGNED end,
	roundspawn = function() end,
}

hook.Add("AcceptInput", "ws_team_spawn", function(ent, input, activator, caller, value)
	if ent:GetClass() ~= "info_player_teamspawn" then return end
	local handler = SPAWN_INPUTS[string.lower(input)]
	if not handler then return end
	handler(WS.SpawnState(ent), value)
	-- the rooms' teams follow their spawns (features/npc's SpawnRooms)
	hook.Run("WSSpawnRoomsChanged")
	return true
end)

local function TeamSpawns()
	local list = ents.FindByClass("info_player_teamspawn")
	local states = {}
	for i, ent in ipairs(list) do states[i] = WS.SpawnState(ent) end
	return list, states
end

local function ControlPoint(name)
	for _, ent in ipairs(ents.FindByName(name)) do
		if ent:GetClass() == "team_control_point" then return ent end
	end
	return NULL
end

-- Control points are asked only on maps with a master or mini-rounds, whose
-- entities have loaded the capture feature.
local function Capture()
	return WS.Feature("capture")
end

local function PointOwner(name)
	local point = ControlPoint(name)
	if IsValid(point) then return Capture():Owner(point) end
	return nil
end

local function PointIndex(name)
	local point = ControlPoint(name)
	if IsValid(point) then return Capture():Index(point) end
	return nil
end

local function ControlPoints()
	local points = {}
	for _, ent in ipairs(ents.FindByClass("team_control_point")) do
		points[#points + 1] = {
			index = Capture():Index(ent),
			owner = Capture():Owner(ent),
			defaultOwner = tonumber(WS.KeyValues(ent).point_default_owner) or WS.TEAM_UNASSIGNED,
		}
	end
	return points
end

-- What the spawns were last set up for: a mini-round entity, or the control
-- point spawns of a map without mini-rounds. A map cleanup recreates the
-- spawns, so it clears this.
local applied = {}

hook.Add("PostCleanupMap", "ws_spawns", function() applied = {} end)

local function PlayingMiniRounds()
	return #ents.FindByClass("team_control_point_round") > 0
end

-- CTeamControlPointRound::SelectedToPlay -> SetupSpawnPointsForRound
local function SetupMiniRound(round)
	applied.round = round
	local names = {}
	for _, point in ipairs(round:Points()) do names[point:GetName()] = true end
	local _, states = TeamSpawns()
	S.SetupForRound(states, round:GetName(), names, PointOwner)
end

-- RecalculateControlPointState, on a map without mini-rounds.
local function RecalculateControlPointSpawns()
	local _, states = TeamSpawns()
	S.RecalculateControlPointState(states, ControlPoints(), applied.controlSpawns, PointIndex)
end

-- CTFGameRules::SetupOnRoundStart without mini-rounds.
local function SetupControlPointSpawns()
	local _, states = TeamSpawns()
	applied.controlSpawns = S.StartControlPointSpawns(states, PointIndex)
	RecalculateControlPointSpawns()
end

-- CTFGameRules::SetupOnRoundStart sends RoundActivate to every entity once
-- the spawns are set: rooms take their team from them, then the forcefields
-- from the rooms, and team filters from their control points.
function WS.RoundActivateSpawnRooms()
	for _, class in ipairs({ "func_respawnroom", "func_respawnroomvisualizer", "filter_activator_tfteam" }) do
		for _, ent in ipairs(ents.FindByClass(class)) do ent:RoundActivate() end
	end
end

-- Set the spawns up for the round being played, if that has not been done.
-- It runs before anyone spawns, so it does not depend on the order in which
-- the round's hooks reach this module.
local function EnsureRoundSetup()
	if PlayingMiniRounds() then
		local round = Capture():CurrentRound()
		-- none chosen yet (Sandbox mode keeps the rounds from activating): the
		-- round that comes first, so only its spawns are live
		if not IsValid(round) then round = Capture():UpcomingRound() end
		if not IsValid(round) or round == applied.round then return end
		SetupMiniRound(round)
	else
		if applied.controlSpawns or #ents.FindByClass("team_control_point_master") == 0 then return end
		SetupControlPointSpawns()
	end
	WS.RoundActivateSpawnRooms()
end

-- A mini-round is (re)selected: set its spawns up even if it is the same one.
hook.Add("WSMiniRoundStart", "ws_spawns", function(round)
	applied.round = nil
	EnsureRoundSetup()
end)

hook.Add("WSRoundActive", "ws_spawns", function()
	EnsureRoundSetup()
	WS.RoundActivateSpawnRooms()
end)

hook.Add("WSPointCaptured", "ws_spawns", function()
	if applied.controlSpawns then RecalculateControlPointSpawns() end
end)

-- The valid spawn points of a team for the round being played.
function WS.SpawnPoints(team)
	EnsureRoundSetup()
	local list, states = TeamSpawns()
	local points = {}
	for i, ent in ipairs(list) do
		if S.Valid(states[i], team) then points[#points + 1] = ent end
	end
	return points
end

-- VEC_HULL_MIN / VEC_HULL_MAX
local HULL_MINS, HULL_MAXS = Vector(-24, -24, 0), Vector(24, 24, 82)

local function Occupied(spot)
	local pos = spot:GetPos()
	for _, ent in ipairs(ents.FindInBox(pos + HULL_MINS, pos + HULL_MAXS)) do
		if ent:IsPlayer() and ent:Alive() then return true end
	end
	return false
end

-- g_pLastSpawnPoints: each team's spot handed out last.
local lastSpawn = {}

-- A map without TF2's team spawns, a CS:S one: the team's side spawns
-- (gameplay.spawn's SIDE_CLASSES) in turn, clear ones first; nil when the
-- map has none for it.
local function PickSideSpawn(team)
	local class = S.SideClass(team)
	if not class then return nil end
	local list = ents.FindByClass(class)
	local last = table.KeyFromValue(list, lastSpawn[team])
	local i = S.PickNext(#list, last, function(j) return not Occupied(list[j]) end)
	if not i then return nil end
	lastSpawn[team] = list[i]
	return list[i]
end

-- CTFPlayer::EntSelectSpawnPoint for RED and BLU: the next valid spot after
-- the team's last one, clear of players if any is; nil when there is none.
function WS.PickSpawn(team)
	EnsureRoundSetup()
	local list, states = TeamSpawns()
	if #list == 0 then return PickSideSpawn(team) end
	local last = table.KeyFromValue(list, lastSpawn[team])
	local i = S.Pick(states, team, last, function(j) return not Occupied(list[j]) end)
	if not i then return nil end
	lastSpawn[team] = list[i]
	return list[i]
end
