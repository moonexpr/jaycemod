-- The AI War panel's slot list (foundation.aiwar.slots), for admins: a tree
-- a side, RED's and BLU's, of its squads (fire teams), each with its
-- soldiers' slots, the leader first, then the slots in no squad (the empty
-- ones among them). Select a slot, or a squad for every slot in it, and act
-- on it with the buttons below (mp_aiwar_slots_*, wetsand/sh_aiwar.lua).
-- The server sends the list (aiwar_slots) once the panel asks, and again
-- whenever it changes.
local Slots = WETSAND.require("foundation.aiwar.slots")
local E = WETSAND.Events

local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE
local TREE_HEIGHT = 280
local HEADER_HEIGHT = 20
local GAP = 4
local NO_SQUAD = "No squad"

local ICONS = {
	squad = "icon16/group.png",
	noSquad = "icon16/folder.png",
	leads = "icon16/star.png",
	follows = "icon16/user.png",
	empty = "icon16/user_gray.png",
}

local PIN_TAGS = {
	[Slots.LEADER] = " (pinned to lead)",
	[Slots.MEMBER] = " (pinned to follow)",
}

local CUSTOM_TEXT = "The slot list sets each side's size (mp_aiwar_team_size -1)."
local SIZED_TEXT = "Each side has mp_aiwar_team_size slots; adding or removing one switches to the slot list."

-- The lists built (one per panel), and the list the server last sent.
local lists = setmetatable({}, { __mode = "k" })
local last = nil

local function SoldierName(class)
	local stored = scripted_ents.Get(class)
	return stored and stored.PrintName or class
end

local function SlotLabel(row)
	local pin = PIN_TAGS[row.pin] or ""
	if row.index == 0 then return string.format("Slot %d: empty%s", row.id, pin) end
	return string.format("Slot %d: %s #%d, %s%s", row.id, SoldierName(row.class), row.index, row.role, pin)
end

local function SlotIcon(row)
	if row.index == 0 then return ICONS.empty end
	return row.leads and ICONS.leads or ICONS.follows
end

local function Ids(rows)
	local ids = {}
	for i, row in ipairs(rows) do ids[i] = row.id end
	return ids
end

local function Key(ids)
	return table.concat(ids, " ")
end

-- One side's tree, rebuilt; the node holding the slots selected before is
-- selected again.
local function Fill(list, side, entry)
	side.header:SetText(string.format("%s: the %s, %d slots", WETSAND.TeamName[entry.team], entry.faction, #entry.slots))
	local tree = side.tree
	tree:Clear()
	local selected = list.selected and list.selected.team == entry.team and Key(list.selected.ids)
	local reselect = nil
	local function Add(parent, text, icon, ids)
		local node = parent:AddNode(text, icon)
		node.slotIds = ids
		if Key(ids) == selected then reselect = node end
		return node
	end
	local shape = Slots.Tree(entry.slots)
	local branches = {}
	for _, squad in ipairs(shape.squads) do
		branches[#branches + 1] = {
			name = squad.name,
			icon = ICONS.squad,
			slots = squad.slots,
		}
	end
	if #shape.loose > 0 then
		branches[#branches + 1] = {
			name = NO_SQUAD,
			icon = ICONS.noSquad,
			slots = shape.loose,
		}
	end
	for _, branch in ipairs(branches) do
		local node = Add(tree, branch.name, branch.icon, Ids(branch.slots))
		for _, row in ipairs(branch.slots) do Add(node, SlotLabel(row), SlotIcon(row), { row.id }) end
		node:SetExpanded(true, true)
	end
	if reselect then tree:SetSelectedItem(reselect) end
end

local function Refresh(list)
	if last == nil then return end
	list.status:SetText(last.custom and CUSTOM_TEXT or SIZED_TEXT)
	for _, entry in ipairs(last.teams) do Fill(list, list.sides[entry.team], entry) end
end

E.Listen("aiwar_slots", "wetsand_aiwar_slots", function(fields)
	last = fields
	for list in pairs(lists) do
		if IsValid(list.container) then Refresh(list) end
	end
end)

local function Side(list, parent, team)
	local side = { team = team }
	side.panel = vgui.Create("DPanel", parent)
	side.panel:SetPaintBackground(false)
	side.header = vgui.Create("DLabel", side.panel)
	side.header:Dock(TOP)
	side.header:SetTall(HEADER_HEIGHT)
	side.header:SetDark(true)
	side.header:SetText(WETSAND.TeamName[team])
	side.tree = vgui.Create("DTree", side.panel)
	side.tree:Dock(FILL)
	-- one selection across both trees
	function side.tree.OnNodeSelected(_, node)
		list.selected = {
			team = team,
			ids = node.slotIds,
		}
		local other = list.sides[team == RED and BLUE or RED]
		other.tree:SetSelectedItem(nil)
	end
	return side
end

-- A button running the command with the selected slots' ids.
local function SelectedButton(panel, list, label, command)
	panel:Button(label).DoClick = function()
		if list.selected == nil then return end
		local args = {}
		for i, id in ipairs(list.selected.ids) do args[i] = tostring(id) end
		RunConsoleCommand(command, unpack(args))
		if command == "mp_aiwar_slots_remove" then list.selected = nil end
	end
end

function WETSAND.AiWarSlotList(panel)
	panel:Help("Slots: the soldiers each side keeps. Select a slot, or a squad for all its slots. "
		.. "A slot pinned to lead leads its squad; one pinned to follow never leads while another is in it.")
	if not LocalPlayer():IsAdmin() then
		panel:Help("The slot list is for admins.")
		return
	end
	local list = { sides = {} }
	list.status = panel:Help(SIZED_TEXT)
	list.container = vgui.Create("DPanel")
	list.container:SetTall(TREE_HEIGHT)
	list.container:SetPaintBackground(false)
	list.sides[RED] = Side(list, list.container, RED)
	list.sides[BLUE] = Side(list, list.container, BLUE)
	function list.container:PerformLayout(w, h)
		local half = (w - GAP) / 2
		list.sides[RED].panel:SetPos(0, 0)
		list.sides[RED].panel:SetSize(half, h)
		list.sides[BLUE].panel:SetPos(half + GAP, 0)
		list.sides[BLUE].panel:SetSize(half, h)
	end
	panel:AddItem(list.container)
	panel:Button("Add RED Slot", "mp_aiwar_slots_add", "RED")
	panel:Button("Add BLU Slot", "mp_aiwar_slots_add", "BLU")
	SelectedButton(panel, list, "Remove Selected", "mp_aiwar_slots_remove")
	SelectedButton(panel, list, "Pin Selected to Lead", "mp_aiwar_slots_leader")
	SelectedButton(panel, list, "Pin Selected to Follow", "mp_aiwar_slots_member")
	SelectedButton(panel, list, "Unpin Selected", "mp_aiwar_slots_unpin")
	lists[list] = true
	Refresh(list)
	E.Request("aiwar_slots_request", {})
end
