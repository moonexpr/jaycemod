-- A soldier (ws/sh_war_soldier.lua) is lag compensated: a player's shot,
-- which the server traces with every lag-compensated entity moved back to
-- where the shooter saw it, finds the soldier where the shooter aimed.
-- GMod compensates only players unless an entity asks (SetLagCompensated),
-- and DrGBase never asks for its NextBots.
local T = dofile("tests/harness.lua")

-- The engine's side of one entity: the lag compensation flag it keeps.
local function Body(ENT)
	local body = setmetatable({ lagCompensated = false }, { __index = ENT })
	function body:SetLagCompensated(on) self.lagCompensated = on end
	function body:IsLagCompensated() return self.lagCompensated end
	function body:GetModel() return "models/combine_soldier.mdl" end
	return body
end

local function SoldierClass()
	local ENT = {}
	local env = setmetatable({
		SERVER = true,
		CLIENT = false,
		FindMetaTable = function() return {} end,
		WS = { require = function(name) return T.require(name) end },
	}, { __index = _G })
	setfenv(assert(loadfile(T.ROOT .. "ws/sh_war_soldier.lua")), env)()
	env.WS.WarSoldier(ENT)
	return ENT
end

T.test("a soldier is lag compensated once DrGBase has initialized it", function()
	local soldier = Body(SoldierClass())
	T.eq(soldier:IsLagCompensated(), false, "not before")
	soldier:CustomInitialize()
	T.eq(soldier:IsLagCompensated(), true, "lag compensated")
end)

T.finish()
