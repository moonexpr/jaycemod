-- Teams as TF2 runs them: the one way to change a player's team
-- (CTFPlayer::ChangeTeam / ForceChangeTeam), the jointeam command
-- (HandleCommand_JoinTeam), auto-assignment (GetAutoTeam), and automatic
-- balancing (CTeamplayRoundBasedRules::BalanceTeams). The rules themselves
-- are in foundation/teams.lua. The server never opens the team menu: a
-- client opens it itself while unassigned, or on the team keys
-- (ws/cl_teams.lua).
local L = WS.TeamRules

-- TF2's convar, as teamplayroundbased_gamerules.cpp defines it;
-- mp_teams_unbalance_limit is shared (sh_core.lua) for the team menu.
local autoteambalance = CreateConVar("mp_autoteambalance", "1", FCVAR_NOTIFY,
	"Automatically balance the teams based on mp_teams_unbalance_limit. 0 = off, 1 = forcibly switch", 0, 1)
local unbalanceLimit = WS.UnbalanceLimit

local UNASSIGNED, SPECTATOR, RED, BLUE = WS.TEAM_UNASSIGNED, WS.TEAM_SPECTATOR, WS.TEAM_RED, WS.TEAM_BLUE

local function Playing(team)
	return team == RED or team == BLUE
end

-- Players without a team and spectators watch the game in observer mode.
local function Observes(team)
	return team == UNASSIGNED or team == SPECTATOR
end

local function Counts()
	return { [RED] = team.NumPlayers(RED), [BLUE] = team.NumPlayers(BLUE) }
end

function WS.AutoTeam()
	return L.AutoTeam(team.NumPlayers(RED), team.NumPlayers(BLUE))
end

-- A switch's suicide is not a death that drops an ammo pack.
local function Die(ply)
	ply.wsChangingTeam = true
	ply:Kill()
	ply.wsChangingTeam = nil
end

-- The one way to change a player's TF2 team. The team is remembered, so a
-- spawn hook of another addon that moves the player is undone (see
-- WS.RestoreTeam). CTFPlayer::ChangeTeam: a live player moving between RED
-- and BLU dies, and comes back with the new team's respawn wave; joining
-- the spectators puts the player into observer mode, and so does
-- UNASSIGNED, the join state: an observer who is not spawned into the game
-- (GM:PlayerSpawn keeps them observing) and whose client shows the team
-- menu. force follows ForceChangeTeam with a full team switch: nobody dies
-- (the round-end team swap, and a new game unassigning everyone). The
-- player joins the new team's DrGBase faction (WS.JoinTeamFaction).
function WS.SetPlayerTeam(ply, newTeam, force)
	local old = ply:Team()
	ply.wsTeam = newTeam
	if newTeam == old then return end
	WS.JoinTeamFaction(ply, newTeam)
	if Observes(newTeam) then
		-- HandleCommand_JoinTeam: a live player dies before becoming a spectator.
		if not force and Playing(old) and ply:Alive() then Die(ply) end
		ply:SetTeam(newTeam)
		WS.StartObserving(ply)
		return
	end
	ply:SetTeam(newTeam)
	if Observes(old) then
		-- The engine needs a spawn or a kill after leaving observer mode; the
		-- player waits, dead, for the new team's respawn wave. The kill comes
		-- after the team change so the wave is the new team's.
		WS.StopObserving(ply)
		if ply:Alive() then
			ply.wsChangingTeam = true
			ply:KillSilent()
			ply.wsChangingTeam = nil
		end
	elseif not force and Playing(old) and ply:Alive() then
		Die(ply)
	end
end

-- CTFPlayer::InitialSpawn (TF_STATE_WELCOME): a new player has no team.
-- GM:PlayerSpawn keeps them observing, and their client opens the team
-- menu once it has loaded.
function WS.SetInitialTeam(ply)
	ply.wsTeam = UNASSIGNED
	ply:SetTeam(UNASSIGNED)
end

-- Undo a team change made behind WS.SetPlayerTeam (other addons put
-- players on their own teams, such as 21 "Runner", in their spawn hooks).
-- A player who never had a TF2 team keeps it if they are on one, and is
-- otherwise left without a team, for their client to show the team menu.
function WS.RestoreTeam(ply)
	if not ply.wsTeam then
		local current = ply:Team()
		if Observes(current) or Playing(current) then
			ply.wsTeam = current
		else
			WS.SetPlayerTeam(ply, UNASSIGNED, true)
		end
	elseif ply:Team() ~= ply.wsTeam then
		ply:SetTeam(ply.wsTeam)
	end
end

-- CTFPlayer::HandleCommand_JoinTeam: "red", "blue", "auto" or "spectate".
-- mp_forceautoteam auto-assigns a pick of RED or BLU, and spectating needs
-- mp_allowspectators (L.ResolveJoin). A join that would unbalance the teams
-- is refused; an unassigned player's client keeps the menu up.
function WS.JoinTeam(ply, name)
	if WS.State() == WS.STATE.GAME_OVER then return end
	local newTeam, refused = L.ResolveJoin(L.ParseJoinTeam(name), WS.ForceAutoTeam:GetBool(),
		WS.AllowSpectators:GetBool())
	if not newTeam then
		ply:PrintMessage(HUD_PRINTCENTER, refused)
		return
	end
	if newTeam == L.AUTO then newTeam = WS.AutoTeam() end
	if newTeam < SPECTATOR or newTeam == ply:Team() then return end
	if newTeam ~= SPECTATOR and L.WouldUnbalance(Counts(), newTeam, ply:Team(), unbalanceLimit:GetInt()) then
		ply:PrintMessage(HUD_PRINTCENTER, "That team is full; join the other team or wait.")
		return
	end
	WS.SetPlayerTeam(ply, newTeam)
end

concommand.Add("jointeam", function(ply, _, args)
	if not IsValid(ply) or not WS.Active() or not args[1] then return end
	WS.JoinTeam(ply, args[1])
end, nil, "Join a team: red, blue, auto or spectate")

-- Balancing ----------------------------------------------------------------

local unbalancedSince, warned

-- CTeamplayRoundBasedRules::BalanceTeams. requireDead: mid-round, only dead
-- players are moved. The recently-switched queue of the SDK is left out;
-- the score still spares anyone moved in the last five minutes.
function WS.BalanceTeams(requireDead)
	if not autoteambalance:GetBool() then return end
	local counts = Counts()
	local heavy, light = L.Unbalanced(counts, unbalanceLimit:GetInt())
	if not heavy then
		unbalancedSince, warned = nil, false
		return
	end
	local now = CurTime()
	unbalancedSince = unbalancedSince or now
	if not warned and now - unbalancedSince > 1 then
		PrintMessage(HUD_PRINTTALK, "Teams will be auto-balanced in 5 seconds")
		warned = true
	end
	local byId, candidates = {}, {}
	for _, ply in ipairs(team.GetPlayers(heavy)) do
		local id = ply:UserID()
		byId[id] = ply
		candidates[#candidates + 1] = {
			id = id,
			score = L.BalanceScore(now, now - ply:TimeConnected(), ply.wsForcedTeamAt),
			alive = ply:Alive(),
		}
	end
	local required = L.SwitchesRequired(counts[heavy], counts[light])
	for _, id in ipairs(L.PickBalanceSwitches(candidates, required, requireDead)) do
		local ply = byId[id]
		WS.SetPlayerTeam(ply, light)
		ply.wsForcedTeamAt = now
		PrintMessage(HUD_PRINTTALK, ply:Nick() .. " was moved to the other team for game balance")
	end
end

-- State_Enter_PREROUND holds balancing off for the first 60 seconds of a
-- round; State_Think_RND_RUNNING balances dead players once a second.
local balanceFrom = 0

hook.Add("WSRoundActive", "ws_teams", function()
	balanceFrom = CurTime() + 60
end)

timer.Create("ws_teams_balance", 1, 0, function()
	if not WS.Active() or WS.State() ~= WS.STATE.RND_RUNNING then return end
	if CurTime() < balanceFrom then return end
	WS.BalanceTeams(true)
end)
