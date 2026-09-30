include("shared.lua")
for _, f in ipairs(GM:WetsandModules("cl_")) do include("wetsand/" .. f) end

function GM:HUDPaint()
	self.BaseClass.HUDPaint(self)
	if not WETSAND.Active() then return end
	-- Features' views draw their HUD elements here.
	hook.Run("SandcastleHUDPaint", ScrW(), ScrH())
end
