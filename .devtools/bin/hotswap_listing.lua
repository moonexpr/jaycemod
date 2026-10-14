-- Prints what `ws_hotswap_feature <feature>` would list on the server
-- (swappable methods, refused ones with their reasons), headlessly: the
-- feature's root loads once as the live controller in a fake GMod, then
-- the server's hotswap.lua reruns it as it does in game. Every engine
-- global the files read is a stub of its own name (any field of it, and
-- any call, is the stub), so a stub is never mistaken for a table the
-- fresh controller holds. Diff the output before and after splitting a
-- controller: a split must not change which methods swap.
--
--   luajit .devtools/bin/hotswap_listing.lua capture   (from the repo root)
local T = dofile("tests/harness.lua")

local feature = assert(arg[1], "usage: hotswap_listing.lua <feature>")
local ROOT_FILE = "features/" .. feature .. "/sv.lua"

local stubs = {}
local function Stub(name)
	if not stubs[name] then
		local stub = setmetatable({}, {})
		getmetatable(stub).__index = function() return stub end
		getmetatable(stub).__call = function() return stub end
		stubs[name] = stub
	end
	return stubs[name]
end

-- Globals: the real ones, then a stub per missing name.
local globals = setmetatable({}, {
	__index = function(_, name)
		local value = _G[name]
		if value == nil then return Stub(name) end
		return value
	end,
})

local events = setmetatable({}, { __index = function(_, name) return Stub("WS.Events." .. name) end })
local GAMEMODE_ROOT, CHUNK_ENV = T.ROOT, globals
local WS = setmetatable({
	FeatureParts = T.FeatureParts,
	Events = events,
	Feature = function(name) return Stub("feature " .. name) end,
}, { __index = function(_, name) return Stub("WS." .. name) end })
-- hotswap.lua reads the root and the module environment off WS.require's upvalues
function WS.require(name)
	local _ = GAMEMODE_ROOT, CHUNK_ENV
	return T.require(name)
end

local liveEnv = setmetatable({ WS = WS }, { __index = globals })
local live = setfenv(assert(loadfile(T.ROOT .. ROOT_FILE)), liveEnv)()
WS.Feature = function(name)
	if name == feature then return live end
	return Stub("feature " .. name)
end

local commands = {}
local hotswapEnv = setmetatable({
	WS = WS,
	_G = globals,
	CompileFile = function(path) return assert(loadfile(path)) end,
	concommand = { Add = function(name, fn) commands[name] = fn end },
	IsValid = function(v) return v ~= nil end,
}, { __index = _G })
setfenv(assert(loadfile(".devtools/bin/server_root/hotswap.lua")), hotswapEnv)()
commands.ws_hotswap_feature(nil, nil, { feature })
