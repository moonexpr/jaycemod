local T = dofile("tests/harness.lua")
local ROOT = T.ROOT

local function Load()
	local definition
	local ws = { TEAM_UNASSIGNED = 0, TEAM_SPECTATOR = 1 }
	local env = setmetatable({
		WS = ws,
		TEAM_UNASSIGNED = 0,
		TEAM_SPECTATOR = 1,
		OBS_MODE_FIXED = 1,
		OBS_MODE_ROAMING = 5,
		DMG_REMOVENORAGDOLL = 8,
		bit = { bor = function(a, b) return a + b end },
		DEFINE_BASECLASS = function() end,
		player_manager = {
			RegisterClass = function(_, class) definition = class end,
			SetPlayerClass = function(ply, class) ply.playerClass = class end,
			RunClass = function(ply, method, ...)
				return definition[method]({ Player = ply }, ...)
			end,
		},
	}, { __index = _G })
	setfenv(assert(loadfile(ROOT .. "player_class/player_spectator.lua")), env)()

	local ply = { wsTeam = 0, team = 0 }
	function ply:Team() return self.team end
	function ply:SetTeam(team) self.team = team end
	function ply:StripWeapons() self.stripped = true end
	function ply:RemoveAllAmmo() self.ammoRemoved = true end
	function ply:Spectate(mode) self.observerMode = mode end
	return ws.Spectator, ply
end

T.test("spawn selects the right class and native spectator spawn behavior", function()
	local spectator, ply = Load()
	T.eq(spectator.SelectSpawnClass(ply, true, false), true, "unassigned player observes")
	T.eq(ply.playerClass, "player_spectator", "selects spectator class")
	spectator.SpawnAsSpectator(ply)
	T.eq(ply.observerMode, 1, "unassigned player uses fixed mode")
	T.eq(ply.stripped, true, "spectator spawn strips weapons")

	ply.team = 2
	T.eq(spectator.SelectSpawnClass(ply, true, true), true, "sandbox class selection preserves observer state")
	T.eq(ply.playerClass, "player_sandcastle", "sandbox class takes precedence")
	spectator.SpawnAsSpectator(ply)
	T.eq(ply.playerClass, "player_sandcastle", "observer spawn preserves the selected Sandbox class")
	T.eq(ply.observerMode, 5, "a teamed observer uses roaming mode")
	T.eq(spectator.SelectSpawnClass(ply, false, false), false, "sandbox play mode is not team observation")
	T.eq(ply.playerClass, "player_combatant", "gameplay class selection")
end)

T.test("team observer transitions use the class's native mode behavior", function()
	local spectator, ply = Load()
	ply.team = 2
	spectator.Enter(ply, 1)
	T.eq(ply.playerClass, "player_spectator", "observer transition selects class")
	T.eq(ply.observerMode, 5, "spectator team uses roaming mode")
	T.eq(ply.stripped, true, "observer transition strips weapons")

	spectator.Enter(ply, 0)
	T.eq(ply.observerMode, 1, "unassigned team uses fixed mode")
end)

T.test("death selects spectator class and suppresses ragdoll before base death", function()
	local spectator, ply = Load()
	local damage = { type = 2 }
	function damage:GetDamageType() return self.type end
	function damage:SetDamageType(value) self.type = value end

	spectator.DoPlayerDeath(ply, damage)
	T.eq(ply.playerClass, "player_spectator", "death selects spectator class")
	T.eq(damage.type, 10, "death suppresses the ragdoll")
end)

T.finish()
