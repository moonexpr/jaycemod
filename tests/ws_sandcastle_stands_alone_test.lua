-- Sandcastle is the base other gamemodes derive from (Wetsands, Club Random),
-- so nothing in its tree reaches for Wetsands: not WS, not the namespaces
-- Wetsands publishes from its includes/ (gameplay, npc, system), and no
-- module of Wetsands' named in a string for WS.require ("games.<...>").
-- A file that needs them is Wetsands' and lives in Wetsands' tree.
local T = dofile ("tests/harness.lua")

local ROOT = "addons/sandcastle/gamemodes/sandcastle/"

-- Lua patterns for each way a file reaches Wetsands, with what it is.
local REACHES =
{
	{ "%f[%w_]WS%f[^%w_]%s*[%.:%[(]", "WS" },
	{ "%f[%w_.:]gameplay%s*[%.%[]", "the gameplay namespace" },
	{ "%f[%w_.:]npc%s*[%.%[]", "the npc namespace" },
	{ "%f[%w_.:]system%s*[%.%[]", "the system namespace" },
	{ "[\"']games%.[%w_.]+[\"']", "a Wetsands module by name" }
}

local function LuaFiles ()
	local files = {}
	for path in io.popen ("find " .. ROOT .. " -name '*.lua' | sort"):lines () do files [#files + 1] = path end
	return files
end

-- Each line of a file that reaches Wetsands, its comment left out: "path:line: what".
local function Reaches (path)
	local found, number = {}, 0
	for line in io.lines (path) do
		number = number + 1
		local code = line:gsub ("%-%-.*$", "")
		for _, reach in ipairs (REACHES) do
			if code:find (reach [1]) then found [#found + 1] = path .. ":" .. number .. ": " .. reach [2] end
		end
	end
	return found
end

T.test ("the scan reads Sandcastle's whole tree", function ()
	T.eq (#LuaFiles () > 100, true, "Sandcastle's Lua files found")
end)

T.test ("the scan finds each way of reaching Wetsands", function ()
	local reaching =
	{
		"WS.Feature (\"x\")", "local B = gameplay.buildings", "npc.targeting", "system.events",
		"ENT.Variant = \"games.gameplay.projectile.jar\""
	}
	for _, code in ipairs (reaching) do
		local hit = false
		for _, reach in ipairs (REACHES) do hit = hit or code:find (reach [1]) ~= nil end
		T.eq (hit, true, code)
	end
	-- a local of the same name read by method, and fields of other tables, are not Wetsands'
	for _, code in ipairs ({ "return gameplay:GetBool ()", "ent.npc.x", "self.system [1]", "NEWS.x" }) do
		local hit = false
		for _, reach in ipairs (REACHES) do hit = hit or code:find (reach [1]) ~= nil end
		T.eq (hit, false, code)
	end
end)

T.test ("no file in Sandcastle reaches Wetsands", function ()
	local found = {}
	for _, path in ipairs (LuaFiles ()) do
		for _, line in ipairs (Reaches (path)) do found [#found + 1] = line end
	end
	T.eq (table.concat (found, "\n"), "", "Sandcastle's references to Wetsands")
end)

T.finish ()
