-- The model viewer's client runtime (addons/model_viewer/lua/) under stubbed
-- GMod globals: the stubs stand in for vgui, hooks and the model only as far as
-- the runtime touches them, so this checks its wiring (what opens it, which
-- sequence a click plays, the controls), not how anything draws.
local T = dofile("tests/harness.lua")
local ROOT = "addons/model_viewer/lua/"
package.path = ROOT .. "includes/modules/?.lua;" .. package.path
CLIENT, SERVER = true, false

LEFT, TOP, RIGHT, BOTTOM, FILL = 1, 2, 3, 4, 5
MOUSE_LEFT, MOUSE_RIGHT = 107, 108

local now = 0
function RealTime() return now end
function ScrW() return 1920 end
function ScrH() return 1080 end
function Vector(x, y, z) return { x = x, y = y, z = z } end
function IsValid(value) return value ~= nil and not value.removed end
function AddCSLuaFile() end
function include(path) return dofile(ROOT .. path) end

local printed = {}
function MsgN(...) printed[#printed + 1] = table.concat({ ... }, " ") end

local MODELS = {
	["models/player/scout.mdl"] = {
		sequences = {
			{ "ref", "", 0.5 },
			{ "run", "ACT_RUN", 2 },
			{ "jump", "ACT_JUMP", 4 },
		},
		poses = { { "move_x", -1, 1 }, { "body_yaw", -45, 45 } },
	},
	["models/props/crate.mdl"] = { sequences = {}, poses = {} },
}

-- As a real client answers: IsValidModel knows no model that is not yet loaded,
-- which is every model the viewer is asked for.
util = { IsValidModel = function() return false end }
file = { Exists = function(path, scope) return scope == "GAME" and MODELS[path] ~= nil end }

local function Entity(path)
	local spec = MODELS[path]
	local ent = { path = path, played = {}, poseValues = {}, cycle = 0 }
	function ent:GetModel() return self.path end
	function ent:GetSequenceCount() return #spec.sequences end
	function ent:GetSequenceName(i) return spec.sequences[i + 1][1] end
	function ent:GetSequenceActivityName(i) return spec.sequences[i + 1][2] end
	function ent:SequenceDuration(i) return spec.sequences[i + 1][3] end
	function ent:GetNumPoseParameters() return #spec.poses end
	function ent:GetPoseParameterName(i) return spec.poses[i + 1][1] end
	function ent:GetPoseParameterRange(i) return spec.poses[i + 1][2], spec.poses[i + 1][3] end
	function ent:SetPoseParameter(name, value) self.poseValues[name] = value end
	function ent:InvalidateBoneCache() end
	function ent:GetRenderBounds() return { x = -10, y = -10, z = 0 }, { x = 10, y = 10, z = 80 } end
	function ent:ResetSequence(sequence) self.played[#self.played + 1] = sequence end
	function ent:SetCycle(cycle) self.cycle = cycle end
	return ent
end

-- vgui: a panel is its registered table over its base's methods, over a base
-- that answers any other method (by its capital) with nothing; a field unset is nil.
local BASES = {}
local Registered = {}
vgui = {}

local function Lookup(class, key)
	while class do
		local definition = Registered[class] or BASES[class]
		if not definition then return nil end
		if definition.methods[key] ~= nil then return definition.methods[key] end
		class = definition.base
	end
	return nil
end

local function Ignored() end

function vgui.Create(class, parent)
	local panel = setmetatable({ class = class, parent = parent, children = {} }, {
		__index = function(_, key)
			local found = Lookup(class, key)
			if found ~= nil or key == "Entity" or not key:match("^%u") then return found end
			return Ignored
		end,
	})
	if parent then parent.children[#parent.children + 1] = panel end
	local init = Lookup(class, "Init")
	if init then init(panel) end
	return panel
end

function vgui.Register(name, methods, base)
	Registered[name] = { methods = methods, base = base }
end

local function Base(name, methods)
	BASES[name] = { methods = methods }
end

Base("Panel", {
	Add = function(self, class) return vgui.Create(class, self) end,
	Remove = function(self)
		self.removed = true
		for _, child in ipairs(self.children) do child:Remove() end
		if rawget(self, "OnRemove") then self:OnRemove() end
	end,
	GetTall = function() return 300 end,
})
BASES.DFrame = { base = "Panel", methods = {
	SetTitle = function(self, title) self.title = title end,
	MakePopup = function(self) self.popped = (self.popped or 0) + 1 end,
	MoveToFront = function(self) self.fronted = (self.fronted or 0) + 1 end,
} }
BASES.DModelPanel = { base = "Panel", methods = {
	SetModel = function(self, path) self.Entity = Entity(path) end,
	GetEntity = function(self) return self.Entity end,
	SetCamPos = function(self, pos) self.camPos = pos end,
	SetLookAt = function(self, pos) self.lookAt = pos end,
} }
BASES.DButton = { base = "Panel", methods = {
	SetText = function(self, text) self.text = text end,
	GetText = function(self) return self.text end,
} }
BASES.DLabel = BASES.DButton
BASES.DTextEntry = { base = "Panel", methods = {
	SetValue = function(self, value) self.value = value end,
	GetValue = function(self) return self.value or "" end,
} }
BASES.DCheckBoxLabel = { base = "Panel", methods = {
	SetValue = function(self, value) self.checked = value end,
	GetChecked = function(self) return self.checked end,
} }
BASES.DNumSlider = { base = "Panel", methods = {
	SetValue = function(self, value)
		if self.value == value then return end
		self.value = value
		self:OnValueChanged(value)
	end,
	GetValue = function(self) return self.value end,
	SetText = function(self, text) self.text = text end,
	IsEditing = function(self) return self.editing == true end,
} }
BASES.DScrollPanel = { base = "Panel", methods = {
	Clear = function(self)
		for _, child in ipairs(self.children) do child:Remove() end
		self.children = {}
	end,
} }
BASES.DListView = { base = "Panel", methods = {
	Init = function(self)
		self.lines = {}
		self.VBar = vgui.Create("Panel", self)
	end,
	Clear = function(self) self.lines = {} end,
	AddColumn = function(self) return vgui.Create("Panel", self) end,
	AddLine = function(self, ...)
		local line = { columns = { ... } }
		function line:SetSelected(on) self.selected = on end
		self.lines[#self.lines + 1] = line
		return line
	end,
	SelectItem = function(self, line)
		line.selected = true
		self:OnRowSelected(1, line)
	end,
	ClearSelection = function(self)
		for _, line in ipairs(self.lines) do line.selected = false end
	end,
	GetDataHeight = function() return 17 end,
} }

local hooks = {}
hook = { Add = function(event, id, fn) hooks[event] = hooks[event] or {}; hooks[event][id] = fn end }
local commands = {}
concommand = { Add = function(name, fn) commands[name] = fn end }
local lists = {}
list = { Set = function(group, name, value) lists[group] = lists[group] or {}; lists[group][name] = value end }

local me = { GetModel = function() return "models/player/scout.mdl" end }
function LocalPlayer() return me end

include("autorun/model_viewer.lua")

-- Finding what the window holds, by what it is.
local function Find(panel, class, match)
	for _, child in ipairs(panel.children) do
		if child.class == class and (not match or match(child)) then return child end
		local found = Find(child, class, match)
		if found then return found end
	end
	return nil
end

local function Button(window, text)
	return Find(window, "DButton", function(b) return b.text == text end)
end

local function Slider(window, text)
	return Find(window, "DNumSlider", function(s) return s.text == text end)
end

local function Run(text) commands.cl_model_viewer(me, "cl_model_viewer", {}, text) end

local function Stage(window) return Find(window, "ModelViewerStage") end
local function Rows(window) return Find(window, "DListView").lines end
local function Played(window) local p = Stage(window).Entity.played; return p[#p] end

-- Opening ------------------------------------------------------------------------

T.test("a bad model is refused by name, and no window opens", function()
	Run("models/nothing.mdl")
	T.eq(ModelViewer.window, nil, "no window")
	T.eq(printed[#printed]:find("models/nothing.mdl", 1, true) ~= nil, true, "says which")
end)

T.test("cl_model_viewer opens a window on the model, playing its first act", function()
	Run("player/scout")
	local window = ModelViewer.window
	T.eq(IsValid(window), true, "open")
	T.eq(window.popped, 1, "takes the mouse")
	T.eq(window.title:find("models/player/scout.mdl", 1, true) ~= nil, true, "the title names it")
	T.eq(Stage(window).Entity.path, "models/player/scout.mdl", "shows it")
	T.eq(#Rows(window), 3, "lists its sequences")
	T.eq(Rows(window)[1].columns[1], "ACT_JUMP", "acts first")
	T.eq(Played(window), 2, "plays the first")
	T.eq(Rows(window)[1].selected, true, "and shows it chosen")
end)

T.test("with no model named, it opens on the player's own", function()
	ModelViewer.window:Remove()
	Run("")
	T.eq(Stage(ModelViewer.window).Entity.path, "models/player/scout.mdl", "the player's model")
end)

T.test("opening another model takes over the open window", function()
	local window = ModelViewer.window
	Run("models/props/crate.mdl")
	T.eq(ModelViewer.window, window, "the same window")
	T.eq(window.fronted, 1, "brought forward")
	T.eq(Stage(window).Entity.path, "models/props/crate.mdl", "the new model")
	T.eq(#Rows(window), 0, "a model with no sequences lists none")
	Run("models/player/scout.mdl")
end)

T.test("a window takes a model typed into it, and says when it cannot", function()
	local window = ModelViewer.window
	local path = Find(window, "DTextEntry")
	path:SetValue("models/nothing.mdl")
	path:OnEnter()
	T.eq(Stage(window).Entity.path, "models/player/scout.mdl", "the model stays")
	T.eq(window.info.text:find("models/nothing.mdl", 1, true) ~= nil, true, "says which")
	path:SetValue("models/props/crate.mdl")
	path:OnEnter()
	T.eq(Stage(window).Entity.path, "models/props/crate.mdl", "takes a good one")
	Run("models/player/scout.mdl")
end)

-- Choosing what plays ---------------------------------------------------------------

T.test("clicking a row plays its sequence, from the start", function()
	local window = ModelViewer.window
	local list = Find(window, "DListView")
	Stage(window):Seek(0.5)
	list:OnRowSelected(2, Rows(window)[2])
	T.eq(Played(window), 1, "the run")
	T.eq(Stage(window).cycle, 0, "from its start")
	T.eq(window.info.text:find("ACT_RUN", 1, true) ~= nil, true, "names the act")
	T.eq(window.info.text:find("run", 1, true) ~= nil, true, "and the sequence")
end)

T.test("Next and Previous step through the rows and wrap", function()
	local window = ModelViewer.window
	local list = Find(window, "DListView")
	list:OnRowSelected(1, Rows(window)[1])
	Button(window, "Next"):DoClick()
	T.eq(Played(window), 1, "the second row")
	T.eq(Rows(window)[1].selected, false, "the first no longer chosen")
	T.eq(Rows(window)[2].selected, true, "the second chosen")
	Button(window, "Next"):DoClick()
	T.eq(Played(window), 0, "the third row")
	Button(window, "Next"):DoClick()
	T.eq(Played(window), 2, "round to the first")
	Button(window, "Previous"):DoClick()
	T.eq(Played(window), 0, "back round to the last")
end)

T.test("a search narrows the rows, and stepping stays within them", function()
	local window = ModelViewer.window
	local search = Find(window, "DTextEntry", function(e) return e ~= Find(window, "DTextEntry") end)
	search:SetValue("act_")
	search:OnChange()
	T.eq(#Rows(window), 2, "those with an act")
	Button(window, "Next"):DoClick()
	T.eq(Played(window), 2, "the first shown")
	Button(window, "Next"):DoClick()
	T.eq(Played(window), 1, "the second shown")
	Button(window, "Next"):DoClick()
	T.eq(Played(window), 2, "round again")
	search:SetValue("nothing like this")
	search:OnChange()
	T.eq(#Rows(window), 0, "no rows")
	local before = #Stage(window).Entity.played
	Button(window, "Next"):DoClick()
	T.eq(#Stage(window).Entity.played, before, "nothing to step to")
	search:SetValue("")
	search:OnChange()
	T.eq(#Rows(window), 3, "all back")
end)

-- Playing --------------------------------------------------------------------------

local function Tick(stage, seconds)
	now = now + seconds
	stage:LayoutEntity(stage.Entity)
end

T.test("each frame the model's cycle advances through what plays", function()
	local window = ModelViewer.window
	local stage = Stage(window)
	Find(window, "DListView"):OnRowSelected(1, Rows(window)[1]) -- jump, 4 seconds
	Tick(stage, 0)
	Tick(stage, 1)
	T.near(stage.Entity.cycle, 0.25, 1e-9, "a quarter of 4 seconds")
	T.near(Slider(window, "Frame").value, 0.25, 1e-9, "the slider follows")
end)

T.test("Pause holds the frame, and the button turns to Play", function()
	local window = ModelViewer.window
	local stage = Stage(window)
	local cycle = stage.cycle
	local pause = Button(window, "Pause")
	pause:DoClick()
	T.eq(pause.text, "Play", "offers Play")
	Tick(stage, 1)
	T.eq(stage.Entity.cycle, cycle, "held")
	pause:DoClick()
	T.eq(pause.text, "Pause", "offers Pause")
	Tick(stage, 1)
	T.near(stage.Entity.cycle, cycle + 0.25, 1e-9, "goes on, and the pause did not count")
end)

T.test("dragging the Frame slider moves the model and holds it there", function()
	local window = ModelViewer.window
	local stage = Stage(window)
	local frame = Slider(window, "Frame")
	frame.editing = true
	frame:SetValue(0.8)
	Tick(stage, 1)
	T.eq(stage.Entity.cycle, 0.8, "where it was dragged, held")
	T.eq(frame.value, 0.8, "the slider is left alone")
	frame.editing = false
	Tick(stage, 1)
	T.near(stage.Entity.cycle, 0.05, 1e-9, "plays on from there, wrapping")
end)

T.test("the speed slider sets the rate", function()
	local window = ModelViewer.window
	local stage = Stage(window)
	stage:Seek(0)
	Slider(window, "Speed"):SetValue(2)
	Tick(stage, 1)
	T.near(stage.Entity.cycle, 0.5, 1e-9, "twice as fast")
	Slider(window, "Speed"):SetValue(1)
end)

T.test("unticking Loop holds the last frame", function()
	local window = ModelViewer.window
	local stage = Stage(window)
	local loop = Find(window, "DCheckBoxLabel")
	T.eq(loop.checked, true, "loops at first")
	loop:OnChange(false)
	stage:Seek(0.9)
	Tick(stage, 1)
	T.eq(stage.Entity.cycle, 1, "stops at the end")
	loop:OnChange(true)
end)

T.test("a model's poses start set, and each has a slider", function()
	local window = ModelViewer.window
	local stage = Stage(window)
	T.eq(stage.Entity.poseValues.move_x, 1, "a walker walks")
	T.eq(stage.Entity.poseValues.body_yaw, 0, "the rest at rest")
	local yaw = Slider(window, "body_yaw")
	yaw:SetValue(30)
	T.eq(stage.Entity.poseValues.body_yaw, 30, "drives the pose")
end)

T.test("a new model's sliders replace the last one's", function()
	local window = ModelViewer.window
	Run("models/props/crate.mdl")
	T.eq(Slider(window, "body_yaw"), nil, "the crate has no poses")
	Run("models/player/scout.mdl")
	T.eq(Slider(window, "body_yaw") ~= nil, true, "the scout's are back")
end)

-- The camera --------------------------------------------------------------------------

T.test("dragging with the left button orbits, with the right lifts the view", function()
	local stage = Stage(ModelViewer.window)
	Tick(stage, 0)
	local cam, look = stage.camPos, stage.lookAt
	stage:OnMousePressed(MOUSE_LEFT)
	stage:OnCursorMoved(10, 10)
	stage:OnCursorMoved(60, 10)
	stage:OnMouseReleased(MOUSE_LEFT)
	Tick(stage, 0)
	T.eq(stage.camPos.x ~= cam.x or stage.camPos.y ~= cam.y, true, "the camera moved round")
	T.eq(stage.lookAt.z, look.z, "looking at the same place")
	stage:OnCursorMoved(90, 90)
	Tick(stage, 0)
	local moved = stage.camPos
	stage:OnCursorMoved(120, 120)
	Tick(stage, 0)
	T.eq(stage.camPos.x, moved.x, "the mouse up, moving it does nothing")
	stage:OnMousePressed(MOUSE_RIGHT)
	stage:OnCursorMoved(120, 120)
	stage:OnCursorMoved(120, 140)
	stage:OnMouseReleased(MOUSE_RIGHT)
	Tick(stage, 0)
	T.eq(stage.lookAt.z > look.z, true, "dragging down lifts the view")
end)

T.test("the wheel moves the camera nearer", function()
	local stage = Stage(ModelViewer.window)
	local before = stage.distance
	stage:OnMouseWheeled(1)
	T.eq(stage.distance < before, true, "nearer")
end)

-- The menus ----------------------------------------------------------------------------

local function Menu()
	local menu = { options = {} }
	function menu:AddOption(text, fn)
		local option = { text = text, fn = fn }
		function option:SetIcon(icon) self.icon = icon end
		self.options[#self.options + 1] = option
		return option
	end
	return menu
end

local function Spawnmenu(contentType, icon)
	local menu = Menu()
	for _, fn in pairs(hooks.SpawnmenuIconMenuOpen) do fn(menu, icon, contentType) end
	return menu
end

T.test("a model's icon in the spawn menu offers the viewer, on that model", function()
	ModelViewer.window:Remove()
	local menu = Spawnmenu("model", { GetModelName = function() return "models/props/crate.mdl" end })
	T.eq(#menu.options, 1, "one option")
	menu.options[1].fn()
	T.eq(Stage(ModelViewer.window).Entity.path, "models/props/crate.mdl", "opens on it")
end)

T.test("other icons do not offer it", function()
	T.eq(#Spawnmenu("entity", {}).options, 0, "an entity's")
	T.eq(#Spawnmenu("weapon", {}).options, 0, "a weapon's")
end)

T.test("the C menu's icon opens the viewer on the player's own model, in its own window", function()
	ModelViewer.window:Remove()
	local widget = lists.DesktopWindows.ModelViewer
	T.eq(type(widget.title), "string", "named")
	T.eq(type(widget.icon), "string", "pictured")
	T.eq(type(widget.width), "number", "the C menu sizes a window by this")
	T.eq(type(widget.height), "number", "the C menu sizes a window by this")
	local given = vgui.Create("DFrame")
	widget.init({}, given)
	T.eq(given.removed, true, "the C menu's own window goes: it would close with the menu")
	T.eq(Stage(ModelViewer.window).Entity.path, "models/player/scout.mdl", "the player's model")
end)

T.finish()
