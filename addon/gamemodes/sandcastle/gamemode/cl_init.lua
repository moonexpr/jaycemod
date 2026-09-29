include("shared.lua")
for _, f in ipairs(GM:WetsandModules("cl_")) do include("wetsand/" .. f) end

-- Tell the server this client has loaded, so the first round's pre-round
-- freeze is not spent on the loading screen.
function GM:InitPostEntity()
	self.BaseClass.InitPostEntity(self)
	net.Start("wetsand_client_loaded")
	net.SendToServer()
end

function GM:HUDPaint()
	self.BaseClass.HUDPaint(self)
	if not WETSAND.Active() then return end
	WETSAND.DrawHUD()
	-- Modules draw their own HUD elements here.
	hook.Run("SandcastleHUDPaint", ScrW(), ScrH())
end

function GM:Think()
	self.BaseClass.Think(self)
	if WETSAND.Active() then WETSAND.AnnouncerThink() end
end
