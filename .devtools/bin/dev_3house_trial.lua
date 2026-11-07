-- dev_3house's assault trial (.devtools/bin/dev_3house_bench.lua's map and helpers' kin): a squad
-- of SIZE RED followers on their legs, armed, against one BLU expert, armed, with EXPERT_HEALTH_SCALE times a soldier's own health.
-- Both sides fight as the base fights (looks, then fires on what it sees): no aim error and no
-- reaction time, which is tf_bot_difficulty's EXPERT; neither side is blinded or held.
--
--   muster   the squad leaves RED's spawn for the staging point on the grass west of the bench
--   assault  the squad is given the assault on the bench; once its first member stages, the
--            expert leaves BLU's spawn for the bench's middle, patrolling it (alert)
--   end      the expert killed (won), a member killed before the leader's signal (failed), the squad
--            fallen back or killed (lost), or TIMEOUT
--
-- Load it, start a trial, then read its log:
--   python3 .devtools/bin/instances.py dev_3house - < .devtools/bin/dev_3house_trial.lua
--   python3 .devtools/bin/instances.py dev_3house 'return NSAssaultTrial.Start()'
--   python3 .devtools/bin/instances.py dev_3house 'return NSAssaultTrial.Report()'
local Legs = nextsoldier.behavior.group_identity

local SIZE = 5
-- The expert's health, as many times a soldier's own.
local EXPERT_HEALTH_SCALE = 5
local SQUAD_KIT = { primary = { "weapon_smg1", "weapon_ar2" }, secondary = "weapon_pistol", melee = "weapon_crowbar" }
local EXPERT_KIT = { primary = { "weapon_ar2" }, secondary = "weapon_pistol", melee = "weapon_crowbar" }
-- The staging point: the grass west of the bench, beyond its west door; how near it a squad has
-- gathered, and how long it has to.
local STAGING_OFFSET = Vector(-640, 0, 0)
local GATHERED, MUSTER_SECONDS = 320, 40
-- How often the trial looks, how long an assault may take, and how often it keeps where each is.
local TICK, TIMEOUT, TRAIL_EVERY = 0.25, 150, 2

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

-- The member's legs, deepest action last.
local function Stack(member)
	local frames = nextsoldier.engine.Stack(member)
	return frames[#frames] and frames[#frames].name or "?"
end

local function Label(ent)
	if ent == T.expert then return "expert" end
	for i, member in ipairs(T.members) do
		if member == ent then return "member " .. i end
	end
	return IsValid(ent) and ent:GetClass() or "world"
end

local function Follower(spot, team, kit)
	local follower = ents.Create("npc_pathfollower")
	follower.NSToolManaged = true
	follower:SetPos(spot)
	follower:Spawn()
	follower:Activate()
	follower:NSSetTeam(team)
	follower:NSSetDriver("legs")
	follower:NSHoldFeet(false)
	follower:NSRespond("ShouldAttack", true)
	follower:NSKit(kit)
	return follower
end

local function Clear()
	hook.Remove("Think", "dev_3house_trial")
	hook.Remove("EntityTakeDamage", "dev_3house_trial")
	for _, member in ipairs(T.members or {}) do
		if IsValid(member) then member:Remove() end
	end
	if IsValid(T.expert) then T.expert:Remove() end
end

local function Living()
	local living = {}
	for _, member in ipairs(T.members) do
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
	for _, member in ipairs(Living()) do
		if member:GetPos():Distance2D(staging) > GATHERED then return false end
	end
	return true
end

local function Assault()
	local controller = WS.Feature("aiwar")
	controller:Classes()
	T.room = controller:RoomForSquad(Point(Named("bench_room")), Point(Staging()), WS.TEAM_RED)
	T.order = Give(Legs.Assault(T.room), Living())
	T.phase, T.assaultAt = "assault", CurTime()
	local flows = {}
	for _, e in ipairs(T.room.entrances or {}) do
		flows[#flows + 1] = string.format("%.0f,%.0f ours %d theirs %d", e.pos.x, e.pos.y, e.flow, e.enemyFlow)
	end
	Log("assault given: entrances " .. table.concat(flows, "; "))
end

local function ReleaseExpert()
	local order = Legs.Muster(Point(Named("bench_room")))
	order:SetMode(Legs.MODE.ALERT)
	Give(order, { T.expert })
	T.released = true
	Log("expert released: to the bench's middle, alert")
end

-- What changed since the last look: the order's steps, each member's first sight of the enemy and
-- the expert's of each member, and the dead.
local function Watch(now)
	local order = T.order
	for i, member in ipairs(T.members) do
		local alive = IsValid(member) and member:Health() > 0
		if not alive and not T.dead[i] then
			T.dead[i] = true
			Log(string.format("member %d killed", i))
		elseif alive then
			if member:HasEnemy() and not T.contact[i] then
				T.contact[i] = true
				Log(string.format("member %d sees the expert (%s)", i, Stack(member)))
			end
			if order and order:StagedAt(member) and not T.staged[i] then
				T.staged[i] = true
				Log(string.format("member %d staged", i))
			end
			if IsValid(T.expert) and T.expert:GetEnemy() == member and T.expertTarget ~= member then
				T.expertTarget = member
				Log(string.format("expert targets member %d (%s)%s", i, Stack(member),
					order and not order:Signalled() and " before the signal" or ""))
			end
		end
	end
	if order then
		for _, step in ipairs({ { "Signalled", "leader signals: Move in!" }, { "Engaged", "decoy has drawn the enemy" } }) do
			if order[step[1]](order) and not T.steps[step[1]] then
				T.steps[step[1]] = true
				Log(step[2])
			end
		end
		if order.cleared and not T.steps.cleared then T.steps.cleared = true Log("leader calls: Room clear!") end
		if order.routed and not T.steps.routed then T.steps.routed = true Log("leader calls: Fall back!") end
	end
	if now >= T.nextTrail then
		T.nextTrail = now + TRAIL_EVERY
		local frame = { t = math.Round(now - T.started, 1), members = {} }
		for i, member in ipairs(T.members) do
			frame.members[i] = IsValid(member) and member:Health() > 0 and Point(member:GetPos()) or false
		end
		frame.expert = IsValid(T.expert) and T.expert:Health() > 0 and Point(T.expert:GetPos()) or false
		T.trail[#T.trail + 1] = frame
	end
end

local function Finish(outcome)
	T.outcome = outcome
	hook.Remove("Think", "dev_3house_trial")
	Log("ended: " .. outcome)
end

local function Step()
	local now = CurTime()
	if now < T.nextLook then return end
	T.nextLook = now + TICK
	Watch(now)
	-- before the leader's signal, one member lost fails the mission; going in, losses are the assault's
	local lost = next(T.dead)
	if lost and not T.steps.Signalled then return Finish(string.format("failed: member %d killed before the assault", lost)) end
	if not (IsValid(T.expert) and T.expert:Health() > 0) then
		return Finish(string.format("won: the expert is dead, %d of %d left", #Living(), SIZE))
	end
	if #Living() == 0 then return Finish("lost: the squad is dead") end
	if T.phase == "muster" then
		if Gathered() or now - T.musterAt >= MUSTER_SECONDS then
			Log(Gathered() and "squad gathered at the staging point" or "muster timed out")
			Assault()
		end
	elseif T.phase == "assault" then
		if not T.released and next(T.staged) then ReleaseExpert() end
		if T.order.routed then return Finish("lost: the squad fell back") end
		if now - T.assaultAt >= TIMEOUT then return Finish("timed out") end
	end
end

function T.Start()
	if game.GetMap() ~= "dev_3house" then error("the trial runs on dev_3house, not " .. game.GetMap(), 2) end
	Clear()
	WS.Feature("aiwar"):SetForcefieldsPassable(true)
	T.members, T.log, T.trail, T.dead, T.contact, T.staged, T.steps = {}, {}, {}, {}, {}, {}, {}
	T.damage, T.outcome, T.released, T.order, T.expertTarget = {}, nil, false, nil, nil
	T.started, T.nextLook, T.nextTrail = CurTime(), 0, 0
	local spawns = ents.FindByName("red_spawn")
	for i = 1, SIZE do T.members[i] = Follower(spawns[i]:GetPos(), WS.TEAM_RED, SQUAD_KIT) end
	T.expert = Follower(ents.FindByName("blu_spawn")[1]:GetPos(), WS.TEAM_BLUE, EXPERT_KIT)
	T.expert:NSKit({ health = EXPERT_HEALTH_SCALE * T.expert:GetMaxHealth() })
	T.expert:SetHealth(T.expert:GetMaxHealth())
	hook.Add("EntityTakeDamage", "dev_3house_trial", function(target, dmg)
		if target ~= T.expert and not table.HasValue(T.members, target) then return end
		local key = Label(dmg:GetAttacker()) .. " > " .. Label(target)
		T.damage[key] = (T.damage[key] or 0) + dmg:GetDamage()
	end)
	-- a tick for the bodies to settle and their trees to start, then out of spawn
	timer.Simple(1, function()
		T.phase, T.musterAt = "muster", CurTime()
		Give(Legs.Muster(Point(Staging())), Living())
		Log("muster given: to the staging point")
		hook.Add("Think", "dev_3house_trial", Step)
	end)
	return "trial started: " .. SIZE .. " RED on their legs against one BLU expert of " .. T.expert:Health() .. " health"
end

function T.Stop()
	Clear()
	return "trial stopped"
end

function T.Report()
	local damage = {}
	for key, amount in SortedPairs(T.damage or {}) do damage[#damage + 1] = string.format("%s: %.0f", key, amount) end
	return util.TableToJSON({
		outcome = T.outcome or "running",
		expert = IsValid(T.expert) and T.expert:Health() or 0,
		squad = #Living(),
		log = T.log,
		damage = damage,
	}, true)
end
