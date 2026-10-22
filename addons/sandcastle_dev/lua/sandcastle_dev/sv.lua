-- Sandcastle's dev workbench: a gamerules harness that stands in for the
-- map's gamerules, capture and restore of the gameplay state, saved
-- scenarios and a hot reload that keeps the state, so a change is tried
-- without changing map. Every command has a Lua function on `dev` that
-- returns a table; the console commands print the same as JSON.
--
-- Only where DEBUG is set: the dev server's mount
-- (.devtools/bin/server_root/sandcastle_dev.lua) sets it and runs this file
-- with its loader (dev.load, dev.require). The addon has no autorun of its
-- own, so a release build that carried it would still never run it. The
-- pure parts are modules in lua/includes/modules/, tested under LuaJIT
-- (tests/dev_*_test.lua).
if not DEBUG or not dev or not dev.load then return end

local PARTS = {
	"sv_util",
	"sv_harness",
	"sv_state",
}

for _, part in ipairs(PARTS) do dev.load("sandcastle_dev/" .. part .. ".lua") end

-- Runs this file again, and through it every part: the workbench's own
-- edits. Its modules load again too.
function dev.reload_self()
	for name in pairs(package.loaded) do
		if string.StartWith(name, "sandcastle_dev_") then package.loaded[name] = nil end
	end
	dev.load("sandcastle_dev/sv.lua")
	return { reloaded = PARTS }
end
