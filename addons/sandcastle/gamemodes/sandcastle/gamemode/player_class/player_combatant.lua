DEFINE_BASECLASS( "player_sandbox" )
local PLAYER = {}
local Weapons = include("player_class/simple_weapon_loadout.lua")

function PLAYER:Loadout()

	-- This would make sense, but breaks existing mods
	--self.Player:StripWeapons()
	self.Player:RemoveAllAmmo()

    Weapons.GiveHL2(self.Player)
    self.Player:Give( "weapon_physcannon" )

	Weapons.GiveCombatantTools(self.Player)
	-- self.Player:Give( "weapon_physgun" )

	self.Player:SwitchToDefaultWeapon()

end
player_manager.RegisterClass( "player_combatant", PLAYER, "player_sandbox" )