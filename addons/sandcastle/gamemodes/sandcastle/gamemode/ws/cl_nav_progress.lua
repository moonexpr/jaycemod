-- The nav mesh progress box on each client (ws/sh_nav_progress.lua
-- defines its event), in the middle of the screen in TF2's look: a dark
-- brown rounded panel, the title in TF2 Build and the stage in TF2
-- Secondary, both in TF2's light tan, over a tan bar on a darker track,
-- full when done and a moving band while the work runs. While it shows,
-- the engine's own progress box (CNavProgress, the viewport panel named
-- nav_progress, uncentred) is hidden wherever it is found.
local P = WS.require("foundation.nav_progress")
local E = WS.Events

-- TF2's 480-tall units; its scheme's colours (TFDarkBrown, TanLight, TanDark).
local WIDE, TALL, BAR_TALL, PAD, CORNER = 300, 74, 10, 10, 6
local TITLE_TALL, BODY_TALL = 14, 10
local DARK_BROWN = Color(42, 39, 37, 240)
local TRACK = Color(25, 23, 22, 255)
local TAN_LIGHT = Color(235, 226, 202)
local TAN_DARK = Color(117, 107, 94)
local TITLE_FONT, BODY_FONT = "WS.NavProgress.Title", "WS.NavProgress.Body"
local BAND, BAND_SPEED = 0.25, 0.6

-- The engine's box (Source's PANEL_NAV_PROGRESS), by its panel name or class.
local ENGINE_BOX = { nav_progress = true, NavProgress = true, CNavProgress = true }
local HIDE_EVERY = 1

local fontsFor

local function Fonts(unit)
	if fontsFor == unit then return end
	surface.CreateFont(TITLE_FONT, { font = "TF2 Build", size = math.Round(TITLE_TALL * unit), weight = 500 })
	surface.CreateFont(BODY_FONT, { font = "TF2 Secondary", size = math.Round(BODY_TALL * unit), weight = 500 })
	fontsFor = unit
end

-- Hides the engine's box among panel's descendants (not ours).
local function HideEngineBox(panel, own)
	for _, child in ipairs(panel:GetChildren()) do
		if child ~= own and (ENGINE_BOX[child:GetName()] or ENGINE_BOX[child:GetClassName()]) then child:SetVisible(false) end
		HideEngineBox(child, own)
	end
end

WS.UI.Define("NavProgress", "DPanel", {
	Init = function(self)
		self:SetMouseInputEnabled(false)
		self:SetKeyboardInputEnabled(false)
		self.nextHide = 0
	end,
	Show = function(self, fields, now)
		self.fields = fields
		self.doneAt = fields.stage == P.DONE and now or self.doneAt
	end,
	Think = function(self)
		local f, now = self.fields, CurTime()
		if not P.Showing(f.stage, self.doneAt or now, now) then return self:Remove() end
		local unit = ScrH() / 480
		self:SetSize(WIDE * unit, TALL * unit)
		self:SetPos((ScrW() - WIDE * unit) / 2, (ScrH() - TALL * unit) / 2)
		if now >= self.nextHide then
			self.nextHide = now + HIDE_EVERY
			HideEngineBox(vgui.GetWorldPanel(), self)
		end
	end,
	Paint = function(self, w, h)
		local f, now = self.fields, CurTime()
		local unit = h / TALL
		Fonts(unit)
		local pad, corner = PAD * unit, CORNER * unit
		draw.RoundedBox(corner, 0, 0, w, h, TAN_DARK)
		draw.RoundedBox(corner, unit, unit, w - 2 * unit, h - 2 * unit, DARK_BROWN)
		draw.SimpleText(string.upper("Navigation mesh: " .. game.GetMap()), TITLE_FONT, pad, pad, TAN_LIGHT)
		draw.SimpleText(P.Body(f.stage, (self.doneAt or now) - f.started, f.areas), BODY_FONT, pad, pad + (TITLE_TALL + 6) * unit, TAN_LIGHT)
		-- the bar: a darker track, tan to its fraction, or a band moving while it runs
		local barX, barY, barW, barH = pad, h - pad - BAR_TALL * unit, w - 2 * pad, BAR_TALL * unit
		draw.RoundedBox(corner / 2, barX, barY, barW, barH, TRACK)
		local fraction = P.Fraction(f.stage)
		local from, to = 0, fraction
		if not fraction then
			local at = (now * BAND_SPEED) % (1 + BAND) - BAND
			from, to = math.max(at, 0), math.min(at + BAND, 1)
		end
		if to > from then
			surface.SetDrawColor(TAN_LIGHT)
			surface.DrawRect(barX + barW * from, barY, barW * (to - from), barH)
		end
	end,
})

local box

E.Listen("game_nav_progress", "ws_nav_progress", function(fields)
	if not IsValid(box) then box = vgui.Create(WS.UI.Name("NavProgress")) end
	box:Show(fields, CurTime())
end)
