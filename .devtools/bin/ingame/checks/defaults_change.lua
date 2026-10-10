-- First half of the ws_defaults_apply check: move two convars that
-- cfg/sandcastle_defaults.cfg lists off their defaults. The harness then
-- sends ws_defaults_apply over RCON, as an admin would, and the
-- defaults_apply check reads them back.
local CONVARS = {
	mp_chattime = "30",
	mp_autoteambalance = "0",
}
local SETTLE = 1 -- seconds for the console to run what it was given

return function(t)
	for name, value in pairs(CONVARS) do RunConsoleCommand(name, value) end
	t:Wait(SETTLE)
	for name, value in pairs(CONVARS) do
		t:Check(name .. " changed to " .. value, GetConVar(name):GetString() == value, GetConVar(name):GetString())
	end
end
