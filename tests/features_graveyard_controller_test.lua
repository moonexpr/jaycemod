-- features/graveyard/sv.lua: a ghost stays one. A bot's outfit and loadout can
-- arrive after it becomes a ghost, so it is held to it, and it harms nobody.
local T = dofile("tests/harness.lua")
local Teams = gameplay.teams
local RED = Teams.RED

local function Controller()
	local hooks = {}
	local features = setmetatable({}, { __index = function() return function() end end })
	local env = setmetatable({
		WS = setmetatable({
			require = T.require,
			Feature = function() return features end,
			TEAM_RED = Teams.RED,
			TEAM_BLUE = Teams.BLUE,
			TEAM_UNASSIGNED = Teams.UNASSIGNED,
			InCondition = function() return false end,
		}, { __index = function() return function() end end }),
		GetConVar = function() return { GetString = function() return "1" end, SetBool = function() end, SetString = function() end } end,
		hook = { Add = function(event, _, fn) hooks[event] = fn end },
		team = { GetPlayers = function() return {} end },
		IsValid = function(ent) return ent ~= nil end,
	}, { __index = _G })
	local controller = setfenv(assert(loadfile(T.ROOT .. "features/graveyard/sv.lua")), env)()
	return controller, hooks
end

local function Ghost(model, weapons)
	local ghost = { model = model, stripped = false }
	function ghost:Team() return RED end
	function ghost:GetPos() return {} end
	function ghost:GetModel() return self.model end
	function ghost:SetModel(m) self.model = m end
	function ghost:GetWeapons() return weapons end
	function ghost:StripWeapons() self.stripped = true end
	return ghost
end

local GHOST_MODEL = "models/props_graveyard/ghost_healing_red.mdl"

T.test("a ghost given a body and guns again loses them", function()
	local controller = Controller()
	local ghost = Ghost("models/player/kleiner.mdl", { {} })
	controller.ghosts[ghost] = true
	controller:Heal()
	T.eq(ghost.model, GHOST_MODEL, "its ghost again")
	T.eq(ghost.stripped, true, "unarmed")
end)

T.test("a ghost as it should be is left alone", function()
	local controller = Controller()
	local ghost = Ghost(GHOST_MODEL, {})
	controller.ghosts[ghost] = true
	controller:Heal()
	T.eq(ghost.stripped, false, "nothing to strip")
end)

T.test("a ghost picks up no weapon; anyone else may", function()
	local controller, hooks = Controller()
	local ghost, living = Ghost(GHOST_MODEL, {}), Ghost(GHOST_MODEL, {})
	controller.ghosts[ghost] = true
	T.eq(hooks.PlayerCanPickupWeapon(ghost), false, "the ghost")
	T.eq(hooks.PlayerCanPickupWeapon(living), nil, "the living")
end)

local function Damage(attacker) return { GetAttacker = function() return attacker end } end

T.test("a ghost is not hurt and hurts nobody", function()
	local controller, hooks = Controller()
	local ghost, living, other = Ghost(GHOST_MODEL, {}), Ghost(GHOST_MODEL, {}), Ghost(GHOST_MODEL, {})
	controller.ghosts[ghost] = true
	T.eq(hooks.EntityTakeDamage(ghost, Damage(living)), true, "not hurt")
	T.eq(hooks.EntityTakeDamage(living, Damage(ghost)), true, "hurts nobody")
	T.eq(hooks.EntityTakeDamage(living, Damage(other)), nil, "the living fight on")
end)

T.finish()
