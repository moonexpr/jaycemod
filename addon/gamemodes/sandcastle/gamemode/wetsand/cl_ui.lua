-- WETSAND.UI: Sandcastle's TF2-styled panels, one look (THEME: a dark box,
-- a white border, white text) as derma prototypes. UI.Define(name, base,
-- proto) registers "WS<name>" on base, a UI name ("Dialog") or any derma
-- class ("DFrame"); a new panel derives from one and overrides only what
-- differs (derma copies the base's methods under the proto's). The library's
-- own: Panel (the box), Label (theme text), Progress (a bar, full to its
-- fraction, or a moving band while it has none) and Dialog (a Panel with a
-- title and a line, kept in the middle of the screen).
local UI = {}
WETSAND.UI = UI

UI.THEME = {
	background = Color(24, 24, 28),
	border = Color(255, 255, 255),
	text = Color(255, 255, 255),
	muted = Color(220, 220, 225),
	borderWidth = 2,
	padding = 12,
	titleFont = "WSTitle",
	bodyFont = "WSBody",
}

surface.CreateFont("WSTitle", { font = "Verdana", size = 18, weight = 800 })
surface.CreateFont("WSBody", { font = "Verdana", size = 15, weight = 500 })

local PREFIX = "WS"

function UI.Name(name) return PREFIX .. name end

-- base: a UI name when the library has defined it, else a derma class.
local defined = {}
function UI.Define(name, base, proto)
	defined[name] = true
	return derma.DefineControl(UI.Name(name), "Sandcastle " .. name, proto, defined[base] and UI.Name(base) or base)
end

function UI.Center(panel)
	local w, h = panel:GetSize()
	panel:SetPos((ScrW() - w) / 2, (ScrH() - h) / 2)
end

local THEME = UI.THEME

-- The box: the theme's background, inside its border.
local function Box(w, h)
	surface.SetDrawColor(THEME.border)
	surface.DrawRect(0, 0, w, h)
	local b = THEME.borderWidth
	surface.SetDrawColor(THEME.background)
	surface.DrawRect(b, b, w - b * 2, h - b * 2)
end

UI.Define("Panel", "DPanel", {
	Init = function(self)
		local p = THEME.padding
		self:DockPadding(p, p, p, p)
	end,
	Paint = function(self, w, h) Box(w, h) end,
})

UI.Define("Label", "DLabel", {
	Init = function(self)
		self:SetFont(THEME.bodyFont)
		self:SetTextColor(THEME.text)
		self:SetContentAlignment(5)
	end,
})

-- fraction: 0..1, or nil for a band that moves while the work runs.
local BAND, BAND_SPEED = 0.25, 0.6

UI.Define("Progress", "DPanel", {
	SetFraction = function(self, fraction) self.fraction = fraction end,
	Paint = function(self, w, h)
		Box(w, h)
		local b = THEME.borderWidth * 2
		local inner = w - b * 2
		surface.SetDrawColor(THEME.border)
		if self.fraction then
			surface.DrawRect(b, b, inner * self.fraction, h - b * 2)
		else
			local at = (CurTime() * BAND_SPEED) % (1 + BAND) - BAND
			local from, to = math.max(at, 0), math.min(at + BAND, 1)
			surface.DrawRect(b + inner * from, b, inner * (to - from), h - b * 2)
		end
	end,
})

UI.Define("Dialog", "Panel", {
	Init = function(self)
		self.title = vgui.Create(UI.Name("Label"), self)
		self.title:SetFont(THEME.titleFont)
		self.title:Dock(TOP)
		self.body = vgui.Create(UI.Name("Label"), self)
		self.body:SetTextColor(THEME.muted)
		self.body:Dock(TOP)
		self.body:DockMargin(0, 6, 0, 0)
	end,
	SetTitle = function(self, text) self.title:SetText(text) end,
	SetBody = function(self, text) self.body:SetText(text) end,
	PerformLayout = function(self) UI.Center(self) end,
})
