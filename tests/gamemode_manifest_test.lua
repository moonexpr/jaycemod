-- The gamemode's manifest, gamemodes/sandcastle/sandcastle.txt, as GMod's
-- main menu reads it (wiki: Gamemode_Creation): its settings block offers
-- convars when a server is started, and GMod creates them before the
-- gamemode's Lua runs. So each must be well formed and default to what the
-- code gives it (addons/sandcastle/cfg/sandcastle_defaults.cfg, which
-- cfg_defaults_test holds to the code), or the menu and the code disagree.
local T = dofile("tests/harness.lua")

local MANIFEST = "addons/sandcastle/gamemodes/sandcastle/sandcastle.txt"
local CFG = "addons/sandcastle/cfg/sandcastle_defaults.cfg"
-- the setting types GMod's menu takes (case-sensitive)
local TYPES = { Text = true, CheckBox = true, Numeric = true }

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

-- A KeyValues file into nested tables: "key" "value" pairs and "key" { ... }.
-- Words are quoted or bare; braces are words of their own; // comments run
-- to the end of the line.
local function KeyValues(text)
	local tokens, at = {}, 1
	while at <= #text do
		local c = text:sub(at, at)
		if c:match("%s") then
			at = at + 1
		elseif text:sub(at, at + 1) == "//" then
			at = (text:find("\n", at, true) or #text) + 1
		elseif c == '"' then
			local stop = text:find('"', at + 1, true)
			tokens[#tokens + 1] = { text = text:sub(at + 1, stop - 1) }
			at = stop + 1
		elseif c == "{" or c == "}" then
			tokens[#tokens + 1] = { text = c, brace = true }
			at = at + 1
		else
			local word = text:match("^[^%s{}\"]+", at)
			tokens[#tokens + 1] = { text = word }
			at = at + #word
		end
	end
	local i = 1
	local function Block()
		local t = {}
		while tokens[i] and tokens[i].text ~= "}" do
			local key = tokens[i].text
			i = i + 1
			if tokens[i].brace and tokens[i].text == "{" then
				i = i + 1
				t[key] = Block()
				i = i + 1
			else
				t[key] = tokens[i].text
				i = i + 1
			end
		end
		return t
	end
	return Block()
end

local function CfgValues()
	local values = {}
	for line in ReadFile(CFG):gmatch("[^\n]+") do
		local name, value = line:match('^%s*([%w_]+)%s+"([^"]*)"%s*$')
		if name then values[name] = value end
	end
	return values
end

local manifest = KeyValues(ReadFile(MANIFEST)).sandcastle

T.test("the manifest names its base, title, maps, category and menu", function()
	T.eq(manifest.base, "sandbox", "base")
	T.eq(manifest.title, "Sandcastle", "title")
	T.eq(manifest.category, "pvp", "category")
	T.eq(manifest.menusystem, "1", "selectable from the menu")
	T.eq(type(manifest.maps), "string", "a map filter")
end)

T.test("every setting is well formed and defaults to what the code gives it", function()
	local defaults, count = CfgValues(), 0
	T.eq(type(manifest.settings), "table", "a settings block")
	for index, s in pairs(manifest.settings) do
		count = count + 1
		local where = "setting " .. index .. " (" .. tostring(s.name) .. ")"
		T.eq(type(s.name) == "string" and type(s.text) == "string" and type(s.help) == "string", true, where .. ": name, text and help")
		T.eq(TYPES[s.type] == true, true, where .. ": a type GMod takes, not " .. tostring(s.type))
		T.eq(defaults[s.name] ~= nil, true, where .. ": a convar the addon creates")
		T.eq(s.default, defaults[s.name], where .. ": the code's default")
		if s.type == "CheckBox" then T.eq(s.default == "0" or s.default == "1", true, where .. ": a switch") end
	end
	T.eq(count > 0, true, "some settings")
end)

T.finish()
