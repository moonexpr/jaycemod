-- Votes (foundation.vote): the settings, the events, and TF2's wording for
-- each kind, shared by the server (ws/sv_votes.lua), the HUD card and the
-- Server tab (ws/cl_votes.lua). Players call map, restart, scramble, team
-- help and difficulty votes; kick votes start only from reports
-- (ws/sv_players_menu.lua). Team help and soldier difficulty have no system
-- behind them yet, so they are not offered (WS.VOTE_READY).
local Vote = WS.require("foundation.vote")
local E = WS.Events

local FLAGS = { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }
CreateConVar("mp_vote_duration", "20", FLAGS, "Seconds a vote runs", 5, 120)
CreateConVar("mp_vote_cooldown", "120", FLAGS, "Seconds a player waits after calling a vote before calling another", 0, 3600)
CreateConVar("mp_vote_map_enabled", "1", FLAGS, "1: players may vote on the next map", 0, 1)
CreateConVar("mp_vote_reset_enabled", "1", FLAGS, "1: players may vote to restart the round", 0, 1)
CreateConVar("mp_vote_scramble_enabled", "1", FLAGS, "1: players may vote to scramble the teams", 0, 1)
CreateConVar("mp_vote_support_enabled", "1", FLAGS, "1: a team may vote to help the other team", 0, 1)
CreateConVar("mp_vote_difficulty_enabled", "1", FLAGS, "1: players may vote on the soldiers' difficulty", 0, 1)

-- The kinds on the wire, by index (vote_call's kind, vote_state's).
WS.VOTE_KINDS = {
	Vote.KIND_KICK,
	Vote.KIND_MAP,
	Vote.KIND_RESET,
	Vote.KIND_SCRAMBLE,
	Vote.KIND_SUPPORT,
	Vote.KIND_DIFFICULTY,
}

function WS.VoteKindIndex(kind)
	for i, k in ipairs(WS.VOTE_KINDS) do
		if k == kind then return i - 1 end
	end
	error("votes: unknown kind " .. tostring(kind))
end

-- The kinds whose effect exists; the others are shown, not offered.
WS.VOTE_READY = {
	[Vote.KIND_MAP] = true,
	[Vote.KIND_RESET] = true,
	[Vote.KIND_SCRAMBLE] = true,
}

-- Whether players may call a kind now, on this realm's view of the convars.
function WS.VoteEnabled(kind)
	return WS.VOTE_READY[kind] == true and GetConVar("mp_vote_" .. kind .. "_enabled"):GetBool()
end

-- TF2's issue names (Vote_*) and questions (TF_vote_*).
WS.VOTE_NAMES = {
	[Vote.KIND_KICK] = "Kick",
	[Vote.KIND_MAP] = "Next Map",
	[Vote.KIND_RESET] = "Restart Round",
	[Vote.KIND_SCRAMBLE] = "Scramble Teams",
	[Vote.KIND_SUPPORT] = "Help Other Team",
	[Vote.KIND_DIFFICULTY] = "Soldier Difficulty",
}

-- reason: a foundation.reports reason, for a kick.
local KICK_REASONS = {
	none = "(no reason given)",
	cheating = "(accused of cheating)",
	idle = "(accused of being idle)",
	scamming = "(accused of scamming)",
}

function WS.VoteQuestion(kind, subject, reason)
	if kind == Vote.KIND_KICK then return "Kick player: " .. subject .. "? " .. KICK_REASONS[reason] end
	if kind == Vote.KIND_MAP then return "Set the next map to " .. subject .. "?" end
	if kind == Vote.KIND_RESET then return "Restart the round?" end
	if kind == Vote.KIND_SCRAMBLE then return "Scramble the teams?" end
	if kind == Vote.KIND_SUPPORT then return "Help " .. subject .. "?" end
	return "Set soldier difficulty to " .. subject .. "?"
end

-- TF_vote_passed_*.
function WS.VotePassed(kind, subject)
	if kind == Vote.KIND_KICK then return "Kicking player: " .. subject .. "..." end
	if kind == Vote.KIND_MAP then return "Next map set to " .. subject .. "..." end
	if kind == Vote.KIND_RESET then return "Restarting the round..." end
	if kind == Vote.KIND_SCRAMBLE then return "Teams will be scrambled." end
	if kind == Vote.KIND_SUPPORT then return subject .. " will get help." end
	return "Soldier difficulty set to " .. subject .. "."
end

local KIND_BITS = 3
local COUNT_BITS = 7
local MAP_COUNT_BITS = 9
local REQUEST_RATE = {
	count = 6,
	seconds = 5,
}

-- subject: the map for a map vote; empty for the rest.
E.Define("vote_call", {
	kind = E.UInt(KIND_BITS),
	subject = E.String(),
}, {
	clientSendable = true,
	rate = REQUEST_RATE,
})

E.Define("vote_cast", { yes = E.Bool() }, {
	clientSendable = true,
	rate = REQUEST_RATE,
})

-- The running vote as one player sees it; running false when none runs.
-- mine: whether this player may still vote.
E.Define("vote_state", {
	running = E.Bool(),
	kind = E.UInt(KIND_BITS),
	question = E.String(),
	caller = E.String(),
	ends = E.Float(),
	yes = E.UInt(COUNT_BITS),
	no = E.UInt(COUNT_BITS),
	quorum = E.UInt(COUNT_BITS),
	mine = E.Bool(),
})

-- A vote is over: TF2's passed line, or why it failed.
E.Define("vote_ended", {
	passed = E.Bool(),
	text = E.String(),
})

-- A request refused, for the player who made it.
E.Define("vote_refused", { text = E.String() })

-- The maps a map vote may name: the server's map cycle.
E.Define("vote_maps", { maps = E.List(E.String(), MAP_COUNT_BITS) })
