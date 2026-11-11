-- Capture the flag: played on any map with a flag (item_teamflag's "flag"
-- controller). The flags and their zones (func_capturezone, func_respawnflag)
-- act on each other and stand on their own; this file holds the tally, told
-- of a capture by round_manager, closes the round at the capture limit and
-- gives the entities its rules (GetRules), which a mode may answer:
--   FlagRules() -> { ownersCarry, mayBeCapped, invaders, scores }
-- A gamemode may tell the entities more through its hooks, or leave them to
-- their own answers for players:
--   FlagTeam(ent) -> the team ent carries for
--   FlagCarrierAlive(ent), FlagMembersInside(ent) -> who stands on ent
--   FlagEvent(ent, event, activator)
local GAME = {}

GAME.Requires = { "flag" }

local RED, BLUE = TEAM_RED, TEAM_BLUE
local GAME_TEAMS = { RED, BLUE }

-- The kinds of a flag's events.
local PICKUP, DROP, CAPTURE, RETURN = "pickup", "drop", "capture", "return"

-- tf_flag_caplimit's default.
local CAPLIMIT_DEFAULT = 3
GAME.CAPLIMIT_DEFAULT = CAPLIMIT_DEFAULT

-- The announcer ---------------------------------------------------------------------

-- CCaptureFlag's BroadcastSound calls: the acting team (the carrier's, or
-- the flag's on a return) hears the Team line, every other the Enemy line.
local LINES =
{
	[PICKUP] = "Stolen",
	[DROP] = "Dropped",
	[CAPTURE] = "Captured",
	[RETURN] = "Returned"
}

function GAME.Lines (e)
	local lines = {}
	for _, t in ipairs (GAME_TEAMS) do
		lines [#lines + 1] =
		{
			team = t,
			sound = "CaptureFlag." .. (t == e.team and "Team" or "Enemy") .. LINES [e.kind]
		}
	end
	return lines
end

-- ResetMessage for MvM's bomb (TF_FLAGTYPE_ATTACK_DEFEND): a return is told
-- to its own team (TF_AD_TEAM_RETURNED) and the defenders
-- (TF_MVM_AD_ENEMY_RETURNED); the bomb's other events go unannounced.
function GAME.InvadeLines (e)
	if e.kind ~= RETURN then return {} end
	local lines = {}
	for _, t in ipairs (GAME_TEAMS) do
		lines [#lines + 1] =
		{
			team = t,
			sound = t == e.team and "AttackDefend.TeamReturned" or "MVM.AttackDefend.EnemyReturned"
		}
	end
	return lines
end

-- The tally -------------------------------------------------------------------------

local Tally = {}
Tally.__index = Tally
GAME.TallyClass = Tally

local function NewTally ()
	return setmetatable ({ caps = { [RED] = 0, [BLUE] = 0 } }, Tally)
end
GAME.NewTally = NewTally

function Tally:Captures (t) return self.caps [t] end

-- Counts a capture; true when it brings the team to a limit above 0.
function Tally:Capture (t, limit)
	self.caps [t] = self.caps [t] + 1
	return limit > 0 and self.caps [t] >= limit
end

function Tally:Reset ()
	for _, t in ipairs (GAME_TEAMS) do self.caps [t] = 0 end
end

function GAME:CreatePanel ()
	local view = WS.Feature ("flag")
	return self:ObjectivePanel (function (w, h)
		if WS.Active () and not WS.HUD:IsHidden ("game.objective.flags") then view.Draw (w, h) end
	end)
end

if SERVER then

	local caplimit = CreateConVar ("tf_flag_caplimit", tostring (CAPLIMIT_DEFAULT), { FCVAR_NOTIFY, FCVAR_REPLICATED },
		"Number of captures to win")

	local tally = NewTally ()
	GAME.tally = tally

	-- A mode's answer, or sandbox's and a plain round's: flags free in sandbox,
	-- and in gameplay only while a round is on.
	local function Rules ()
		return hook.Run ("FlagRules") or
			{
				ownersCarry = false,
				mayBeCapped = not GAMEMODE:IsGameplay () or GAMEMODE:GetRoundState () == ROUND_ACTIVE,
				scores = true
			}
	end
	GAME.Rules = Rules

	function GAME.CapLimit () return caplimit:GetInt () end

	local function FlagEntities () return ents.FindByClass ("item_teamflag") end
	local function ZoneEntities () return ents.FindByClass ("func_capturezone") end
	local function ResetEntities () return ents.FindByClass ("func_respawnflag") end

	-- item_teamflag -> its model.
	function GAME.Flags ()
		local flags = {}
		for _, ent in ipairs (FlagEntities ()) do flags [ent] = ent.flagModel end
		return flags
	end

	-- func_capturezone -> itself, its team and enabled.
	function GAME.Zones ()
		local zones = {}
		for _, ent in ipairs (ZoneEntities ()) do zones [ent] = ent end
		return zones
	end

	-- func_respawnflag -> itself, its enabled.
	function GAME.ResetZones ()
		local zones = {}
		for _, ent in ipairs (ResetEntities ()) do zones [ent] = ent end
		return zones
	end

	function GAME.Model (ent) return ent.flagModel end
	function GAME.ZoneTeam (ent) return ent.team end

	-- The game ----------------------------------------------------------------------------

	function GAME:GetRules ()
		local rules = Rules ()
		return
		{
			FlagOwnersCarry = rules.ownersCarry,
			FlagMayBeCapped = rules.mayBeCapped,
			FlagInvaders = rules.invaders,
			FlagScores = rules.scores
		}
	end

	-- WINREASON_FLAG_CAPTURE_LIMIT. A full reset, no team switch, the round scored.
	local FLAG_CAPTURE_LIMIT = 3

	-- What everyone hears of a capture; a derived game replaces it.
	function GAME.AnnounceCapture (info)
		PrintMessage (HUD_PRINTCENTER, team.GetName (info.team) .. " captured the intelligence")
	end

	-- A flag captured, where the mode counts captures.
	function GAME:TeamScored (info)
		if info.event ~= "flag_capture" then return end
		self.AnnounceCapture (info)
		if tally:Capture (info.team, caplimit:GetInt ()) then
			round_manager.RoundOutcome (
				{
					team = info.team,
					reason = FLAG_CAPTURE_LIMIT,
					forceMapReset = true,
					switchTeams = false
				}
			)
		end
	end

	-- Each round counts its own captures.
	function GAME:RoundPrepare ()
		tally:Reset ()
	end

	-- The flags each team has captured, and the limit.
	function GAME:Standing (objective)
		objective.captures =
		{
			[RED] = tally:Captures (RED),
			[BLUE] = tally:Captures (BLUE)
		}
		objective.caplimit = caplimit:GetInt ()
	end

end

game_manager.RegisterClass ("game_ctf", GAME, "game_default")
