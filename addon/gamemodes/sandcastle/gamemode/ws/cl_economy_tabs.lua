-- With the economy switched off (mp_economy_enabled 0, ws/sh_toggles.lua),
-- the Loadout and Store tabs leave the spawn menu, and come back when it is
-- switched on. The tab files name themselves in WS.EconomyTabs; this keeps
-- each removed tab's entry to put back, and rebuilds the spawn menu
-- (spawnmenu_reload) when the setting changes after it was first built.
WS.EconomyTabs = WS.EconomyTabs or {}

local removed = {}
local shown

local function Apply(on)
	local tabs = spawnmenu.GetCreationTabs()
	for name in pairs(WS.EconomyTabs) do
		if on and removed[name] then
			tabs[name], removed[name] = removed[name], nil
		elseif not on and tabs[name] then
			removed[name], tabs[name] = tabs[name], nil
		end
	end
end

local function Sync()
	local on = WS.EconomyEnabled()
	if on == shown then return end
	local built = shown ~= nil
	shown = on
	Apply(on)
	if built or not on then RunConsoleCommand("spawnmenu_reload") end
end

hook.Add("InitPostEntity", "ws_economy_tabs", Sync)
hook.Add("WSServerSettingsChanged", "ws_economy_tabs", Sync)
