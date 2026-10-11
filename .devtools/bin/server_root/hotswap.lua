-- Hot swapping on the dedicated server (server_root.py): code edited while
-- the server runs, loaded without a restart, where lua_refresh_file cannot
-- reach (it re-runs included files, and modules and features are compiled).
-- From the server console (srcds.py rcon) or a superadmin:
--   ws_hotswap_module <foundation.capture.area>   runs the module's file
--     again; module(...) keeps its table, so the new functions are where
--     every holder of the module has them, and its state stays
--   ws_hotswap_feature <capture> <Method|Table.Method> [...]   runs the
--     feature's sv.lua again, and through it every sv_ part, with its side
--     effects stubbed (hooks, timers, commands, convar callbacks, net,
--     WS.Events.Listen and Ignore, other features), and copies only the
--     methods named onto the live controller, whose state stays.
--     Soldier.Move copies onto live.Soldier, so instances whose metatable
--     it is see the new method. All or nothing: if any name is missing from
--     the fresh run, names a table the live controller lacks, or closes
--     over the fresh controller or a table on it (which would act on the
--     unused fresh run, not the live state), nothing is copied and each
--     refused name is printed with its reason.
--   ws_hotswap_feature <capture>   copies nothing; prints the methods a swap
--     would take and the ones it would refuse, with the reasons
-- A new sv_ part is picked up by a swap. A new cl_ or sh_ part, or a change
-- to a local the live code already holds, still needs the map to change.

-- sh_core's WS.require keeps the gamemode's root and the modules'
-- environment as upvalues.
local function RequireUpvalue(wanted)
	for i = 1, math.huge do
		local name, value = debug.getupvalue(WS.require, i)
		if not name then return nil end
		if name == wanted then return value end
	end
end

local function Tell(ply, text)
	if IsValid(ply) then ply:ChatPrint(text) else print(text) end
end

local function Allowed(ply)
	if not IsValid(ply) or ply:IsSuperAdmin() then return true end
	Tell(ply, "hotswap: superadmins only")
	return false
end

concommand.Add("ws_hotswap_module", function(ply, _, args)
	if not Allowed(ply) then return end
	local name = args[1]
	local chunk = CompileFile(RequireUpvalue("GAMEMODE_ROOT") .. name:gsub("%.", "/") .. ".lua")
	setfenv(chunk, RequireUpvalue("CHUNK_ENV"))(name)
	Tell(ply, "hotswap: " .. name .. " reloaded")
end)

-- Stands for anything a feature's file reaches at load: every field and
-- call is itself, so nothing outside the rerun changes.
local INERT = setmetatable({}, {})
getmetatable(INERT).__index = function() return INERT end
getmetatable(INERT).__call = function() return INERT end

local STUBBED = { hook = INERT, timer = INERT, concommand = INERT, cvars = INERT, net = INERT }

-- The environment a feature's root reruns in; its parts get the same one
-- through WS.FeatureParts(getfenv(1), ...). WS.Events keeps Define and the
-- rest, but Listen and Ignore do nothing, so a listener stays the live one
-- and never becomes a closure over the unused fresh controller. Every read
-- of WS.Events in the rerun, a load-time alias included, gets this table.
local function RerunEnv()
	local events = setmetatable({ Listen = INERT, Ignore = INERT }, { __index = WS.Events })
	local ws = setmetatable({ Feature = function() return INERT end, Events = events }, { __index = WS })
	return setmetatable({ WS = ws }, { __index = function(_, key)
		if STUBBED[key] then return STUBBED[key] end
		if key == "util" then return setmetatable({ AddNetworkString = INERT }, { __index = util }) end
		return _G[key]
	end })
end

-- The tables a copied method must not hold: the fresh controller and every
-- table on it (its ports, its state). They belong to the fresh run, which
-- nothing live uses, so a method holding one would read or change the
-- wrong state.
local function Forbidden(fresh)
	local set = { [fresh] = true }
	for _, value in pairs(fresh) do
		if type(value) == "table" then set[value] = true end
	end
	return set
end

-- How fn reaches a forbidden table, as upvalue names joined by " > ", or
-- nil. Follows function upvalues and the direct function fields of table
-- upvalues, transitively, each once; never a table's nested tables, so the
-- walk stays out of WS and the libraries. Matches tables by identity, and
-- reads upvalues only (the server has no debug.setupvalue to rebind them).
local Through

local function Reach(fn, forbidden, seen)
	if seen[fn] or debug.getinfo(fn, "S").what == "C" then return nil end
	seen[fn] = true
	for i = 1, math.huge do
		local name, value = debug.getupvalue(fn, i)
		if name == nil then return nil end
		local path = Through(name, value, forbidden, seen)
		if path then return path end
	end
end

function Through(name, value, forbidden, seen)
	if type(value) == "function" then
		local rest = Reach(value, forbidden, seen)
		return rest and name .. " > " .. rest
	end
	if type(value) ~= "table" then return nil end
	if forbidden[value] then return name end
	if seen[value] then return nil end
	seen[value] = true
	for key, field in pairs(value) do
		if type(field) == "function" then
			local rest = Reach(field, forbidden, seen)
			if rest then return name .. "." .. tostring(key) .. " > " .. rest end
		end
	end
end

-- A requested name, resolved: { name, into, key, fn } to copy fn to
-- into[key], or { name, reason } when it is refused.
local function Resolve(name, fresh, live, forbidden)
	local tableName, key = name:match("^([^.]+)%.([^.]+)$")
	local from, into = fresh, live
	if tableName then
		from, into = fresh[tableName], live[tableName]
		if type(from) ~= "table" or type(into) ~= "table" then return { name = name, reason = "not a table" } end
	else
		key = name
	end
	local fn = from[key]
	if fn == nil then return { name = name, reason = "missing" } end
	if type(fn) ~= "function" then return { name = name, reason = "not a function" } end
	local path = Reach(fn, forbidden, {})
	if path then return { name = name, reason = "closes over the controller through " .. path } end
	return {
		name = name,
		into = into,
		key = key,
		fn = fn,
	}
end

-- Every name a swap could be asked for: the fresh controller's methods,
-- the methods of each table on it as Table.Method, and the live methods
-- the fresh run no longer has. Sorted.
local function AllNames(fresh, live)
	local names, seen = {}, {}
	local function Add(name)
		if not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	for key, value in pairs(fresh) do
		if type(key) == "string" and type(value) == "function" then Add(key) end
		if type(key) == "string" and type(value) == "table" then
			for method, fn in pairs(value) do
				if type(method) == "string" and type(fn) == "function" then Add(key .. "." .. method) end
			end
		end
	end
	for key, value in pairs(live) do
		if type(key) == "string" and type(value) == "function" and fresh[key] == nil then Add(key) end
	end
	table.sort(names)
	return names
end

local function ResolveAll(names, fresh, live)
	local forbidden = Forbidden(fresh)
	local swappable, refused = {}, {}
	for _, name in ipairs(names) do
		local resolved = Resolve(name, fresh, live, forbidden)
		if resolved.reason then refused[#refused + 1] = resolved else swappable[#swappable + 1] = resolved end
	end
	return swappable, refused
end

local function TellRefused(ply, heading, refused)
	Tell(ply, heading)
	for _, item in ipairs(refused) do Tell(ply, "  " .. item.name .. ": " .. item.reason) end
end

-- One name a line: the console cuts a long line short.
local function TellListing(ply, feature, swappable, refused)
	if #swappable == 0 then
		Tell(ply, "hotswap: " .. feature .. " swappable: none")
	else
		Tell(ply, "hotswap: " .. feature .. " swappable:")
		for _, item in ipairs(swappable) do Tell(ply, "  " .. item.name) end
	end
	if #refused == 0 then
		Tell(ply, "hotswap: " .. feature .. " refused: none")
	else
		TellRefused(ply, "hotswap: " .. feature .. " refused:", refused)
	end
end

concommand.Add("ws_hotswap_feature", function(ply, _, args)
	if not Allowed(ply) then return end
	local feature = args[1]
	local live = WS.Feature(feature)
	local chunk = CompileFile(RequireUpvalue("GAMEMODE_ROOT") .. "features/" .. feature .. "/sv.lua")
	local fresh = setfenv(chunk, RerunEnv())()
	if #args < 2 then
		TellListing(ply, feature, ResolveAll(AllNames(fresh, live), fresh, live))
		return
	end
	local swappable, refused = ResolveAll({ unpack(args, 2) }, fresh, live)
	if #refused > 0 then
		TellRefused(ply, "hotswap: " .. feature .. " refused, nothing copied:", refused)
		return
	end
	for _, item in ipairs(swappable) do item.into[item.key] = item.fn end
	Tell(ply, "hotswap: " .. feature .. " " .. table.concat(args, " ", 2) .. " swapped")
end)
