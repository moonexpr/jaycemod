AddCSLuaFile()

TOOL.Category = "NextSoldier"
TOOL.Name = "#tool.ns_squadcreator.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar = {
	order = "Muster",
	spacing = "1",
}

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" },
}

local SQUAD_MEMBER = "npc_squadmember"
local LIFT = Vector(0, 0, 1)

local ORDER_NAMES = {
	Muster = "Muster at the aim",
	FallBack = "Fall back to the aim, away from you",
}

if CLIENT then
	language.Add("tool.ns_squadcreator.name", "Squad Creator")
	language.Add("tool.ns_squadcreator.desc", "Give a group of squad members orders, and see where the legs would put each")
	language.Add("tool.ns_squadcreator.left", "Spawn a squad member, or add/remove one from your selection")
	language.Add("tool.ns_squadcreator.right", "Give the selected members the chosen order here")
	language.Add("tool.ns_squadcreator.reload", "Dissolve the selected members and clear your selection")
end

local selections = setmetatable({}, { __mode = "k" })

local function Selection(ply)
	local selected = selections[ply]
	if not selected then
		selected = {}
		selections[ply] = selected
	end
	return selected
end

-- The members of a selection still there, in the order of their indexes.
local function Members(selected)
	local members = {}
	for member in pairs(selected) do
		if IsValid(member) then members[#members + 1] = member else selected[member] = nil end
	end
	table.sort(members, function(a, b) return a:EntIndex() < b:EntIndex() end)
	return members
end

local function Select(member, selected, on)
	selected[member] = on or nil
	member:SetNW2Bool("NSSquadSelected", on)
end

function TOOL:LeftClick(trace)
	if CLIENT then return true end
	local ply = self:GetOwner()
	if not IsValid(ply) then return false end

	local selected = Selection(ply)
	local hit = trace.Entity
	if IsValid(hit) and hit:GetClass() == SQUAD_MEMBER then
		Select(hit, selected, not selected[hit])
		return true
	end
	if not trace.Hit or trace.HitSky then return false end

	local member = ents.Create(SQUAD_MEMBER)
	if not IsValid(member) then
		ply:ChatPrint("[Squad Creator] Could not create " .. SQUAD_MEMBER .. ".")
		return false
	end
	member.NSLaneTeam = WS.TeamOf(ply) or WS.TEAM_UNASSIGNED
	member:SetNW2Int("ws_team", member.NSLaneTeam)
	member:SetPos(trace.HitPos + LIFT)
	member:Spawn()
	member:Activate()
	ply:AddCleanup("ns_squadcreator", member)
	undo.Create("Squad Member")
	undo.AddEntity(member)
	undo.SetPlayer(ply)
	undo.Finish()
	Select(member, selected, true)
	return true
end

local function Point(v) return { x = v.x, y = v.y, z = v.z } end

function TOOL:RightClick(trace)
	if CLIENT then return true end
	local ply = self:GetOwner()
	if not IsValid(ply) or not trace.Hit or trace.HitSky then return false end

	local members = Members(Selection(ply))
	if #members == 0 then
		ply:ChatPrint("[Squad Creator] Spawn or select a squad member with left-click first.")
		return false
	end
	local Legs = nextsoldier.behavior.group_identity
	local point = Point(trace.HitPos)
	local order
	if self:GetClientInfo("order") == "FallBack" then
		order = Legs.FallBack(point, Point(ply:GetPos()))
		if not order then
			ply:ChatPrint("[Squad Creator] A fall back needs a point away from you: aim further off.")
			return false
		end
	else
		order = Legs.Muster(point)
	end
	local positions = {}
	for i, member in ipairs(members) do positions[i] = Point(member:GetPos()) end
	local places = order:Places(positions, nextsoldier.engine.GroupSpacing(), members[1]:NSLegsAdmit(trace.HitPos))
	for i, member in ipairs(members) do member:NSLegsGive(order, places[i]) end
	return true
end

function TOOL:Reload()
	if CLIENT then return true end
	local ply = self:GetOwner()
	if not IsValid(ply) then return false end
	local selected = Selection(ply)
	for _, member in ipairs(Members(selected)) do
		member:NSLegsGive(nil)
		Select(member, selected, false)
	end
	return true
end

function TOOL.BuildCPanel(panel)
	panel:Help("A test of the legs alone: members stand still and a cross shows where an order would put each, red at its feet where no place near had room. A place is only where a body fits with no wall between it and the order's point. Left-click to spawn or select, right-click to give the order, reload to dissolve.")
	local combo = panel:ComboBox("Order", "ns_squadcreator_order")
	for order, name in pairs(ORDER_NAMES) do combo:AddChoice(name, order) end
	panel:CheckBox("Show spacing (a ring its radius, pink with an arrow when a teammate pushes)", "ns_squadcreator_spacing")
end
