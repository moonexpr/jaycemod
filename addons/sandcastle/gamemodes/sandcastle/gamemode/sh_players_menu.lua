-- The scoreboard's player menu (ws/cl_players_menu.lua draws it, ws/sv_players_menu.lua
-- answers it): copy a player's Steam3 ID, report them (games.gameplay.reports),
-- give them money, mute them; and for holders of the players privilege,
-- kick, ban and give money from nothing. Players never call a kick vote:
-- mp_reports_kick_count reports of one player start one (WSReportsReached).
local Reports = gameplay.reports
local E = WS.Events

CreateConVar("mp_reports_kick_count", "3", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
	"Reports of one player, each from a different player, that start a vote to kick them (two on a server of exactly three players)",
	1, 32)

-- The amounts the menu offers a player giving money, and an admin.
WS.PLAYERS_MENU_GIFTS = { 10, 50, 100 }
WS.PLAYERS_MENU_GRANTS = { 100, 500, 1000 }

-- Ban lengths in minutes, 0 for permanent. An admin mod offers its own.
WS.PLAYERS_MENU_BANS = {
	{
		label = "1 Hour",
		minutes = 60,
	},
	{
		label = "1 Day",
		minutes = 1440,
	},
	{
		label = "1 Week",
		minutes = 10080,
	},
	{
		label = "Permanently",
		minutes = 0,
	},
}

-- What an admin does to a player (game_admin_player's action).
WS.ADMIN_KICK, WS.ADMIN_BAN, WS.ADMIN_GRANT = 0, 1, 2

-- TF2's wording for each reason, in the menu and the vote.
WS.REPORT_LABELS = {
	[Reports.CHEATING] = "Player is Cheating",
	[Reports.IDLE] = "Player is Idle",
	[Reports.SCAMMING] = "Player is Scamming",
	[Reports.NONE] = "No Reason Given",
}

local REASON_BITS = 2
local ACTION_BITS = 2
local AMOUNT_BITS = 24
local REQUEST_RATE = {
	count = 6,
	seconds = 5,
}

-- reason: an index into Reports.REASONS.
E.Define("game_player_report", {
	target = E.Entity(),
	reason = E.UInt(REASON_BITS),
}, {
	clientSendable = true,
	rate = REQUEST_RATE,
})

E.Define("game_money_transfer", {
	target = E.Entity(),
	amount = E.UInt(AMOUNT_BITS),
}, {
	clientSendable = true,
	rate = REQUEST_RATE,
})

-- value: the ban's index into WS.PLAYERS_MENU_BANS, or the amount granted.
E.Define("game_admin_player", {
	target = E.Entity(),
	action = E.UInt(ACTION_BITS),
	value = E.UInt(AMOUNT_BITS),
}, {
	clientSendable = true,
	rate = REQUEST_RATE,
})

-- How a request went, for the player who made it.
E.Define("game_players_menu_said", {
	text = E.String(),
	refused = E.Bool(),
})
