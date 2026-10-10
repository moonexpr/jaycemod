include("shared.lua")
-- cl_ui (WS.UI) loads first: other cl_ modules build their panels on it.
include("ws/cl_ui.lua")
for _, f in ipairs(GM:WSModules("cl_")) do
	if f ~= "cl_ui.lua" then include("ws/" .. f) end
end

function GM:HUDPaint()
	self.BaseClass.HUDPaint(self)
	if not WS.Active() then return end
	-- Features' views draw their HUD elements here.
	hook.Run("SandcastleHUDPaint", ScrW(), ScrH())
end
