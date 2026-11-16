-- game_ctf and game_payload: their rules go by the round alone. A game never
-- asks whether the gamemode is in sandbox or gameplay mode.
local T = dofile ("tests/harness.lua")

ROUND_WAITING, ROUND_PREPARE, ROUND_ACTIVE, ROUND_OVER = 0, 1, 2, 3
SERVER = true
FCVAR_NOTIFY, FCVAR_REPLICATED = 0, 0
CreateConVar = function () return { GetInt = function () return 3 end } end
local state
GAMEMODE =
{
	GetRoundState = function () return state end,
	IsGameplay = function () error ("a game asked which mode the gamemode is in", 2) end
}
hook = { Run = function () end }
local G = "addons/sandcastle/gamemodes/sandcastle/gamemode/gamerules/"
dofile (G .. "game_ctf.lua")
dofile (G .. "game_payload.lua")
local Ctf, Payload = game_manager.GetClass ("game_ctf"), game_manager.GetClass ("game_payload")

local ROUNDS =
{
	{ ROUND_WAITING, true, "no round on" },
	{ ROUND_PREPARE, false, "preparing" },
	{ ROUND_ACTIVE, true, "a round on" },
	{ ROUND_OVER, false, "over" }
}

T.test ("flags may be captured but while a round is being prepared or is over", function ()
	for _, case in ipairs (ROUNDS) do
		state = case [1]
		T.eq (Ctf:GetRules ().FlagMayBeCapped, case [2], case [3])
	end
end)

T.test ("carts run but while a round is being prepared or is over", function ()
	for _, case in ipairs (ROUNDS) do
		state = case [1]
		T.eq (Payload:GetRules ().CartRunning, case [2], case [3])
	end
end)

T.finish ()
