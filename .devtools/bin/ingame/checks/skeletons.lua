-- Skeletons (docs/pass3-halloween.md §11, P0): the map's tf_zombie_spawners,
-- enabled as capturing point 1 would, spawn tf_zombie NPCs that bind to the
-- npc controller; none is left unbound; killed, they leave no server
-- prop_ragdoll (ragdolls are the clients'), and every NPC is gone or bound.
local SPAWN_TIMEOUT = 30
local SETTLE = 5 -- seconds of skeletons living before they are counted again
local REMOVE_TIMEOUT = 15
local KILL_DAMAGE = 100000

local function Unbound(npc)
	local list = {}
	for _, ent in ipairs(ents.GetAll()) do
		if ent.Variant and ent:IsNextBot() and not npc.npcs[ent] then list[#list + 1] = tostring(ent) end
	end
	return list
end

return function(t)
	local spawners = ents.FindByClass("tf_zombie_spawner")
	local names = {}
	for _, s in ipairs(spawners) do names[#names + 1] = s:GetName() end
	t:Info("spawners", names)
	t:Info("navmesh_areas", navmesh.IsLoaded() and navmesh.GetNavAreaCount() or 0)
	t:Check("the map has tf_zombie_spawners", #spawners > 0, #spawners .. " spawners")
	if #spawners == 0 then return end

	local ragdollsBefore = #ents.FindByClass("prop_ragdoll")
	for _, s in ipairs(spawners) do s:Fire("Enable") end
	local spawned, took = t:WaitFor(SPAWN_TIMEOUT, function() return #ents.FindByClass("tf_zombie") > 0 end)
	t:Check("enabled spawners spawn tf_zombie", spawned ~= nil,
		string.format("%d after %.1f s", #ents.FindByClass("tf_zombie"), took))
	if not spawned then return end
	t:Wait(SETTLE)

	local npc = t:Feature("npc")
	t:Check("the npc feature is loaded", npc ~= nil, "")
	if not npc then return end
	local zombies = ents.FindByClass("tf_zombie")
	local bound = 0
	for _, z in ipairs(zombies) do
		if npc.npcs[z] then bound = bound + 1 end
	end
	t:Info("skeletons", #zombies)
	t:Check("every tf_zombie is bound to the npc controller", bound == #zombies, bound .. " of " .. #zombies)
	local unbound = Unbound(npc)
	t:Check("no unbound NPCs", #unbound == 0, table.concat(unbound, ", "))

	for _, s in ipairs(spawners) do s:Fire("Disable") end
	local world = game.GetWorld()
	for _, z in ipairs(ents.FindByClass("tf_zombie")) do
		if IsValid(z) then z:TakeDamage(KILL_DAMAGE, world, world) end
	end
	local gone, goneAfter = t:WaitFor(REMOVE_TIMEOUT, function() return #ents.FindByClass("tf_zombie") == 0 end)
	t:Info("skeletons_left_after_kill", #ents.FindByClass("tf_zombie"))
	t:Check("killed skeletons are removed", gone ~= nil,
		string.format("%d left after %.1f s", #ents.FindByClass("tf_zombie"), goneAfter))
	local ragdolls = #ents.FindByClass("prop_ragdoll") - ragdollsBefore
	t:Check("no server prop_ragdoll after the NPC deaths", ragdolls == 0, ragdolls .. " new")
	unbound = Unbound(npc)
	t:Check("no unbound NPCs after the deaths", #unbound == 0, table.concat(unbound, ", "))
end
