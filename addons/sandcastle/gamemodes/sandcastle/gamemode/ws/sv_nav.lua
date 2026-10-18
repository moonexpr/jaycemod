-- The map's navigation mesh, which every NextBot walks (the AI war's
-- soldiers, the bosses). TF2 ships a mesh for few of its maps (its bots
-- generate one), and GMod cannot load TF2's own (.devtools/bin/nav_convert.py
-- converts those). mp_nav_generate, for admins and the server console,
-- builds one: GMod's generator walks out from seeds, and TF2 maps spawn
-- players at info_player_teamspawn, which it does not seed from, so every
-- spawn point and control point is a seed. It walks only what stands in
-- place, and a map's spawn doors, setup gates and bridges (cp_steel's slide
-- out to its last point as the others fall) stand shut or drawn back: every
-- door is unlocked, and opened, or closed when it is a floor (flat and
-- wide: a bridge, laid out by closing it), spawn barriers are made
-- passable, and it
-- begins once no door moves (or after DOOR_WAIT). The generator walks
-- through every door (Source's IsEntityWalkable), a laid bridge too, so each
-- floor gets a stand-in it walks on: an always-solid func_brush of the
-- floor's own brush where it lies, gone with the map reset. It runs in Sandbox mode
-- (entered first; refused while sv_gameplay_disable_sandbox forbids it), so
-- no round closes a door meanwhile, with every spawn limit (sbox_max<kind>,
-- one per cleanup kind) at 0 so nothing new stands in its way. When it is
-- done GMod has saved maps/<map>.nav, the limits are put back, the map is
-- reset (its doors and gates put back), and the admin who started it is
-- told. Every client's progress box follows each stage
-- (WS.NavProgress, ws/sh_nav_progress.lua). Meanwhile, and while
-- the engine's own nav_generate runs, players still join, but nobody picks
-- a team or spawns: one who would spawn watches instead, and the dead stay
-- down; when it is done, all of them spawn.
--
-- An idle server builds its own: once it is idle (WSServerIdle,
-- ws/sv_idle.lua) on a map with no mesh, it runs as the console's would, and
-- goes back to Gameplay mode when it left it to generate, so the rounds and
-- the next-map vote carry on.
local Gamemode = WS.require("foundation.gamemode")
local Doors = WS.require("foundation.npc.doors")
local Progress = WS.require("foundation.nav_progress")
local Clip = WS.require("foundation.npc.clip")
local NavGaps = WS.require("foundation.nav_gaps")

local SEEDS = { "info_player_teamspawn", "info_player_start", "team_control_point" }
local DOORS = { "func_door", "func_door_rotating", "prop_door_rotating" }
local BARRIERS = { "func_respawnroomvisualizer" }
local DOOR_WAIT = 60
local HELD = "Calculating the navigation mesh: you spawn when it is done"
local POLL = "ws_nav_generate"

-- func_door's m_toggle_state while opening or closing; prop_door_rotating's
-- m_eDoorState
local TOGGLE_MOVING = { [2] = true, [3] = true }
local PROP_DOOR_MOVING = { [1] = true, [3] = true }

local underWay = false
-- players made to watch while it runs, spawned when it is done
local held = {}


function WS.NavMeshUsable()
	return navmesh.IsLoaded() and navmesh.GetNavAreaCount() > 0
end

-- Whether players are held back from teams and spawning now.
local function Holding()
	return underWay or navmesh.IsGenerating()
end

hook.Add("PlayerSpawn", "ws_nav_hold", function(ply)
	if not Holding() then return end
	held[ply] = true
	WS.StartObserving(ply)
	ply:PrintMessage(HUD_PRINTCENTER, HELD)
	return true
end)

hook.Add("PlayerDeathThink", "ws_nav_hold", function()
	if Holding() then return false end
end)

local function RefuseTeam(ply)
	if not Holding() then return end
	ply:PrintMessage(HUD_PRINTCENTER, HELD)
	return true
end

hook.Add("PlayerRequestTeam", "ws_nav_hold", RefuseTeam)
hook.Add("ShowTeam", "ws_nav_hold", RefuseTeam)

-- Spawns everyone held back: those made to watch, and the dead.
local function Release()
	for _, ply in ipairs(player.GetHumans()) do
		if held[ply] or not ply:Alive() then
			WS.StopObserving(ply)
			ply:Spawn()
		end
	end
	held = {}
end

-- The masks walkers move under on this map, and the traces that stand in
-- for their walking take (foundation.npc.clip: on a players' map, the
-- player's clips), read off the map's entities once.
local CLIP_MASKS = {
	[Clip.PLAYER] = { solid = MASK_PLAYERSOLID, brushes = MASK_PLAYERSOLID_BRUSHONLY },
	[Clip.NPC] = { solid = MASK_NPCSOLID, brushes = MASK_NPCSOLID_BRUSHONLY },
}
local clipMasks

function WS.ClipMasks()
	if not clipMasks then
		local classes = {}
		for i, ent in ipairs(ents.GetAll()) do classes[i] = ent:GetClass() end
		clipMasks = CLIP_MASKS[Clip.For(classes)]
	end
	return clipMasks
end

-- The mesh's seams (foundation.nav_gaps), linked both ways where a walker
-- crosses: a soldier's hull above step height sweeps across clear under the
-- clip masks, and finds floor (a clip brush counts) under the seam. Swept
-- GAP_BATCH a tick, to keep the tick short; once the map's mesh has loaded
-- and after mp_nav_generate, since the links live only in memory.
local GAP_BATCH = 64
local GAP_TIMER = "ws_nav_gaps"
local CROSS_MINS, CROSS_MAXS = Vector(-12, -12, 0), Vector(12, 12, 72 - NavGaps.STEP_HEIGHT)
local STEP = Vector(0, 0, NavGaps.STEP_HEIGHT)
local FLOOR_MAXS = Vector(12, 12, 1)

local function V(p) return Vector(p.x, p.y, p.z) end
local function Point(v) return { x = v.x, y = v.y, z = v.z } end

local function Crosses(from, to, mask)
	local across = util.TraceHull({ start = from + STEP, endpos = to + STEP, mins = CROSS_MINS, maxs = CROSS_MAXS, mask = mask })
	if across.Hit or across.StartSolid then return false end
	local middle = (from + to) / 2
	local below = util.TraceHull({ start = middle + STEP, endpos = middle - STEP, mins = CROSS_MINS, maxs = FLOOR_MAXS, mask = mask })
	return below.Hit and not below.StartSolid
end

function WS.BridgeNavGaps()
	timer.Remove(GAP_TIMER)
	if not WS.NavMeshUsable() then return end
	local byId, areas = {}, {}
	for i, area in ipairs(navmesh.GetAllNavAreas()) do
		local extent = area:GetExtentInfo()
		byId[area:GetID()] = area
		areas[i] = { id = area:GetID(), lo = Point(extent.lo), hi = Point(extent.hi) }
	end
	local candidates = NavGaps.Candidates(areas,
		function(id, x, y) return byId[id]:GetZ(Vector(x, y, 0)) end,
		function(from, to) return byId[from]:IsConnected(byId[to]) end)
	local mask, next, linked = WS.ClipMasks().brushes, 1, 0
	timer.Create(GAP_TIMER, 0, 0, function()
		for i = next, math.min(next + GAP_BATCH - 1, #candidates) do
			local c = candidates[i]
			local a, b = byId[c.a], byId[c.b]
			if IsValid(a) and IsValid(b) and Crosses(V(c.from), V(c.to), mask) then
				if not a:IsConnected(b) then a:ConnectTo(b) end
				if not b:IsConnected(a) then b:ConnectTo(a) end
				linked = linked + 1
			end
		end
		next = next + GAP_BATCH
		if next > #candidates then
			timer.Remove(GAP_TIMER)
			print(string.format("Navigation mesh: linked %d of %d seams between areas", linked, #candidates))
			-- routes planned before may lack the ways just linked
			if linked > 0 then hook.Run("WSNavLinked") end
		end
	end)
end

-- GMod loads the mesh after the map's entities: the sweep waits for it, a
-- second at a time, up to NAV_LOAD_WAIT (a map without one never has it).
local NAV_LOAD_WAIT = 60

hook.Add("InitPostEntity", "ws_nav_gaps", function()
	timer.Create(GAP_TIMER, 1, NAV_LOAD_WAIT, function()
		if WS.NavMeshUsable() then WS.BridgeNavGaps() end
	end)
end)

local function Tell(ply, text)
	if IsValid(ply) then ply:ChatPrint(text) else print(text) end
end

local function Each(classes, fn)
	for _, class in ipairs(classes) do
		for _, ent in ipairs(ents.FindByClass(class)) do fn(ent) end
	end
end

local function IsFloor(door)
	local mins, maxs = door:OBBMins(), door:OBBMaxs()
	return Doors.IsFloor({ x = maxs.x - mins.x, y = maxs.y - mins.y, z = maxs.z - mins.z })
end

local function AnyDoorMoving()
	local moving = false
	Each(DOORS, function(door)
		if door:GetClass() == "prop_door_rotating" then
			moving = moving or PROP_DOOR_MOVING[door:GetInternalVariable("m_eDoorState")] == true
		else
			moving = moving or TOGGLE_MOVING[door:GetInternalVariable("m_toggle_state")] == true
		end
	end)
	return moving
end

-- Generates the mesh for ply (nil: the console); resume: back to Gameplay
-- mode after, when it was left for this. Whether it started.
local function Generate(ply, resume)
	if underWay or navmesh.IsGenerating() then
		Tell(ply, "Navigation mesh: already being generated")
		return false
	end
	if GetConVar("sv_gameplay_enabled"):GetBool() then
		if GetConVar("sv_gameplay_disable_sandbox"):GetBool() then
			Tell(ply, "Navigation mesh: it is generated in Sandbox mode, which sv_gameplay_disable_sandbox 1 forbids; set it to 0 first")
			return false
		end
		WS.Feature("gamemode"):Request(Gamemode.SANDBOX, Gamemode.SOURCE_BUTTON, ply)
	else
		resume = false
	end
	underWay = true
	local limits = {}
	for _, kind in ipairs(cleanup.GetTable()) do
		local limit = GetConVar("sbox_max" .. kind)
		if limit then
			limits[limit] = limit:GetString()
			limit:SetString("0")
		end
	end
	local up, seeds = Vector(0, 0, 1), 0
	Each(SEEDS, function(ent)
		navmesh.AddWalkableSeed(ent:GetPos(), up)
		seeds = seeds + 1
	end)
	Each(DOORS, function(door)
		door:Fire("Unlock")
		door:Fire(IsFloor(door) and "Close" or "Open")
	end)
	Each(BARRIERS, function(barrier) barrier:SetNotSolid(true) end)
	Tell(ply, "Navigation mesh: opening " .. game.GetMap() .. "'s doors, then generating from " .. seeds .. " seeds; this takes a few minutes")
	local started = CurTime()
	WS.NavProgress(Progress.OPENING)
	local giveUp, began = started + DOOR_WAIT, false
	timer.Create(POLL, 1, 0, function()
		if not began then
			if AnyDoorMoving() and CurTime() < giveUp then return end
			began = true
			Each(DOORS, function(door)
				if not IsFloor(door) then return end
				local standIn = ents.Create("func_brush")
				standIn:SetModel(door:GetModel())
				standIn:SetPos(door:GetPos())
				standIn:SetAngles(door:GetAngles())
				standIn:SetKeyValue("Solidity", "2")
				standIn:Spawn()
			end)
			navmesh.BeginGeneration()
			WS.NavProgress(Progress.GENERATING)
			return
		end
		if navmesh.IsGenerating() then return end
		timer.Remove(POLL)
		underWay = false
		for limit, value in pairs(limits) do limit:SetString(value) end
		game.CleanUpMap()
		Release()
		WS.BridgeNavGaps()
		WS.NavProgress(Progress.DONE, navmesh.GetNavAreaCount())
		Tell(ply, "Navigation mesh: done, " .. navmesh.GetNavAreaCount() .. " areas, saved as maps/" .. game.GetMap() .. ".nav; the map was reset")
		if resume then WS.Feature("gamemode"):Request(Gamemode.GAMEPLAY, Gamemode.SOURCE_CONSOLE, nil) end
	end)
	return true
end

concommand.Add("mp_nav_generate", function(ply)
	if not WS.Can(ply, WS.require("foundation.permissions").RULES) then
		Tell(ply, "Navigation mesh: you may not generate it")
		return
	end
	Generate(ply, false)
end, nil, "Generate this map's navigation mesh from its spawn and control points, its doors open (admins); takes a few minutes and resets the map")

-- The idle server's own run (ws/sv_idle.lua).
hook.Add("WSServerIdle", "ws_nav", function()
	if WS.NavMeshUsable() or underWay or navmesh.IsGenerating() then return end
	if Generate(nil, true) then print("Navigation mesh: the server is idle and " .. game.GetMap() .. " has none; generating one") end
end)
