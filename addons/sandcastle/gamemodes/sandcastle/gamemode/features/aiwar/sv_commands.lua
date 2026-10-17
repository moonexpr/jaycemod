-- Part of the AI war controller (sv.lua): the ws_aiwar_* and ns_* console commands.
local Controller, Map = ...
local Orders = WS.require("foundation.aiwar.orders")
local Tactics = WS.require("foundation.wartactics")
local Squad = WS.require("foundation.aiwar.squad")
local Slots = WS.require("foundation.aiwar.slots")
local Lanes = WS.require("foundation.aiwar.lanes")
local Tuning = WS.require("foundation.ns.tuning")
local Permissions = WS.require("foundation.permissions")
local RED, BLUE = Map.RED, Map.BLUE
local NEXTSOLDIER = Permissions.NEXTSOLDIER

local function Tell(ply, lines)
	for _, line in ipairs(lines) do
		print(line)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) end
	end
end

concommand.Add("ws_aiwar_report", function(ply)
	if not WS.Can(ply, NEXTSOLDIER) then return end
	if not Controller.war then
		Tell(ply, { "AI war: not running" })
		return
	end
	Tell(ply, Controller:Report())
	if IsValid(ply) then ply:ChatPrint("AI war: report printed to your console") end
end, nil, "Print every AI war soldier's role, action, route and last trip to the console")

-- NextSoldier's commands (docs/ns-debugging.md), for admins, printed to the
-- caller's console (and the server's). Named ns_<subject>_<verb>.
local function AdminCommand(name, run, help)
	concommand.Add(name, function(ply, _, args)
		if not WS.Can(ply, NEXTSOLDIER) then return end
		Tell(ply, run(args))
	end, nil, help)
end

-- Those that read the soldiers run while the war is on.
local function WarCommand(name, run, help)
	AdminCommand(name, function(args)
		if not Controller.war then return { name .. ": the AI war is not running" } end
		return run(args)
	end, help)
end

local TEAM_NAMED = {
	RED = RED,
	BLU = BLUE,
	BLUE = BLUE,
}

WarCommand("ns_squads_print", function(args)
	local team = args[1] and TEAM_NAMED[string.upper(args[1])]
	if args[1] and not team then return { "ns_squads_print: RED, BLU, or nothing for both" } end
	return Controller:SquadReport(team)
end, "Print each NextSoldier squad: its leader, formation spread, bound, flank, fall back, lane and each member's place; RED or BLU for one side")

WarCommand("ns_lanes_print", function()
	return Controller:LaneReport()
end, "Print each team's lanes: length against the shortest, overlap, and the squads holding them")

WarCommand("ns_lanes_replan", function()
	Controller:ReplanLanes()
	return { "ns_lanes_replan: every team's lanes are planned again at the next think" }
end, "Plan every team's lanes again; the lanes found stand until the new ones are ready")

-- Squads and jobs by hand, for testing how squads work: soldiers named by
-- entity index (the AI War panel's slot list sends them).
local function Indexes(command, args, from)
	local ids, bad = Slots.ParseIds({ unpack(args, from) })
	if ids == nil then return nil, { string.format("%s: '%s' is no entity index", command, bad) } end
	return ids
end

WarCommand("ns_squads_form", function(args)
	local indexes, told = Indexes("ns_squads_form", args, 1)
	if indexes == nil then return told end
	return Controller:FormSquadOf(indexes)
end, "Form a squad by hand of soldiers by entity index, the first leading; it may be any size, and keeps the leader's job")

WarCommand("ns_squads_join", function(args)
	local indexes, told = Indexes("ns_squads_join", args, 1)
	if indexes == nil then return told end
	if #indexes < 2 then return { "ns_squads_join: a soldier in the squad, then the soldiers to join it (entity indexes)" } end
	return Controller:JoinSquadOf(indexes[1], { unpack(indexes, 2) })
end, "Put soldiers (entity indexes after the first) in the squad of the first; it becomes a squad by hand")

WarCommand("ns_squads_leave", function(args)
	local indexes, told = Indexes("ns_squads_leave", args, 1)
	if indexes == nil then return told end
	return Controller:LeaveSquadOf(indexes)
end, "Take soldiers by entity index out of their squads (solo, or regrouped with ns_squads_auto_enabled)")

WarCommand("ns_squads_dissolve", function()
	return Controller:DissolveSquads()
end, "Dissolve every squad; with ns_squads_auto_enabled 0 every soldier stays solo until grouped by hand")

WarCommand("ns_jobs_assign", function(args)
	if args[1] == nil then return { "ns_jobs_assign: a job, then soldiers' entity indexes" } end
	local indexes, told = Indexes("ns_jobs_assign", args, 2)
	if indexes == nil then return told end
	return Controller:AssignJob(string.lower(args[1]), indexes)
end, "Give soldiers by entity index a job by hand (in a squad by hand, the whole squad's); the war leaves it be")

WarCommand("ns_jobs_release", function(args)
	local indexes, told = Indexes("ns_jobs_release", args, 1)
	if indexes == nil then return told end
	return Controller:ReleaseJob(indexes)
end, "Hand soldiers' jobs by entity index back to the war")

WarCommand("ns_battlelines_print", function()
	return Controller:LineReport()
end, "Print each team's battle lines: its front, its posts' width and depth, and the squads in contact or falling back")

-- Tuning the tactics while they run (foundation.ns.tuning). A lanes
-- constant plans the lanes again. Values last until the map changes.
local function Tuner()
	Controller.tuner = Controller.tuner or Tuning.Tuner.New({
		tactics = Tactics,
		orders = Orders,
		lanes = Lanes,
		squad = Squad,
	})
	return Controller.tuner
end

local function Replan(tunable)
	if Controller.war and (tunable == nil or Tuning.Replans(tunable)) then Controller:ReplanLanes() end
end

AdminCommand("ns_tactics_list", function(args)
	local lines = Tuner():Lines(args[1] or "")
	table.insert(lines, 1, "NextSoldier tactics constants (ns_tactics_tune <name> <value|reset> changes one):")
	if #lines == 1 then lines[2] = "  none named like '" .. args[1] .. "'" end
	return lines
end, "List NextSoldier's tactics constants, the changed ones first, with their defaults; a word lists those named like it")

AdminCommand("ns_tactics_tune", function(args)
	if #args < 2 then return { "ns_tactics_tune: <name> <value>, or <name> reset; ns_tactics_list lists the names" } end
	local tuner = Tuner()
	local ok, result
	if args[2] == "reset" then ok, result = tuner:Reset(args[1]) else ok, result = tuner:Set(args[1], args[2]) end
	if not ok then return { "ns_tactics_tune: " .. result } end
	Replan(result)
	return { "ns_tactics_tune: " .. tuner:Line(result) }
end, "Set one of NextSoldier's tactics constants until the map changes (<name> <value>), or put it back (<name> reset)")

AdminCommand("ns_tactics_reset", function()
	Tuner():ResetAll()
	Replan(nil)
	return { "ns_tactics_reset: every tactics constant back to its default" }
end, "Put every NextSoldier tactics constant back to its default")

-- The overlay is the nbdebug feature's AIWAR layer (ws_nb_debug AIWAR),
-- drawn with the other NPC debug layers; it sets ply.wsAiwarDebug.
concommand.Add("ws_aiwar_debug", function(ply)
	if not IsValid(ply) or not WS.Can(ply, NEXTSOLDIER) then return end
	WS.Feature("nbdebug"):ToggleLayer(ply, WS.require("foundation.npc.debug").AIWAR)
end, nil, "Toggle drawing each AI war soldier's route, goal and state (ws_nb_debug AIWAR)")

-- The soldiers' Npcs, for the nbdebug feature's other layers (PATH, COST,
-- BEHAVIOR, NAV): see the npc controller's WSNbDebugNpcs.
hook.Add("WSNbDebugNpcs", "ws_aiwar", function(found)
	for ent, entry in pairs(Controller.soldiers) do
		if IsValid(ent) then found[ent] = entry.npc end
	end
end)

-- Tracing a soldier's bridge (docs/aiwar-command.md §6): every query DrGBase
-- asks its orders, with the answer, and every event it tells them, printed
-- to the server console. Aim at a soldier (or give its entity index) to
-- toggle it; no soldier in sight turns all tracing off.
concommand.Add("ws_aiwar_trace", function(ply, _, args)
	if not WS.Can(ply, NEXTSOLDIER) then return end
	local ent = args[1] and Entity(tonumber(args[1]) or -1) or (IsValid(ply) and ply:GetEyeTrace().Entity)
	local function Say(text)
		print(text)
		if IsValid(ply) then ply:ChatPrint(text) end
	end
	if not (IsValid(ent) and Controller.soldiers[ent]) then
		for other in pairs(Controller.soldiers) do
			if IsValid(other) then other.NSTrace = nil end
		end
		Say("AI war trace: off for every soldier")
		return
	end
	ent.NSTrace = not ent.NSTrace or nil
	Say(string.format("AI war trace: #%d %s (server console)", ent:EntIndex(), ent.NSTrace and "on" or "off"))
end, nil, "Trace the queries and events between an AI war soldier (aimed at, or by entity index) and its orders")
