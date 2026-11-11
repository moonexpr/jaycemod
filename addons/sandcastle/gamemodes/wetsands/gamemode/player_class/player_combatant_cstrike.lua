DEFINE_BASECLASS ("player_base")
local PLAYER = {}
local Weapons = GM.SimpleWeaponLoadout

function PLAYER:Loadout ()
	self.Player:RemoveAllAmmo ()
	Weapons.GiveHL2 (self.Player)
	-- Weapons.GiveBM(self.Player)
	-- Weapons.GiveHL2Extended(self.Player)
	self.Player:Give ("weapon_physcannon")
	-- Weapons.GiveSandboxTools(self.Player)
	-- self.Player:Give( "weapon_physgun" )

	self.Player:SwitchToDefaultWeapon ()

end
player_manager.RegisterClass ("player_combatant_cstrike", PLAYER, "player_combatant")
