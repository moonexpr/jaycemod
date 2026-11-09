--[[---------------------------------------------------------

  Rounds, while the gamemode is in gameplay mode

  A round is prepared, played and ended; the games in
  gamerules/ say who won it. A team's score is its rounds won,
  and the first team to sandcastle_winlimit takes the match.

-----------------------------------------------------------]]

DEFINE_BASECLASS( "gamemode_base" )

local PREPARE_TIME = 5
local ROUND_TIME = 300
local OVER_TIME = 8

local winlimit = CreateConVar( "sandcastle_winlimit", "3", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Rounds a team must win to take the match", 1 )

local matchOver = false

local function SetRound( state, duration )

	SetGlobal2Int( "SandcastleRoundState", state )
	SetGlobal2Float( "SandcastleRoundEnd", duration and CurTime() + duration or 0 )
	hook.Run( "OnRoundStateChanged", state )

end

local function StartRound()

	game.CleanUpMap()
	SetRound( ROUND_PREPARE, PREPARE_TIME )

	for _, ply in ipairs( player.GetAll() ) do
		if ( team.Joinable( ply:Team() ) ) then ply:Spawn() end
	end

end

local function EndRound( winner )

	SetRound( ROUND_OVER, OVER_TIME )

	if ( !winner ) then
		PrintMessage( HUD_PRINTCENTER, "Stalemate" )
		return
	end

	team.AddScore( winner, 1 )
	PrintMessage( HUD_PRINTCENTER, team.GetName( winner ) .. " wins the round" )
	matchOver = team.GetScore( winner ) >= winlimit:GetInt()

end

local function RoundWinner()

	for _, name in ipairs( game_manager.Active() ) do
		local winner = game_manager.RunClass( name, "RoundWinner" )
		if ( winner ) then return winner end
	end

end

function GM:RoundThink()

	local state = self:GetRoundState()

	if ( !self:IsGameplay() ) then
		if ( state != ROUND_WAITING ) then SetRound( ROUND_WAITING ) end
		return
	end

	local roundEnd = self:GetRoundEnd()
	local expired = roundEnd > 0 && CurTime() >= roundEnd

	if ( state == ROUND_WAITING ) then
		if ( team.NumPlayers( TEAM_RED ) > 0 && team.NumPlayers( TEAM_BLUE ) > 0 ) then StartRound() end
	elseif ( state == ROUND_PREPARE ) then
		if ( expired ) then SetRound( ROUND_ACTIVE, ROUND_TIME ) end
	elseif ( state == ROUND_ACTIVE ) then
		local winner = RoundWinner()
		if ( winner || expired ) then EndRound( winner ) end
	elseif ( expired ) then
		if ( matchOver ) then game.LoadNextMap() else StartRound() end
	end

end

--[[---------------------------------------------------------
	Name: gamemode:PlayerDeathThink()
	Desc: The dead wait for the next round
-----------------------------------------------------------]]
function GM:PlayerDeathThink( ply )

	if ( self:IsGameplay() && self:GetRoundState() == ROUND_ACTIVE ) then return false end

	return BaseClass.PlayerDeathThink( self, ply )

end

--[[---------------------------------------------------------
	Name: gamemode:PlayerLoadout()
	Desc: Sandbox's tools stay out of a round
-----------------------------------------------------------]]
function GM:PlayerLoadout( ply )

	BaseClass.PlayerLoadout( self, ply )

	if ( !self:IsGameplay() ) then return end

	ply:StripWeapon( "weapon_physgun" )
	ply:StripWeapon( "gmod_tool" )
	ply:StripWeapon( "gmod_camera" )

end
