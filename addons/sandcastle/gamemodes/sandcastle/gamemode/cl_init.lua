include("shared.lua")
-- cl_ui (WS.UI) loads first: other cl_ modules build their panels on it.
include("ws/cl_ui.lua")
for _, f in ipairs(GM:WSModules("cl_")) do
	if f ~= "cl_ui.lua" then include("ws/" .. f) end
end

-- Every HUD element of the gamemode, in order (WS.HUD, ws/sh_core.lua).
function GM:HUDPaint()
	self.BaseClass.HUDPaint(self)
	WS.HUD:Draw(ScrW(), ScrH())
end
