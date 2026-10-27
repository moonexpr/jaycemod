-- The soundscapes each client precaches as it loads (ws/sh_announcer.lua),
-- so a line the server broadcasts or the client cues plays the moment it
-- comes: the gamemode's own (the announcer's, the match's music and
-- stings, the HUD's chimes). A feature's own come with it, as it loads
-- (features/<name>/resources.lua). One missed still plays, precached as it
-- does; ws_soundscapes_late lists those, for a list to take.
module(...)

PRELOAD = {
	-- the countdown to Gameplay mode (features/gamemode/sv.lua)
	"MatchMaking.RoundStartCasual",
	"Announcer.TournamentModeStart",
	"Announcer.CompGame1Begins60Seconds",
	"Announcer.CompGame1Begins30Seconds",
	"Announcer.CompGame1Begins10Seconds",
	"Announcer.CompGameBegins05Seconds",
	"Announcer.CompGameBegins04Seconds",
	"Announcer.CompGameBegins03Seconds",
	"Announcer.CompGameBegins02Seconds",
	"Announcer.CompGameBegins01Seconds",
	"Announcer.CompGameBeginsFight",
	"Hud.Hint",

	-- the round timer's (games.gameplay.rounds.timer, features/rounds/cl.lua)
	"Announcer.RoundBegins60Seconds",
	"Announcer.RoundBegins30Seconds",
	"Announcer.RoundBegins10Seconds",
	"Announcer.RoundBegins5Seconds",
	"Announcer.RoundBegins4Seconds",
	"Announcer.RoundBegins3Seconds",
	"Announcer.RoundBegins2Seconds",
	"Announcer.RoundBegins1Seconds",
	"Announcer.RoundEnds5minutes",
	"Announcer.RoundEnds2minutes",
	"Announcer.RoundEnds60seconds",
	"Announcer.RoundEnds30seconds",
	"Announcer.RoundEnds20seconds",
	"Announcer.RoundEnds10seconds",
	"Announcer.RoundEnds9seconds",
	"Announcer.RoundEnds8seconds",
	"Announcer.RoundEnds7seconds",
	"Announcer.RoundEnds6seconds",
	"Announcer.RoundEnds5seconds",
	"Announcer.RoundEnds4seconds",
	"Announcer.RoundEnds3seconds",
	"Announcer.RoundEnds2seconds",
	"Announcer.RoundEnds1seconds",
	"Game.Overtime",
	"Ambient.Siren",

	-- the round's announcer: first blood, points, close to winning, scores
	"Announcer.AM_FirstBloodRandom",
	"Announcer.Success",
	"Announcer.Failure",
	"Announcer.OurTeamCloseToWinning",
	"Announcer.EnemyTeamCloseToWinning",
	"Hud.PointCaptured",
	"Hud.EndRoundScored",

	-- the round's and the match's end (features/rounds/sv_effects.lua)
	"Game.YourTeamWon",
	"Game.YourTeamLost",
	"Game.Stalemate",
	"Game.SuddenDeath",
	"Announcer.CompRoundWinBlu",
	"Announcer.CompRoundWinRed",
	"Announcer.CompRoundStalemate",
	"Announcer.CompMatchWinBlu",
	"Announcer.CompMatchWinRed",
	"Announcer.AM_TeamScrambleRandom",
	"MatchMaking.MatchEndWinMusicCasual",
	"MatchMaking.MatchEndLoseMusicCasual",
	"MatchMaking.MatchEndBlueWinMusic",
	"MatchMaking.MatchEndRedWinMusic",
	"MatchMaking.RoundEndStalemateMusic",

	-- time awarded, and the Administrator's notices (ws.admin_notices)
	"Announcer.TimeAdded",
	"Announcer.TimeAddedForEnemy",
	"Announcer.TimeAwardedForTeam",
	"Announcer.TimeAwardedCongrats",
	"Announcer.TimeAwardedSuccess",
	"Announcer.SecurityAlert",
}
