-- The AI War panel's slot list (foundation.aiwar.slots), for admins, for
-- testing how squads work:
-- - a slider a side over its slots (mp_aiwar_slots_size);
-- - switches: every soldier paused (ns_soldiers_paused), and whether the
--   war forms squads itself (ns_squads_auto_enabled);
-- - a tree a side, RED's and BLU's, of its squads (fire teams), each with
--   its soldiers' slots, the leader first, then the slots in no squad.
--   Click to select, Ctrl+click to add to the selection (a squad picks all
--   its soldiers; the first picked leads a squad formed from them); the
--   buttons and the right-click menu form, join and leave squads
--   (ns_squads_*), give jobs by hand (ns_jobs_*), pin and remove slots
--   (a squad's or the No squad folder's all at once), and debug a soldier
--   as its own context menu does (ws/cl_nb_menu.lua).
-- The server sends the list (game_aiwar_slots) once the panel asks, and again
-- whenever it changes.
local Slots = WS.require("foundation.aiwar.slots")
local Squad = WS.require("games.ns.squad")
local E = WS.Events

local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE
local TREE_HEIGHT = 300
local HEADER_HEIGHT = 20
local GAP = 4
local SEND_AFTER = 0.4 -- a slider sends once the player stops dragging
local NO_SQUAD = "No squad"

local ICONS = {
	squad = "icon16/group.png",
	noSquad = "icon16/folder.png",
	leads = "icon16/star.png",
	follows = "icon16/user.png",
	empty = "icon16/user_gray.png",
	form = "icon16/group_add.png",
	join = "icon16/group_go.png",
	leave = "icon16/group_delete.png",
	job = "icon16/wrench.png",
	remove = "icon16/delete.png",
}

local PIN_TAGS = {
	[Squad.LEADER] = ", pinned to lead",
	[Squad.MEMBER] = ", pinned to follow",
}

-- The pins a slot may be given (its menu option is checked for a slot so pinned).
local PINS = {
	{
		label = "Pin to Lead",
		command = "mp_aiwar_slots_leader",
		icon = "icon16/star.png",
		pin = Squad.LEADER,
	},
	{
		label = "Pin to Follow",
		command = "mp_aiwar_slots_member",
		icon = "icon16/user.png",
		pin = Squad.MEMBER,
	},
	{
		label = "Unpin",
		command = "mp_aiwar_slots_unpin",
		icon = "icon16/user_gray.png",
		pin = Slots.NONE,
	},
}

local CUSTOM_TEXT = "The sliders set each side's slots (mp_aiwar_team_size -1)."
local SIZED_TEXT = "Each side has mp_aiwar_team_size slots; moving a slider sets each side's own."

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
	local job = row.job_by_hand and row.role .. " (by hand)" or row.role
	return string.format("Slot %d: %s #%d, %s%s", row.id, SoldierName(row.class), row.index, job, pin)
end

local function SlotIcon(row)
	if row.index == 0 then return ICONS.empty end
	return row.leads and ICONS.leads or ICONS.follows
end

local function Strings(numbers)
	local strings = {}
	for i, n in ipairs(numbers) do strings[i] = tostring(n) end
	return strings
end

local function Run(command, ...)
	RunConsoleCommand(command, unpack(Strings({ ... })))
end

-------------------------------------------------------------------------------
-- Selection: the nodes picked, on one side, in the order picked

local function Pick(list, side, nodes)
	for _, node in ipairs(list.picked or {}) do
		if IsValid(node) then node:SetSelected(false) end
	end
	list.pickedSide, list.picked = side, nodes
	for _, node in ipairs(nodes) do node:SetSelected(true) end
end

local function Toggle(list, side, node)
	if list.pickedSide ~= side then return Pick(list, side, { node }) end
	local nodes, found = {}, false
	for _, each in ipairs(list.picked) do
		if each == node then found = true else nodes[#nodes + 1] = each end
	end
	if not found then nodes[#nodes + 1] = node end
	Pick(list, side, nodes)
end

-- The soldiers picked, as their rows, in the order picked.
local function Soldiers(list)
	local groups = {}
	for _, node in ipairs(list.picked or {}) do
		if IsValid(node) then groups[#groups + 1] = node.rows end
	end
	return Slots.Picked(groups)
end

local function Indexes(rows)
	local indexes = {}
	for i, row in ipairs(rows) do indexes[i] = row.index end
	return indexes
end

-- The slots picked (empty ones too), as their ids.
local function SlotIds(list)
	local ids, seen = {}, {}
	for _, node in ipairs(list.picked or {}) do
		for _, row in ipairs(IsValid(node) and node.rows or {}) do
			if not seen[row.id] then
				seen[row.id] = true
				ids[#ids + 1] = row.id
			end
		end
	end
	return ids
end

-------------------------------------------------------------------------------
-- Squads and jobs of the soldiers picked

-- A squad of the soldiers: `leader` (a row, or nil for the first) leads.
local function FormSquad(soldiers, leader)
	if #soldiers == 0 then return end
	leader = leader or soldiers[1]
	local indexes = { leader.index }
	for _, row in ipairs(soldiers) do
		if row ~= leader then indexes[#indexes + 1] = row.index end
	end
	Run("ns_squads_form", unpack(indexes))
end

local function LeaveSquad(soldiers)
	if #soldiers > 0 then Run("ns_squads_leave", unpack(Indexes(soldiers))) end
end

-- The squads on a side, by name, with a soldier in each to name it by.
local function SquadsOf(side)
	local squads = {}
	if last == nil then return squads end
	for _, entry in ipairs(last.teams) do
		if entry.team == side then
			for _, squad in ipairs(Slots.Tree(entry.slots).squads) do
				local soldiers = Slots.Picked({ squad.slots })
				if #soldiers > 0 then
					squads[#squads + 1] = {
						name = squad.name,
						soldier = soldiers[1],
					}
				end
			end
		end
	end
	return squads
end

local function AllDo(soldiers, job)
	for _, row in ipairs(soldiers) do
		if row.role ~= job then return false end
	end
	return #soldiers > 0
end

-- The right-click menu over what is picked (the node clicked, if it was not).
local function OpenMenu(list, side, node)
	local inPicked = false
	for _, each in ipairs(list.picked or {}) do inPicked = inPicked or each == node end
	if not inPicked or list.pickedSide ~= side then Pick(list, side, { node }) end
	local soldiers = Soldiers(list)
	local menu = DermaMenu()
	if #soldiers > 0 then
		local clicked = node.row and node.row.index > 0 and node.row or nil
		menu:AddOption(#soldiers > 1 and "New Squad of the Selection" or "New Squad Led by This Soldier", function()
			FormSquad(soldiers, clicked)
		end):SetIcon(ICONS.form)
		local join, joinOption = menu:AddSubMenu("Join Squad")
		joinOption:SetIcon(ICONS.join)
		for _, squad in ipairs(SquadsOf(side)) do
			join:AddOption(string.format("%s (#%d)", squad.name, squad.soldier.index), function()
				Run("ns_squads_join", squad.soldier.index, unpack(Indexes(soldiers)))
			end)
		end
		menu:AddOption("Leave Squad", function() LeaveSquad(soldiers) end):SetIcon(ICONS.leave)
		local jobs, jobOption = menu:AddSubMenu("Job")
		jobOption:SetIcon(ICONS.job)
		for _, job in ipairs(last and last.jobs or {}) do
			jobs:AddOption(job, function() RunConsoleCommand("ns_jobs_assign", job, unpack(Strings(Indexes(soldiers)))) end)
				:SetChecked(AllDo(soldiers, job))
		end
		jobs:AddSpacer()
		jobs:AddOption("Hand Back to the War", function() Run("ns_jobs_release", unpack(Indexes(soldiers))) end)
		menu:AddSpacer()
	end
	local ids = SlotIds(list)
	for _, pin in ipairs(PINS) do
		local option = menu:AddOption(pin.label, function() Run(pin.command, unpack(ids)) end)
		option:SetIcon(pin.icon)
		if node.row then option:SetChecked(node.row.pin == pin.pin) end
	end
	menu:AddSpacer()
	menu:AddOption(#ids > 1 and string.format("Remove %d Slots and Their Soldiers", #ids) or "Remove Slot and Its Soldier", function()
		Run("mp_aiwar_slots_remove", unpack(ids))
		Pick(list, side, {})
	end):SetIcon(ICONS.remove)
	if #soldiers == 1 then
		menu:AddSpacer()
		menu:AddOption("Spectate NPC", function() Run("ws_spectate_npc", soldiers[1].index) end):SetIcon("icon16/eye.png")
	end
	-- one soldier: the debugging its NPC's own context menu offers
	if #soldiers == 1 and WS.NpcDebugAllowed(LocalPlayer()) then
		WS.NpcSelectOption(menu, soldiers[1].index)
		local debug, debugOption = menu:AddSubMenu("Debug NPC")
		debugOption:SetIcon("icon16/bug.png")
		WS.NpcDebugMenu(debug, soldiers[1].index, true)
	end
	menu:Open()
end

-------------------------------------------------------------------------------
-- The trees and sliders

-- One side's tree, rebuilt; the slots picked before are picked again.
local function Fill(list, side, entry)
	side.header:SetText(string.format("%s: the %s, %d slots", WS.TeamName[entry.team], entry.faction, #entry.slots))
	local before = {}
	if list.pickedSide == entry.team then
		for i, node in ipairs(list.picked) do before[i] = node.key end
	end
	local byKey = {}
	local tree = side.tree
	tree:Clear()
	local function Add(parent, text, icon, rows, key, row)
		local node = parent:AddNode(text, icon)
		node.rows, node.key, node.row = rows, key, row
		byKey[key] = node
		return node
	end
	local shape = Slots.Tree(entry.slots)
	local branches = {}
	for _, squad in ipairs(shape.squads) do
		local byHand = false
		for _, row in ipairs(squad.slots) do byHand = byHand or row.squad_by_hand end
		branches[#branches + 1] = {
			name = squad.name .. (byHand and " (by hand)" or ""),
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
		local node = Add(tree, branch.name, branch.icon, branch.slots, "squad " .. branch.name)
		for _, row in ipairs(branch.slots) do Add(node, SlotLabel(row), SlotIcon(row), { row }, "slot " .. row.id, row) end
		node:SetExpanded(true, true)
	end
	if list.pickedSide == entry.team then
		local nodes = {}
		for _, key in ipairs(before) do
			if byKey[key] then nodes[#nodes + 1] = byKey[key] end
		end
		Pick(list, entry.team, nodes)
	end
end

-- A slider follows the server's count unless the player is dragging it; a
-- count past its range shows at its end, and is not sent back.
local function Follow(slider, count)
	if slider:IsEditing() then return end
	slider.serverCount = math.Clamp(count, Slots.SLIDER_MIN, Slots.SLIDER_MAX)
	slider:SetValue(slider.serverCount)
end

local function Refresh(list)
	if last == nil then return end
	list.status:SetText(last.custom and CUSTOM_TEXT or SIZED_TEXT)
	for _, entry in ipairs(last.teams) do
		Fill(list, list.sides[entry.team], entry)
		Follow(list.sliders[entry.team], #entry.slots)
	end
end

E.Listen("game_aiwar_slots", "ws_aiwar_slots", function(fields)
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
	side.header:SetText(WS.TeamName[team])
	side.tree = vgui.Create("DTree", side.panel)
	side.tree:Dock(FILL)
	-- a click picks the node alone; Ctrl+click adds it to the pick, or takes it out
	function side.tree.DoClick(_, node)
		if input.IsControlDown() then
			Toggle(list, team, node)
			return true
		end
		Pick(list, team, { node })
		return false
	end
	function side.tree.DoRightClick(_, node)
		OpenMenu(list, team, node)
		return true
	end
	return side
end

local function SlotSlider(panel, team)
	local name = WS.TeamName[team]
	local slider = panel:NumSlider(name .. " slots", nil, Slots.SLIDER_MIN, Slots.SLIDER_MAX, 0)
	function slider:OnValueChanged(value)
		local count = math.Round(value)
		-- nothing is sent before the server's count came, or for the count it sent
		if self.serverCount == nil or count == self.serverCount then return end
		timer.Create("ws_aiwar_slots_" .. name, SEND_AFTER, 1, function()
			RunConsoleCommand("mp_aiwar_slots_size", name, tostring(count))
		end)
	end
	return slider
end

function WS.AiWarSlotList(panel)
	panel:Help("Testing squads: pause the soldiers, turn the war's own squads off, dissolve them, and form your own. "
		.. "Click a slot to select it, Ctrl+click to add more (a squad selects all its soldiers); right-click for more.")
	if not WS.Can(LocalPlayer(), WS.require("games.system.permissions").NEXTSOLDIER) then
		panel:Help("The slot list is for admins.")
		return
	end
	local list = {
		sides = {},
		sliders = {},
	}
	list.status = panel:Help(SIZED_TEXT)
	list.sliders[RED] = SlotSlider(panel, RED)
	list.sliders[BLUE] = SlotSlider(panel, BLUE)
	WS.ServerCheckBox(panel, "Pause every soldier", "ns_soldiers_paused")
	WS.ServerCheckBox(panel, "The war forms squads itself", "ns_squads_auto_enabled")
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
	panel:Button("New Squad of the Selection (first picked leads)").DoClick = function() FormSquad(Soldiers(list), nil) end
	panel:Button("Leave Squad (Selection)").DoClick = function() LeaveSquad(Soldiers(list)) end
	panel:Button("Dissolve All Squads", "ns_squads_dissolve")
	lists[list] = true
	Refresh(list)
	E.Request("game_aiwar_slots_request", {})
end
