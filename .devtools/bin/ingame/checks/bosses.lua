-- Halloween bosses (docs/pass3-halloween.md §11 "Templates", P1): each
-- boss the map spawns from a point_template comes out on the template's
-- ForceSpawn, binds to the npc controller with an npc state, and, killed,
-- goes cleanly: the boss is removed, no prop_ragdoll is left on the server,
-- and nothing it brought outlives it. One boss at a time.
-- args: { bosses = { { template = name, class = boss class }... } }
local SPAWN_TIMEOUT = 15
local ALIVE_SECONDS = 3 -- how long the boss acts before it is killed
local KILL_DAMAGE = 1000000
local KILL_TIMEOUT = 5
local REMOVE_TIMEOUT = 30
local LEFTOVER_TIMEOUT = 30 -- for what it brought (a loot vortex) to go
-- Not the boss's: players, what bots carry, and what dead bots drop.
local IGNORED = {
	player = true,
	tf_ammo_pack = true,
}

local function Snapshot()
	local set = {}
	for _, ent in ipairs(ents.GetAll()) do set[ent] = true end
	return set
end

local function NewEntities(before)
	local list = {}
	for _, ent in ipairs(ents.GetAll()) do
		local owner = ent:GetOwner()
		if not before[ent] and not IGNORED[ent:GetClass()] and not ent:IsWorld() and not ent:IsWeapon()
			and not (IsValid(owner) and owner:IsPlayer()) then
			list[#list + 1] = ent
		end
	end
	return list
end

local function Classes(list)
	local names = {}
	for _, ent in ipairs(list) do names[#names + 1] = IsValid(ent) and ent:GetClass() or "?" end
	table.sort(names)
	return table.concat(names, ", ")
end

-- Kills the boss: world damage first, then a bot's, as some bosses ignore
-- damage that is not a player's.
local function Kill(t, boss)
	local world = game.GetWorld()
	boss:TakeDamage(KILL_DAMAGE, world, world)
	if t:WaitFor(KILL_TIMEOUT, function() return not IsValid(boss) or boss:Health() <= 0 end) then return "world" end
	local bot = player.GetBots()[1]
	if IsValid(bot) and IsValid(boss) then
		boss:TakeDamage(KILL_DAMAGE, bot, bot)
		if t:WaitFor(KILL_TIMEOUT, function() return not IsValid(boss) or boss:Health() <= 0 end) then return "a bot" end
	end
end

local function RunBoss(t, npc, spec)
	local label = spec.class .. " from " .. spec.template
	local template = ents.FindByName(spec.template)[1]
	if not t:Check(label .. ": the point_template exists", IsValid(template), tostring(template)) then return end
	local before = Snapshot()
	local ragdollsBefore = #ents.FindByClass("prop_ragdoll")
	template:Fire("ForceSpawn")
	local boss = t:WaitFor(SPAWN_TIMEOUT, function()
		for _, ent in ipairs(ents.FindByClass(spec.class)) do
			if not before[ent] then return ent end
		end
	end)
	if not t:Check(label .. ": ForceSpawn spawns the boss", boss ~= nil, "") then return end
	local state = npc and npc.npcs[boss]
	t:Check(label .. ": bound to the npc controller", state ~= nil, tostring(boss))
	t:Check(label .. ": has its npc state", state ~= nil and state:State() ~= nil, "")
	t:Wait(ALIVE_SECONDS)
	local alive = IsValid(boss)
	t:Check(label .. ": still there after " .. ALIVE_SECONDS .. " s", alive, "")
	if not alive then return end
	local described = state and state:Describe()
	t:Info(spec.template .. "_describe", described and tostring(described) or "")
	t:Info(spec.template .. "_health", boss:Health())

	local killedBy = Kill(t, boss)
	t:Check(label .. ": killed", killedBy ~= nil, killedBy and ("by " .. killedBy) or
		("health " .. (IsValid(boss) and boss:Health() or "gone")))
	local removed, took = t:WaitFor(REMOVE_TIMEOUT, function() return not IsValid(boss) end)
	t:Check(label .. ": removed after its death", removed ~= nil, string.format("%.1f s", took))
	if not removed then
		boss:Remove()
	end
	local clean, cleanTook = t:WaitFor(LEFTOVER_TIMEOUT, function() return #NewEntities(before) == 0 end)
	t:Check(label .. ": nothing it brought is left", clean ~= nil,
		string.format("after %.0f s: %s", cleanTook, Classes(NewEntities(before))))
	for _, ent in ipairs(NewEntities(before)) do
		if IsValid(ent) then ent:Remove() end
	end
	local ragdolls = #ents.FindByClass("prop_ragdoll") - ragdollsBefore
	t:Check(label .. ": no server prop_ragdoll", ragdolls == 0, ragdolls .. " new")
end

return function(t)
	local npc = t:Feature("npc")
	for _, spec in ipairs(t.args.bosses or {}) do RunBoss(t, npc or WS.Feature("npc"), spec) end
	t:Info("npc_feature_loaded_before", npc ~= nil)
end
