-- TF2's team numbers, and its team rules as pure functions: joining,
-- auto-assignment, balance, and the team tests of the spawn-room entities.
local ipairs, math, pairs, string, table = ipairs, math, pairs, string, table
local STATE = require("foundation.rounds.state")
module(...)

-- The team numbers of shareddefs.h, which map keyvalues (TeamNum) use too.
INVALID = -1 -- TEAM_INVALID
UNASSIGNED = 0 -- TEAM_UNASSIGNED
SPECTATOR = 1 -- TEAM_SPECTATOR
RED = 2 -- TF_TEAM_RED
BLUE = 3 -- TF_TEAM_BLUE
HALLOWEEN = 5 -- TF_TEAM_HALLOWEEN: the Halloween bosses and skeletons
FIRST_GAME_TEAM = RED -- FIRST_GAME_TEAM: RED and BLU are the teams that play
AUTO = "auto"

-- HandleCommand_JoinTeam: g_aTeamNames, compared case-insensitively. A name
-- it does not know leaves the command's initial choice, RED. "blu" is
-- Sandcastle's alias, since that is how TF2 spells the team everywhere else.
local JOIN_NAMES = {
	unassigned = UNASSIGNED,
	spectator = SPECTATOR,
	spectate = SPECTATOR,
	spectatearena = SPECTATOR,
	red = RED,
	blue = BLUE,
	blu = BLUE,
	auto = AUTO,
}

function ParseJoinTeam(name)
	local team = JOIN_NAMES[string.lower(name)]
	if team == nil then return RED end
	return team
end

-- CTFPlayer::GetAutoTeam: the team with fewer players. On an even split TF2
-- gives attackers the player on escort (payload) maps; Sandcastle does so on
-- every map, so a lone player lands on BLU and can push the cart.
function AutoTeam(red, blue)
	if blue < red then return BLUE end
	if red < blue then return RED end
	return BLUE
end

-- counts[t] is the number of players on each game team t now, the mover
-- included; the game teams are exactly its keys.

local function GameTeams(counts)
	local teams = {}
	for t in pairs(counts) do teams[#teams + 1] = t end
	table.sort(teams)
	return teams
end

-- CTeamplayRoundBasedRules::WouldChangeUnbalanceTeams.
function WouldUnbalance(counts, newTeam, currentTeam, limit)
	if newTeam == currentTeam or limit <= 0 or counts[newTeam] == nil then return false end
	local joined = counts[newTeam] + 1
	for t, n in pairs(counts) do
		if t ~= newTeam then
			if t == currentTeam then n = math.max(0, n - 1) end
			if joined - n > limit then return true end
		end
	end
	return false
end

-- CTeamplayRoundBasedRules::AreTeamsUnbalanced: heavy and light team, or nil.
function Unbalanced(counts, limit)
	if limit <= 0 then return nil end
	local heavy, light
	for _, t in ipairs(GameTeams(counts)) do
		if not heavy or counts[t] > counts[heavy] then heavy = t end
		if not light or counts[t] < counts[light] then light = t end
	end
	if counts[heavy] - counts[light] > limit then return heavy, light end
	return nil
end

function SwitchesRequired(heavyCount, lightCount)
	return math.floor((heavyCount - lightCount) / 2)
end

-- CBaseMultiplayerPlayer::CalculateTeamBalanceScore: higher is switched
-- first, so the newest players move and anyone moved in the last 5 minutes
-- is spared.
function BalanceScore(now, connectedAt, lastForcedAt)
	local score = -math.floor(now - connectedAt)
	if lastForcedAt and now - lastForcedAt < 300 then score = score - 10000 end
	return score
end

-- The selection loop of CTeamplayRoundBasedRules::BalanceTeams: the best
-- `required` + 2 candidates by score; mid-round only dead ones may move.
-- candidates: { id, score, alive }. Returns the ids to switch.
function PickBalanceSwitches(candidates, required, requireDead)
	local sorted = {}
	for i, c in ipairs(candidates) do sorted[i] = c end
	table.sort(sorted, function(a, b) return a.score > b.score end)
	local picked = {}
	for i = 1, math.min(#sorted, required + 2) do
		if #picked >= required then break end
		local c = sorted[i]
		if not requireDead or not c.alive then picked[#picked + 1] = c.id end
	end
	return picked
end

-- CFilterTFTeam::PassesFilterImpl, then CBaseFilter::PassesFilter's
-- negation: during team win the winners pass every team filter (the impl
-- answers "no" to a negated filter, which the negation turns into a pass).
function FilterPasses(filterTeam, negated, entTeam, state, winner)
	local impl
	if state == STATE.TEAM_WIN and entTeam == winner then
		impl = not negated
	else
		impl = entTeam == filterTeam
	end
	if negated then return not impl end
	return impl
end

-- TF2's humiliation: while the winners celebrate a round (TEAM_WIN) or the
-- match (GAME_OVER), a player or soldier of the other playing team cannot
-- attack. winner: the round's or the match's, UNASSIGNED for none.
function Humiliated(state, winner, team)
	if state ~= STATE.TEAM_WIN and state ~= STATE.GAME_OVER then return false end
	return winner >= FIRST_GAME_TEAM and team >= FIRST_GAME_TEAM and team ~= winner
end

-- CFuncRespawnRoomVisualizer::ShouldCollide: a RED door stops players whose
-- movement mask holds CONTENTS_REDTEAM, which is BLU players, and the other
-- way round; any other non-zero team stops every player.
function VisualizerBlocks(vizTeam, playerTeam)
	if vizTeam == UNASSIGNED then return false end
	if vizTeam == RED then return playerTeam == BLUE end
	if vizTeam == BLUE then return playerTeam == RED end
	return true
end

-- CFuncRespawnRoomVisualizer::ShouldTransmit: drawn for players of the
-- other playing team while its room is active and nobody has won.
function VisualizerVisible(vizTeam, roomActive, teamWin, viewerTeam)
	if not roomActive or teamWin or vizTeam == UNASSIGNED then return false end
	return viewerTeam >= FIRST_GAME_TEAM and viewerTeam ~= vizTeam
end

-- CRegenerateZone::Touch: a zone with a team serves only that team; during
-- team win every zone serves the winners and none the losers; nothing
-- during a stalemate.
function RegenerateAllowed(zoneTeam, playerTeam, state, winner)
	if state == STATE.TEAM_WIN then
		if winner ~= playerTeam then return false end
	elseif zoneTeam ~= UNASSIGNED and playerTeam ~= zoneTeam then
		return false
	end
	return state ~= STATE.STALEMATE
end

-- teamplay_broadcast_audio (ClientModeShared::FireGameEvent): whether the
-- local player, on localTeam, hears a sound broadcast to soundTeam. Ours
-- broadcasts to everyone as UNASSIGNED (TF2 uses 255); others inverts it,
-- for the lines every player not on the team hears as their own.
function HearsBroadcast(soundTeam, others, localTeam)
	if others then return localTeam ~= soundTeam end
	return soundTeam == UNASSIGNED or soundTeam == localTeam
end

-- The team menu (CTFTeamMenu) --------------------------------------------------

-- CTFTeamMenu::ShowPanel: nobody changes teams once the game is over, nor
-- does a player of a losing team while the winners celebrate.
function TeamMenuAllowed(state, currentTeam, winner)
	if state == STATE.GAME_OVER then return false end
	return not (state == STATE.TEAM_WIN and currentTeam >= FIRST_GAME_TEAM and currentTeam ~= winner)
end

-- What the client does with its team menu, which it opens itself: TF2's
-- fallback state is having no team, and an unassigned player sees the menu
-- (as a fresh join does), whoever unassigned them.
MENU_STAY, MENU_OPEN, MENU_CLOSE = 0, 1, 2

-- view: rounds (the map has rounds), ready (the client has loaded), team
-- (the local player's now), openedOn (its team when the open menu opened,
-- nil while closed), state and winner (the round's). The open menu closes
-- once the team changes to a real one; the closed menu opens for the
-- unassigned while the menu is allowed.
function TeamMenuReaction(view)
	if view.openedOn ~= nil then
		if view.team ~= view.openedOn and view.team ~= UNASSIGNED then return MENU_CLOSE end
		return MENU_STAY
	end
	if view.rounds and view.ready and view.team == UNASSIGNED and TeamMenuAllowed(view.state, view.team, view.winner) then
		return MENU_OPEN
	end
	return MENU_STAY
end

local TEAM_FULL = "Team is full"

local function Choice(kind, spec, currentTeam)
	return {
		kind = kind,
		index = spec.index,
		label = spec.name,
		color = spec.color,
		count = spec.count,
		command = spec.command,
		enabled = true,
		current = spec.index ~= nil and spec.index == currentTeam,
	}
end

-- CTFTeamMenu::OnTick: a game team is disabled while it is the heavy team
-- or joining it would unbalance the teams.
local function TeamChoice(spec, counts, currentTeam, limit)
	local c = Choice("team", spec, currentTeam)
	local heavy = Unbalanced(counts, limit)
	if heavy == spec.index or WouldUnbalance(counts, spec.index, currentTeam, limit) then
		c.enabled, c.reason = false, TEAM_FULL
	end
	return c
end

-- The menu as data, for any game's teams. teams: the joinable teams in
-- screen order, each { index, name, color, count, command }. extras.auto
-- { name, command } and extras.spectate { index, name, command, count } are
-- offered when present. Hotkeys number auto, spectate, then the teams
-- (Teammenu.res: &1 random, &2 spectate, &3 BLU, &4 RED). Cancel only once
-- the player has a team (CTFTeamMenu::Update).
function TeamMenu(teams, currentTeam, limit, extras)
	local counts = {}
	for _, t in ipairs(teams) do counts[t.index] = t.count end
	local menu = { teams = {}, choices = {}, cancel = currentTeam ~= UNASSIGNED }
	local function Add(c)
		menu.choices[#menu.choices + 1] = c
		c.hotkey = #menu.choices
		return c
	end
	if extras.auto then menu.auto = Add(Choice("auto", extras.auto, currentTeam)) end
	if extras.spectate then menu.spectate = Add(Choice("spectate", extras.spectate, currentTeam)) end
	for i, t in ipairs(teams) do menu.teams[i] = Add(TeamChoice(t, counts, currentTeam, limit)) end
	return menu
end
