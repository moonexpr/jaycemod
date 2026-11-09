--[[---------------------------------------------------------

  Rounds, while the gamemode is in gameplay mode

  The match is round_manager's; these are the gamemode's
  answers to it, and what a round changes for a player.

-----------------------------------------------------------]]

include( "includes/modules/round_manager.lua" )

DEFINE_BASECLASS( "gamemode_base" )

function GM:RoundThink()

	round_manager.Think( self:IsGameplay() )

end

--[[---------------------------------------------------------
	Name: gamemode:RoundWin()
	Desc: A map ended the round
-----------------------------------------------------------]]
function GM:RoundWin( winner, info )

	round_manager.Declare( winner )

end

--[[---------------------------------------------------------
	Name: gamemode:PlayerDeath()
	Desc: The games being played hear of it
-----------------------------------------------------------]]
function GM:PlayerDeath( ply, inflictor, attacker )

	BaseClass.PlayerDeath( self, ply, inflictor, attacker )
	game_manager.RunActive( "PlayerDeath", ply, inflictor, attacker )

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
