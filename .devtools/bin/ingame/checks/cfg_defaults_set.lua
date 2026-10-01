-- First half of the sandcastle_defaults check: move two convars that exist
-- on every map off their defaults. GMod refuses `exec` from Lua
-- (game.ConsoleCommand blocked!), so the harness then sends
-- `exec sandcastle_defaults` over RCON, as an admin would, and the
-- cfg_defaults check reads them back.
local CONVARS = {
	mp_autoteambalance = "0",
	mp_teams_unbalance_limit = "3",
}
local SETTLE = 1 -- seconds for the console to run what it was given

return function(t)
	for name, value in pairs(CONVARS) do RunConsoleCommand(name, value) end
	t:Wait(SETTLE)
	for name, value in pairs(CONVARS) do
		t:Check(name .. " changed to " .. value, GetConVar(name):GetString() == value, GetConVar(name):GetString())
	end
end
