include("shared.lua")
for _, f in ipairs(GM:WSModules("cl_")) do include("ws/" .. f) end

function GM:HUDPaint()
	self.BaseClass.HUDPaint(self)
	if not WS.Active() then return end
	-- Features' views draw their HUD elements here.
	hook.Run("SandcastleHUDPaint", ScrW(), ScrH())
end
