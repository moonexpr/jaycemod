-- player_sandbox's sibling: the same player, without its StartMove and FinishMove
-- (HL2's jump boost). Its cl_player* convars are player_sandbox's, which Sandbox
-- still loads.
DEFINE_BASECLASS( "player_default" )
local PLAYER = {}
local Weapons = GM.SimpleWeaponLoadout

PLAYER.DuckSpeed = 0.1
PLAYER.UnDuckSpeed = 0.1
PLAYER.TauntCam = TauntCamera()
PLAYER.SlowWalkSpeed = 100
PLAYER.WalkSpeed = 200
PLAYER.RunSpeed = 400

function PLAYER:Loadout()
	self.Player:RemoveAllAmmo()
	Weapons.GiveHL2(self.Player)
	self.Player:Give("weapon_physcannon")
	Weapons.GiveSandboxTools(self.Player)
	self.Player:SwitchToDefaultWeapon()
end

function PLAYER:SetModel()
	BaseClass.SetModel(self)

	local ply = self.Player
	ply:SetSkin(ply:GetInfoNum("cl_playerskin", 0))

	local groups = string.Explode(" ", ply:GetInfo("cl_playerbodygroups") or "")
	for index = 0, ply:GetNumBodyGroups() - 1 do
		ply:SetBodygroup(index, tonumber(groups[index + 1]) or 0)
	end
end

function PLAYER:Spawn()
	BaseClass.Spawn(self)

	local ply = self.Player
	ply:SetPlayerColor(Vector(ply:GetInfo("cl_playercolor")))

	local weaponColor = Vector(ply:GetInfo("cl_weaponcolor"))
	if weaponColor:Length() < 0.001 then weaponColor = Vector(0.001, 0.001, 0.001) end
	ply:SetWeaponColor(weaponColor)
end

function PLAYER:ShouldDrawLocal()
	if self.TauntCam:ShouldDrawLocalPlayer(self.Player, self.Player:IsPlayingTaunt()) then return true end
end

function PLAYER:CreateMove(cmd)
	if self.TauntCam:CreateMove(cmd, self.Player, self.Player:IsPlayingTaunt()) then return true end
end

function PLAYER:CalcView(view)
	if self.TauntCam:CalcView(view, self.Player, self.Player:IsPlayingTaunt()) then return true end
end

player_manager.RegisterClass( "player_sandcastle", PLAYER, "player_default" )
