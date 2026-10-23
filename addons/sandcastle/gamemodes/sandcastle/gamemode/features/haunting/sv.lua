-- The haunting feature's controller: CTFGameRules::BeginHaunting. It keeps
-- the ghosts about (m_ghostVector), asks features.haunting.ghost's Haunt who
-- lives on and where new ones rise, and spawns them (the ghost entity).
-- The holiday controller says whether the map may be haunted. Loaded by the
-- first haunting (the Wheel of Fate's Ghosts).
local Ghost = WS.require("features.haunting.ghost")

local GHOST_CLASS = "ghost"

local Controller = {
	npcs = WS.Feature("npc"),
	holiday = WS.Feature("holiday"),
	ghosts = {}, -- the ghost entities about, oldest first
}

-- The haunting's world: the living RED and BLU players, and the nav areas
-- outside the spawn rooms.
local World = {}

function World:RandomInt(lo, hi) return math.random(lo, hi) end
function World:RandomFloat(lo, hi) return math.Rand(lo, hi) end

function World:LivingPlayerOrigins()
	local origins = {}
	for _, ply in ipairs(player.GetAll()) do
		local t = ply:Team()
		if ply:Alive() and (t == WS.TEAM_RED or t == WS.TEAM_BLUE) then origins[#origins + 1] = ply:GetPos() end
	end
	return origins
end

function World:SpawnAreaCenters()
	local centers = {}
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		if Controller.npcs:SpawnRoomTeam(area) == WS.TEAM_UNASSIGNED then centers[#centers + 1] = area:GetCenter() end
	end
	return centers
end

function Controller:BeginHaunting(count, minDuration, maxDuration)
	if not self.holiday:HauntingAllowed() then return end
	local about = {}
	for _, ghost in ipairs(self.ghosts) do
		if IsValid(ghost) then about[#about + 1] = ghost end
	end
	local plan = Ghost.Haunt(World, about, count, minDuration, maxDuration)
	for _, extend in ipairs(plan.extend) do
		Ghost.SetLifetime(extend.ghost.npc:State(), extend.lifetime)
	end
	for _, rise in ipairs(plan.spawn) do
		about[#about + 1] = self.npcs:Spawn(GHOST_CLASS, { lifetime = rise.lifetime }, rise.pos, angle_zero)
	end
	self.ghosts = about
end

return Controller
