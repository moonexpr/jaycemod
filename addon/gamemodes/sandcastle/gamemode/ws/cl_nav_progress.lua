-- The nav mesh progress box on each client (ws/sh_nav_progress.lua
-- defines its event): a WS.UI dialog in the middle of the screen.
local P = WS.require("foundation.nav_progress")
local E = WS.Events

local WIDE, TALL, BAR_TALL = 420, 112, 20

WS.UI.Define("NavProgress", "Dialog", {
	Init = function(self)
		self:SetSize(WIDE, TALL)
		self:SetMouseInputEnabled(false)
		self:SetKeyboardInputEnabled(false)
		self:SetTitle("Navigation mesh: " .. game.GetMap())
		self.bar = vgui.Create(WS.UI.Name("Progress"), self)
		self.bar:Dock(BOTTOM)
		self.bar:SetTall(BAR_TALL)
	end,
	Show = function(self, fields, now)
		self.fields = fields
		self.doneAt = fields.stage == P.DONE and now or self.doneAt
	end,
	Think = function(self)
		local f, now = self.fields, CurTime()
		if not P.Showing(f.stage, self.doneAt or now, now) then return self:Remove() end
		self:SetBody(P.Body(f.stage, (self.doneAt or now) - f.started, f.areas))
		self.bar:SetFraction(P.Fraction(f.stage))
	end,
})

local box

E.Listen("nav_progress", "ws_nav_progress", function(fields)
	if not IsValid(box) then box = vgui.Create(WS.UI.Name("NavProgress")) end
	box:Show(fields, CurTime())
end)
