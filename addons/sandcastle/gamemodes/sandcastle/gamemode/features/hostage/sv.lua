-- The hostage feature's controller. It puts the round in the hostage mode
-- (features.hostage.round), owns the round's rules (features.hostage.model)
-- and applies them to the map's hostages through their hostage_entity
-- observers, each of which tells whether its hostage lives and whether it
-- stands in a rescue zone: a held hostage within USE_RANGE of a living BLU
-- soldier or player follows them; one whose rescuer dies or leaves is let go;
-- one led into a func_hostage_rescue (else, on a map without one, the zone
-- round BLU's spawns: features.hostage.zone) is rescued; one no longer alive
-- is killed; and once none is left unresolved with half or more rescued, BLU
-- wins (HOSTAGES_RESCUED). RED wins by killing BLU, which the rounds
-- controller decides as it does in arena. A hostage that can follow, be armed
-- or be rescued (npc_civilian: SetLeader, Arm, Rush, Rescued) is told so; a
-- hostage of another class (a prop) is only observed.
--
-- The map's settings are its cs_logic_hostage's (features.hostage.config),
-- made with the defaults on a map without one.
--
-- One hostage a round is armed (features.hostage.pistol), its gun hidden
-- until, freed, it fires at RED: from then it can be killed, which the round
-- counts (killed hostages are never rescued); its pistol then lies where it
-- fell, the hostages still held or following rush for it, and the first to
-- reach it is armed with it.
--
-- The AI war reads it through Snapshot (features.aiwar.sv_field): every
-- hostage of the round, rescued ones too, so the groups of hostages stay the
-- same all round.
--
-- Loaded by hostage_entity. It loads rounds.
local Rescue = WS.require("features.hostage.model")
local Round = WS.require("features.hostage.round")
local Zone = WS.require("features.hostage.zone")
local Hotfixes = WS.require("features.hostage.hotfixes")
local Voice = WS.require("features.hostage.voice")
local Pistol = WS.require("features.hostage.pistol")
local Announcer = WS.require("features.hostage.announcer")
local Hud = WS.require("features.hostage.hud")
local State = WS.require("games.gameplay.rounds.state")
local Rounds = gameplay.rounds

local THINK_INTERVAL = 0.1
local THINK_HOOK = "ws_hostage"
-- The zone reaches this far past BLU's farthest spawn.
local ZONE_MARGIN = 150

local BLUE = WS.TEAM_BLUE

-- Its voice carries as a voice does, and it calls for help to a BLU soldier
-- within CALL_RANGE of it, in sight.
local VOICE_LEVEL = 80
local CALL_RANGE = 600
-- The model addon clients download (features.hostage.models).
local MODEL_WORKSHOP = "3172805326"

-- The round's timer: when it runs out RED has kept the hostages and wins
-- (features.hostage.round).
local roundTime = CreateConVar("mp_hostage_roundtime", "240", { FCVAR_NOTIFY, FCVAR_REPLICATED },
	"Length of a hostage round in seconds, shown as its timer; when it runs out the hostages were not rescued and RED wins. 0: untimed.",
	0, 3600)

local LOGIC_CLASS = "cs_logic_hostage"

local Controller = {
	rounds = WS.Feature("rounds"),
	bound = {}, -- id -> its hostage_entity observer, while it is there
	known = {}, -- id -> { home, pos } for each hostage of the round
	round = nil, -- features.hostage.model's round
	pistol = nil, -- features.hostage.pistol's, nil without hostages or with none armed
	armed = false, -- whether the pistol's first holder has its pistol yet
	pistolEnt = nil, -- the pistol lying, as an entity
	logic = nil, -- the map's cs_logic_hostage
	zone = nil,
	won = false,
	nextThink = 0,
}

-- The map's hostage settings (features.hostage.config): its
-- cs_logic_hostage's, made with the defaults on a map without one.
function Controller:Config()
	if not IsValid(self.logic) then
		self.logic = ents.FindByClass(LOGIC_CLASS)[1]
		if not IsValid(self.logic) then
			self.logic = ents.Create(LOGIC_CLASS)
			self.logic:Spawn()
		end
	end
	return self.logic:Config()
end

Controller.rounds:SetMode(Round.Mode)
SetGlobal2Bool("ws_round_arena", true)

function Controller:Configure()
	self.rounds:ConfigureRound({ hostageRoundTime = roundTime:GetInt() })
end

-- Before the first pre-round reads it.
Controller:Configure()

-- The nav area whose centre is at pos (a hotfix's position), or nil.
local function AreaAt(pos)
	local area = navmesh.GetNearestNavArea(Vector(pos.x, pos.y, pos.z), false, Hotfixes.TOLERANCE * 2)
	if area and Hotfixes.Near(area:GetCenter(), pos) then return area end
	return nil
end

-- The map's curated navigation fixes (features.hostage.hotfixes): each link
-- through a wall is cut both ways, before the war plans a route.
function Controller:ApplyHotfixes()
	local map = game.GetMap()
	local cut = 0
	for _, fix in ipairs(Hotfixes.For(map)) do
		local a, b = AreaAt(fix.a), AreaAt(fix.b)
		if a and b then
			a:Disconnect(b)
			b:Disconnect(a)
			cut = cut + 1
		else
			print(string.format("hostage hotfix not applied on %s: no nav area at %s (%s)", map, a and "b" or "a", fix.why))
		end
	end
	if cut > 0 then print(string.format("hostage: %d nav link(s) cut on %s", cut, map)) end

	local removed = 0
	for _, fix in ipairs(Hotfixes.Areas(map)) do
		local area = AreaAt(fix.at)
		if area then
			area:Remove()
			removed = removed + 1
		else
			print(string.format("hostage hotfix not applied on %s: no nav area at the %s", map, fix.why))
		end
	end
	if removed > 0 then print(string.format("hostage: %d nav area(s) removed on %s", removed, map)) end
end

-- Applied once, as soon as the nav mesh is up: at load, at InitPostEntity, and
-- before the war reads the map (Snapshot), whichever comes first.
function Controller:EnsureHotfixes()
	if self.hotfixed or not navmesh.IsLoaded() then return end
	self.hotfixed = true
	self:ApplyHotfixes()
end

hook.Add("InitPostEntity", "ws_hostage_hotfixes", function() Controller:EnsureHotfixes() end)

local function Alive(ent)
	if not IsValid(ent) then return false end
	if ent:IsPlayer() then return ent:Alive() end
	return ent:Health() > 0
end

-- A hostage_entity binds as it is made and unbinds as it goes.
function Controller:Bind(observer)
	local id = "h" .. observer:EntIndex()
	observer.wsHostageId, observer.wsHome = id, observer:GetPos()
	self.bound[id] = observer
end

function Controller:Unbind(observer)
	if self.bound[observer.wsHostageId] == observer then self.bound[observer.wsHostageId] = nil end
end

-- The hostage an id's observer observes, while it is there, else nil.
function Controller:BodyOf(id)
	local observer = self.bound[id]
	return IsValid(observer) and observer:Body() or nil
end

-- A round's hostages are those bound as it begins. One is drawn to be armed
-- (the map's pistol setting), and is armed once its hostage has spawned and
-- if it can be (Arm).
function Controller:NewRound()
	local ids = {}
	self.known = {}
	for id, observer in pairs(self.bound) do
		if IsValid(observer) then
			ids[#ids + 1] = id
			self.known[id] = { home = observer.wsHome, pos = observer:GetPos() }
		end
	end
	table.sort(ids)
	self.round = #ids > 0 and Rescue.New(ids) or nil
	self.zone = nil
	self.won = false
	SafeRemoveEntity(self.pistolEnt)
	self.pistolEnt = nil
	self.pistol = self:Config().pistol and Pistol.Arm(ids, math.random) or nil
	self.armed = false
end

-- The pistol's first holder, given its pistol once its hostage has spawned;
-- a hostage that cannot carry one (a prop) leaves the round with none.
function Controller:ArmFirst()
	local pistol = self.pistol
	if self.armed or not pistol or not pistol:Holder() then return end
	local observer = self.bound[pistol:Holder()]
	if not (IsValid(observer) and observer:Spawned()) then return end
	self.armed = true
	local body = observer:Body()
	if body and body.Arm then
		body:Arm(Pistol.CLASS, Pistol.STATS)
	else
		self.pistol = nil
	end
end

-- The announcer's line of a hostage's change (features.hostage.announcer),
-- each team its own; an event no sooner than ANNOUNCE_GAP after its last (a
-- hostage let go and taken again at once is not announced over and over).
local ANNOUNCE_GAP = 4
local announced = {}

function Controller:Announce(before, after)
	local event = Announcer.Event(before, after)
	if not event then return end
	local now = CurTime()
	if now - (announced[event] or -math.huge) < ANNOUNCE_GAP then return end
	announced[event] = now
	for _, team in ipairs({ WS.TEAM_RED, BLUE }) do
		WS.BroadcastSoundFile(team, Announcer.Pick(event, team, math.random))
	end
end

-- A hostage its observer no longer sees alive: the round counts it killed,
-- and its pistol, if it held it, lies where it was last seen.
function Controller:Killed(id)
	local round = self.round
	local state = round:StateOf(id)
	if state == Rescue.HELD or state == Rescue.FOLLOWING then
		self.round = round:Kill(id)
		self:Announce(state, Rescue.KILLED)
	end
	local pistol = self.pistol
	if pistol and pistol:Holder() == id then
		local pos = self.known[id].pos
		self.pistol = pistol:Drop({ x = pos.x, y = pos.y, z = pos.z })
		local lying = ents.Create(Pistol.CLASS)
		lying:SetPos(pos + Vector(0, 0, 16))
		lying.wsHostagePistol = true
		lying:Spawn()
		self.pistolEnt = lying
	end
end

-- The armed hostage, once it has fired, fights for BLU: the war's bots see it
-- as they see BLU.
hook.Add("WSWarFighters", "ws_hostage_pistol", function(fighters)
	local pistol = Controller.pistol
	local holder = pistol and pistol:Holder() and Controller:BodyOf(pistol:Holder())
	if holder and holder.Revealed and holder:Revealed() and holder:Health() > 0 and not holder.rescued and fighters[BLUE] then
		table.insert(fighters[BLUE], holder)
	end
end)

-- The pistol lying is the hostages' alone: no player takes it up.
hook.Add("PlayerCanPickupWeapon", "ws_hostage_pistol", function(_, weapon)
	if weapon.wsHostagePistol then return false end
end)

-- While the pistol lies, the hostages still held or following rush for it,
-- and the nearest within reach is armed with it.
function Controller:RushForPistol()
	local pistol, round = self.pistol, self.round
	if not (pistol and pistol:Lying()) then return end
	local rushers, positions = {}, {}
	for _, id in ipairs(pistol:Rushers(round)) do
		local body = self:BodyOf(id)
		if body and body.Rush and body.Arm then
			local pos = body:GetPos()
			rushers[id], positions[id] = body, { x = pos.x, y = pos.y, z = pos.z }
		end
	end
	local claimant = pistol:Claimant(positions)
	if claimant then
		self.pistol = pistol:PickUp(claimant)
		SafeRemoveEntity(self.pistolEnt)
		self.pistolEnt = nil
		for _, ent in pairs(rushers) do ent:Rush(nil) end
		rushers[claimant]:Arm(Pistol.CLASS, Pistol.STATS)
		return
	end
	local lying = IsValid(self.pistolEnt) and self.pistolEnt:GetPos() or Vector(pistol:Lying().x, pistol:Lying().y, pistol:Lying().z)
	for _, ent in pairs(rushers) do ent:Rush(lying) end
end

local function BluSpawns()
	local spots = {}
	for _, ent in ipairs(ents.FindByClass("info_player_counterterrorist")) do spots[#spots + 1] = ent:GetPos() end
	if #spots == 0 then
		for _, ent in ipairs(WS.SpawnPoints(BLUE)) do spots[#spots + 1] = ent:GetPos() end
	end
	return spots
end

-- The rescue zone round BLU's spawns; nil while it has none.
-- The map's func_hostage_rescue brushes as world boxes, the one nearest
-- BLU's spawns (spots) first: the war leads hostages to it, home.
local function RescueBoxes(spots)
	local boxes = {}
	for _, ent in ipairs(ents.FindByClass("func_hostage_rescue")) do
		local mins, maxs = ent:WorldSpaceAABB()
		boxes[#boxes + 1] = { mins = mins, maxs = maxs, mid = (mins + maxs) / 2 }
	end
	if #spots > 0 then
		local home = Vector(0, 0, 0)
		for _, p in ipairs(spots) do home = home + p end
		home = home / #spots
		table.sort(boxes, function(a, b) return a.mid:DistToSqr(home) < b.mid:DistToSqr(home) end)
	end
	return boxes
end

-- The rescue zone, where the war leads the hostages: the map's own rescue
-- brushes, else round BLU's spawns; nil while it has neither. zoneFromBrushes:
-- whether it is the brushes', which then decide a rescue (InRescueZone).
function Controller:ZoneOf()
	if not self.zone then
		local spots = BluSpawns()
		local boxes = RescueBoxes(spots)
		self.zoneFromBrushes = #boxes > 0
		if #boxes > 0 then
			self.zone = Zone.Boxes(boxes)
		elseif #spots > 0 then
			self.zone = Zone.Of(spots, ZONE_MARGIN)
		end
	end
	return self.zone
end

-- Whether the hostage id's observer sees it in a rescue zone: a
-- func_hostage_rescue, or on a map without one the zone round BLU's spawns.
function Controller:InRescueZone(id, observer)
	if self.zoneFromBrushes then return observer:InRescueZone() end
	return Zone.Contains(self.zone, self.known[id].pos)
end

-- A living BLU soldier or player within reach of the hostage.
local function RescuerNear(hostage)
	for _, other in ipairs(ents.FindInSphere(hostage:GetPos(), Rescue.USE_RANGE)) do
		if other ~= hostage and other.Team and (other:IsPlayer() or other:IsNPC() or other:IsNextBot()) and Alive(other)
			and WS.TeamOf(other) == BLUE then
			return other
		end
	end
	return nil
end

-- What the AI war reads: each hostage of the round { id, home, pos, state,
-- rescuer }, in vectors, and the zone's centre.
function Controller:Snapshot()
	self:EnsureHotfixes()
	local list = {}
	if not self.round and next(self.bound) then self:NewRound() end
	local round = self.round
	if not round then return list, nil end
	for id, info in pairs(self.known) do
		list[#list + 1] = { id = id, home = info.home, pos = info.pos, state = round:StateOf(id), rescuer = round:RescuerOf(id) }
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	local zone = self:ZoneOf()
	return list, zone and Vector(zone.center.x, zone.center.y, zone.center.z)
end

-- Whether the round's hostages were replaced: none of them is bound and
-- others are (a cleanup made the map's hostages anew after the round began).
function Controller:Replaced()
	if not next(self.bound) then return false end
	for id in pairs(self.known) do
		if self.bound[id] then return false end
	end
	return true
end

-- One living hostage of the round (body, its observer's): taken by a BLU
-- soldier near, let go when its rescuer is no more, rescued in a rescue zone;
-- told whom to follow and what to say, when it can be.
function Controller:Observe(id, info, body, observer)
	info.pos = body:GetPos()
	local round = self.round
	local before = round:StateOf(id)
	if before == Rescue.HELD then
		local rescuer = RescuerNear(body)
		if rescuer then round = round:Follow(id, rescuer) end
	elseif not Alive(round:RescuerOf(id)) then
		round = round:Release(id)
	elseif self:InRescueZone(id, observer) then
		round = round:Rescue(id)
		if body.Rescued then body:Rescued() end
	end
	self.round = round
	local after = round:StateOf(id)
	if body.SetLeader then body:SetLeader(after == Rescue.FOLLOWING and round:RescuerOf(id) or nil) end
	self:Voice(body, before, after)
	self:Announce(before, after)
end

-- What the hostage HUD reads (features.hostage.hud, cl.lua): each hostage
-- of the round, in id order, its state and how far it has come toward the
-- rescue zone (ws_hostage_*).
function Controller:Publish()
	local zone = self.zone
	if not (self.round and zone) then return end
	local ids = {}
	for id in pairs(self.known) do ids[#ids + 1] = id end
	table.sort(ids)
	SetGlobal2Int("ws_hostage_count", #ids)
	for i, id in ipairs(ids) do
		local info = self.known[id]
		SetGlobal2String("ws_hostage_" .. i .. "_state", self.round:StateOf(id))
		SetGlobal2Float("ws_hostage_" .. i .. "_progress", Hud.Progress(info.pos, info.home, zone.center))
	end
end

-- The rules applied to the map, every THINK_INTERVAL while the round is on.
function Controller:Think()
	self:EnsureHotfixes()
	self:Configure()
	if not self.round or self:Replaced() then
		if next(self.bound) then self:NewRound() end
		return
	end
	self:ArmFirst()
	local zone = self:ZoneOf()
	if self.rounds:State() ~= State.STALEMATE or not zone then return end
	for id, info in pairs(self.known) do
		local observer = self.bound[id]
		local state = self.round:StateOf(id)
		local alive = state == Rescue.HELD or state == Rescue.FOLLOWING
		-- an observer gone (the map cleaned up) or not yet spawned its hostage says nothing
		if IsValid(observer) and observer:Spawned() and alive then
			if observer:Lives() then
				self:Observe(id, info, observer:Body(), observer)
			else
				self:Killed(id)
			end
		end
	end
	self:RushForPistol()
	self:Publish()
	if not self.won and self.round:Outcome() == Rescue.RESCUED_WIN then
		self.won = true
		self.rounds:SetWinningTeam(BLUE, Rounds.WINREASON.HOSTAGES_RESCUED, true, false, false)
	end
end

-- What a hostage says (features.hostage.voice): a line as its state changes
-- (taken, left behind, rescued), and now and then, no sooner than
-- FOLLOW_CHATTER after its last, while following or, held, calling for help
-- to a BLU soldier near.
local CHANGES = {
	[Rescue.HELD .. ">" .. Rescue.FOLLOWING] = Voice.TAKEN,
	[Rescue.FOLLOWING .. ">" .. Rescue.HELD] = Voice.LEFT,
	[Rescue.FOLLOWING .. ">" .. Rescue.RESCUED] = Voice.RESCUED,
}

local function BluNear(ent)
	for _, other in ipairs(ents.FindInSphere(ent:GetPos(), CALL_RANGE)) do
		if other.Team and (other:IsPlayer() or other:IsNextBot()) and Alive(other) and WS.TeamOf(other) == BLUE and ent:Visible(other) then
			return true
		end
	end
	return false
end

function Controller:Voice(ent, before, after)
	local now = CurTime()
	local event = CHANGES[before .. ">" .. after]
	if not event then
		if now - (ent.wsSpokeAt or -math.huge) < Voice.FOLLOW_CHATTER then return end
		if after == Rescue.FOLLOWING then
			event = Voice.FOLLOWING
		elseif after == Rescue.HELD and BluNear(ent) then
			event = Voice.CALLING
		else
			return
		end
	end
	if not Voice.MaySpeak(ent.wsSpokeAt, now) then return end
	ent.wsSpokeAt = now
	ent:EmitSound(Voice.Pick(event, math.random(#Voice.Lines(event))), VOICE_LEVEL)
end

-- Clients fetch the hostages' models (their Workshop addon) and the lines
-- they say; the server precaches the lines.
resource.AddWorkshop(MODEL_WORKSHOP)
for _, path in ipairs(Voice.All()) do
	resource.AddFile("sound/" .. path)
	util.PrecacheSound(path)
end
-- the announcer's lines are TF2's (mounted); the HUD's track is TF2
-- Classified's, in the addon (.devtools/bin/tf2c_assets.py)
for _, path in ipairs(Announcer.All()) do util.PrecacheSound(path) end
for _, name in ipairs({ "vip_track", "vip_home", "vip_car", "vip_civ", "vip_civ_bottom" }) do
	resource.AddFile("materials/hud/" .. name .. ".vmt")
end
SetGlobal2Bool("ws_hostage", true)

hook.Add("Think", THINK_HOOK, function()
	local now = CurTime()
	if now < Controller.nextThink or not WS.Active() then return end
	Controller.nextThink = now + THINK_INTERVAL
	Controller:Think()
end)

Controller:EnsureHotfixes()

Controller.rounds:AddRoundListener(Rounds.PHASE_ARENA_START, Rounds.LISTEN_LOGIC, function() Controller:NewRound() end)

return Controller
