-- addons/sandcastle/cfg/sandcastle_defaults.cfg holds every convar the
-- addon creates, each at the default its code gives it (commented out where
-- it needs sv_cheats), and only those.
local T = dofile("tests/harness.lua")

local ADDON = "addons/sandcastle"
local CFG = ADDON .. "/cfg/sandcastle_defaults.cfg"

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

-- name -> value, from lines `name "value"` and `// name "value"`.
local function CfgValues()
	local values = {}
	for line in ReadFile(CFG):gmatch("[^\n]+") do
		local name, value = line:match('^%s*/?/?%s*([%w_]+)%s+"([^"]*)"%s*$')
		if name then
			T.eq(values[name], nil, name .. " listed once")
			values[name] = value
		end
	end
	return values
end

-- The convars whose default the code gives as a literal string: name -> value.
-- And how many convars are created from anything else.
local function CodeDefaults()
	local defaults, indirect = {}, 0
	local list = assert(io.popen("find " .. ADDON .. " -name '*.lua'"))
	for path in list:lines() do
		local text = ReadFile(path)
		for call in text:gmatch("[%w_]*ConVar%w*%b()") do
			if call:match("^CreateConVar") or call:match("^CreateClientConVar") or call:match("^ConVarOrCreate") then
				local name, value = call:match('^[%w_]+%(%s*"([%w_]+)",%s*"([^"]*)"')
				if name then defaults[name] = value else indirect = indirect + 1 end
			end
		end
	end
	list:close()
	return defaults, indirect
end

-- The convars created from constants, loops and tables, resolved from the
-- modules that hold their defaults.
local function IndirectDefaults(defaults)
	defaults.mp_aiwar_team_size = tostring(T.require("features.aiwar.model").TEAM_SIZE_DEFAULT)
	defaults.ws_nodegraph_max_nodes = tostring(T.require("foundation.nodegraph").MAX_NODES)
	defaults.tf_max_active_zombie = tostring(T.require("features.haunting.zombie").MAX_ACTIVE_DEFAULT)
	defaults.tf_flag_caplimit = tostring(T.require("features.flag.model").CAPLIMIT_DEFAULT)
	defaults.ws_mvm_setup_time = tostring(T.require("features.mvm.model").SETUP_SECONDS)
	defaults.tf_bot_difficulty = tostring(T.require("features.aiwar.marksmanship").DEFAULT)
	for _, boss in ipairs({ "features.haunting.eyeball_boss", "features.haunting.headless_hatman", "features.haunting.merasmus" }) do
		for name, value in pairs(T.require(boss).CONVARS) do defaults[name] = tostring(value) end
	end
	local Overlay = T.require("features.nbdebug.ns_overlay")
	for _, part in ipairs(Overlay.PARTS) do defaults[Overlay.ConVar(part)] = "1" end
end

-- The creating calls IndirectDefaults resolves: the bosses' table, the
-- zombie cap, the flag cap limit, MvM's setup time, the soldiers' difficulty, the node graph cap, the war's team size,
-- the overlay's parts;
-- the rounds' helper ConVarOrCreate, its definition and its CreateConVar;
-- and sh_core's replicating CreateConVar and the client's copy of a server
-- convar (system_server_convars), which create none of their own.
local INDIRECT_CALLS = 12

T.test("every convar the code creates is in the cfg at its default", function()
	local defaults, indirect = CodeDefaults()
	T.eq(indirect, INDIRECT_CALLS, "no convar created another way the test does not resolve")
	IndirectDefaults(defaults)
	local values, count = CfgValues(), 0
	for name, default in pairs(defaults) do
		count = count + 1
		T.eq(values[name], default, name)
	end
	T.eq(count >= 40, true, "the convars were found: " .. count)
end)

T.test("the cfg sets nothing the code does not create", function()
	local defaults = CodeDefaults()
	IndirectDefaults(defaults)
	for name in pairs(CfgValues()) do T.eq(defaults[name] ~= nil, true, name .. " is created by the code") end
end)

T.finish()
