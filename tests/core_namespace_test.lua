-- foundation.core.namespace: the global tables a namespace index fills, one
-- explicit Export or Replace a key.
local T = dofile("tests/harness.lua")
local Namespace = T.require("foundation.core.namespace")

local function Raises(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raises")
	return tostring(err)
end

local function Has(text, part, what)
	T.eq(text:find(part, 1, true) ~= nil, true, what .. ": " .. text)
end

T.test("a namespace is the global table of that name, made when absent", function()
	local globals = { math = { floor = 1 } }
	T.eq(Namespace.Namespace(globals, "math"), globals.math, "an existing table is extended")
	local list = Namespace.Namespace(globals, "list")
	T.eq(globals.list, list, "an absent one is made")
	T.eq(Namespace.Namespace(globals, "list"), list, "and found again")
end)

T.test("a global that is not a table cannot be a namespace", function()
	local err = Raises(Namespace.Namespace, { list = 3 }, "list")
	Has(err, "list", "names it")
end)

T.test("export sets a free key", function()
	local globals = {}
	local list = Namespace.Namespace(globals, "list")
	local queue = { New = function() end }
	Namespace.Export(list, "queue", queue)
	T.eq(list.queue, queue, "exported")
end)

T.test("export refuses a key something else holds, naming it", function()
	local globals = { math = { random = function() end } }
	local math = Namespace.Namespace(globals, "math")
	local err = Raises(Namespace.Export, math, "random", {})
	Has(err, "math.random", "names the key")
	Has(err, "Replace", "points at the declared way")
end)

T.test("export refuses nothing and a key that is not a name", function()
	local list = Namespace.Namespace({}, "list")
	Has(Raises(Namespace.Export, list, "queue", nil), "list.queue", "a missing value names its key")
	Raises(Namespace.Export, list, 3, {})
	Raises(Namespace.Export, list, "", {})
	Raises(Namespace.Export, "list", "queue", {})
end)

T.test("exporting a key again, as a reload does, replaces its own value", function()
	local list = Namespace.Namespace({}, "list")
	Namespace.Export(list, "Queue", function() return 1 end)
	local fresh = function() return 2 end
	Namespace.Export(list, "Queue", fresh)
	T.eq(list.Queue, fresh, "the reloaded value")
end)

T.test("replace takes a key over on purpose, and again on a reload", function()
	local default = function() return "gmod" end
	local math = Namespace.Namespace({ math = { Clamp = default } }, "math")
	local ours = function() return "ours" end
	Namespace.Replace(math, "Clamp", ours)
	T.eq(math.Clamp, ours, "replaced")
	local reloaded = function() return "reloaded" end
	Namespace.Replace(math, "Clamp", reloaded)
	T.eq(math.Clamp, reloaded, "replaced again")
end)

T.test("replace refuses a key nothing holds: there is no default to replace", function()
	local math = Namespace.Namespace({ math = {} }, "math")
	Has(Raises(Namespace.Replace, math, "Clamp", function() end), "math.Clamp", "names the key")
end)

T.test("an index runs in an environment of the calls, require and the globals", function()
	local globals = { print = print }
	globals._G = globals
	local loaded = { ["foundation.list.queue"] = { New = function() end } }
	local function require(name) return loaded[name] end
	local env = Namespace.Environment(globals, require)
	local index = assert(loadstring([[
		local list = Namespace("list")
		Export(list, "queue", require("foundation.list.queue"))
		Export(list, "Queue", list.queue.New)
		Export(_G, "Queue", list.queue.New)
	]]))
	setfenv(index, env)()
	T.eq(globals.list.queue, loaded["foundation.list.queue"], "the module")
	T.eq(globals.list.Queue, loaded["foundation.list.queue"].New, "a factory in the namespace")
	T.eq(globals.Queue, loaded["foundation.list.queue"].New, "and as a plain global")
	T.eq(rawget(env, "list"), nil, "an index's locals stay its own")
end)

T.finish()
