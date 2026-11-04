DEFINE_BASECLASS( "player_sandbox" )
local PLAYER = {}
local Weapons = GM.SimpleWeaponLoadout

function PLAYER:Loadout()
	self.Player:RemoveAllAmmo()
	Weapons.GiveHL2(self.Player)
	self.Player:Give("weapon_physcannon")
	Weapons.GiveSandboxTools(self.Player)
	self.Player:SwitchToDefaultWeapon()
end

player_manager.RegisterClass( "player_sandcastle", PLAYER, "player_sandbox" )