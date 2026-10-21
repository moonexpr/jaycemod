include("shared.lua")
-- cl_ui (WS.UI) loads first: other cl_ modules build their panels on it;
-- then cl_client_settings (WS.PersistClientConVars), which keeps their
-- settings.
local LOADED_FIRST = { "cl_ui.lua", "cl_client_settings.lua" }
local loaded = {}
for _, f in ipairs(LOADED_FIRST) do
	include("ws/" .. f)
	loaded[f] = true
end
for _, f in ipairs(GM:WSModules("cl_")) do
	if not loaded[f] then include("ws/" .. f) end
end

-- Every HUD element of the gamemode, in order (WS.HUD, ws/sh_core.lua).
function GM:HUDPaint()
	self.BaseClass.HUDPaint(self)
	WS.HUD:Draw(ScrW(), ScrH())
end
