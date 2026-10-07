-- Second half of the wetsand_defaults_apply check (defaults_change moved
-- the convars; the harness sent wetsand_defaults_apply over RCON just
-- before this, and passes its reply as args.before_reply): the command read
-- cfg/sandcastle_defaults.cfg from the GAME path, ran its lines, and the
-- convars are back to the defaults it lists.
local DEFAULTS = {
	mp_chattime = "10",
	mp_autoteambalance = "1",
}
local SETTLE = 1 -- the lines run through the console on the next frame

return function(t)
	local reply = t.args.before_reply or ""
	t:Check("the reply says it ran the cfg's lines", string.find(reply, "ran %d+ lines") ~= nil, reply)
	t:Check("the reply does not say not found", string.find(reply, "not found", 1, true) == nil, reply)
	t:Wait(SETTLE)
	for name, value in pairs(DEFAULTS) do
		t:Check("wetsand_defaults_apply puts " .. name .. " back to " .. value,
			GetConVar(name):GetString() == value, GetConVar(name):GetString())
	end
end
