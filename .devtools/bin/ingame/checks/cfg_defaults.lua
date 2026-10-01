-- Second half of the sandcastle_defaults check (cfg_defaults_set moved the
-- convars; the harness sent `exec sandcastle_defaults` over RCON just
-- before this): the cfg was found in the addon's cfg folder and put them
-- back to the defaults it lists (addon/cfg/sandcastle_defaults.cfg).
local DEFAULTS = {
	mp_autoteambalance = "1",
	mp_teams_unbalance_limit = "1",
}
local SETTLE = 1

return function(t)
	t:Wait(SETTLE)
	for name, value in pairs(DEFAULTS) do
		t:Check("exec sandcastle_defaults puts " .. name .. " back to " .. value,
			GetConVar(name):GetString() == value, GetConVar(name):GetString())
	end
	t:Info("sv_gameplay_enabled_after_exec", GetConVar("sv_gameplay_enabled"):GetString())
end
