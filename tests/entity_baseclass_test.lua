-- GMod's baseclass.Get(name), called while an entity file loads, also sets ENT.Base = name (what
-- DEFINE_BASECLASS relies on). An entity file that reaches any class but its own base that way,
-- at its top level, silently takes that class as its base and skips the ones between.
local T = dofile ("tests/harness.lua")

local ROOTS =
{
	"addons/sandcastle/gamemodes/sandcastle/entities/entities/",
	"addons/nextsoldier/lua/entities/"
}

local function Files ()
	local files = {}
	for _, root in ipairs (ROOTS) do
		local list = io.popen ('find "' .. root .. '" -name "*.lua"')
		for path in list:lines () do files [#files + 1] = path end
		list:close ()
	end
	table.sort (files)
	return files
end

T.test ("an entity file reaches no class but its own base with baseclass.Get as it loads", function ()
	local checked = 0
	for _, path in ipairs (Files ()) do
		local f = assert (io.open (path, "r"))
		local text = f:read ("*a")
		f:close ()
		local base = text:match ('\nENT%.Base = "([%w_]+)"') or text:match ('^ENT%.Base = "([%w_]+)"')
		for line in text:gmatch ("[^\n]+") do
			local reached = line:match ('^local [%w_]+ = baseclass%.Get%s*%("([%w_]+)"%)')
			if reached then
				checked = checked + 1
				T.eq (reached, base, path .. " reaches " .. reached .. " as it loads, its base " .. tostring (base))
			end
		end
	end
	T.eq (checked > 0, true, "some reached")
end)

T.finish ()
