-- The gamemode's convars are replicated and notify (ws/sh_core.lua
-- wraps CreateConVar for its own files), and a client is told the
-- server-only ones, so its console knows every one: it completes their
-- names and shows their server values, and a change is told in chat.
local bor, gsub, ipairs, match, sub, type = bit.bor, string.gsub, ipairs, string.match, string.sub, type
module(...)

-- Whether a chunk's source (debug.getinfo's source or short_src) is one of
-- the gamemode's own files, the gamemode being folder.
function Ours(source, folder)
	local path = gsub(source, "^@", "")
	local prefix = "gamemodes/" .. folder .. "/"
	return sub(path, 1, #prefix) == prefix
end

-- Whether a source is a client-only file (ws/cl_*.lua, a feature's
-- cl.lua): its convars are the client's own, which the client sets, so
-- they are never replicated (only the server may set a replicated one).
function ClientOnly(source)
	local file = match(source, "([^/]+)$")
	return file == "cl.lua" or sub(file, 1, 3) == "cl_"
end

-- The flags every gamemode convar gets: FCVAR_REPLICATED and FCVAR_NOTIFY.
function Added(REPLICATED, NOTIFY)
	return bor(REPLICATED, NOTIFY)
end

-- A convar's flags (nil, a number, or a list of numbers, as CreateConVar
-- takes them) with the added ones among them, as a number.
function Flags(flags, added)
	local all = added
	if type(flags) == "number" then
		all = bor(all, flags)
	elseif type(flags) == "table" then
		for _, flag in ipairs(flags) do all = bor(all, flag) end
	end
	return all
end
