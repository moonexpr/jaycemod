-- Minimal harness for Sandcastle's pure-logic libraries, run under plain
-- LuaJIT (no GMod). Libraries under test live in gamemode/foundation/ and use
-- no GMod globals, so a test loads them with T.require.
local T = { passed = 0, failed = 0 }

T.ROOT = "addon/gamemodes/sandcastle/gamemode/"

-- Lua 5.1's require for a module(...) file under T.ROOT, as WS.require
-- does in the game: once, calling the chunk with its dotted name. Above its
-- module(...) call the chunk sees this require, to load its siblings.
local CHUNK_ENV = setmetatable({}, { __index = _G })

function T.require(name)
	if package.loaded[name] == nil then
		local chunk = assert(loadfile(T.ROOT .. name:gsub("%.", "/") .. ".lua"))
		setfenv(chunk, CHUNK_ENV)(name)
	end
	return package.loaded[name]
end
CHUNK_ENV.require = T.require

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
