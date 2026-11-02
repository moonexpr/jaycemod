DEFINE_BASECLASS( "player_base" )
local PLAYER = {}
local Weapons = GM.SimpleWeaponLoadout

function PLAYER:Loadout()
	self.Player:RemoveAllAmmo()
	Weapons.GiveCStrike(self.Player)
	-- Weapons.GiveHL2Extended(self.Player)
	self.Player:Give( "weapon_physcannon" )
	Weapons.GiveCombatantTools(self.Player)
	-- self.Player:Give( "weapon_physgun" )

	self.Player:SwitchToDefaultWeapon()

end
player_manager.RegisterClass( "player_combatant_cstrike", PLAYER, "player_base" )