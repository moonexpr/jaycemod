DEFINE_BASECLASS( "player_sandbox" )
local PLAYER = {}

function PLAYER:Loadout()
	self.Player:StripWeapons()
	self.Player:RemoveAllAmmo()
end

player_manager.RegisterClass( "player_spectator", PLAYER, "player_sandbox" )
