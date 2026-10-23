include("shared.lua")
-- cl_client_settings (WS.PersistClientConVars) loads first: it keeps the
-- other modules' settings. Then the player's feedback, what they hear and
-- see of their own hits (cl_hits), the last thing to fail: it reads nothing
-- of the HUD and loads before any of it. Then cl_ui (WS.UI), which other
-- cl_ modules build their panels on, and cl_tf_hud (WS.TFHud), which the
-- HUD panels draw with; then the rest.
local LOADED_FIRST = { "cl_client_settings.lua", "cl_hits.lua", "cl_ui.lua", "cl_tf_hud.lua" }

-- A module failing at load is reported with its stack, and the rest load
-- on: one broken panel takes no other module with it.
local function Load(f)
	xpcall(include, ErrorNoHaltWithStack, "ws/" .. f)
end

local loaded = {}
for _, f in ipairs(LOADED_FIRST) do
	Load(f)
	loaded[f] = true
end
for _, f in ipairs(GM:WSModules("cl_")) do
	if not loaded[f] then Load(f) end
end

-- Every HUD element of the gamemode, in order (WS.HUD, ws/sh_core.lua).
function GM:HUDPaint()
	self.BaseClass.HUDPaint(self)
	WS.HUD:Draw(ScrW(), ScrH())
end
