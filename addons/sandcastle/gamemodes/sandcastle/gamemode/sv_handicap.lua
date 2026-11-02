-- The Help Other Team handicap (games.gameplay.handicap; decision Q6,
-- docs/spawn-menu-design.md): a passed support vote grants it to a team
-- (ws/sv_votes.lua) for the rest of the game. The helped team's respawn
-- waves shorten (the rounds controller's SetWaveScale), its soldiers hold
-- the handicap's capabilities (War:SetCapabilities; no behaviour until the
-- AI Commander offers the ambush job), and clients read the team from
-- Global2 ws_handicap_team. A scramble and a new game clear it, and it
-- lasts no longer than the map, as the Lua state does.
--   WS.Handicap() -> the current value; WS.GrantHandicap(team);
--   WS.ClearHandicap(). WSHandicapChanged(handicap) tells the rest.
local Handicap = gameplay.handicap

local GAME_TEAMS = { WS.TEAM_RED, WS.TEAM_BLUE }
local HOOK = "ws_handicap"

local current = Handicap.New()

local function Apply()
	if WS.FeatureLoaded("rounds") then
		for _, t in ipairs(GAME_TEAMS) do WS.Feature("rounds"):SetWaveScale(t, current:WaveScale(t)) end
	end
	if WS.FeatureLoaded("aiwar") and WS.Feature("aiwar").war then
		local war = WS.Feature("aiwar").war
		for _, t in ipairs(GAME_TEAMS) do war:SetCapabilities(t, current:Capabilities(t)) end
	end
	SetGlobal2Int("ws_handicap_team", current:Supported())
	hook.Run("WSHandicapChanged", current)
end

function WS.Handicap()
	return current
end

-- A refusal (games.gameplay.handicap's ALREADY_SUPPORTED) when that team is helped already.
function WS.GrantHandicap(t)
	current = current:Grant(t)
	Apply()
end

function WS.ClearHandicap()
	if current:Supported() == WS.TEAM_UNASSIGNED then return end
	current = Handicap.New()
	Apply()
end

hook.Add("WSTeamsScrambled", HOOK, WS.ClearHandicap)
hook.Add("WSGameBegin", HOOK, WS.ClearHandicap)
