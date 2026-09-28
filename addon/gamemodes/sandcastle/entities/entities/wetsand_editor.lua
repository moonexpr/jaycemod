-- The base of Sandcastle's editors (edit_gamerules, edit_roundtimer): a
-- Sandbox editor like the Sun, Fog and Sky editors (base_edit), spawned from
-- the Editors category, edited through its right-click "Edit Properties".
-- Only admins spawn or edit one, and a map has at most one of each. It
-- shows the game's current values, refreshed twice a second, and hands
-- each edit to the editors feature; its actions are right-click entries
-- (WETSAND.EditorAction).
--
-- A subclass lists its fields in ENT.Fields, each { name, type ("Int",
-- "Float" or "Bool"), title, category, min, max, read(editors) -> value,
-- write(editors, value), default }. A field without read is an input only
-- (an amount the actions use) and starts at its default.
AddCSLuaFile()
DEFINE_BASECLASS("base_edit")

ENT.Type = "anim"
ENT.Base = "base_edit"

ENT.Spawnable = false
ENT.AdminOnly = true
ENT.Category = "Editors"
ENT.Fields = {}

local MIRROR_INTERVAL = 0.5
local EDIT_TYPE = { Int = "Int", Float = "Float", Bool = "Boolean" }

function ENT:SetupDataTables()
	local slots = {}
	for order, field in ipairs(self.Fields) do
		local slot = slots[field.type] or 0
		slots[field.type] = slot + 1
		self:NetworkVar(field.type, slot, field.name, {
			KeyName = string.lower(field.name),
			Edit = {
				type = EDIT_TYPE[field.type],
				title = field.title,
				category = field.category,
				min = field.min,
				max = field.max,
				order = order,
			},
		})
		if SERVER then self:NetworkVarNotify(field.name, self.OnFieldEdited) end
	end
end

function ENT:CanEditVariables(ply)
	return ply:IsAdmin()
end

if CLIENT then return end

-- One editor of a kind per map.
function ENT:SpawnFunction(ply, tr, class)
	if IsValid(ents.FindByClass(class)[1]) then
		ply:ChatPrint("There is already a " .. self.PrintName .. " on this map")
		return
	end
	if not tr.Hit then return end
	local ent = ents.Create(class)
	ent:SetPos(tr.HitPos + tr.HitNormal * 16)
	ent:Spawn()
	ent:Activate()
	return ent
end

function ENT:Initialize()
	BaseClass.Initialize(self)
	self.editors = WETSAND.Feature("editors")
	self.fieldByName = {}
	self.mirroring = true
	for _, field in ipairs(self.Fields) do
		self.fieldByName[field.name] = field
		if not field.read and field.default ~= nil then self["Set" .. field.name](self, field.default) end
	end
	self.mirroring = false
	self:Mirror()
end

-- Show the game's values; setting them here is not an edit.
function ENT:Mirror()
	self.mirroring = true
	for _, field in ipairs(self.Fields) do
		if field.read then self["Set" .. field.name](self, field.read(self.editors)) end
	end
	self.mirroring = false
end

function ENT:OnFieldEdited(name, old, new)
	if self.mirroring or not self.editors or old == new then return end
	local field = self.fieldByName[name]
	if field.write then field.write(self.editors, new) end
end

function ENT:Think()
	self:Mirror()
	self:NextThink(CurTime() + MIRROR_INTERVAL)
	return true
end
