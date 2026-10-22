-- ws/sv_voices.lua loaded in a fake GMod: its hooks are kept and called as
-- the engine would, with fake players.
local T = dofile("tests/harness.lua")
local Teams = T.require("games.gameplay.teams")
local Voices = T.require("foundation.npc.voices")

local SOURCE = T.ROOT .. "ws/sv_voices.lua"
local UNVOICED_MODEL = "models/editor/playerstart.mdl"

-- war: whether the AI war is on; its faction for each fighting team.
local function Load(war)
	local hooks = {}
	local ws = {
		require = T.require,
		TEAM_RED = Teams.RED,
		TEAM_BLUE = Teams.BLUE,
		AiWarActive = function() return war end,
		Feature = function()
			return {
				FactionName = function(_, team)
					local name = ({ [Teams.RED] = "Combine", [Teams.BLUE] = "Resistance" })[team]
					return name or error("no faction fights for team " .. tostring(team))
				end,
			}
		end,
	}
	local env = setmetatable({
		WS = ws,
		hook = { Add = function(event, _, fn) hooks[event] = fn end },
		CurTime = function() return 100 end,
	}, { __index = _G })
	setfenv(assert(loadfile(SOURCE)), env)()
	return hooks
end

local function Player(team)
	local ply = { sounds = {} }
	function ply:GetModel() return UNVOICED_MODEL end
	function ply:Team() return team end
	function ply:GetMaxHealth() return 100 end
	function ply:GetPos() return { x = 0, y = 0, z = 0 } end
	function ply:EmitSound(path) self.sounds[#self.sounds + 1] = path end
	return ply
end

T.test("the fake player's model has no voice of its own", function()
	T.eq(Voices.For(UNVOICED_MODEL), nil, "unvoiced")
end)

T.test("in a war, a player on no team keeps the engine's voice", function()
	local hooks = Load(true)
	for _, team in ipairs({ Teams.UNASSIGNED, Teams.SPECTATOR }) do
		local ply = Player(team)
		hooks.PlayerHurt(ply, nil, 50, 10)
		T.eq(#ply.sounds, 0, "no cry, team " .. team)
		T.eq(hooks.PlayerDeathSound(ply), nil, "the engine's death sound, team " .. team)
	end
end)

T.test("in a war, a player on a fighting team cries in its faction's voice", function()
	local hooks = Load(true)
	local ply = Player(Teams.BLUE)
	hooks.PlayerHurt(ply, nil, 50, 10)
	T.eq(#ply.sounds, 1, "one cry")
end)

T.finish()
