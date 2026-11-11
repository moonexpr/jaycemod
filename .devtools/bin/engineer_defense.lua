-- The engineers' defence bench: RED's engineers (npc_pathfollower on their legs, armed, building
-- level-3 sentries) fortify the room of a control point against the AI war's BLU squad. Run on the
-- dev server through server_lua.py:
--
--   dt lua -f .devtools/bin/engineer_defense.lua           defines ENGDEF
--   dt lua 'return ENGDEF.Start({ point = "cap_red_1" })'   engineers out, fortifying, the war on
--   dt lua 'return ENGDEF.Status()'                        one line: the round, works, engineers, BLU
--   dt lua 'return ENGDEF.Report()'                        what happened since Start
--   dt lua 'return ENGDEF.Stop()'                          engineers and their works gone
--
-- opts: point (a team_control_point's name), count (3), weapon ("weapon_shotgun"), level (3),
-- blue (the war's BLU slots, 7), respawn (seconds an engineer waits to come back, at RED's
-- spawn nearest the point, on its teleporter's entrance once one stands, 0 for never; 8). The
-- order's home is just outside that spawn's room. A fallen engineer rejoins the same order. blueRespawn: BLU's respawn
-- wave in seconds (0: at once), else the map's.
ENGDEF = ENGDEF or {}
local E = ENGDEF

local RESPAWN_CHECK = 0.5

local function Point (v) return { x = v.x, y = v.y, z = v.z } end

local function OnMesh (pos)
	local area = navmesh.GetNearestNavArea (pos, false, 400)
	return area and area:GetClosestPointOnArea (pos) or pos
end

-- RED's spawn live this round (WS.SpawnPoints, the game's own) nearest the point. A map's other
-- spawns, for its later stages, may stand nearer and still be walled off from it.
local function RedSpawn (cap)
	local best, distance
	for _, spawn in ipairs (WS.SpawnPoints (WS.TEAM_RED)) do
		local d = spawn:GetPos ():Distance (cap)
		if not distance or d < distance then best, distance = spawn, d end
	end
	return best and best:GetPos () or cap
end

-- Just outside the spawn room holding spawn (func_respawnroom), on the side nearest the point: where
-- TF2's engineers put a teleporter's entrance, out of the spawn's doors and ledges. The spawn itself
-- with no room found.
local OUTSIDE_REACH = 250

local function OutsideSpawn (spawn, cap)
	for _, room in ipairs (ents.FindByClass ("func_respawnroom")) do
		local mins, maxs = room:WorldSpaceAABB ()
		if spawn:WithinAABox (mins - Vector (0, 0, 64), maxs + Vector (0, 0, 64)) then
			local best, distance
			for _, area in ipairs (navmesh.Find (spawn, 1500, 400, 400)) do
				local c = area:GetCenter ()
				local inside = c:WithinAABox (mins - Vector (0, 0, 64), maxs + Vector (0, 0, 64))
				local near = c:WithinAABox (mins - Vector (OUTSIDE_REACH, OUTSIDE_REACH, 128), maxs + Vector (OUTSIDE_REACH, OUTSIDE_REACH, 128))
				if not inside and near and area:GetSizeX () >= 48 and area:GetSizeY () >= 48 then
					local d = c:Distance (cap)
					if not distance or d < distance then best, distance = c, d end
				end
			end
			if best then return best end
		end
	end
	return spawn
end

local function Engineer (pos, opts)
	local f = ents.Create ("npc_pathfollower")
	f.NSToolManaged = true
	f.Weapons = { opts.weapon }
	f.NSSentryLevel = opts.level
	f:SetPos (OnMesh (pos) + Vector (0, 0, 4))
	f:Spawn ()
	f:Activate ()
	f:NSSetTeam (WS.TEAM_RED)
	f:NSSetDriver ("legs")
	return f
end

local function Log (what)
	E.log [#E.log + 1] = string.format ("%5.1f %s", CurTime () - E.startedAt, what)
end

function E.Start (opts)
	opts = opts or {}
	opts.point = opts.point or "cap_red_1"
	opts.count, opts.weapon, opts.level = opts.count or 3, opts.weapon or "weapon_shotgun", opts.level or 3
	opts.blue, opts.respawn = opts.blue or 7, opts.respawn or 8
	E.Stop ()
	local cap = ents.FindByName (opts.point) [1]
	if not IsValid (cap) then return "no point " .. opts.point end
	E.opts, E.cap, E.spawn = opts, cap:GetPos (), RedSpawn (cap:GetPos ())
	E.startedAt, E.log, E.engineers, E.deaths, E.kills = CurTime (), {}, {}, 0, 0
	local war = WS.Feature ("aiwar")
	if not war.rooms then war:FindRoomsNow () end
	-- each on its own nav area near the point, the nearest first, clear for a body
	local starts = {}
	for _, area in ipairs (navmesh.Find (E.cap, 600, 64, 64)) do
		local c = area:GetCenter ()
		local clear = not util.TraceHull ({ start = c + Vector (0, 0, 4), endpos = c + Vector (0, 0, 4), mins = Vector (-16, -16, 0), maxs = Vector (16, 16, 72), mask = MASK_NPCSOLID }).Hit
		if clear and area:GetSizeX () >= 32 and area:GetSizeY () >= 32 then starts [#starts + 1] = c end
	end
	table.sort (starts, function (a, b) return a:Distance (E.cap) < b:Distance (E.cap) end)
	if #starts < opts.count then return "no room for engineers near " .. opts.point end
	local positions = {}
	for i = 1, opts.count do
		local f = Engineer (starts [i], opts)
		E.engineers [i] = f
		positions [i] = Point (f:GetPos ())
	end
	local middle = { x = 0, y = 0, z = 0 }
	for _, p in ipairs (positions) do middle.x, middle.y = middle.x + p.x / #positions, middle.y + p.y / #positions end
	local room = war:RoomForSquad (Point (E.cap), middle, WS.TEAM_RED)
	if not room then return "no room at " .. opts.point end
	local Legs = nextsoldier.behavior.group_identity
	-- home at RED's spawn: a teleporter from it to the works, when it is far enough to save a walk
	E.home = OutsideSpawn (E.spawn, E.cap)
	local order = nextsoldier.squad.behaviors.fortify.Fortify (room, Point (E.home))
	order:SetMode (Legs.MODE.STATIONARY)
	order:SetRoom (room)
	local admit = function (around) return E.engineers [1]:NSLegsAdmit (around) end
	E.places = order:Places (positions, nextsoldier.engine.GroupSpacing (), admit (E.cap), admit)
	for i, f in ipairs (E.engineers) do f:NSLegsGive (order, E.places [i]) end
	order:Lead (E.engineers [1])
	E.order = order
	-- the war: BLU's squad alone
	war:SlotPlan ()
	war:SetSlotCount (WS.TEAM_RED,  0)
	war:SetSlotCount (WS.TEAM_BLUE, opts.blue)
	if not war.war then war:Start () end
	-- BLU's respawn wave, as a map sets it (tf_gamerules' SetBlueTeamRespawnWaveTime): 0, at once
	if opts.blueRespawn then WS.Feature ("rounds"):ProxyInput ("SetBlueTeamRespawnWaveTime", tostring (opts.blueRespawn)) end
	hook.Add ("WSPointCaptured",   "engdef", function (_, team) Log ("captured by " .. team) end)
	hook.Add ("WSRoundWin",        "engdef", function (winner, reason) Log ("round won by " .. tostring (winner) .. " (" .. tostring (reason) .. ")") end)
	hook.Add ("WSObjectDestroyed", "engdef", function (object, attacker)
		Log (object:GetClass () .. " destroyed by " .. tostring (IsValid (attacker) and (attacker.Nick and attacker:Nick () or attacker:GetClass ())))
	end)
	hook.Add ("WSTeleported", "engdef", function (rider)
		Log ("teleported " .. tostring (IsValid (rider) and rider:GetClass () or rider))
	end)
	hook.Add ("OnNPCKilled", "engdef", function (npc, attacker, inflictor)
		if npc:GetClass () == "npc_pathfollower" then
			local name = function (e) return IsValid (e) and (e.Nick and e:Nick () or e:GetClass ()) or "world" end
			Log ("an engineer killed by " .. name (attacker) .. " with " .. name (inflictor))
		end
		if WS.TeamNumber (npc) == WS.TEAM_BLUE and IsValid (attacker) and (attacker:GetClass () == "obj_sentrygun" or attacker:GetClass () == "npc_pathfollower") then E.kills = E.kills + 1 end
	end)
	hook.Add ("PlayerDeath", "engdef", function (ply, _, attacker)
		if ply:Team () == WS.TEAM_BLUE and IsValid (attacker) and (attacker:GetClass () == "npc_pathfollower" or (IsValid (attacker:GetOwner ()) and attacker:GetOwner ():GetClass () == "npc_pathfollower")) then E.kills = E.kills + 1 end
	end)
	E.dead, E.owned = {}, {}
	timer.Create ("engdef_respawn", RESPAWN_CHECK, 0, function ()
		for i, f in ipairs (E.engineers) do
			-- what each has built, kept while it lives, for it to have back
			if IsValid (f) and f:Health () > 0 then
				E.owned [i] = E.owned [i] or {}
				for _, class in ipairs ({ "obj_sentrygun", "obj_dispenser", "obj_teleporter" }) do
					for _, o in ipairs (ents.FindByClass (class)) do
						if o:GetBuilder () == f then E.owned [i] [o] = true end
					end
				end
			end
			if not (IsValid (f) and f:Health () > 0) and not E.dead [i] then
				E.dead [i] = CurTime ()
				E.deaths = E.deaths + 1
				Log ("engineer " .. i .. " down")
			end
			if E.dead [i] and opts.respawn > 0 and CurTime () - E.dead [i] >= opts.respawn then
				E.dead [i] = nil
				-- back at RED's spawn, on the teleporter's entrance when one stands, to be carried
				local entrance = E.order:WorksOf ("teleporter_entrance") [1]
				local pad = entrance and E.order:Object (entrance.id)
				-- with none yet, out at its spot, to build it on the way
				local at = IsValid (pad) and pad:GetPos () + Vector (0, 0, 16) or E.home + Vector ((i - 2) * 56, 0, 0)
				local back = Engineer (at, opts)
				-- the same engineer come back, as a TF2 player: its buildings its own still
				for object in pairs (E.owned [i] or {}) do
					if IsValid (object) then object:SetBuilder (back) end
				end
				back:NSLegsGive (E.order, E.places [i])
				E.engineers [i] = back
				Log ("engineer " .. i .. " back")
			end
		end
	end)
	return "engineers out: works " .. #order:Works ()
end

function E.Status ()
	if not E.order then return "not started" end
	local works = {}
	for _, w in ipairs (E.order:Works ()) do
		local o = E.order:Object (w.id)
		works [#works + 1] = w.kind:sub (1, 6) .. (IsValid (o) and (":" .. o:Health () .. "/" .. string.format ("%.1f", o:Constructed ())) or "-")
	end
	local eng = {}
	for i, f in ipairs (E.engineers) do eng [i] = IsValid (f) and f:Health () > 0 and f:Health () or "dead" end
	local blu, near = 0, 0
	for ent in pairs (WS.Feature ("aiwar").soldiers or {}) do
		if IsValid (ent) and WS.TeamNumber (ent) == WS.TEAM_BLUE and ent:Health () > 0 then
			blu = blu + 1
			if ent:GetPos ():Distance (E.cap) < 1200 then near = near + 1 end
		end
	end
	local left = GetGlobal2Float ("ws_timer_end_time", 0) - CurTime ()
	return string.format ("%4ds st%d left %4ds%s | %s | eng %s | blu %d near %d | kills %d deaths %d", CurTime () - E.startedAt,
		WS.State (), left, GetGlobal2Bool ("ws_timer_in_setup") and " setup" or "", table.concat (works, " "),
		table.concat (eng, ","), blu, near, E.kills, E.deaths)
end

function E.Report ()
	return table.concat (E.log or {}, "\n")
end

function E.Stop ()
	timer.Remove ("engdef_respawn")
	for _, name in ipairs ({ "WSPointCaptured", "WSRoundWin", "WSObjectDestroyed", "WSTeleported", "OnNPCKilled", "PlayerDeath" }) do hook.Remove (name, "engdef") end
	for _, f in ipairs (E.engineers or {}) do if IsValid (f) then f:Remove () end end
	for _, class in ipairs ({ "obj_sentrygun", "obj_dispenser", "obj_teleporter" }) do
		for _, o in ipairs (ents.FindByClass (class)) do o:Remove () end
	end
	E.engineers, E.order = {}, nil
	return "stopped"
end

return "ENGDEF loaded"
