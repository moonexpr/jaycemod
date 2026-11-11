AddCSLuaFile ("shared.lua")
AddCSLuaFile ("cl_init.lua")
include ("shared.lua")

local Model = WS.require ("features.builder.model")

local WIRE_THINK_TIME = 0.25
local MARKER_MINS, MARKER_MAXS = Vector (-16, -16, 0), Vector (16, 16, 32)
local NO_TEAM_COLOR = Color (255, 255, 255)
local TEAM_COLORS =
{
	[WS.TEAM_RED] = Color (255, 90, 80),
	[WS.TEAM_BLUE] = Color (90, 150, 255)
}

-- What it was placed as, before it spawns: its id and a volume's box.
function ENT:Configure (id, box)
	self:SetPieceId (id)
	if not box then return end
	self:SetBoxMins (box.mins)
	self:SetBoxMaxs (box.maxs)
end

function ENT:Id ()
	return self:GetPieceId ()
end

function ENT:BodyModelPath ()
	return self.MarkerModel
end

-- The team it shows: a class without one shows none.
function ENT:ShownTeam ()
	return self.GetTeamNum and self:GetTeamNum () or nil
end

-- Its look, its body and its colour, as its properties have them. Fixed in place
-- and in nobody's way (debris: the toolgun's and the wire tool's traces still
-- hit it).
function ENT:Settle ()
	self:SetModel (self:BodyModelPath ())
	if self.OwnBox then
		self:PhysicsInitBox (self:OBBMins (), self:OBBMaxs ())
	else
		self:PhysicsInitBox (MARKER_MINS, MARKER_MAXS)
	end
	self:SetCollisionGroup (COLLISION_GROUP_DEBRIS)
	local phys = self:GetPhysicsObject ()
	if IsValid (phys) then phys:EnableMotion (false) end
	self:SetColor (TEAM_COLORS [self:ShownTeam ()] or NO_TEAM_COLOR)
end

function ENT:Initialize ()
	for _, prop in ipairs (self.Properties) do self ["Set" .. prop.name] (self, prop.default) end
	self:Settle ()
	if WireLib then
		self.Inputs = WireLib.CreateInputs (self, self.WirePorts.inputs)
		self.Outputs = WireLib.CreateOutputs (self, self.WirePorts.outputs)
	end
end

-- An edit is applied once it has taken: a notice comes before it does.
function ENT:OnPropertyEdited ()
	timer.Simple (0, function ()
		if IsValid (self) then self:Settle () end
	end)
end

-- Sets the properties given, by name (a tool's settings; a double click).
function ENT:Update (values)
	for name, value in pairs (values) do self ["Set" .. name] (self, value) end
	self:Settle ()
end

-- In a game it neither shows nor stops a bullet; its wires stay.
function ENT:SetInGame (on)
	self:SetNotSolid (on)
	self:SetNoDraw (on)
end

-- What the undo list calls it, once placed.
function ENT:UndoLabel ()
	return self.PrintName
end

-- Told it was placed by a tool: returns what else came with it, to undo together.
function ENT:OnPlaced (ply)
end

-- Its game -------------------------------------------------------------------------------

-- Its Hammer keyvalues on the entity of target.
function ENT:Keys (target)
	return Model.Keys (self.Properties, function (name) return self ["Get" .. name] (self) end, target)
end

-- Adds to the game what it makes (a class may take its kind whole: CompileAll).
function ENT:Compile (game)
end

-- Wire ------------------------------------------------------------------------------------

-- The entity of its game its inputs reach.
function ENT:CompiledName ()
	return Model.Name (self:Id ())
end

function ENT:WireTarget ()
	return WS.Feature ("builder").compiled [self:CompiledName ()]
end

-- What an input asks: fire input at its entity, or call own on itself.
function ENT:WireCommand (port, value)
	local command = self.WireCommands [port]
	if not command then error (string.format ("a %s has no input %s", self.Kind, tostring (port)), 2) end
	return command (value)
end

-- Wiremod's call into a component.
function ENT:TriggerInput (port, value)
	local command = self:WireCommand (port, value)
	if command == Model.NOTHING then return end
	if command.own then return self [command.own] (self, command.param) end
	local target = self:WireTarget ()
	if IsValid (target) then target:Fire (command.input, command.param) end
end

-- The values of its outputs, while its game has its entity.
function ENT:WireStatus (target)
	return {}
end

function ENT:Think ()
	if not WireLib then return end
	self:NextThink (CurTime () + WIRE_THINK_TIME)
	local target = self:WireTarget ()
	if IsValid (target) then
		for port, value in pairs (self:WireStatus (target)) do WireLib.TriggerOutput (self, port, value) end
	end
	return true
end

function ENT:OnRemove ()
	if WireLib then WireLib.Remove (self) end
end

-- Saves and dupes ---------------------------------------------------------------------------

-- As Wiremod's own entities keep their wires through the duplicator.
function ENT:PreEntityCopy ()
	if IsValid (self.nodeEnt) then self.nodeIndex = self.nodeEnt:EntIndex () end
	if not WireLib then return end
	duplicator.ClearEntityModifier (self, "WireDupeInfo")
	local info = WireLib.BuildDupeInfo (self)
	if info then duplicator.StoreEntityModifier (self, "WireDupeInfo", info) end
end

-- What the save's JSON cannot hold, and the next paste makes anew.
function ENT:OnEntityCopyTableFinish (data)
	data.Inputs, data.Outputs, data.nodeEnt, data.helper = nil, nil, nil, nil
end

function ENT:OnDuplicated (data)
	self.savedNodeIndex = data.nodeIndex
	WS.Feature ("builder"):Adopt (self)
end

function ENT:PostEntityPaste (ply, ent, created)
	local node = self.savedNodeIndex and created [self.savedNodeIndex]
	if IsValid (node) then
		self:SetNodeId (node:Id ())
		self.nodeEnt = node
		node.helper = self
		node:DeleteOnRemove (self)
	end
	if WireLib and self.EntityMods and self.EntityMods.WireDupeInfo then
		WireLib.ApplyDupeInfo (ply, self, self.EntityMods.WireDupeInfo, function (id, default)
			local pasted = created [id]
			if IsValid (pasted) then return pasted end
			return default
		end)
	end
end

-- Helpers are not spawnable from the menu, which the duplicator's generic paste
-- would hold against a player: each class pastes through the builder.
for _, class in pairs (Model.CLASSES) do
	duplicator.RegisterEntityClass (class, function (ply, data) return WS.Feature ("builder"):Paste (ply, data) end, "Data")
end
