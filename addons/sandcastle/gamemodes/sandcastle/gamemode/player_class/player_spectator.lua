DEFINE_BASECLASS( "player_sandbox" )
local PLAYER = {}

PLAYER.DuckSpeed			= 0.1		-- How fast to go from not ducking, to ducking
PLAYER.UnDuckSpeed			= 0.1		-- How fast to go from ducking, to not ducking


--
-- See gamemodes/base/player_class/player_default.lua for all overridable variables
--
PLAYER.SlowWalkSpeed		= 100
PLAYER.WalkSpeed 			= 200
PLAYER.RunSpeed				= 400

local function IsObserving(ply)
	return ply:Team() == TEAM_SPECTATOR or ply:GetObserverMode() ~= OBS_MODE_NONE
end

local function CanRoam(ply)
	return ply:Team() == TEAM_SPECTATOR and ply:GetObserverMode() == OBS_MODE_ROAMING
end

local function StopMoving(move)
	move:SetForwardSpeed(0)
	move:SetSideSpeed(0)
	move:SetUpSpeed(0)
	move:SetVelocity(vector_origin)
end

--
-- Set up the network table accessors
--
function PLAYER:SetupDataTables()
	BaseClass.SetupDataTables( self )
end


function PLAYER:Loadout()
	self.Player:StripWeapons()
	self.Player:RemoveAllAmmo()
end

function PLAYER:SetModel()
	BaseClass.SetModel( self )
	if IsObserving(self.Player) then self.Player:SetNoDraw(true) end
end

--
-- Called when the player spawns
--
function PLAYER:Spawn()
	BaseClass.Spawn( self )
	if IsObserving(self.Player) then
		self.Player:SetNoDraw(true)
		self.Player:SetSolid(SOLID_NONE)
	end
end

--
-- Player should not be able to see themselves.
--
function PLAYER:ShouldDrawLocal()
	return false
end

--
-- Allow player class to create move
--
function PLAYER:CreateMove( cmd )
	if not CanRoam(self.Player) then
		cmd:SetForwardMove(0)
		cmd:SetSideMove(0)
		cmd:SetUpMove(0)
	end
	return true
end

--
-- Allow changing the player's view
--
function PLAYER:CalcView( view )
	return true
end

function PLAYER:StartMove( move )
	if not CanRoam(self.Player) then StopMoving(move) end
end

function PLAYER:FinishMove( move )
	if not CanRoam(self.Player) then StopMoving(move) end
end


player_manager.RegisterClass( "player_spectator", PLAYER, "player_sandbox" )
