-- The dev workbench's reload of a feature (sandcastle_dev's sv_reload.lua) runs the feature's
-- server root again with its `local Controller = {` rewritten to adopt the live controller. A
-- root the rewrite does not find is refused, so every feature's server files stop reloading: each
-- root's declaration must be one the reload's own pattern finds, exactly once, however the
-- formatter lays its opening brace.
local T = dofile ("tests/harness.lua")

local RELOAD = "addons/sandcastle_dev/lua/sandcastle_dev/sv_reload.lua"
local FEATURES = "addons/sandcastle/gamemodes/wetsands/gamemode/features/"

local function ReadFile (path)
	local file = assert (io.open (path))
	local text = file:read ("*a")
	file:close ()
	return text
end

-- The reload's own pattern and replacement, as its source writes them.
local function Adoption ()
	local source = ReadFile (RELOAD)
	local from = string.match (source, "\nlocal ADOPT_FROM = (%b\"\")")
	local to = string.match (source, "\nlocal ADOPT_TO = (%b\"\")")
	T.eq (from ~= nil and to ~= nil, true, "the reload names what it rewrites")
	return loadstring ("return " .. from) (), loadstring ("return " .. to) ()
end

local function Roots ()
	local roots = {}
	local found = io.popen ("ls " .. FEATURES .. "*/sv.lua")
	for path in found:lines () do roots [#roots + 1] = path end
	found:close ()
	return roots
end

-- A root with no controller (the system feature's: only its parts) has nothing to adopt, and the
-- reload says so; the rule is for the roots that declare one.
T.test ("the reload adopts the controller of every feature's server root that declares one, once", function ()
	local from, to = Adoption ()
	local declaring, missed = 0, {}
	for _, path in ipairs (Roots ()) do
		local source = ReadFile (path)
		if string.find (source, "\nlocal Controller%f[%W]") then
			declaring = declaring + 1
			local _, count = string.gsub (source, from, to, 1)
			if count ~= 1 then missed [#missed + 1] = path end
		end
	end
	T.eq (declaring > 0,              true, "found the roots declaring a controller")
	T.eq (table.concat (missed, " "), "",   "roots the reload would refuse")
end)

T.test ("what the reload writes still opens the controller's table, for the adoption to take", function ()
	local from, to = Adoption ()
	local rewritten = string.gsub ("\nlocal Controller =\n{\n\twar = nil\n}\n", from, to, 1)
	local adopted
	local chunk = assert (loadstring (rewritten .. "return Controller"))
	setfenv (chunk, { __dev_adopt = function (fresh)
		adopted = fresh
		return "the live controller"
	end })
	T.eq (chunk (),       "the live controller", "the root's Controller is what the adoption returns")
	T.eq (type (adopted), "table",               "the adoption is handed the root's fresh table")
end)

T.finish ()
