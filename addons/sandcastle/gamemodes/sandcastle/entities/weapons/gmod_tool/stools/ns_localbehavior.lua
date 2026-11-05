AddCSLuaFile()

TOOL.Category = "NextSoldier"
TOOL.Name = "#tool.ns_localbehavior.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar = {
	order = "Muster",
	mode = "0",
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

-- The squad's mode (the legs' MODE, one whole number a squad), what its members do about their
-- places: the menu's names by number.
local MODE_NAMES = {
	[0] = "Stationary: wait at their places",
	[1] = "Alert: patrol round the point, each on its side",
	[2] = "Cautious: wander near their places",
	[3] = "Panic: make for the way out furthest from the threat",
}

-- The doors of the room at point, from the AI war's rooms where they are found, as the ways out
-- a panicked squad makes for; nil where none are known.
local function Exits(point)
	local controller = WS.Feature("aiwar")
	local rooms = controller and controller.rooms
	local area = navmesh.GetNearestNavArea(Vector(point.x, point.y, point.z))
	local room = rooms and IsValid(area) and wartactics.rooms.RoomOf(rooms, area:GetID())
	if not (room and room.doors and room.doors[1]) then return nil end
	local exits = {}
	for i, door in ipairs(room.doors) do exits[i] = door.pos end
	return exits
end

if CLIENT then
	language.Add("tool.ns_localbehavior.name", "Local Behavior Tool")
	language.Add("tool.ns_localbehavior.desc", "Inspect how members place themselves within a room or enclosed area: muster, fall back, spacing")
	language.Add("tool.ns_localbehavior.left", "Spawn a squad member, or add/remove one from your selection")
	language.Add("tool.ns_localbehavior.right", "Give the selected members the chosen order here")
	language.Add("tool.ns_localbehavior.reload", "Dissolve the selected members and clear your selection")
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
		ply:ChatPrint("[Local Behavior] Could not create " .. SQUAD_MEMBER .. ".")
		return false
	end
	member.NSLaneTeam = WS.TeamOf(ply) or WS.TEAM_UNASSIGNED
	member:SetNW2Int("ws_team", member.NSLaneTeam)
	member:SetPos(trace.HitPos + LIFT)
	member:Spawn()
	member:Activate()
	ply:AddCleanup("ns_localbehavior", member)
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
		ply:ChatPrint("[Local Behavior] Spawn or select a squad member with left-click first.")
		return false
	end
	local Legs = nextsoldier.behavior.group_identity
	local point = Point(trace.HitPos)
	local order
	if self:GetClientInfo("order") == "FallBack" then
		order = Legs.FallBack(point, Point(ply:GetPos()))
		if not order then
			ply:ChatPrint("[Local Behavior] A fall back needs a point away from you: aim further off.")
			return false
		end
	else
		order = Legs.Muster(point)
	end
	order:SetMode(Legs.MODE(self:GetClientNumber("mode")) or Legs.MODE.STATIONARY)
	order:SetExits(Exits(point))
	local positions = {}
	for i, member in ipairs(members) do positions[i] = Point(member:GetPos()) end
	local places = order:Places(positions, nextsoldier.engine.GroupSpacing(), members[1]:NSLegsAdmit(trace.HitPos))
	for i, member in ipairs(members) do member:NSLegsGive(order, places[i]) end
	return true
end

-- The selected members' squads take the menu's mode as it changes.
function TOOL:Think()
	if CLIENT then return end
	local selected = selections[self:GetOwner()]
	if not selected then return end
	-- the menu's number, parsed: one the legs do not know (typed in the console) changes nothing
	local mode = nextsoldier.behavior.group_identity.MODE(self:GetClientNumber("mode"))
	if not mode then return end
	for _, member in ipairs(Members(selected)) do
		local order = member:NSLegsOrder()
		if order and order.mode ~= mode then order:SetMode(mode) end
	end
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
	local combo = panel:ComboBox("Order", "ns_localbehavior_order")
	for order, name in pairs(ORDER_NAMES) do combo:AddChoice(name, order) end
	panel:Help("The squad's mode: where each member goes about its place. A white ring is where it is going now, and its path there is drawn. A panicked squad makes for the doors of the room it is in, where the AI war has found the map's rooms, else away from you.")
	local mode = panel:ComboBox("Mode", "ns_localbehavior_mode")
	for number = 0, 3 do mode:AddChoice(MODE_NAMES[number], number) end
	panel:CheckBox("Show spacing (a ring its radius, pink with an arrow when a teammate pushes)", "ns_localbehavior_spacing")
end
