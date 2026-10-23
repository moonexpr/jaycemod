-- Minimal harness for Sandcastle's pure-logic libraries, run under plain
-- LuaJIT (no GMod). Libraries under test live in gamemode/foundation/ and use
-- no GMod globals, so a test loads them with T.require.
local T = { passed = 0, failed = 0 }

T.ROOT = "addons/sandcastle/gamemodes/sandcastle/gamemode/"

-- Lua 5.1's require for a module(...) file under T.ROOT, as WS.require
-- does in the game: once, calling the chunk with its dotted name. Above its
-- module(...) call the chunk sees this require, to load its siblings.
local CHUNK_ENV = setmetatable({}, { __index = _G })

-- The repo's own addons' GMod modules (lua/includes/modules/<name>.lua,
-- which GMod's require loads by a name without dots).
T.MODULE_DIRS = {
	"addons/responserules/lua/includes/modules/",
	"addons/teamtint/lua/includes/modules/",
	"addons/sandcastle_dev/lua/includes/modules/",
}

local function Path(name)
	if not name:find(".", 1, true) then
		for _, dir in ipairs(T.MODULE_DIRS) do
			local path = dir .. name .. ".lua"
			local f = io.open(path, "r")
			if f then
				f:close()
				return path
			end
		end
	end
	return T.ROOT .. name:gsub("%.", "/") .. ".lua"
end

function T.require(name)
	if package.loaded[name] == nil then
		local chunk = assert(loadfile(Path(name)))
		setfenv(chunk, CHUNK_ENV)(name)
	end
	return package.loaded[name]
end
CHUNK_ENV.require = T.require

local function ReadFile(path)
	local file = assert(io.open(path))
	local text = file:read("*a")
	file:close()
	return text
end

-- The index and init files shared_loader.lua runs, in its order.
function T.Indexes()
	local paths = {}
	for path in ReadFile(T.ROOT .. "shared_loader.lua"):gmatch('Index%(%s*"([%w_/.]+)"%s*%)') do
		paths[#paths + 1] = path
	end
	return paths
end

-- Every published module: T.Published.global[module name] -> its global
-- ("math.geometry", or "transaction" at foundation's root), and
-- T.Published.module[global] -> the module name, read from the indexes.
T.Published = { global = {}, module = {} }
for _, path in ipairs(T.Indexes()) do
	local text = ReadFile(T.ROOT .. path)
	local namespaces = { _G = "" }
	for var, name in text:gmatch('local%s+([%w_]+)%s*=%s*Namespace%(%s*"([%w_]+)"%s*%)') do namespaces[var] = name .. "." end
	local function Publish(var, key, module)
		local global = assert(namespaces[var], path .. ": no namespace " .. var) .. key
		T.Published.global[module], T.Published.module[global] = global, module
	end
	for var, key, module in text:gmatch('Export%(%s*([%w_]+)%s*,%s*"([%w_]+)"%s*,%s*require%(%s*"([%w_.]+)"%s*%)%s*%)') do Publish(var, key, module) end
	for var, key, module in text:gmatch('Defer%(%s*([%w_]+)%s*,%s*"([%w_]+)"%s*,%s*"([%w_.]+)"%s*%)') do Publish(var, key, module) end
end

-- The modules a source text uses, each once: every require of one, and
-- every read of a published module's global (math.geometry, transaction),
-- comments left out.
function T.Uses(text)
	local code = text:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
	local uses, seen = {}, {}
	local function Add(name)
		if not seen[name] then
			seen[name] = true
			uses[#uses + 1] = name
		end
	end
	for name in code:gmatch("require%(%s*[\"']([%w_.]+)[\"']") do Add(name) end
	for global, module in pairs(T.Published.module) do
		if code:find("%f[%w_.]" .. global:gsub("%.", "%%.") .. "%f[^%w_]") then Add(module) end
	end
	table.sort(uses)
	return uses
end

-- The globals, published as shared_loader.lua publishes them in the game:
-- foundation's at once, games' on first read, so a module may read another
-- by its global (math.geometry) under LuaJIT too.
do
	local env = T.require("foundation.core.namespace").Environment(_G, T.require)
	for _, path in ipairs(T.Indexes()) do
		local chunk = assert(loadfile(T.ROOT .. path))
		setfenv(chunk, env)()
	end
end

-- A gamemode tree on disk: `root` is the folder holding features/, ending in
-- "/" (T.ROOT, or a temp directory in the harness's own tests).
--   RealmSource(name, realm): the text of features/<name>/<realm>.lua, then
--     of every <realm>_*.lua beside it in name order, joined by newlines, so
--     a test reading a controller's text reads its parts too.
--   FeatureParts(env, name): games.system.features Parts over files loaded
--     from root, as WS.FeatureParts in the game.
function T.FeatureTree(root)
	local tree = {}
	local function Read(path)
		local f = io.open(root .. path, "rb")
		if not f then return nil end
		local text = f:read("*a")
		f:close()
		return text
	end

	function tree.RealmSource(name, realm)
		local Features = T.require("games.system.features")
		local rootPath = Features.PartPath(name, realm)
		local texts = { Read(rootPath) or error("no " .. root .. rootPath, 2) }
		local list = assert(io.popen("ls -1 '" .. root .. Features.ROOT .. name .. "'"))
		local parts = {}
		for fileName in list:lines() do
			if fileName:match("^" .. realm .. "_.*%.lua$") then parts[#parts + 1] = fileName end
		end
		list:close()
		table.sort(parts)
		for _, fileName in ipairs(parts) do texts[#texts + 1] = Read(Features.ROOT .. name .. "/" .. fileName) end
		return table.concat(texts, "\n")
	end

	local port = {}
	function port:Compile(path)
		return (loadfile(root .. path))
	end
	function tree.FeatureParts(env, name)
		return T.require("games.system.features").Parts(port, env, name)
	end
	return tree
end

do
	local gamemode = T.FeatureTree(T.ROOT)
	T.RealmSource, T.FeatureParts = gamemode.RealmSource, gamemode.FeatureParts
end

-- A recorder of a load's wiring, whose ids must be unique across a
-- feature's files: fake hook, concommand, cvars, timer and Events tables that record
-- each registration by the key GMod replaces it under, as "<kind> <key>".
--   wiring:Registered() -> every key recorded, in order, repeats included
--   wiring:Duplicates() -> the keys recorded more than once, in first order
-- A convar callback without an id is added, not replaced, so it has no key.
function T.Wiring()
	local recorded = {}
	local function Record(...)
		recorded[#recorded + 1] = table.concat({ ... }, " ")
	end
	local wiring = {
		hook = { Add = function(event, id) Record("hook", event, tostring(id)) end },
		concommand = { Add = function(name) Record("concommand", name) end },
		cvars = {
			AddChangeCallback = function(name, _, id)
				if id ~= nil then Record("cvars", name, id) end
			end,
		},
		timer = { Create = function(name) Record("timer", name) end },
		Events = { Listen = function(event, id) Record("listen", event, id) end },
	}
	function wiring:Registered()
		local list = {}
		for i, key in ipairs(recorded) do list[i] = key end
		return list
	end
	function wiring:Duplicates()
		local counts, list = {}, {}
		for _, key in ipairs(recorded) do
			counts[key] = (counts[key] or 0) + 1
			if counts[key] == 2 then list[#list + 1] = key end
		end
		return list
	end
	return wiring
end

function T.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		T.passed = T.passed + 1
	else
		T.failed = T.failed + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

function T.eq(actual, expected, what)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
	end
end

-- A tuning value (a timing, a radius, damage, money) the operator tweaks: a
-- test checks it is still defined, never its number; behaviour is tested
-- through the constant.
function T.defined(value, what)
	if type(value) ~= "number" then
		error(string.format("%s: expected a number, got %s", what or "value", tostring(value)), 2)
	end
end

function T.near(actual, expected, epsilon, what)
	if math.abs(actual - expected) > (epsilon or 1e-6) then
		error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
	end
end

function T.finish()
	print(string.format("%d passed, %d failed", T.passed, T.failed))
	os.exit(T.failed == 0 and 0 or 1)
end

return T
