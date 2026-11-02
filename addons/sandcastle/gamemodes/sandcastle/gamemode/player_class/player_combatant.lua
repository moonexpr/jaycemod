DEFINE_BASECLASS( "player_sandbox" )
local PLAYER = {}

function PLAYER:Loadout()

	-- This would make sense, but breaks existing mods
	--self.Player:StripWeapons()
	self.Player:RemoveAllAmmo()

    self.Player:GiveAmmo( 256,	"Pistol", 		true )
    self.Player:GiveAmmo( 256,	"SMG1",         true )
    self.Player:GiveAmmo( 5,	"SMG1_Grenade", true )
    self.Player:GiveAmmo( 5,	"grenade", 		true )
    self.Player:GiveAmmo( 64,	"Buckshot", 	true )
    self.Player:GiveAmmo( 32,	"357", 			true )
    self.Player:GiveAmmo( 32,	"XBowBolt", 	true )
    self.Player:GiveAmmo( 6,	"AR2AltFire", 	true )
    self.Player:GiveAmmo( 100,	"AR2", 			true )

    self.Player:Give( "weapon_crowbar" )
    self.Player:Give( "weapon_pistol" )
    self.Player:Give( "weapon_smg1" )
    self.Player:Give( "weapon_frag" )
    self.Player:Give( "weapon_physcannon" )
    self.Player:Give( "weapon_crossbow" )
    self.Player:Give( "weapon_shotgun" )
    self.Player:Give( "weapon_357" )
    self.Player:Give( "weapon_rpg" )
    self.Player:Give( "weapon_ar2" )

    -- The only reason I'm leaving this out is because
    -- I don't want to add too many weapons to the first
    -- row because that's where the gravgun is.
    --pl:Give( "weapon_stunstick" )


	self.Player:Give( "gmod_tool" )
	self.Player:Give( "gmod_camera" )
	-- self.Player:Give( "weapon_physgun" )

	self.Player:SwitchToDefaultWeapon()

end
player_manager.RegisterClass( "player_combatant", PLAYER, "player_sandbox" )