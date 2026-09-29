-- The team select screen (CTFTeamMenu, resource/ui/Teammenu.res) for any
-- game's teams. WETSAND.TeamRules.TeamMenu decides the choices; this file draws
-- them and sends jointeam, which the server checks again. TF2's configuration
-- (BLU left, RED right, its hotkeys) is at the bottom.
local L = WETSAND.TeamRules

-- Teammenu.res lays the screen out in units of 480 to the screen's height:
-- doors 124 x 310 at y 101 with the team counts above them, the spectate
-- box 82 x 57 at y 232, and a shaded bar 50 high along the bottom.
local UNIT = 480
local DOOR_W, DOOR_Y, DOOR_H, HEADER = 124, 101, 310, 48
local BOX_W, BOX_Y, BOX_H, BOX_LABEL = 82, 232, 57, 20
local GAP, TEAM_GAP = 28, 64
local BAR_H, CANCEL_W, CANCEL_H = 50, 150, 30
local REFRESH = 0.1 -- CTFTeamMenu's tick signal: every 100 ms

local TEXT = Color(235, 227, 203)
local BACKDROP = Color(24, 21, 19, 245)
local BAR = Color(0, 0, 0, 200)
local DISABLED = Color(75, 72, 68)
local SHADE = Color(0, 0, 0, 170)

local function CreateFonts()
	local s = ScrH() / UNIT
	surface.CreateFont("Sandcastle.TeamMenu.Title", { font = "Coolvetica", size = math.Round(26 * s) })
	surface.CreateFont("Sandcastle.TeamMenu.Count", { font = "Coolvetica", size = math.Round(34 * s) })
	surface.CreateFont("Sandcastle.TeamMenu.Name", { font = "Coolvetica", size = math.Round(30 * s) })
	surface.CreateFont("Sandcastle.TeamMenu.Label", { font = "Coolvetica", size = math.Round(16 * s) })
	surface.CreateFont("Sandcastle.TeamMenu.Small", { font = "Roboto", size = math.Round(9 * s), weight = 800 })
end
CreateFonts()

local function Scale(c, f)
	return Color(math.min(255, c.r * f), math.min(255, c.g * f), math.min(255, c.b * f), c.a)
end

local function Rect(color, x, y, w, h)
	surface.SetDrawColor(color)
	surface.DrawRect(x, y, w, h)
end

local function Band(text, font, w, y, s)
	Rect(SHADE, 0, y - 11 * s, w, 22 * s)
	draw.SimpleText(text, font, w / 2, y, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- A choice: a door (a team, auto-assign) or the spectate box -----------------------

local CHOICE = {}

function CHOICE:Init()
	self:SetText("")
	self:SetKeyboardInputEnabled(false) -- the keys belong to the menu
end

-- choice: an entry of L.TeamMenu; scale: pixels per layout unit.
function CHOICE:SetChoice(choice, scale)
	self.choice, self.scale = choice, scale
	self:SetEnabled(choice.enabled)
end

function CHOICE:DoClick()
	self:GetParent():Choose(self.choice)
end

function CHOICE:BodyColor()
	local c = self.choice
	if not c.enabled then return DISABLED end
	if self:IsHovered() then return Scale(c.color, 1.3) end
	return c.color
end

function CHOICE:DrawHotkey(x, y)
	local s = self.scale
	Rect(SHADE, x, y, 14 * s, 14 * s)
	draw.SimpleText(self.choice.hotkey, "Sandcastle.TeamMenu.Small", x + 7 * s, y + 7 * s, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- A panelled door in the choice's colour below the header.
function CHOICE:DrawDoor(w, h, top)
	local s, color = self.scale, self:BodyColor()
	local inset, body = 6 * s, h - top
	Rect(Scale(color, 0.45), 0, top, w, body)
	Rect(color, inset, top + inset, w - 2 * inset, body - 2 * inset)
	local panel = Scale(color, 0.8)
	Rect(panel, 2 * inset, top + 2 * inset, w - 4 * inset, body * 0.34)
	Rect(panel, 2 * inset, top + body * 0.42, w - 4 * inset, body * 0.34)
	Rect(Scale(color, 0.5), w - 5 * inset, top + body * 0.5, 2 * inset, 2 * inset) -- the knob
	self:DrawHotkey(2 * inset, top + 2 * inset)
end

function CHOICE:DrawMarks(w, h, top)
	local c, s = self.choice, self.scale
	if c.current then
		surface.SetDrawColor(TEXT)
		surface.DrawOutlinedRect(0, top, w, h - top, math.max(1, math.Round(2 * s)))
		Band("YOUR TEAM", "Sandcastle.TeamMenu.Small", w, h - 20 * s, s)
	end
	if c.reason then Band(string.upper(c.reason), "Sandcastle.TeamMenu.Small", w, top + (h - top) * 0.2, s) end
end

local PAINT = {}

function PAINT.team(self, w, h)
	local c, s = self.choice, self.scale
	local top = HEADER * s
	draw.SimpleText(c.count, "Sandcastle.TeamMenu.Count", w / 2, top / 2, c.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	self:DrawDoor(w, h, top)
	draw.SimpleText(c.label, "Sandcastle.TeamMenu.Name", w / 2, top + (h - top) * 0.82, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	self:DrawMarks(w, h, top)
end

function PAINT.auto(self, w, h)
	local c, s = self.choice, self.scale
	local top = HEADER * s
	draw.SimpleText(c.label, "Sandcastle.TeamMenu.Label", w / 2, top / 2, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	self:DrawDoor(w, h, top)
	draw.SimpleText("?", "Sandcastle.TeamMenu.Count", w / 2, top + (h - top) * 0.5, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- A screen, with the spectator count, above its label.
function PAINT.spectate(self, w, h)
	local c, s = self.choice, self.scale
	local box, inset = BOX_H * s, 5 * s
	local color = self:BodyColor()
	Rect(Scale(color, 0.45), 0, 0, w, box)
	Rect(color, inset, inset, w - 2 * inset, box - 2 * inset)
	draw.SimpleText(c.count, "Sandcastle.TeamMenu.Label", w / 2, box / 2, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	self:DrawHotkey(inset, inset)
	draw.SimpleText(c.label, "Sandcastle.TeamMenu.Label", w / 2, box + BOX_LABEL * s / 2, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if c.current then
		surface.SetDrawColor(TEXT)
		surface.DrawOutlinedRect(0, 0, w, box, math.max(1, math.Round(2 * s)))
	end
end

function CHOICE:Paint(w, h)
	PAINT[self.choice.kind](self, w, h)
end

vgui.Register("WetsandTeamChoice", CHOICE, "DButton")

-- The cancel button ----------------------------------------------------------------

local CANCEL = {}

function CANCEL:Init()
	self:SetKeyboardInputEnabled(false)
	self:SetFont("Sandcastle.TeamMenu.Label")
	self:SetTextColor(TEXT)
end

function CANCEL:DoClick()
	self:GetParent():Remove()
end

function CANCEL:Paint(w, h)
	Rect(self:IsHovered() and Color(120, 60, 40) or Color(60, 55, 50), 0, 0, w, h)
end

vgui.Register("WetsandTeamCancel", CANCEL, "DButton")

-- The menu -------------------------------------------------------------------------

local MENU = {}

local function BoundKey(bind)
	local name = input.LookupBinding(bind)
	return name and input.GetKeyCode(name)
end

local function Counted(entry)
	local t = { count = team.NumPlayers(entry.index) }
	for k, v in pairs(entry) do t[k] = v end
	return t
end

function MENU:Init()
	self:SetSize(ScrW(), ScrH())
	self.cancelButton = vgui.Create("WetsandTeamCancel", self)
	self.nextRefresh = 0
end

-- config: { title, teams = { { index, name, color, command } }, auto, spectate,
-- limit (a convar), autoKey, cancel = { label, key }, closeBinds }.
function MENU:SetConfig(config)
	self.config = config
	self.cancelButton:SetText(config.cancel.label)
	-- CTFTeamMenu::ShowPanel reads the bound keys when the menu opens.
	self.closeKeys = {}
	for _, bind in ipairs(config.closeBinds) do
		local key = BoundKey(bind)
		if key then self.closeKeys[key] = true end
	end
	self.scoreKey = BoundKey("+showscores")
	self.menu = self:Build()
	self.choicePanels = {}
	for i in ipairs(self.menu.choices) do self.choicePanels[i] = vgui.Create("WetsandTeamChoice", self) end
	self:Refresh()
end

function MENU:Build()
	local config = self.config
	local teams = {}
	for i, t in ipairs(config.teams) do teams[i] = Counted(t) end
	local extras = { auto = config.auto, spectate = config.spectate and Counted(config.spectate) }
	return L.TeamMenu(teams, LocalPlayer():Team(), config.limit:GetInt(), extras)
end

function MENU:Refresh()
	self.menu = self:Build()
	local s = self:GetTall() / UNIT
	for i, c in ipairs(self.menu.choices) do self.choicePanels[i]:SetChoice(c, s) end
	self.cancelButton:SetVisible(self.menu.cancel)
end

function MENU:Think()
	if RealTime() < self.nextRefresh then return end
	self.nextRefresh = RealTime() + REFRESH
	self:Refresh()
end

local function Width(c)
	if c.kind == "spectate" then return BOX_W end
	return DOOR_W
end

local function Gap(a, b)
	if a.kind == "team" and b.kind == "team" then return TEAM_GAP end
	return GAP
end

-- The choices in a centred row, in the model's order.
function MENU:PerformLayout(w, h)
	local s = h / UNIT
	local choices = self.menu.choices
	local total = 0
	for i, c in ipairs(choices) do total = total + Width(c) + (i > 1 and Gap(choices[i - 1], c) or 0) end
	local x = (w - total * s) / 2
	for i, c in ipairs(choices) do
		if i > 1 then x = x + Gap(choices[i - 1], c) * s end
		local p = self.choicePanels[i]
		if c.kind == "spectate" then
			p:SetPos(math.Round(x), math.Round(BOX_Y * s))
			p:SetSize(math.Round(BOX_W * s), math.Round((BOX_H + BOX_LABEL) * s))
		else
			p:SetPos(math.Round(x), math.Round((DOOR_Y - HEADER) * s))
			p:SetSize(math.Round(DOOR_W * s), math.Round((DOOR_H + HEADER) * s))
		end
		x = x + Width(c) * s
	end
	self.cancelButton:SetPos(math.Round(w - (CANCEL_W + 40) * s), math.Round(h - (BAR_H + CANCEL_H) / 2 * s))
	self.cancelButton:SetSize(math.Round(CANCEL_W * s), math.Round(CANCEL_H * s))
end

function MENU:Paint(w, h)
	local s = h / UNIT
	Rect(BACKDROP, 0, 0, w, h)
	Rect(BAR, 0, h - BAR_H * s, w, BAR_H * s)
	draw.SimpleText(self.config.title, "Sandcastle.TeamMenu.Title", 30 * s, h - BAR_H / 2 * s, TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

-- CTFTeamMenu::OnCommand: a disabled team keeps the menu open; picking the
-- team the player is on sends nothing.
function MENU:Choose(choice)
	if not choice.enabled then return end
	if not choice.current then RunConsoleCommand("jointeam", choice.command) end
	self:Remove()
end

-- CTFTeamMenu::OnKeyCodePressed: the changeteam key (and Cancel's) closes the
-- menu once the player has a team, the auto key auto-assigns, the scoreboard
-- key shows the scores; the number keys are Teammenu.res's hotkeys.
function MENU:OnKeyCodePressed(code)
	local menu, config = self.menu, self.config
	if code == self.scoreKey then
		GAMEMODE:ScoreboardShow()
		self.scoreboardShown = true
	elseif self.closeKeys[code] or code == config.cancel.key then
		if menu.cancel then self:Remove() end
	elseif code == config.autoKey and menu.auto then
		self:Choose(menu.auto)
	elseif menu.choices[code - KEY_0] then
		self:Choose(menu.choices[code - KEY_0]) -- KEY_1 .. KEY_9 follow KEY_0
	end
end

function MENU:OnKeyCodeReleased(code)
	if code == self.scoreKey then
		GAMEMODE:ScoreboardHide()
		self.scoreboardShown = false
	end
end

function MENU:OnRemove()
	if self.scoreboardShown then GAMEMODE:ScoreboardHide() end
end

vgui.Register("WetsandTeamMenu", MENU, "EditablePanel")

-- TF2's team menu ------------------------------------------------------------------

local TEAM_MENU = {
	title = "SELECT A TEAM",
	teams = {
		{ index = WETSAND.TEAM_BLUE, name = WETSAND.TeamName[WETSAND.TEAM_BLUE], color = WETSAND.TeamColor[WETSAND.TEAM_BLUE], command = "blue" },
		{ index = WETSAND.TEAM_RED, name = WETSAND.TeamName[WETSAND.TEAM_RED], color = WETSAND.TeamColor[WETSAND.TEAM_RED], command = "red" },
	},
	auto = { name = "AUTO-ASSIGN", color = Color(112, 102, 88), command = "auto" },
	spectate = { index = WETSAND.TEAM_SPECTATOR, name = "SPECTATE", color = Color(62, 60, 58), command = "spectate" },
	limit = WETSAND.UnbalanceLimit,
	autoKey = KEY_SPACE,
	cancel = { label = "CANCEL (0)", key = KEY_0 },
	closeBinds = { "changeteam", "gm_showteam" },
}

local menu

-- CTFTeamMenu::ShowPanel does nothing while the menu is already up.
function WETSAND.OpenTeamMenu()
	if IsValid(menu) then return end
	menu = vgui.Create("WetsandTeamMenu")
	menu:SetConfig(TEAM_MENU)
	menu:MakePopup()
end

net.Receive("wetsand_team_menu_open", function()
	WETSAND.OpenTeamMenu()
end)

-- The server opens the menu for a player without a team once the client can
-- receive it.
hook.Add("InitPostEntity", "wetsand_teams", function()
	net.Start("wetsand_team_menu_request")
	net.SendToServer()
end)

hook.Add("OnScreenSizeChanged", "wetsand_teams", function()
	CreateFonts()
	if IsValid(menu) then
		menu:SetSize(ScrW(), ScrH())
		menu:Refresh()
	end
end)
