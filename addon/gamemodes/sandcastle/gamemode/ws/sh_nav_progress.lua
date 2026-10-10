-- The nav mesh progress box while mp_nav_generate runs (ws/sv_nav.lua):
-- the server tells every client the stage (foundation.nav_progress), when
-- it began and, done, the areas made; each client shows a WS.UI dialog
-- in the middle of its screen. The engine's own progress box (CNavProgress)
-- still opens beside it: GMod gives Lua no hold on it.
local P = WS.require("foundation.nav_progress")
local E = WS.Events

local AREA_BITS = 16

E.Define("nav_progress", {
	stage = E.UInt(2),
	started = E.Float(),
	areas = E.UInt(AREA_BITS),
})

if SERVER then
	function WS.NavProgress(stage, started, areas)
		E.Fire("nav_progress", { stage = stage, started = started, areas = areas or 0 })
	end
	return
end

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
