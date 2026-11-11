-- obj_teleporter (CObjectTeleporter, tf_obj_teleporter.cpp), level 1: an entrance and its exit
-- (IsExit, set before Spawn), each linked as it is set up to its builder's other end standing
-- alone (Link). Both built, a teammate standing on a charged entrance is carried to
-- the exit (gameplay.buildings' Carries, Charged); the pair then recharges.
AddCSLuaFile ()

ENT.Base = "base_obj"
ENT.Kind = "teleporter"
ENT.Model = "models/buildables/teleporter.mdl"
ENT.PrintName = "Teleporter"
ENT.Spawnable = true
ENT.Category = "Sandcastle"

local Buildings = gameplay.buildings

local SEND_SOUND = "weapons/teleporter_send.wav"
local RECEIVE_SOUND = "weapons/teleporter_receive.wav"
-- What counts as standing on its pad, above its origin; and how far over the exit one arrives.
local PAD_MINS, PAD_MAXS = Vector (-24, -24, 0), Vector (24, 24, 24)
local ARRIVE_UP = Vector (0, 0, 16)

function ENT:ObjDataTables ()
	self:NetworkVar ("Bool", 0, "IsExit")
	self:NetworkVar ("Entity", 1, "Partner")
	self:NetworkVar ("Float", 1, "LastTrip")
end

-- The pair, as a builder sets it up: this the entrance, exit its exit.
function ENT:Link (exit)
	self:SetIsExit (false)
	exit:SetIsExit (true)
	self:SetPartner (exit)
	exit:SetPartner (self)
end

-- Its last trip as gameplay.buildings counts it: nil before the first.
function ENT:Tripped ()
	local last = self:GetLastTrip ()
	if last <= 0 then return nil end
	return last
end

if SERVER then
	-- From the spawn menu: the exit of its spawner's entrance standing alone, else an entrance.
	function ENT:ObjSpawnMenu (ply)
		for _, other in ipairs (ents.FindByClass ("obj_teleporter")) do
			if other ~= self and other:GetBuilder () == ply and not other:GetIsExit () and not IsValid (other:GetPartner ()) then
				self:SetIsExit (true)
				return
			end
		end
	end

	-- Its builder's other end, standing without a partner, becomes its partner.
	function ENT:ObjInitialize ()
		local builder = self:GetBuilder ()
		for _, other in ipairs (ents.FindByClass ("obj_teleporter")) do
			if other ~= self and other:GetBuilder () == builder and other:GetIsExit () ~= self:GetIsExit ()
				and not IsValid (other:GetPartner ()) then
				if self:GetIsExit () then other:Link (self) else self:Link (other) end
				return
			end
		end
	end

	function ENT:ObjThink ()
		if self:GetIsExit () then return end
		local exit = self:GetPartner ()
		if not (IsValid (exit) and exit:IsBuilt () and Buildings.Charged (self:Tripped (), CurTime ())) then return end
		local pos = self:GetPos ()
		for _, rider in ipairs (ents.FindInBox (pos + PAD_MINS, pos + PAD_MAXS)) do
			if (rider:IsPlayer () or rider:IsNPC () or rider:IsNextBot ()) and rider:Health () > 0
				and Buildings.Carries (self:GetObjTeam (), WS.TeamNumber (rider)) then
				self:EmitSound (SEND_SOUND)
				rider:SetPos (exit:GetPos () + ARRIVE_UP)
				exit:EmitSound (RECEIVE_SOUND)
				self:SetLastTrip (CurTime ())
				exit:SetLastTrip (CurTime ())
				hook.Run ("WSTeleported", rider, self, exit)
				return
			end
		end
	end
end
