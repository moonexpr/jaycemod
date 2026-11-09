-- The flag feature's model (features.flag.model): item_teamflag's carry,
-- drop and return rules (CCaptureFlag, entity_capture_flag.cpp), the
-- capture zone's rule (CCaptureZone, func_capture_zone.cpp), the CTF tally
-- against tf_flag_caplimit, the CTF mode and what TF2's flag panel shows
-- (CTFFlagStatus, tf_hud_flagstatus.cpp).
local T = dofile("tests/harness.lua")
local Flag = T.require("features.flag.model")
local FlagState = dofile("addons/sandcastle/gamemodes/sandcastle/entities/entities/item_teamflag/state.lua")
local Rounds = gameplay.rounds
local State = T.require("games.gameplay.rounds.state")
local Teams = gameplay.teams

local NOBODY, RED, BLUE = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local CARRIER, OTHER = "carrier", "other"
local NOW = 100
local CTF = {
	ownersCarry = false,
	mayBeCapped = true,
}
local MVM = {
	ownersCarry = true,
	mayBeCapped = true,
}

local function Kinds(events)
	local kinds = {}
	for i, e in ipairs(events) do kinds[i] = e.kind end
	return table.concat(kinds, ",")
end

-- Who carries ----------------------------------------------------------------------

T.test("in CTF a team's flag is carried by its enemies, a neutral one by anyone", function()
	T.eq(FlagState.MayCarry(RED, BLUE, false), true, "BLU takes RED's")
	T.eq(FlagState.MayCarry(RED, RED, false), false, "RED keeps off its own")
	T.eq(FlagState.MayCarry(NOBODY, RED, false), true, "a neutral flag, RED")
	T.eq(FlagState.MayCarry(NOBODY, BLUE, false), true, "a neutral flag, BLU")
	T.eq(FlagState.MayCarry(RED, NOBODY, false), false, "nobody's carrier")
end)

T.test("in MvM the bomb is carried by its own team only", function()
	T.eq(FlagState.MayCarry(BLUE, BLUE, true), true, "BLU's robots carry BLU's bomb")
	T.eq(FlagState.MayCarry(BLUE, RED, true), false, "RED cannot")
	T.eq(FlagState.MayCarry(NOBODY, RED, true), true, "a neutral bomb, anyone")
end)

T.test("flags may be capped but in the pre-round and after a win (FlagsMayBeCapped)", function()
	T.eq(Flag.MayBeCapped(State.RND_RUNNING), true, "running")
	T.eq(Flag.MayBeCapped(State.STALEMATE), true, "sudden death")
	T.eq(Flag.MayBeCapped(State.PREROUND), false, "pre-round")
	T.eq(Flag.MayBeCapped(State.TEAM_WIN), false, "won")
end)

-- A flag's life ---------------------------------------------------------------------

T.test("a flag starts at home, enabled unless StartDisabled", function()
	local flag = FlagState.New({ team = RED })
	T.eq(flag:State(), Flag.HOME, "home")
	T.eq(flag:Enabled(), true, "enabled")
	T.eq(flag:Carrier(), nil, "no carrier")
	T.eq(FlagState.New({ team = RED, disabled = true }):Enabled(), false, "StartDisabled")
	T.defined(FlagState.RETURN_TIME_DEFAULT, "the return time's default")
	T.eq(FlagState.New({ team = RED }):ReturnTime(), FlagState.RETURN_TIME_DEFAULT, "ReturnTime's default")
end)

T.test("an enemy picks the flag up; its own team, a disabled flag or a cap-free state refuse", function()
	local flag = FlagState.New({ team = RED })
	T.eq(Kinds(flag:PickUp(OTHER, RED, CTF)), "", "its own team")
	T.eq(Kinds(flag:PickUp(OTHER, BLUE, { ownersCarry = false, mayBeCapped = false })), "", "in the pre-round")
	local off = FlagState.New({ team = RED, disabled = true })
	T.eq(Kinds(off:PickUp(CARRIER, BLUE, CTF)), "", "disabled")
	local events = flag:PickUp(CARRIER, BLUE, CTF)
	T.eq(Kinds(events), Flag.PICKUP, "picked up")
	T.eq(events[1].team, BLUE, "by BLU")
	T.eq(flag:State(), Flag.CARRIED, "carried")
	T.eq(flag:Carrier(), CARRIER, "the carrier")
	T.eq(flag:CarrierTeam(), BLUE, "the carrier's team")
	T.eq(Kinds(flag:PickUp(OTHER, BLUE, CTF)), "", "a carried flag is not taken again")
end)

T.test("a dropped flag waits ReturnTime, then returns home", function()
	local flag = FlagState.New({
		team = RED,
		returnTime = FlagState.RETURN_TIME_DEFAULT,
	})
	flag:PickUp(CARRIER, BLUE, CTF)
	local events = flag:Drop(NOW)
	T.eq(Kinds(events), Flag.DROP, "dropped")
	T.eq(events[1].team, BLUE, "BLU dropped it")
	T.eq(flag:State(), Flag.DROPPED, "on the ground")
	T.eq(flag:Carrier(), nil, "nobody carries it")
	T.eq(flag:ReturnAt(), NOW + FlagState.RETURN_TIME_DEFAULT, "its return")
	T.eq(Kinds(flag:Think(NOW + FlagState.RETURN_TIME_DEFAULT - 1)), "", "not yet")
	local back = flag:Think(NOW + FlagState.RETURN_TIME_DEFAULT)
	T.eq(Kinds(back), Flag.RETURN, "returned")
	T.eq(back[1].team, RED, "to its team")
	T.eq(flag:State(), Flag.HOME, "home")
	T.eq(Kinds(flag:Drop(NOW)), "", "a flag at home does not drop")
end)

T.test("an enemy takes a dropped flag up again; its own team leaves it", function()
	local flag = FlagState.New({ team = RED })
	flag:PickUp(CARRIER, BLUE, CTF)
	flag:Drop(NOW)
	T.eq(Kinds(flag:PickUp(OTHER, RED, CTF)), "", "RED does not touch-return it")
	T.eq(Kinds(flag:PickUp(OTHER, BLUE, CTF)), Flag.PICKUP, "BLU takes it again")
	T.eq(Kinds(flag:Think(NOW + FlagState.RETURN_TIME_DEFAULT)), "", "a carried flag does not return")
end)

T.test("a carrier in its own team's zone captures, and the flag goes home", function()
	local flag = FlagState.New({ team = RED })
	flag:PickUp(CARRIER, BLUE, CTF)
	local events = flag:Capture()
	T.eq(Kinds(events), Flag.CAPTURE, "captured")
	T.eq(events[1].team, BLUE, "for BLU")
	T.eq(flag:State(), Flag.HOME, "home again")
	T.eq(Kinds(flag:Capture()), "", "nothing left to capture")
end)

T.test("MvM: BLU picks up its bomb and delivers it to its own zone", function()
	local bomb = FlagState.New({ team = BLUE })
	T.eq(Kinds(bomb:PickUp(OTHER, RED, MVM)), "", "RED cannot")
	T.eq(Kinds(bomb:PickUp(CARRIER, BLUE, MVM)), Flag.PICKUP, "a robot takes it")
	T.eq(Kinds(bomb:Capture()), Flag.CAPTURE, "delivered")
end)

-- CCaptureFlag::Drop: a flag dropped in a func_respawnflag zone (bigrock's
-- death pit) is reset at once, as its OnReturn says (the map's relays).
T.test("a flag dropped in a reset zone returns home at once", function()
	local flag = FlagState.New({ team = BLUE, returnTime = 60000 })
	flag:PickUp(CARRIER, BLUE, MVM)
	local events = flag:Drop(NOW, true)
	T.eq(Kinds(events), Flag.DROP .. "," .. Flag.RETURN, "dropped, then returned")
	T.eq(events[1].team, BLUE, "BLU dropped it")
	T.eq(events[2].team, BLUE, "home to its team")
	T.eq(flag:State(), Flag.HOME, "home")
	flag:PickUp(CARRIER, BLUE, MVM)
	T.eq(Kinds(flag:Drop(NOW, false)), Flag.DROP, "outside one it lies where it fell")
end)

T.test("ForceDrop drops a carried flag; ForceReset returns it, ForceResetSilent quietly", function()
	local flag = FlagState.New({ team = RED })
	flag:PickUp(CARRIER, BLUE, CTF)
	T.eq(Kinds(flag:Reset(false)), Flag.RETURN, "reset")
	T.eq(flag:State(), Flag.HOME, "home")
	flag:PickUp(CARRIER, BLUE, CTF)
	T.eq(Kinds(flag:Reset(true)), "", "silently")
	T.eq(flag:State(), Flag.HOME, "home, silently")
	T.eq(Kinds(flag:Reset(false)), "", "a flag at home has nothing to return")
end)

T.test("disabling a flag sends it home silently; enabling lets it be taken", function()
	local flag = FlagState.New({ team = RED })
	flag:PickUp(CARRIER, BLUE, CTF)
	T.eq(Kinds(flag:SetEnabled(false)), "", "silent")
	T.eq(flag:State(), Flag.HOME, "home")
	T.eq(flag:Enabled(), false, "disabled")
	flag:SetEnabled(true)
	T.eq(Kinds(flag:PickUp(CARRIER, BLUE, CTF)), Flag.PICKUP, "enabled")
end)

-- The announcer ---------------------------------------------------------------------

T.test("each team hears its Team line when it acts and the Enemy line otherwise", function()
	local lines = Flag.Lines({
		kind = Flag.PICKUP,
		team = BLUE,
	})
	T.eq(#lines, 2, "both teams")
	local heard = {}
	for _, l in ipairs(lines) do heard[l.team] = l.sound end
	T.eq(heard[BLUE], "CaptureFlag.TeamStolen", "the takers")
	T.eq(heard[RED], "CaptureFlag.EnemyStolen", "the robbed")
	heard = {}
	for _, l in ipairs(Flag.Lines({ kind = Flag.RETURN, team = RED })) do heard[l.team] = l.sound end
	T.eq(heard[RED], "CaptureFlag.TeamReturned", "the flag's team, on its return")
	T.eq(heard[BLUE], "CaptureFlag.EnemyReturned", "the other")
end)

-- CCaptureFlag::ResetMessage for MvM's bomb (TF_FLAGTYPE_ATTACK_DEFEND):
-- its own team hears AttackDefend.TeamReturned, the defenders MvM's
-- EnemyReturned; nothing else of the bomb is announced.
T.test("MvM's bomb going home is told to both teams; its other events are not", function()
	local heard = {}
	for _, l in ipairs(Flag.InvadeLines({ kind = Flag.RETURN, team = BLUE })) do heard[l.team] = l.sound end
	T.eq(heard[BLUE], "AttackDefend.TeamReturned", "the robots")
	T.eq(heard[RED], "MVM.AttackDefend.EnemyReturned", "the defenders")
	T.eq(#Flag.InvadeLines({ kind = Flag.DROP, team = BLUE }), 0, "a drop: nothing")
	T.eq(#Flag.InvadeLines({ kind = Flag.PICKUP, team = BLUE }), 0, "a pickup: nothing")
end)

-- The CTF tally ---------------------------------------------------------------------

T.test("a team reaching tf_flag_caplimit captures wins", function()
	T.defined(Flag.CAPLIMIT_DEFAULT, "tf_flag_caplimit's default")
	local tally = Flag.NewTally()
	for _ = 1, Flag.CAPLIMIT_DEFAULT - 1 do T.eq(tally:Capture(BLUE, Flag.CAPLIMIT_DEFAULT), false, "short") end
	T.eq(tally:Captures(BLUE), Flag.CAPLIMIT_DEFAULT - 1, "counted")
	T.eq(tally:Captures(RED), 0, "RED's own count")
	T.eq(tally:Capture(BLUE, Flag.CAPLIMIT_DEFAULT), true, "the limit")
	tally:Reset()
	T.eq(tally:Captures(BLUE), 0, "a new round")
	T.eq(tally:Capture(RED, 0), false, "no limit, no win")
end)

T.test("the CTF mode: flags decide the rounds, above control points and under payload", function()
	T.eq(Flag.Mode.NAME, "ctf", "named")
	T.eq(Flag.Mode.OBJECTIVE, true, "no round limits")
	T.eq(Flag.Mode.FLAG_CAPS_SCORE, true, "caps score")
	T.eq(Flag.Mode.FLAG_OWNERS_CARRY, false, "enemies carry")
	T.eq(Flag.Mode.PRIORITY > T.require("features.rounds.control_points").Mode.PRIORITY, true, "over CP")
	T.eq(Flag.Mode.PRIORITY < T.require("features.payload.round").Mode.PRIORITY, true, "under payload")
	T.eq(Rounds.Mode.FLAG_CAPS_SCORE, false, "other modes' caps do not score")
	T.eq(Rounds.Mode.FLAG_OWNERS_CARRY, false, "nor do owners carry")
end)

-- The flag panel --------------------------------------------------------------------

T.test("the status icon is home, dropped or moving; MvM's bomb image dropped or carried", function()
	T.eq(Flag.StatusIcon(Flag.HOME), "hud/objectives_flagpanel_ico_flag_home", "home")
	T.eq(Flag.StatusIcon(Flag.DROPPED), "hud/objectives_flagpanel_ico_flag_dropped", "dropped")
	T.eq(Flag.StatusIcon(Flag.CARRIED), "hud/objectives_flagpanel_ico_flag_moving", "carried")
	T.eq(Flag.BombImage(Flag.HOME), "hud/bomb_dropped", "a bomb at home")
	T.eq(Flag.BombImage(Flag.DROPPED), "hud/bomb_dropped", "a dropped bomb")
	T.eq(Flag.BombImage(Flag.CARRIED), "hud/bomb_carried", "a carried bomb")
end)

T.test("the compass is the flag's team colour, pointing once the flag leaves home", function()
	T.eq(Flag.Compass(RED, Flag.HOME), "hud/objectives_flagpanel_compass_red_noarrow", "RED's at home")
	T.eq(Flag.Compass(BLUE, Flag.CARRIED), "hud/objectives_flagpanel_compass_blue", "BLU's taken")
	T.eq(Flag.Compass(NOBODY, Flag.DROPPED), "hud/objectives_flagpanel_compass_grey", "neutral")
end)

T.test("a carrier sees the carried image in the flag's colour", function()
	T.eq(Flag.CarriedImage(RED, BLUE), "hud/objectives_flagpanel_carried_red", "RED's flag")
	T.eq(Flag.CarriedImage(BLUE, RED), "hud/objectives_flagpanel_carried_blue", "BLU's flag")
	T.eq(Flag.CarriedImage(NOBODY, RED), "hud/objectives_flagpanel_carried_red", "a neutral flag, in the carrier's")
end)

local function Shown(team, state, enabled)
	return {
		team = team,
		state = state,
		enabled = enabled ~= false,
	}
end

T.test("CTF's panel shows BLU's flag on the left and RED's on the right, a neutral one where free", function()
	local red, blue = Shown(RED, Flag.HOME), Shown(BLUE, Flag.CARRIED)
	local slots = Flag.Slots({ red, blue }, false)
	T.eq(slots[Flag.SLOT_BLUE], blue, "BLU's")
	T.eq(slots[Flag.SLOT_RED], red, "RED's")
	local neutral = Shown(NOBODY, Flag.HOME)
	T.eq(Flag.Slots({ neutral }, false)[Flag.SLOT_BLUE], neutral, "a neutral flag, left")
	T.eq(Flag.Slots({ Shown(RED, Flag.HOME, false) }, false)[Flag.SLOT_RED], nil, "a disabled flag is hidden")
end)

T.test("MvM's panel shows one bomb on the left, a carried one first", function()
	local waiting, carried = Shown(BLUE, Flag.HOME), Shown(BLUE, Flag.CARRIED)
	local slots = Flag.Slots({ waiting, carried }, true)
	T.eq(slots[Flag.SLOT_BLUE], carried, "the carried bomb")
	T.eq(slots[Flag.SLOT_RED], nil, "no second panel")
	T.eq(Flag.Slots({ Shown(BLUE, Flag.HOME, false), waiting }, true)[Flag.SLOT_BLUE], waiting, "an enabled bomb")
end)

-- CTF's time limit: the team with more captures wins, by them; even
-- captures leave it to the scores (a tie of both: sudden death).
T.test("at the time limit the team with more captures wins", function()
	local W = Rounds.WINREASON
	local winner, reason = Flag.Mode:TimelimitWin({
		scores = { [Teams.RED] = 2, [Teams.BLUE] = 0 },
		captures = { [Teams.RED] = 1, [Teams.BLUE] = 3 },
	})
	T.eq(winner, Teams.BLUE, "most captures")
	T.eq(reason, W.MOST_CAPTURES, "won by them")
	winner, reason = Flag.Mode:TimelimitWin({
		scores = { [Teams.RED] = 2, [Teams.BLUE] = 0 },
		captures = { [Teams.RED] = 1, [Teams.BLUE] = 1 },
	})
	T.eq(winner, Teams.RED, "even captures: the scores")
	T.eq(reason, W.TIMELIMIT, "by points")
end)

-- CFuncRespawnRoom::RespawnRoomTouch: a carrier running into its own team's
-- respawn room drops the flag; another team's room, or one of no team, no.
T.test("a carrier in its own team's respawn room drops the flag", function()
	T.eq(FlagState.DropsIn(Teams.RED, Teams.RED), true, "its own")
	T.eq(FlagState.DropsIn(Teams.BLUE, Teams.RED), false, "the enemy's")
	T.eq(FlagState.DropsIn(Teams.UNASSIGNED, Teams.RED), false, "no team's")
end)

-- The entity (item_teamflag): its outputs, what it networks, where it sits -----------

local NO_ENTITY = "NULL"
local ENTITY_FILE = "addons/sandcastle/gamemodes/sandcastle/entities/entities/item_teamflag/init.lua"

local function Point(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, {
		__add = function(a, b) return Point(a.x + b.x, a.y + b.y, a.z + b.z) end,
		__sub = function(a, b) return Point(a.x - b.x, a.y - b.y, a.z - b.z) end,
	})
end

-- An entity's class, loaded as the server loads it, and the globals it set.
-- world is what it asks of the gamemode and the map:
-- { rules (the scenario's, every key optional), team (ent -> team),
-- inside (ent -> who stands on it), dead (ent), byClass (class -> entities), scored }.
local function EntityClass(trace, world, file)
	world = world or {}
	world.scored = world.scored or {}
	world.events = world.events or {}
	world.tally = world.tally or Flag.NewTally()
	world.limit = world.limit or 3
	local class, globals = {}, world.globals or {}
	local function Set(name, value) globals[name] = value end
	-- The generic calls the games answer; the entities name no game.
	local rounds = {
		AddTeamScore = function(info)
			world.scored[#world.scored + 1] = info.team
			world.scoredInfo = info
			if world.onScore then world.onScore(info.team) end
		end,
	}
	local games = {
		Standing = function(objective)
			if world.noStanding then return end
			objective.captures = { [RED] = world.tally:Captures(RED), [BLUE] = world.tally:Captures(BLUE) }
			objective.caplimit = world.limit
		end,
	}
	local hooks = {
		FlagTeam = function(ent) return (world.team or {})[ent] end,
		FlagCarrierAlive = function(ent) return ent ~= world.dead end,
		FlagMembersInside = function(ent) return (world.inside or {})[ent] or {} end,
		FlagEvent = function(_, e) world.events[#world.events + 1] = e.kind end,
	}
	local scenario = { GetRules = function() return world.rules or {} end }
	local env = setmetatable({
		round_manager = rounds,
		game_manager = {
			GetCurrentScenario = function() return scenario end,
			RunActive = function(name, ...) games[name](...) end,
		},
		ents = { FindByClass = function(name) return (world.byClass or {})[name] or {} end },
		player = { GetAll = function() return world.players or {} end },
		CurTime = function() return NOW end,
		IsValid = function(ent) return ent ~= nil and ent ~= NO_ENTITY end,
		ENT = class,
		CLIENT = false,
		TEAM_RED = RED,
		TEAM_BLUE = BLUE,
		TF_TEAM_UNASSIGNED = NOBODY,
		NULL = NO_ENTITY,
		AddCSLuaFile = function() end,
		include = function(name) if name == "state.lua" then return FlagState end end,
		Vector = Point,
		Angle = function(p, y, r) return { p = p, y = y, r = r } end,
		angle_zero = "angle_zero",
		MASK_SOLID_BRUSHONLY = "brushes",
		hook = {
			Add = function() end,
			Run = function(name, ...) if not world.noAnswers then return hooks[name](...) end end,
		},
		util = { TraceLine = function() return trace or { Hit = false } end },
		SetGlobal2Int = Set,
		SetGlobal2Bool = Set,
		SetGlobal2Vector = Set,
		vector_origin = "origin",
	}, { __index = _G })
	setfenv(assert(loadfile(file or ENTITY_FILE)), env)()
	return class, globals
end

-- A flag of the class, recording what it is told.
local function FlagEntity(class, model)
	local fired, nw = {}, {}
	local function Network(self, name, value) nw[name] = value end
	local ent = setmetatable({
		flagModel = model,
		fired = fired,
		nw = nw,
		SetNW2Int = Network,
		SetNW2String = Network,
		SetNW2Bool = Network,
		SetNW2Entity = Network,
		TriggerOutput = function(_, name, activator) fired[#fired + 1] = name .. ":" .. tostring(activator) end,
		GetPos = function(self) return self.pos end,
		SetSkin = function(self, skin) self.skin = skin end,
		NextThink = function(self, at) self.nextThink = at end,
		wsHome = "home",
		wsHomeAngles = "homeAngles",
		SetParent = function(self, parent) self.parent = parent end,
		SetPos = function(self, pos) self.pos = pos end,
		SetAngles = function(self, angles) self.angles = angles end,
		SetLocalPos = function(self, pos) self.localPos = pos end,
		SetLocalAngles = function(self, angles) self.localAngles = angles end,
		GetAngles = function() return { y = 90 } end,
	}, { __index = class, __tostring = function() return "flag" end })
	return ent
end

local function Carrier(pos)
	return setmetatable({
		GetPos = function(self) return self.at end,
		WorldSpaceCenter = function(self) return self.at end,
		GetModel = function() return "models/boneless.mdl" end,
		LookupBone = function() return nil end,
		at = pos or Point(0, 0, 0),
	}, { __tostring = function() return "carrier" end })
end

local RESET_ZONE_FILE = "addons/sandcastle/gamemodes/sandcastle/entities/entities/func_respawnflag.lua"
local CAPTURE_ZONE_FILE = "addons/sandcastle/gamemodes/sandcastle/entities/entities/func_capturezone.lua"

-- A zone of file's class, `crossed` saying whether a carrier's move passes through it.
local function Zone(file, world, _, crossed)
	local fired = {}
	return setmetatable({
		enabled = true,
		team = NOBODY,
		fired = fired,
		TriggerOutput = function(_, name, activator) fired[#fired + 1] = name .. ":" .. tostring(activator) end,
		Crossed = crossed,
		WorldSpaceCenter = function(self) return self.center end,
	}, { __index = EntityClass(nil, world, file) })
end

-- World with capture zones, each { team, center[, enabled] }.
local function CaptureZones(world, specs)
	world.globals = world.globals or {}
	local zones = {}
	for i, spec in ipairs(specs) do
		local zone = Zone(CAPTURE_ZONE_FILE, world)
		zone.team, zone.center = spec.team, spec.center
		zone.enabled = spec.enabled ~= false
		zones[i] = zone
	end
	world.byClass = { func_capturezone = zones }
	return zones
end

local function FlagCarriedBy(world, carrier, team)
	local model = FlagState.New({ team = team == BLUE and RED or BLUE })
	local ent = FlagEntity(EntityClass(nil, world), model)
	world.team = world.team or {}
	world.team[carrier] = team
	model:PickUp(carrier, team, CTF)
	return ent, model
end

T.test("a flag fires its own output and its carrier team's", function()
	local class = EntityClass()
	local cases = {
		{ Flag.PICKUP, RED, "OnPickup:who,OnPickupTeam1:who" },
		{ Flag.PICKUP, BLUE, "OnPickup:who,OnPickupTeam2:who" },
		{ Flag.CAPTURE, RED, "OnCapture:who,OnCapTeam1:who" },
		{ Flag.CAPTURE, BLUE, "OnCapture:who,OnCapTeam2:who" },
		{ Flag.DROP, RED, "OnDrop:who" },
		{ Flag.RETURN, BLUE, "OnReturn:who" },
		{ Flag.RETURN, NOBODY, "OnReturn:who" },
		{ Flag.PICKUP, NOBODY, "OnPickup:who" },
	}
	for _, case in ipairs(cases) do
		local ent = FlagEntity(class)
		ent:FireOutputs({ kind = case[1], team = case[2] }, "who")
		T.eq(table.concat(ent.fired, ","), case[3], case[1] .. " by team " .. case[2])
	end
end)

T.test("a flag networks its model's state", function()
	local class = EntityClass()
	local model = FlagState.New({ team = RED })
	local ent = FlagEntity(class, model)
	ent:Publish()
	T.eq(ent.nw.ws_flag_team, RED, "team")
	T.eq(ent.nw.ws_flag_state, Flag.HOME, "state")
	T.eq(ent.nw.ws_flag_enabled, true, "enabled")
	T.eq(ent.nw.ws_flag_carrier, NO_ENTITY, "no carrier")
	T.eq(ent.nw.ws_flag_carrier_team, NOBODY, "no carrier's team")
	model:PickUp(CARRIER, BLUE, CTF)
	ent:Publish()
	T.eq(ent.nw.ws_flag_state, Flag.CARRIED, "carried")
	T.eq(ent.nw.ws_flag_carrier, CARRIER, "its carrier")
	T.eq(ent.nw.ws_flag_carrier_team, BLUE, "its carrier's team")
end)

T.test("a flag networks the game's tally", function()
	local world = { limit = 5 }
	local class, globals = EntityClass(nil, world)
	world.tally:Capture(BLUE, 5)
	FlagEntity(class):PublishTally()
	T.eq(globals["ws_flag_caps_" .. RED], 0, "RED's")
	T.eq(globals["ws_flag_caps_" .. BLUE], 1, "BLU's")
	T.eq(globals.ws_flag_caplimit, 5, "the limit")
	T.eq(globals.ws_flag_scores, true, "scored")
end)

T.test("a flag networks no tally when no game being played counts captures", function()
	local world = { noStanding = true }
	local class, globals = EntityClass(nil, world)
	FlagEntity(class):PublishTally()
	T.eq(globals.ws_flag_caplimit, nil, "nothing to network")
end)

T.test("a capture is told to the round manager, adding nothing to the rounds won", function()
	local carrier = Carrier()
	local world = {}
	local ent = FlagCarriedBy(world, carrier, BLUE)
	ent:Capture(carrier)
	T.eq(world.scoredInfo.team, BLUE, "the team")
	T.eq(world.scoredInfo.activator, carrier, "who")
	T.eq(world.scoredInfo.event, "flag_capture", "what for")
	T.eq(world.scoredInfo.score, 0, "a capture is not a round won")
end)

-- game_ctf as the server loads it, with the round manager it closes rounds through.
local function CtfGame(limit, flagRules, gameplay, roundState)
	local game
	local wins, printed = {}, {}
	local env = setmetatable({
		SERVER = true,
		hook = { Run = function(name) if name == "FlagRules" then return flagRules end end },
		GAMEMODE = {
			IsGameplay = function() return gameplay end,
			GetRoundState = function() return roundState end,
		},
		ROUND_ACTIVE = "active",
		HUD_PRINTCENTER = "center",
		PrintMessage = function(_, text) printed[#printed + 1] = text end,
		team = { GetName = function(t) return t == BLUE and "BLU" or "RED" end },
		CreateConVar = function() return { GetInt = function() return limit end } end,
		game_manager = { RegisterClass = function(_, tab) game = tab end },
		round_manager = { RoundOutcome = function(outcome) wins[#wins + 1] = outcome end },
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/gamerules/game_ctf.lua")), env)()
	return game, wins, printed
end

T.test("the game announces a capture, unless a derived game replaces that", function()
	local game, _, printed = CtfGame(5)
	local capture = { team = BLUE, event = "flag_capture" }
	game:TeamScored(capture)
	T.eq(printed[1], "BLU captured the intelligence", "announced")
	function game.AnnounceCapture() end
	game:TeamScored(capture)
	T.eq(#printed, 1, "replaced")
end)

T.test("the game closes the round at the capture limit, giving its reason", function()
	local game, wins = CtfGame(2)
	local capture = { team = BLUE, event = "flag_capture" }
	game:TeamScored(capture)
	T.eq(#wins, 0, "one of two")
	game:TeamScored(capture)
	T.eq(#wins, 1, "the limit")
	T.eq(wins[1].team, BLUE, "the capturing team")
	T.eq(wins[1].reason, Rounds.WINREASON.FLAG_CAPTURE_LIMIT, "its reason")
	T.eq(wins[1].forceMapReset, true, "a full reset")
	T.eq(wins[1].switchTeams, false, "no team switch")
end)

T.test("the game ignores scores that are not captures", function()
	local game, wins = CtfGame(1)
	game:TeamScored({ team = BLUE, event = "round_win" })
	T.eq(game.tally:Captures(BLUE), 0, "uncounted")
	T.eq(#wins, 0, "no win")
end)

T.test("the game gives its mode's flag rules as optional keys", function()
	local game = CtfGame(1, { ownersCarry = true, mayBeCapped = false, invaders = BLUE, scores = false })
	local rules = game:GetRules()
	T.eq(rules.FlagOwnersCarry, true, "who carries")
	T.eq(rules.FlagMayBeCapped, false, "whether they may be taken")
	T.eq(rules.FlagInvaders, BLUE, "the invaders")
	T.eq(rules.FlagScores, false, "whether captures score")
end)

T.test("the flag's entities name no game and no module of a game's", function()
	for _, file in ipairs({ ENTITY_FILE, CAPTURE_ZONE_FILE, RESET_ZONE_FILE }) do
		local source = assert(io.open(file, "r")):read("*a")
		T.eq(source:find("GetClass", 1, true), nil, file .. " looks a game up")
		T.eq(source:find("game_ctf", 1, true), nil, file .. " names game_ctf")
		T.eq(source:find("%f[%w_]capture_flag%f[^%w_]"), nil, file .. " reads capture_flag")
	end
end)

T.test("Wetsands asks the flag and the zones themselves who may carry and capture", function()
	local root = "addons/sandcastle/gamemodes/wetsands/gamemode/features/"
	for _, file in ipairs({ "flag/soldier.lua", "flag/sv.lua", "aiwar/sv_field.lua" }) do
		local source = assert(io.open(root .. file, "r")):read("*a")
		for _, name in ipairs({ "MayCapture", "MayCarry", "DropsIn", "New" }) do
			T.eq(source:find("Flag%a*%." .. name .. "%("), nil, file .. " calls " .. name .. " of the model")
		end
	end
end)

T.test("the feature's names for a flag's states and events are the entity's", function()
	for _, name in ipairs({ "HOME", "CARRIED", "DROPPED", "PICKUP", "DROP", "CAPTURE", "RETURN" }) do
		T.eq(Flag[name], FlagState[name], name)
	end
end)

T.test("a scenario that says nothing leaves a flag free to take, and its captures reported", function()
	local carrier = Carrier()
	local world = { rules = {}, team = { [carrier] = BLUE } }
	local model = FlagState.New({ team = RED })
	local ent = FlagEntity(EntityClass(nil, world), model)
	T.eq(ent:Give(carrier), true, "taken")
	ent:Capture(carrier)
	T.eq(#world.scored, 1, "reported")
end)

T.test("a flag's owners may not take it unless the scenario says so", function()
	local carrier = Carrier()
	local world = { rules = {}, team = { [carrier] = RED } }
	local model = FlagState.New({ team = RED })
	local ent = FlagEntity(EntityClass(nil, world), model)
	T.eq(ent:Give(carrier), false, "by default")
	world.rules = { FlagOwnersCarry = true }
	T.eq(ent:Give(carrier), true, "the scenario's rule")
end)

T.test("a scenario can keep a flag from being taken", function()
	local carrier = Carrier()
	local world = { rules = { FlagMayBeCapped = false }, team = { [carrier] = BLUE } }
	local model = FlagState.New({ team = RED })
	local ent = FlagEntity(EntityClass(nil, world), model)
	world.inside = { [ent] = { carrier } }
	ent:Think()
	T.eq(model:Carrier(), nil, "left alone")
end)

T.test("the invaders' spawn room keeps the flag when the scenario names them", function()
	local carrier = Carrier()
	local room = { active = true, team = BLUE, PointIsWithin = function() return true end }
	local world = { rules = { FlagInvaders = BLUE }, byClass = { func_respawnroom = { room } } }
	local ent, model = FlagCarriedBy(world, carrier, BLUE)
	ent:Think()
	T.eq(model:State(), Flag.CARRIED, "kept")
end)

T.test("with no mode's answer, flags can be taken in sandbox, and in gameplay only during a round", function()
	local function MayBeCapped(gameplay, state)
		return (CtfGame(1, nil, gameplay, state)):GetRules().FlagMayBeCapped
	end
	T.eq(MayBeCapped(false, "waiting"), true, "sandbox")
	T.eq(MayBeCapped(true, "waiting"), false, "gameplay, between rounds")
	T.eq(MayBeCapped(true, "active"), true, "gameplay, in a round")
end)

-- A player as GMod has one, for the entities' own answers.
local function Player(team, alive, at)
	return setmetatable({
		Team = function() return team end,
		IsPlayer = function() return true end,
		Alive = function() return alive end,
		GetPos = function() return at end,
		WorldSpaceCenter = function() return at end,
		GetModel = function() return "models/boneless.mdl" end,
		LookupBone = function() return nil end,
	}, { __tostring = function() return "player" end })
end

-- Bounds that hold whatever is at INSIDE and nothing else.
local INSIDE = Point(0, 0, 0)
local function Bounded(ent)
	ent.OBBMins = function() return Point(-1, -1, -1) end
	ent.OBBMaxs = function() return Point(1, 1, 1) end
	ent.WorldToLocal = function(_, pos)
		return { WithinAABox = function() return pos == INSIDE end }
	end
	return ent
end

T.test("with no gamemode's answer a flag goes by players: team, life and who stands on it", function()
	local inside, away, dead = Player(BLUE, true, INSIDE), Player(BLUE, true, Point(9, 9, 9)), Player(BLUE, false, INSIDE)
	local world = { noAnswers = true, players = { away, dead, inside } }
	local model = FlagState.New({ team = RED })
	local ent = Bounded(FlagEntity(EntityClass(nil, world), model))
	ent:Think()
	T.eq(model:Carrier(), inside, "the living player on it, of a team that may")
	inside.Alive = function() return false end
	ent:Think()
	T.eq(model:State(), Flag.DROPPED, "dropped when it dies")
end)

T.test("with no gamemode's answer a capture zone goes by where the carrier is", function()
	local carrier = Player(BLUE, true, INSIDE)
	local world = { noAnswers = true }
	local ent, model = FlagCarriedBy(world, carrier, BLUE)
	local zone = Bounded(Zone(CAPTURE_ZONE_FILE, world))
	T.eq(zone:TakeFlag(ent, Player(BLUE, true, Point(9, 9, 9))), false, "someone away from it")
	T.eq(model:State(), Flag.CARRIED, "still carried")
	T.eq(zone:TakeFlag(ent, carrier), true, "the carrier inside it")
end)

T.test("a zone caps for its own team's carriers, or any team's when it has none", function()
	local zone = Zone(CAPTURE_ZONE_FILE)
	zone.team = RED
	T.eq(zone:MayCapture(RED), true, "RED's zone, RED's carrier")
	T.eq(zone:MayCapture(BLUE), false, "RED's zone, BLU's carrier")
	zone.team = NOBODY
	T.eq(zone:MayCapture(BLUE), true, "a neutral zone")
end)

T.test("a flag says who may carry it", function()
	local flag = FlagState.New({ team = RED })
	T.eq(flag:MayCarry(BLUE, false), true, "its enemy")
	T.eq(flag:MayCarry(RED, false), false, "its own team")
	T.eq(flag:MayCarry(RED, true), true, "its own team, where owners carry")
end)

T.test("SetReturnTime takes a number, or goes back to the default", function()
	local ent, model = FlagCarriedBy({}, Carrier(), BLUE)
	ent:AcceptInput("SetReturnTime", "who", nil, "30")
	T.eq(model:ReturnTime(), 30, "the number")
	ent:AcceptInput("SetReturnTime", "who", nil, "junk")
	T.eq(model:ReturnTime(), FlagState.RETURN_TIME_DEFAULT, "the default")
end)

T.test("the flag feature calls nothing the game gave to the entities", function()
	local gone = { "Give", "Score", "Playing", "ForgetCarry", "Carry", "GoHome", "PublishFlag", "PublishTally", "PublishZones" }
	for _, part in ipairs({ "sv.lua", "soldier.lua" }) do
		local source = assert(io.open("addons/sandcastle/gamemodes/wetsands/gamemode/features/flag/" .. part, "r")):read("*a")
		for _, name in ipairs(gone) do
			T.eq(source:find("Game." .. name .. "(", 1, true), nil, part .. " calls Game." .. name)
		end
	end
end)

T.test("a flag's think networks the tally", function()
	local world = {}
	local class, globals = EntityClass(nil, world)
	local ent = FlagEntity(class, FlagState.New({ team = RED }))
	ent:Think()
	T.eq(globals.ws_flag_caplimit, world.limit, "networked")
end)

T.test("a capture is networked by the think that made it", function()
	local carrier = Carrier()
	local world = { globals = {} }
	local ent = FlagCarriedBy(world, carrier, BLUE)
	local zone = Zone(CAPTURE_ZONE_FILE, world)
	world.inside = { [zone] = { carrier } }
	world.byClass = { func_capturezone = { zone } }
	world.onScore = function(team) world.tally:Capture(team, world.limit) end
	ent:Think()
	T.eq(world.globals["ws_flag_caps_" .. BLUE], 1, "already counted")
end)

T.test("a capture zone networks where each team's carrier takes the flag", function()
	local world = {}
	local zones = CaptureZones(world, { { team = RED, center = "red's" }, { team = BLUE, center = "blu's" } })
	zones[1]:Publish()
	T.eq(world.globals["ws_flag_zone_" .. RED], "red's", "RED's zone")
	T.eq(world.globals["ws_flag_zone_" .. BLUE], "blu's", "BLU's zone")
end)

T.test("a neutral capture zone serves both teams, and the first enabled zone wins", function()
	local world = {}
	local zones = CaptureZones(world, {
		{ team = BLUE, center = "off", enabled = false },
		{ team = NOBODY, center = "neutral" },
		{ team = BLUE, center = "later" },
	})
	zones[1]:Publish()
	T.eq(world.globals["ws_flag_zone_" .. RED], "neutral", "RED's")
	T.eq(world.globals["ws_flag_zone_" .. BLUE], "neutral", "BLU's")
end)

T.test("a team with no enabled capture zone networks none", function()
	local world = {}
	local zones = CaptureZones(world, { { team = RED, center = "red's", enabled = false } })
	zones[1]:Publish()
	T.eq(world.globals["ws_flag_zone_" .. RED], "origin", "none")
end)

T.test("a capture zone's inputs network the change", function()
	local world = {}
	local zones = CaptureZones(world, { { team = RED, center = "red's" } })
	zones[1]:AcceptInput("Disable")
	T.eq(world.globals["ws_flag_zone_" .. RED], "origin", "disabled")
	zones[1]:AcceptInput("Enable")
	T.eq(world.globals["ws_flag_zone_" .. RED], "red's", "enabled")
	zones[1]:AcceptInput("SetTeam", nil, nil, tostring(BLUE))
	T.eq(world.globals["ws_flag_zone_" .. RED], "origin", "no longer RED's")
	T.eq(world.globals["ws_flag_zone_" .. BLUE], "red's", "BLU's now")
end)

T.test("a restored capture zone networks its state", function()
	local world = {}
	local zones = CaptureZones(world, { { team = RED, center = "red's" } })
	zones[1]:SetEnabled(false)
	T.eq(zones[1].enabled, false, "set")
	T.eq(world.globals["ws_flag_zone_" .. RED], "origin", "networked")
end)

T.test("a flag goes home unparented", function()
	local ent = FlagEntity(EntityClass())
	ent.parent = CARRIER
	ent.wsHome, ent.wsHomeAngles = "home", "homeAngles"
	ent:GoHome()
	T.eq(ent.parent, NO_ENTITY, "let go")
	T.eq(ent.pos, "home", "where it started")
	T.eq(ent.angles, "homeAngles", "as it stood")
end)

T.test("a flag rides a carrier without the carry bone at its origin", function()
	local ent = FlagEntity(EntityClass())
	local carrier = {
		GetModel = function() return "models/boneless.mdl" end,
		LookupBone = function() return nil end,
	}
	ent:Carry(carrier)
	T.eq(ent.parent, carrier, "parented")
	T.defined(ent.localPos.z, "offset from it")
	T.eq(ent.localAngles, "angle_zero", "upright")
end)

T.test("a dropped flag lands on the ground under the carrier, level", function()
	local ground = Point(1, 2, 3)
	local ent = FlagEntity(EntityClass({ Hit = true, HitPos = ground }))
	ent.parent = CARRIER
	ent:PutDown(Point(1, 2, 50))
	T.eq(ent.parent, NO_ENTITY, "let go")
	T.eq(ent.pos, ground, "on the ground")
	T.eq(ent.angles.y, 90, "still facing its way")
	T.eq(ent.angles.p, 0, "level")
end)

T.test("a flag over nothing stays where the carrier was", function()
	local ent = FlagEntity(EntityClass({ Hit = false }))
	local at = Point(1, 2, 50)
	ent:PutDown(at)
	T.eq(ent.pos, at, "where it was let go")
end)

T.test("Reset takes a carried flag from its carrier and home, firing its own outputs", function()
	local carrier = Carrier()
	local ent, model = FlagCarriedBy({}, carrier, BLUE)
	ent:Reset()
	T.eq(table.concat(ent.fired, ","), "OnDrop:carrier,OnReturn:carrier", "dropped, then returned")
	T.eq(model:State(), Flag.HOME, "home")
	T.eq(ent.pos, "home", "at home")
	T.eq(ent.nw.ws_flag_state, Flag.HOME, "networked")
end)

T.test("Reset returns a dropped flag and leaves one at home alone", function()
	local world = {}
	local ent, model = FlagCarriedBy(world, Carrier(), BLUE)
	model:Drop(NOW, false)
	ent:Reset()
	T.eq(table.concat(ent.fired, ","), "OnReturn:flag", "returned")
	ent:Reset()
	T.eq(#ent.fired, 1, "already home")
end)

T.test("a respawn zone resets a flag whose carrier crossed it", function()
	local zone = Zone(RESET_ZONE_FILE, {}, nil, function() return true end)
	local ent = FlagCarriedBy({}, Carrier(), BLUE)
	T.eq(zone:CarrierCrossed(ent, "from", "to"), true, "taken")
	T.eq(table.concat(ent.fired, ","), "OnDrop:carrier,OnReturn:carrier", "the flag's outputs")
	T.eq(#zone.fired, 0, "none of its own")
end)

T.test("a respawn zone leaves a flag alone when disabled or not crossed", function()
	local crossed = Zone(RESET_ZONE_FILE, {}, nil, function() return true end)
	crossed.enabled = false
	local missed = Zone(RESET_ZONE_FILE, {}, nil, function() return false end)
	for _, zone in ipairs({ crossed, missed }) do
		local ent = FlagCarriedBy({}, Carrier(), BLUE)
		T.eq(zone:CarrierCrossed(ent, "from", "to"), false, "not taken")
		T.eq(#ent.fired, 0, "nothing fired")
	end
end)

T.test("the zones take their own inputs", function()
	local reset = Zone(RESET_ZONE_FILE)
	T.eq(reset:AcceptInput("Disable"), true, "reset disable")
	T.eq(reset.enabled, false, "disabled")
	T.eq(reset:AcceptInput("Enable"), true, "reset enable")
	T.eq(reset.enabled, true, "enabled")
	T.eq(reset:AcceptInput("Nonsense"), false, "unknown")
	local capture = Zone(CAPTURE_ZONE_FILE)
	T.eq(capture:AcceptInput("SetTeam", nil, nil, tostring(BLUE)), true, "capture setteam")
	T.eq(capture.team, BLUE, "its team")
	T.eq(capture:AcceptInput("Disable"), true, "capture disable")
	T.eq(capture.enabled, false, "capture disabled")
	T.eq(capture:AcceptInput("Nonsense"), false, "capture unknown")
end)

T.test("a capture zone takes a flag from a carrier inside it, and the game scores", function()
	local carrier = Carrier()
	local world = {}
	local ent, model = FlagCarriedBy(world, carrier, BLUE)
	local zone = Zone(CAPTURE_ZONE_FILE, world)
	world.inside = { [zone] = { carrier } }
	T.eq(zone:TakeFlag(ent, carrier), true, "captured")
	T.eq(model:State(), Flag.HOME, "home")
	T.eq(table.concat(ent.fired, ","), "OnCapture:carrier,OnCapTeam2:carrier", "the flag's outputs")
	T.eq(table.concat(zone.fired, ","), "OnCapture:carrier,OnCapTeam2:carrier", "the zone's")
	T.eq(world.scored[1], BLUE, "scored once for BLU")
	T.eq(#world.scored, 1, "once")
	T.eq(world.events[#world.events], Flag.CAPTURE, "the gamemode told")
end)

T.test("a capture zone refuses when disabled, another team's, or the carrier is outside", function()
	local carrier = Carrier()
	local cases = {
		function(zone, world) zone.enabled = false; world.inside = { [zone] = { carrier } } end,
		function(zone, world) zone.team = RED; world.inside = { [zone] = { carrier } } end,
		function(zone, world) world.inside = { [zone] = {} } end,
	}
	for i, case in ipairs(cases) do
		local world = {}
		local ent, model = FlagCarriedBy(world, carrier, BLUE)
		local zone = Zone(CAPTURE_ZONE_FILE, world)
		case(zone, world)
		T.eq(zone:TakeFlag(ent, carrier), false, "case " .. i)
		T.eq(model:State(), Flag.CARRIED, "still carried")
		T.eq(#zone.fired, 0, "no outputs")
	end
end)

T.test("a capture does not score when the mode's flags score nothing", function()
	local carrier = Carrier()
	local world = { rules = { FlagScores = false } }
	local ent = FlagCarriedBy(world, carrier, BLUE)
	local zone = Zone(CAPTURE_ZONE_FILE, world)
	world.inside = { [zone] = { carrier } }
	zone:TakeFlag(ent, carrier)
	T.eq(#world.scored, 0, "unscored")
end)

T.test("a flag drops when its carrier dies or changes team", function()
	local carrier = Carrier(Point(5, 5, 5))
	local dead = { dead = carrier }
	local ent, model = FlagCarriedBy(dead, carrier, BLUE)
	ent:Think()
	T.eq(model:State(), Flag.DROPPED, "dead")
	local changed = {}
	local other, otherModel = FlagCarriedBy(changed, carrier, BLUE)
	changed.team[carrier] = RED
	other:Think()
	T.eq(otherModel:State(), Flag.DROPPED, "changed team")
end)

T.test("a flag carried into its team's active respawn room drops", function()
	local carrier = Carrier()
	local room = { active = true, team = BLUE, PointIsWithin = function() return true end }
	local world = { byClass = { func_respawnroom = { room } } }
	local ent, model = FlagCarriedBy(world, carrier, BLUE)
	ent:Think()
	T.eq(model:State(), Flag.DROPPED, "dropped")
end)

T.test("a flag sweeps its carrier's path through the respawn zones", function()
	local carrier = Carrier(Point(0, 0, 100))
	local world = {}
	local seen
	local zone = { CarrierCrossed = function(_, _, from, to) seen = { from, to } return false end }
	world.byClass = { func_respawnflag = { zone } }
	local ent = FlagCarriedBy(world, carrier, BLUE)
	ent:Think()
	carrier.at = Point(0, 0, 0)
	ent:Think()
	T.eq(seen[1].z, 100, "from where it was at the last think")
	T.eq(seen[2].z, 0, "to where it is")
end)

T.test("a flag thinks its carrier into a capture zone", function()
	local carrier = Carrier()
	local world = {}
	local ent, model = FlagCarriedBy(world, carrier, BLUE)
	local zone = Zone(CAPTURE_ZONE_FILE, world)
	world.inside = { [zone] = { carrier } }
	world.byClass = { func_capturezone = { zone } }
	ent:Think()
	T.eq(model:State(), Flag.HOME, "captured")
	T.eq(#zone.fired, 2, "by the zone")
end)

T.test("a flag at home is picked up by who stands on it", function()
	local carrier = Carrier()
	local world = { team = { [carrier] = BLUE } }
	local model = FlagState.New({ team = RED })
	local ent = FlagEntity(EntityClass(nil, world), model)
	world.inside = { [ent] = { carrier } }
	ent:Think()
	T.eq(model:Carrier(), carrier, "taken")
	T.eq(ent.parent, carrier, "on its back")
	T.eq(table.concat(ent.fired, ","), "OnPickup:carrier,OnPickupTeam2:carrier", "fired")
end)

T.test("a flag is given to a carrier only if the rules let it", function()
	local carrier = Carrier()
	local world = { team = { [carrier] = BLUE } }
	local model = FlagState.New({ team = BLUE })
	local ent = FlagEntity(EntityClass(nil, world), model)
	T.eq(ent:Give(carrier), false, "its own team's flag")
	model:SetTeam(RED)
	T.eq(ent:Give(carrier), true, "the enemy's")
	T.eq(model:Carrier(), carrier, "carried")
end)

T.test("a flag takes its own inputs", function()
	local carrier = Carrier()
	local ent, model = FlagCarriedBy({}, carrier, BLUE)
	T.eq(ent:AcceptInput("ForceReset", "who"), true, "taken")
	T.eq(model:State(), Flag.HOME, "home")
	T.eq(ent:AcceptInput("SetTeam", "who", nil, tostring(BLUE)), true, "set team")
	T.eq(model:Team(), BLUE, "its team")
	T.eq(ent.skin, 1, "BLU's skin")
	T.eq(ent:AcceptInput("Nonsense", "who"), false, "unknown")
end)

T.test("a carried flag dropped over a respawn zone goes home", function()
	local carrier = Carrier(Point(0, 0, 10))
	local zone = { enabled = true, Crossed = function() return true end, CarrierCrossed = function() return false end }
	local world = { byClass = { func_respawnflag = { zone } } }
	local ent, model = FlagCarriedBy(world, carrier, BLUE)
	ent:Drop(NOW)
	T.eq(model:State(), Flag.HOME, "home")
	T.eq(table.concat(ent.fired, ","), "OnDrop:carrier,OnReturn:carrier", "dropped, then returned")
end)

T.finish()
