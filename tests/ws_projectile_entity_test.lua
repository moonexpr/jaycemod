-- entities/ws_projectile.lua: a projectile is given its Config before Spawn.
-- Another addon's weapon spawning one by class name gives none: it is refused
-- once and removed, not left to fail every tick.
local T = dofile("tests/harness.lua")

local function Projectile()
	local ENT = {}
	local env = setmetatable({ ENT = ENT, AddCSLuaFile = function() end, CLIENT = false }, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/entities/entities/ws_projectile.lua")), env)()
	ENT.Remove = function(self) self.removed = true end
	ENT.GetClass = function() return "tf_projectile_pipe" end
	return ENT
end

T.test("a configured projectile reads its config", function()
	local ent, config = Projectile(), {}
	ent:Configure(config)
	T.eq(ent:Config(), config, "as given")
	T.eq(ent.removed, nil, "kept")
end)

T.test("a projectile spawned with no config is removed and refused by name", function()
	local ent = Projectile()
	local ok, err = pcall(ent.Config, ent)
	T.eq(ok, false, "refused")
	T.eq(tostring(err):find("tf_projectile_pipe", 1, true) ~= nil, true, "names the class")
	T.eq(ent.removed, true, "removed")
end)

-- The TF2 Weapon Pack ships these two classes; its weapons spawn them by name.
T.test("Sandcastle's rocket and pipe leave TF2's class names to the weapon pack", function()
	local dir = "addons/sandcastle/gamemodes/sandcastle/entities/entities/"
	for _, name in ipairs({ "pipe", "rocket" }) do
		T.eq(io.open(dir .. "tf_projectile_" .. name .. ".lua"), nil, "no tf_projectile_" .. name)
		T.eq(io.open(dir .. "ent_projectile_" .. name .. ".lua") ~= nil, true, "ent_projectile_" .. name)
	end
end)

T.finish()
