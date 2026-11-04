-- The viewer's window: the model on its stage beside the list of its sequences,
-- which a click, Next or Previous plays, with the controls of what is playing.
local Catalog = model_viewer_catalog

local WIDTH, HEIGHT = 1000, 660
local LIST_WIDTH = 420
local ROW_TALL, POSES_TALL, LOOP_WIDE = 26, 120, 60
local MAX_SPEED = 3

local PANEL = {}

local function Slider(parent, text, low, high, value, changed)
	local slider = vgui.Create("DNumSlider", parent)
	slider:Dock(BOTTOM)
	slider:SetText(text)
	slider:SetMin(low)
	slider:SetMax(high)
	slider:SetDecimals(2)
	slider.OnValueChanged = changed
	slider:SetValue(value)
	return slider
end

local function Button(parent, text, click)
	local button = vgui.Create("DButton", parent)
	button:Dock(LEFT)
	button:DockMargin(0, 0, 4, 0)
	button:SetText(text)
	button.DoClick = click
	return button
end

function PANEL:Init()
	self:SetSize(math.min(WIDTH, ScrW()), math.min(HEIGHT, ScrH()))
	self:SetSizable(true)
	self:SetMinWidth(640)
	self:SetMinHeight(420)
	self:Center()

	self.path = vgui.Create("DTextEntry", self)
	self.path:Dock(TOP)
	self.path:DockMargin(0, 0, 0, 4)
	self.path.OnEnter = function(entry) self:Take(entry:GetValue()) end

	self:BuildList()
	self:BuildStage()
end

function PANEL:BuildList()
	local side = vgui.Create("Panel", self)
	side:Dock(RIGHT)
	side:DockMargin(4, 0, 0, 0)
	side:SetWide(LIST_WIDTH)

	self.search = vgui.Create("DTextEntry", side)
	self.search:Dock(TOP)
	self.search:DockMargin(0, 0, 0, 4)
	self.search:SetPlaceholderText("Search acts and sequences")
	self.search:SetUpdateOnType(true)
	self.search.OnChange = function() self:Refill() end

	self.list = vgui.Create("DListView", side)
	self.list:Dock(FILL)
	self.list:SetMultiSelect(false)
	self.list:SetSortable(false) -- Next and Previous walk the rows in this order
	self.list:AddColumn("Act")
	self.list:AddColumn("Sequence")
	self.list:AddColumn("Seconds"):SetFixedWidth(60)
	self.list.OnRowSelected = function(_, _, line) self:Choose(line) end
end

function PANEL:BuildStage()
	local main = vgui.Create("Panel", self)
	main:Dock(FILL)

	-- First: the sliders below tell it their values as they are made. A docked
	-- FILL takes what the others leave, whatever the order.
	self.stage = vgui.Create("ModelViewerStage", main)
	self.stage:Dock(FILL)
	self.stage.IsHeld = function() return self.frameSlider:IsEditing() end
	self.stage.OnCycle = function(_, cycle)
		if not self.frameSlider:IsEditing() then self.frameSlider:SetValue(cycle) end
	end

	self.info = vgui.Create("DLabel", main)
	self.info:Dock(TOP)
	self.info:SetText("")

	self.poseSliders = vgui.Create("DScrollPanel", main)
	self.poseSliders:Dock(BOTTOM)
	self.poseSliders:SetTall(POSES_TALL)

	self.frameSlider = Slider(main, "Frame", 0, 1, 0, function(slider, value)
		if slider:IsEditing() then self.stage:Seek(value) end
	end)
	Slider(main, "Speed", 0, MAX_SPEED, 1, function(_, value) self.stage.rate = value end)

	local row = vgui.Create("Panel", main)
	row:Dock(BOTTOM)
	row:SetTall(ROW_TALL)
	row:DockPadding(0, 2, 0, 2)
	Button(row, "Previous", function() self:Step(-1) end)
	Button(row, "Pause", function(button)
		self.stage.paused = not self.stage.paused
		button:SetText(self.stage.paused and "Play" or "Pause")
	end)
	Button(row, "Next", function() self:Step(1) end)
	local loop = vgui.Create("DCheckBoxLabel", row)
	loop:Dock(LEFT)
	loop:DockMargin(4, 2, 0, 0)
	loop:SetWide(LOOP_WIDE)
	loop:SetText("Loop")
	loop:SetValue(true)
	loop.OnChange = function(_, on) self.stage.loop = on end
end

-- Text typed into the window: a model to show, or why it cannot be.
function PANEL:Take(text)
	local path, why = ModelViewer.Resolve(text)
	if path then self:Load(path) else self.info:SetText(why) end
end

function PANEL:Load(path)
	self:SetTitle("Model Viewer: " .. path)
	self.path:SetValue(path)
	self.stage:ShowModel(path)
	self.entries = Catalog.Sequences(self.stage:GetEntity())
	self:BuildPoses()
	self.info:SetText("")
	self.search:SetValue("")
	self:Refill()
	self:Step(1)
end

function PANEL:BuildPoses()
	self.poseSliders:Clear()
	for _, pose in ipairs(self.stage.poses) do
		local slider = vgui.Create("DNumSlider", self.poseSliders)
		slider:Dock(TOP)
		slider:SetText(pose.name)
		slider:SetMin(pose.min)
		slider:SetMax(pose.max)
		slider:SetDecimals(2)
		slider:SetValue(pose.value)
		slider.OnValueChanged = function(_, value) self.stage:Pose(pose.name, value) end
	end
end

-- The rows again, for what the search keeps; nothing chosen among them.
function PANEL:Refill()
	self.list:Clear()
	self.lines, self.place = {}, nil
	for place, entry in ipairs(Catalog.Matching(self.entries, self.search:GetValue())) do
		local line = self.list:AddLine(entry.act, entry.name, string.format("%.2f", entry.seconds))
		line.entry, line.place = entry, place
		self.lines[place] = line
	end
end

function PANEL:Choose(line)
	self.place = line.place
	self.stage:Play(line.entry)
	local entry = line.entry
	self.info:SetText(string.format("%s  %s  %.2f s", entry.act, entry.name, entry.seconds))
end

function PANEL:Step(by)
	local place = Catalog.Step(#self.lines, self.place, by)
	if not place then return end
	self.list:ClearSelection()
	self.list:SelectItem(self.lines[place])
	self.list.VBar:AnimateTo((place - 1) * self.list:GetDataHeight() - self.list:GetTall() / 2, 0.1)
end

vgui.Register("ModelViewerWindow", PANEL, "DFrame")
