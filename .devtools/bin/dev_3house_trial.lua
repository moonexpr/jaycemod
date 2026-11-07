-- dev_3house's assault trials (.devtools/bin/dev_3house_bench.lua's map and helpers' kin): a RED
-- squad of followers on their legs, armed, assaults the bench, held by BLU followers, armed. Each
-- runs two stacks: its main stack fights (nextsoldier.behavior.squad_member: holding its fire on a
-- mission its leader has yet to activate), its leggings put its feet where its order says. Both
-- sides fight as the base fights: no aim error and no reaction time, which is tf_bot_difficulty's
-- EXPERT; neither side is blinded or held.
--
--   ambush   twelve RED against six BLU lying in ambush inside the bench by the entrance RED's
--            flow comes in by, from the start
--   expert   five RED against one BLU of five times a soldier's health, which leaves its spawn for
--            the bench's middle once RED's first member stages, patrolling it (alert)
--   occupy   six BLU occupying the bench, guards patrolling round it and their leader checking in
--            on them; SILENCE_AFTER in, one guard is killed unheard: passed once its leader has told
--            the director, the squad has stacked up (the bench's alarm sounding) and, on its word,
--            reached where the guard was last heard from
--
-- In each, RED's squad leaves its spawn for the staging point on the grass west of the bench, then
-- is given the assault: it stages round the bench, hopping door to door out of its sight, and goes
-- in on its leader's signal. The trial ends failed with a RED member killed before the signal, won
-- with BLU dead or the room called clear (BLU fled), lost with RED fallen back or dead, or at TIMEOUT.
--
-- Load it, start a trial, then read its log:
--   python3 .devtools/bin/instances.py dev_3house - < .devtools/bin/dev_3house_trial.lua
--   python3 .devtools/bin/instances.py dev_3house 'return NSAssaultTrial.Start("ambush")'
--   python3 .devtools/bin/instances.py dev_3house 'return NSAssaultTrial.Report()'
local Legs = nextsoldier.behavior.group_identity

local KIT = { primary = { "weapon_smg1", "weapon_ar2" }, secondary = "weapon_pistol", melee = "weapon_crowbar" }
local RIFLE = { primary = { "weapon_ar2" }, secondary = "weapon_pistol", melee = "weapon_crowbar" }
-- red, blue: how many of each; health: BLU's, as many times a soldier's own; blue: BLU's order.
local TRIALS = {
	ambush = { red = 12, blue = 6, health = 1, kit = KIT, blue_order = "ambush" },
	expert = { red = 5, blue = 1, health = 5, kit = RIFLE, blue_order = "patrol" },
	occupy = { red = 0, blue = 6, health = 1, kit = KIT, blue_order = "occupy" },
}
-- The occupation: how long after it is given a guard is silenced, how long the squad has after to
-- reach where it was last heard from, and how near that it has.
local SILENCE_AFTER, RESPOND_SECONDS, REACHED = 40, 60, 160
-- The staging point: the grass west of the bench's court, out of its sight; how near it a squad has
-- gathered, and how long it has to.
local STAGING_OFFSET = Vector(-900, 0, 0)
local GATHERED, MUSTER_SECONDS = 384, 40
-- How often the trial looks, how long an assault may take, and how often it keeps where each is.
local TICK, TIMEOUT, TRAIL_EVERY = 0.25, 180, 2
-- An ambush is laid before RED sets out: RED waits until each of BLU lies at its place (within
-- LAID of it), or LAY_SECONDS.
local LAID, LAY_SECONDS = 48, 30

NSAssaultTrial = NSAssaultTrial or {}
local T = NSAssaultTrial

local function Named(name)
	local found = ents.FindByName(name)[1]
	if not IsValid(found) then error("dev_3house has no " .. name .. ": is this the map?", 2) end
	return found:GetPos()
end

local function Point(v) return { x = v.x, y = v.y, z = v.z } end

local function Ground(v)
	local tr = util.TraceLine({ start = v + Vector(0, 0, 64), endpos = v - Vector(0, 0, 256), mask = MASK_NPCSOLID_BRUSHONLY })
	return tr.HitPos + Vector(0, 0, 1)
end

local function Staging() return Ground(Named("bench_room") + STAGING_OFFSET) end

local function Log(what)
	T.log[#T.log + 1] = string.format("%6.2f %s", CurTime() - T.started, what)
end

-- What its leggings do now, deepest action last.
local function Legging(member)
	local frames = nextsoldier.engine.GroupStack(member)
	return frames[#frames] and frames[#frames].name or "?"
end

local function Label(ent)
	for i, member in ipairs(T.red or {}) do
		if member == ent then return "red " .. i end
	end
	for i, member in ipairs(T.blue or {}) do
		if member == ent then return "blue " .. i end
	end
	return IsValid(ent) and ent:GetClass() or "world"
end

local function Follower(spot, team, kit, name)
	local follower = ents.Create("npc_pathfollower")
	follower.NSToolManaged, follower.NSRadioName = true, name
	follower:SetPos(spot)
	follower:Spawn()
	follower:Activate()
	follower:NSSetTeam(team)
	follower:NSSetDriver("legs")
	follower:NSHoldFeet(false)
	follower:NSKit(kit)
	return follower
end

local function Clear()
	hook.Remove("Think", "dev_3house_trial")
	hook.Remove("EntityTakeDamage", "dev_3house_trial")
	for _, side in ipairs({ T.red or {}, T.blue or {} }) do
		for _, member in ipairs(side) do
			if IsValid(member) then member:Remove() end
		end
	end
	T.red, T.blue = {}, {}
end

local function Living(side)
	local living = {}
	for _, member in ipairs(side) do
		if IsValid(member) and member:Health() > 0 then living[#living + 1] = member end
	end
	return living
end

-- members given order, their places from where each stands, led by the first.
local function Give(order, members)
	local positions = {}
	for i, member in ipairs(members) do positions[i] = Point(member:GetPos()) end
	local at = Vector(order.point.x, order.point.y, order.point.z)
	local places = order:Places(positions, nextsoldier.engine.GroupSpacing(), members[1]:NSLegsAdmit(at),
		function(around) return members[1]:NSLegsAdmit(around) end)
	for i, member in ipairs(members) do member:NSLegsGive(order, places[i]) end
	order:Lead(members[1])
	return order
end

local function Gathered()
	local staging = Staging()
	for _, member in ipairs(Living(T.red)) do
		if member:GetPos():Distance2D(staging) > GATHERED then return false end
	end
	return true
end

local function Entrances(room)
	local flows = {}
	for _, e in ipairs(room.entrances or {}) do
		flows[#flows + 1] = string.format("%.0f,%.0f ours %d theirs %d", e.pos.x, e.pos.y, e.flow, e.enemyFlow)
	end
	return table.concat(flows, "; ")
end

-- Each of BLU at its place in the ambush.
local function Laid()
	if not T.blueOrder then return false end
	for _, member in ipairs(Living(T.blue)) do
		local place = member:NSLegsPlace()
		if place and member:GetPos():Distance2D(Vector(place.x, place.y, place.z)) > LAID then return false end
	end
	return true
end

local function Assault()
	local controller = WS.Feature("aiwar")
	controller:Classes()
	T.room = controller:RoomForSquad(Point(Named("bench_room")), Point(Staging()), WS.TEAM_RED)
	T.order = Give(Legs.Assault(T.room), Living(T.red))
	T.phase, T.assaultAt = "assault", CurTime()
	Log("RED given the assault: entrances " .. Entrances(T.room))
end

-- BLU's order: lying in ambush at once, or, released as RED's first stages, patrolling the bench.
local function Ambush()
	local controller = WS.Feature("aiwar")
	controller:Classes()
	local room = controller:RoomForSquad(Point(Named("bench_room")), Point(Named("blu_muster")), WS.TEAM_BLUE)
	T.blueOrder = Give(Legs.Ambush(room), T.blue)
	Log(string.format("BLU given the ambush at %.0f,%.0f", T.blueOrder.entrance.x, T.blueOrder.entrance.y))
end

local function Patrol()
	local order = Legs.Muster(Point(Named("bench_room")))
	order:SetMode(Legs.MODE.ALERT)
	T.blueOrder = Give(order, T.blue)
	T.released = true
	Log("BLU released: to the bench's middle, alert")
end

local function Once(key, what)
	if T.steps[key] then return end
	T.steps[key] = true
	Log(what)
end

-- What changed since the last look: each side's orders' steps, first sightings, and the dead.
local function Watch(now)
	local order, blue = T.order, T.blueOrder
	for side, members in pairs({ red = T.red, blue = T.blue }) do
		for i, member in ipairs(members) do
			local key = side .. " " .. i
			local alive = IsValid(member) and member:Health() > 0
			if not alive and not T.dead[key] then
				T.dead[key] = now
				Log(key .. " killed" .. (side == "red" and order and not order:Signalled() and " before the signal" or ""))
			elseif alive and member:HasEnemy() and not T.contact[key] then
				T.contact[key] = true
				Log(string.format("%s sees %s (%s)", key, Label(member:GetEnemy()), Legging(member)))
			end
			if alive and side == "red" and order and order:StagedAt(member) then Once("staged " .. i, key .. " staged") end
		end
	end
	if order then
		if order:Signalled() then Once("signal", "RED leader: Move in!") end
		if order:Engaged() then Once("engaged", "RED decoy has drawn the enemy") end
		if order.cleared then Once("cleared", "RED leader: Room clear!") end
		if order.abandoned then Once("abandoned", "RED leader lost: mission abandoned, Fall back!")
		elseif order.routed then Once("routed", "RED: Fall back!") end
	end
	if blue then
		if blue.Sprung and blue:Sprung() then Once("sprung", "BLU leader: Now!") end
		if blue.routed then Once("blue routed", "BLU: Fall back!") end
	end
	if now >= T.nextTrail then
		T.nextTrail = now + TRAIL_EVERY
		local frame = { t = math.Round(now - T.started, 1), red = {}, blue = {} }
		for side, members in pairs({ red = T.red, blue = T.blue }) do
			for i, member in ipairs(members) do
				frame[side][i] = IsValid(member) and member:Health() > 0 and Point(member:GetPos()) or false
			end
		end
		T.trail[#T.trail + 1] = frame
	end
end

local function Finish(outcome)
	T.outcome = outcome
	hook.Remove("Think", "dev_3house_trial")
	Log("ended: " .. outcome)
end

-- Each call over a squad's radio since the last look, into the log.
local function Calls(order, key)
	if not order then return end
	T.heard[key] = T.heard[key] or 0
	for i = T.heard[key] + 1, #order.radio do
		local call = order.radio[i]
		local namer = IsValid(order.leader) and order.leader or T.blue[1]
		Log(string.format("radio %s -> %s: %s", namer:NSLegsNameOf(call.from), namer:NSLegsNameOf(call.to), call.text))
	end
	T.heard[key] = #order.radio
end

-- The occupation: BLU holds the bench; a guard silenced SILENCE_AFTER in, the squad's response.
local function Occupation(now)
	local order = T.blueOrder
	if not order then
		if not WS.Feature("aiwar"):Classes() then return end
		local room = WS.Feature("aiwar"):RoomForSquad(Point(Named("bench_room")), Point(Named("blu_muster")), WS.TEAM_BLUE)
		T.blueOrder, T.occupiedAt = Give(Legs.Occupy(room), T.blue), now
		local guards = 0
		for _, member in ipairs(T.blue) do
			if T.blueOrder:PatrolOf(member:NSLegsPlace()) then guards = guards + 1 end
		end
		Log(string.format("BLU given the occupation: %d of %d on patrol round a loop of %d stops", guards, #T.blue, #T.blueOrder.loop))
		return
	end
	Calls(order, "blue")
	if not T.silenced and now - T.occupiedAt >= SILENCE_AFTER then
		for i, member in ipairs(T.blue) do
			if IsValid(member) and member:Health() > 0 and order:PatrolOf(member:NSLegsPlace()) then
				T.silenced = member
				Log(string.format("blue %d silenced at %.0f,%.0f", i, member:GetPos().x, member:GetPos().y))
				member:TakeDamage(10000)
				break
			end
		end
	end
	if order.alarm and not T.steps.alarm then
		T.steps.alarm = true
		local bench = ents.FindByName("bench_alarm")[1]
		Log(string.format("alarm raised at %.0f,%.0f, by the exit at %.0f,%.0f; the bench's alarm %s", order.alarm.at.x,
			order.alarm.at.y, order.alarm.exit.x, order.alarm.exit.y, IsValid(bench) and (bench.sounding and "sounding" or "silent") or "missing"))
	end
	if order:Signalled() then
		local there = 0
		for _, member in ipairs(Living(T.blue)) do
			if member:GetPos():Distance2D(Vector(order.alarm.at.x, order.alarm.at.y, 0)) <= REACHED then there = there + 1 end
		end
		if there == #Living(T.blue) then return Finish(string.format("passed: %d of BLU reached where the guard was last heard from", there)) end
	end
	if T.silenced and now - T.occupiedAt - SILENCE_AFTER >= RESPOND_SECONDS then return Finish("timed out: the squad never reached it") end
end

local function Step()
	local now = CurTime()
	if now < T.nextLook then return end
	T.nextLook = now + TICK
	Watch(now)
	if T.spec.blue_order == "occupy" then
		if T.outcome == nil then Occupation(now) end
		return
	end
	Calls(T.order, "red")
	Calls(T.blueOrder, "blue")
	local order = T.order
	for key in pairs(T.dead) do
		if key:find("^red") and not (order and order:Signalled()) then return Finish("failed: " .. key .. " killed before the assault") end
	end
	if #Living(T.blue) == 0 then return Finish(string.format("won: BLU dead, %d of %d RED left", #Living(T.red), #T.red)) end
	if order and order.cleared then
		return Finish(string.format("won: the room clear, %d of %d RED left, %d of %d BLU fled", #Living(T.red), #T.red,
			#Living(T.blue), #T.blue))
	end
	if #Living(T.red) == 0 then return Finish("lost: RED dead") end
	-- BLU lies in ambush once the war's classes know which way RED comes in (worked out as the map loads)
	if T.spec.blue_order == "ambush" and not T.blueOrder and WS.Feature("aiwar"):Classes() then Ambush() end
	if T.phase == "lay" and (Laid() or now - T.layAt >= LAY_SECONDS) then
		Log(Laid() and "BLU lies in wait" or "BLU's ambush not laid in time")
		T.phase = "set out"
	end
	if T.phase == "set out" then
		T.phase, T.musterAt = "muster", now
		Give(Legs.Muster(Point(Staging())), Living(T.red))
		Log("RED given the muster: to the staging point")
	elseif T.phase == "muster" then
		if Gathered() or now - T.musterAt >= MUSTER_SECONDS then
			Log(Gathered() and "RED gathered at the staging point" or "RED's muster timed out")
			Assault()
		end
	elseif T.phase == "assault" then
		if T.spec.blue_order == "patrol" and not T.released and next(order.stagedAt or {}) then Patrol() end
		if order.routed then return Finish(order.abandoned and "lost: RED's leader killed, the mission abandoned" or "lost: RED fell back") end
		if now - T.assaultAt >= TIMEOUT then return Finish("timed out") end
	end
end

function T.Start(name)
	name = name or "ambush"
	local spec = TRIALS[name]
	if not spec then error("no trial " .. tostring(name) .. ": ambush or expert", 2) end
	if game.GetMap() ~= "dev_3house" then error("the trial runs on dev_3house, not " .. game.GetMap(), 2) end
	Clear()
	WS.Feature("aiwar"):SetForcefieldsPassable(true)
	T.spec, T.log, T.trail, T.dead, T.contact, T.steps, T.damage, T.heard = spec, {}, {}, {}, {}, {}, {}, {}
	T.silenced, T.occupiedAt = nil, nil
	T.outcome, T.released, T.order, T.blueOrder = nil, false, nil, nil
	T.started, T.nextLook, T.nextTrail = CurTime(), 0, 0
	local reds, blues = ents.FindByName("red_spawn"), ents.FindByName("blu_spawn")
	for i = 1, spec.red do T.red[i] = Follower(reds[i]:GetPos(), WS.TEAM_RED, KIT, "red " .. i) end
	for i = 1, spec.blue do
		local blue = Follower(blues[i]:GetPos(), WS.TEAM_BLUE, spec.kit, "blue " .. i)
		blue:NSKit({ health = spec.health * blue:GetMaxHealth() })
		blue:SetHealth(blue:GetMaxHealth())
		T.blue[i] = blue
	end
	hook.Add("EntityTakeDamage", "dev_3house_trial", function(target, dmg)
		local victim = Label(target)
		if not (victim:find("^red") or victim:find("^blue")) then return end
		local key = Label(dmg:GetAttacker()) .. " > " .. victim
		T.damage[key] = (T.damage[key] or 0) + dmg:GetDamage()
	end)
	-- a tick for the bodies to settle and their trees to start; then BLU lays its ambush, if it
	-- has one, before RED sets out
	timer.Simple(1, function()
		T.phase, T.layAt = spec.blue_order == "ambush" and "lay" or "set out", CurTime()
		hook.Add("Think", "dev_3house_trial", Step)
	end)
	return string.format("trial %s started: %d RED, %d BLU of %d health", name, spec.red, spec.blue, T.blue[1]:Health())
end

function T.Stop()
	Clear()
	return "trial stopped"
end

function T.Report()
	local damage, dealt = {}, {}
	for key, amount in pairs(T.damage or {}) do
		local by = key:match("^(.-) >")
		dealt[by] = (dealt[by] or 0) + amount
	end
	for by, amount in SortedPairs(dealt) do damage[#damage + 1] = string.format("%s dealt %.0f", by, amount) end
	return util.TableToJSON({
		outcome = T.outcome or "running",
		red = #Living(T.red or {}),
		blue = #Living(T.blue or {}),
		log = T.log,
		damage = damage,
	}, true)
end
