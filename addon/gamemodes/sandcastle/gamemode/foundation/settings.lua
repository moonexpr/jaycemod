-- The server convars an admin may set from the Utilities menu. On a
-- dedicated server a client cannot set a server's convar itself ("Can't
-- change replicated ConVar ... from console of client"), so the menu sends
-- ws_server_set name value, and the server sets it after Parse holds
-- the value to the range the menu's control offers. Every setting is an
-- integer.
local floor, format, tonumber = math.floor, string.format, tonumber
local AiWar = require("foundation.aiwar")
local Slots = require("foundation.aiwar.slots")
module(...)

SETTINGS = {
	mp_aiwar_team_size = { min = Slots.CUSTOM_SIZE, max = AiWar.TEAM_SIZE_MAX },
	ws_aiwar_debug_full = { min = 0, max = 1 },
	ns_squads_auto_enabled = { min = 0, max = 1 },
	ns_soldiers_paused = { min = 0, max = 1 },
	ws_nodegraph_max_nodes = { min = 64, max = 8192 },
}

-- The convar's text for the value text names, rounded to a whole number;
-- or nil and why it is refused.
function Parse(name, text)
	local setting = SETTINGS[name]
	if not setting then return nil, format("%s is not a setting the menu may change", name) end
	local number = tonumber(text)
	if not number then return nil, format("%s takes a number, not %q", name, text) end
	local value = floor(number + 0.5)
	if value < setting.min or value > setting.max then
		return nil, format("%s takes %d to %d", name, setting.min, setting.max)
	end
	return format("%d", value)
end
