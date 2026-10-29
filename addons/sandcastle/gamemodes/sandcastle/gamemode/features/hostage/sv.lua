-- The hostage feature's controller. It puts the round in the hostage mode
-- (features.hostage.round), owns the round's rules (features.hostage.model)
-- and applies them to the map's hostage_entity hostages: a held hostage
-- within USE_RANGE of a living BLU soldier or player follows them; one whose
-- rescuer dies or leaves is let go; one led into the rescue zone round BLU's
-- spawns (features.hostage.zone) is rescued; and once none is left
-- unresolved with half or more rescued, BLU wins (HOSTAGES_RESCUED). RED
-- wins by killing BLU, which the rounds controller decides as it does in
-- arena.
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
local State = WS.require("games.gameplay.rounds.state")
local Rounds = gameplay.rounds

local THINK_INTERVAL = 0.1
local THINK_HOOK = "ws_hostage"
-- The zone reaches this far past BLU's farthest spawn.
local ZONE_MARGIN = 150

local BLUE = WS.TEAM_BLUE

-- The round's timer: when it runs out RED has kept the hostages and wins
-- (features.hostage.round).
local roundTime = CreateConVar("mp_hostage_roundtime", "240", { FCVAR_NOTIFY, FCVAR_REPLICATED },
	"Length of a hostage round in seconds, shown as its timer; when it runs out the hostages were not rescued and RED wins. 0: untimed.",
	0, 3600)

local Controller = {
	rounds = WS.Feature("rounds"),
	bound = {}, -- id -> its entity, while it lives
	known = {}, -- id -> { home, pos } for each hostage of the round
	round = nil, -- features.hostage.model's round
	zone = nil,
	won = false,
	nextThink = 0,
}

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

	-- the tops of props the mesh calls walkable (dumpsters) go
	local props = Hotfixes.Props(map)
	local tops = {}
	if #props > 0 then
		for _, area in ipairs(navmesh.GetAllNavAreas()) do
			local center = area:GetCenter()
			for _, prop in ipairs(props) do
				if Hotfixes.OnTop(prop, center) then
					tops[#tops + 1] = area
					break
				end
			end
		end
	end
	for _, area in ipairs(tops) do area:Remove() end
	if #tops > 0 then print(string.format("hostage: %d nav area(s) on top of props removed on %s", #tops, map)) end
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
function Controller:Bind(ent)
	local id = "h" .. ent:EntIndex()
	ent.wsHostageId, ent.wsHome = id, ent:GetPos()
	self.bound[id] = ent
end

function Controller:Unbind(ent)
	if self.bound[ent.wsHostageId] == ent then self.bound[ent.wsHostageId] = nil end
end

-- A round's hostages are those bound as it begins.
function Controller:NewRound()
	local ids = {}
	self.known = {}
	for id, ent in pairs(self.bound) do
		if IsValid(ent) then
			ids[#ids + 1] = id
			self.known[id] = { home = ent.wsHome, pos = ent:GetPos() }
		end
	end
	table.sort(ids)
	self.round = #ids > 0 and Rescue.New(ids) or nil
	self.zone = nil
	self.won = false
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
function Controller:ZoneOf()
	if not self.zone then
		local spots = BluSpawns()
		if #spots == 0 then return nil end
		self.zone = Zone.Of(spots, ZONE_MARGIN)
	end
	return self.zone
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

-- The rules applied to the map, every THINK_INTERVAL while the round is on.
function Controller:Think()
	self:EnsureHotfixes()
	self:Configure()
	if not self.round then
		if next(self.bound) then self:NewRound() end
		return
	end
	local zone = self:ZoneOf()
	if self.rounds:State() ~= State.STALEMATE or not zone then return end
	local round = self.round
	for id, info in pairs(self.known) do
		local ent = self.bound[id]
		if IsValid(ent) then
			info.pos = ent:GetPos()
			local state = round:StateOf(id)
			if state == Rescue.HELD then
				local rescuer = RescuerNear(ent)
				if rescuer then round = round:Follow(id, rescuer) end
			elseif state == Rescue.FOLLOWING then
				if not Alive(round:RescuerOf(id)) then
					round = round:Release(id)
				elseif Zone.Contains(zone, info.pos) then
					round = round:Rescue(id)
					ent:Rescued()
				end
			end
			local leader = round:StateOf(id) == Rescue.FOLLOWING and round:RescuerOf(id) or nil
			ent:SetLeader(leader)
		end
	end
	self.round = round
	if not self.won and round:Outcome() == Rescue.RESCUED_WIN then
		self.won = true
		self.rounds:SetWinningTeam(BLUE, Rounds.WINREASON.HOSTAGES_RESCUED, true, false, false)
	end
end

hook.Add("Think", THINK_HOOK, function()
	local now = CurTime()
	if now < Controller.nextThink or not WS.Active() then return end
	Controller.nextThink = now + THINK_INTERVAL
	Controller:Think()
end)

Controller:EnsureHotfixes()

Controller.rounds:AddRoundListener(Rounds.PHASE_ARENA_START, Rounds.LISTEN_LOGIC, function() Controller:NewRound() end)

return Controller
