-- ws/sv_content.lua: clients download every file under the gamemode's
-- content/ (GMod mounts it as game content on the server alone), at its
-- path under content/. Run against a fake file system.
local T = dofile("tests/harness.lua")

local TREE = {
	["gamemodes/sandcastle/content/"] = { {}, { "materials", "sound" } },
	["gamemodes/sandcastle/content/materials/"] = { {}, { "sandcastle" } },
	["gamemodes/sandcastle/content/materials/sandcastle/"] = { {}, { "kill_icons" } },
	["gamemodes/sandcastle/content/materials/sandcastle/kill_icons/"] = { { "hl2_0a1b2c3d.png", "hl2_0a1b2c3d_neg.png" }, {} },
	["gamemodes/sandcastle/content/sound/"] = { { "loose.wav" }, { "npc" } },
	["gamemodes/sandcastle/content/sound/npc/"] = { { "hello.wav" }, {} },
}

local function Load()
	local sent = {}
	local env = setmetatable({
		GM = { FolderName = "sandcastle" },
		file = {
			Find = function(pattern, path)
				T.eq(path, "GAME", "searched as game content")
				local dir = pattern:match("^(.*/)%*$")
				local entry = TREE[dir] or { {}, {} }
				return entry[1], entry[2]
			end,
		},
		resource = { AddFile = function(p) sent[#sent + 1] = p end },
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sv_content.lua")), env)()
	return sent
end

T.test("every file under content/, at any depth, is sent at its game path", function()
	local sent = Load()
	table.sort(sent)
	T.eq(table.concat(sent, " "), table.concat({
		"materials/sandcastle/kill_icons/hl2_0a1b2c3d.png",
		"materials/sandcastle/kill_icons/hl2_0a1b2c3d_neg.png",
		"sound/loose.wav",
		"sound/npc/hello.wav",
	}, " "))
end)

T.finish()
