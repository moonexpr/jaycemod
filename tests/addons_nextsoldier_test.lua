-- NextSoldier's addon (addons/nextsoldier): the soldier's modules under
-- lua/nextsoldier/, its base entities under lua/entities/, and the response
-- rules it speaks by (their GMod modules, their autorun and their scripts).
-- The gamemode loads the modules from the LUA path's root, not its own
-- folder, and keeps none of them.
local T = dofile("tests/harness.lua")

local ADDON = "addons/nextsoldier/"
local GAMEMODE_BASES = { "base_nextsoldier_npc", "base_nextsoldier_combat" }
local RESPONSE_RULES = {
	"lua/includes/modules/responserules.lua",
	"lua/includes/modules/responserules_script.lua",
	"lua/autorun/server/responserules.lua",
	"scripts/responserules/response_rules.txt",
	"scripts/responserules/combine.txt",
	"scripts/responserules/rebel.txt",
	"scripts/responserules/gestures.txt",
}

local function Exists(path)
	local file = io.open(path, "r")
	if file then file:close() end
	return file ~= nil
end

local function Lines(command)
	local pipe = assert(io.popen(command))
	local lines = {}
	for line in pipe:lines() do lines[#lines + 1] = line end
	pipe:close()
	return lines
end

T.test("the addon has a manifest", function()
	T.eq(Exists(ADDON .. "addon.json"), true, ADDON .. "addon.json")
end)

T.test("every nextsoldier module the index publishes is the addon's", function()
	local count = 0
	for module in pairs(T.Published.global) do
		if module:match("^nextsoldier%.") then
			count = count + 1
			T.eq(T.Path(module), ADDON .. "lua/" .. module:gsub("%.", "/") .. ".lua", module)
			T.eq(Exists(T.Path(module)), true, T.Path(module))
		end
	end
	T.eq(count > 0, true, "nextsoldier modules published")
end)

T.test("the index runs from the addon", function()
	T.eq(T.File("nextsoldier/sh_init.lua"), ADDON .. "lua/nextsoldier/sh_init.lua")
	T.eq(Exists(T.File("nextsoldier/sh_init.lua")), true, "the addon's index")
end)

T.test("the gamemode keeps no NextSoldier module", function()
	T.eq(#Lines("ls " .. T.ROOT .. "nextsoldier/ 2>/dev/null"), 0, T.ROOT .. "nextsoldier/")
end)

T.test("the soldier's base is the addon's; the gamemode's actors and combatants are the gamemode's", function()
	T.eq(Exists(ADDON .. "lua/entities/base_nextsoldier.lua"), true, "the base in the addon")
	T.eq(Exists(T.Entity("base_nextsoldier.lua")), false, "the base out of the gamemode")
	for _, class in ipairs(GAMEMODE_BASES) do
		T.eq(Exists(T.Entity(class .. ".lua")), true, class .. " in the gamemode")
		T.eq(Exists(ADDON .. "lua/entities/" .. class .. ".lua"), false, class .. " out of the addon")
	end
end)

local function Read(path)
	local file = assert(io.open(path))
	local text = file:read("*a")
	file:close()
	return text
end

local function Code(path)
	return (Read(path):gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", ""))
end

T.test("NextSoldier reads nothing of the gamemode, whose host hands it what it needs", function()
	for _, path in ipairs(Lines("find " .. ADDON .. "lua/nextsoldier " .. ADDON .. "lua/entities -name '*.lua'")) do
		local code = Code(path)
		T.eq(code:find("%f[%w_]WS%f[^%w_]"), nil, path .. " reads WS")
		T.eq(code:find("%f[%w_]GAMEMODE%f[^%w_]"), nil, path .. " reads GAMEMODE")
		for _, used in ipairs(T.Uses(code)) do
			T.eq(used:match("^games%.") or used:match("^features%.") or used:match("^includes%."), nil,
				path .. " reads " .. used)
		end
	end
end)

T.test("NextSoldier loads by plain includes, a line a file, each its own module's name", function()
	local init = Code(T.File("nextsoldier/sh_init.lua"))
	T.eq(init:find("Defer", 1, true), nil, "no Defer")
	T.eq(init:find("Namespace", 1, true), nil, "no Namespace")
	T.eq(Code(T.ROOT .. "shared_loader.lua"):find('Index("nextsoldier/', 1, true), nil, "not an Index of the gamemode's")

	local lines, order = {}, {}
	for path in init:gmatch('Load%("([%w_/.]+)"%)') do
		T.eq(lines[path], nil, path .. " loaded once")
		lines[path] = true
		order[#order + 1] = path
	end
	for _, full in ipairs(Lines("find " .. ADDON .. "lua/nextsoldier -name '*.lua'")) do
		local path = full:sub(#ADDON + #"lua/" + 1)
		if path ~= "nextsoldier/sh_init.lua" then
			T.eq(lines[path], true, path .. " has its line")
			local name = path:gsub("%.lua$", ""):gsub("/", ".")
			T.eq(Code(full):match('module%("([%w_.]+)"%)'), name, path .. " names its module")
		end
	end
	T.eq(#order > 0, true, "the lines were read")
end)

T.test("the collections are the addon's only exports, each file a part at its path", function()
	local keys = {}
	for key in pairs(nextsoldier) do keys[#keys + 1] = key end
	table.sort(keys)
	T.eq(table.concat(keys, ","), "base,behavior,body,bots,host,locomotion,senses,squad,world")
	T.eq(nextsoldier.world.doors, package.loaded["nextsoldier.world.doors"], "a part is its module")
	T.eq(type(nextsoldier.world.BrushSweep), "function", "a single export is a function of its collection")
end)

T.test("a host is held to the port before a soldier reads it", function()
	local Host = nextsoldier.host
	T.eq(pcall(Host.Install, {}), false, "a host lacking the port's methods is refused")
	local kept = Host.current
	local host = {}
	for _, method in ipairs(Host.PORT:Methods()) do host[method] = function() end end
	T.eq(Host.Install(host), host)
	T.eq(Host.current, host)
	Host.current = kept
end)

T.test("jumping is the base's, whatever class asks it to", function()
	local base = Code(ADDON .. "lua/entities/base_nextsoldier.lua")
	local war = Code(T.ROOT .. "sh_war_soldier.lua")
	for _, method in ipairs({
		"OnStartClimbing", "CustomClimbing", "NSVaultPlan", "NSVaultRun", "NSVault", "NSHop", "NSHopPlain", "NSTakeHop",
		"JumpAct", "JumpSequence", "PlaysJump",
	}) do
		T.eq(base:find("function ENT:" .. method .. "(", 1, true) ~= nil, true, method .. " in the base")
	end
	for _, method in ipairs({ "CustomClimbing", "NSVaultPlan", "NSVaultRun", "NSVault", "NSHop", "NSHopPlain" }) do
		T.eq(war:find("function ENT:" .. method .. "(", 1, true), nil, method .. " out of the war's soldier")
	end
end)

T.test("the response rules are merged into the addon", function()
	for _, path in ipairs(RESPONSE_RULES) do T.eq(Exists(ADDON .. path), true, path) end
	T.eq(#Lines("ls addons/responserules/ 2>/dev/null"), 0, "addons/responserules/ is gone")
	T.eq(T.Path("responserules"), ADDON .. "lua/includes/modules/responserules.lua", "GMod's require finds it")
end)

T.test("the base takes the one model it is given and falls as a player falls", function()
	local base = Code(ADDON .. "lua/entities/base_nextsoldier.lua")
	T.eq(base:find("self:SetModel(self.Model)", 1, true) ~= nil, true, "its model")
	T.eq(base:find("Models", 1, true), nil, "no list to draw one from")
	T.eq(base:find('self.loco:SetGravity(GetConVar("sv_gravity"):GetFloat())', 1, true) ~= nil, true, "a player's gravity")
end)

T.test("a path's climb lands past the ledge's foot, and plans its path again from there", function()
	local base = Code(ADDON .. "lua/entities/base_nextsoldier.lua")
	T.eq(base:find("Leap.Landing(after, pos, goal.type == CLIMB_UP)", 1, true) ~= nil, true, "where it lands")
	T.eq(base:find("end, ledge, function() PathAgain(self) end)", 1, true) ~= nil, true, "its path planned again")
end)

T.test("a rappel shows a rope and sounds, for as long as it lasts", function()
	local war = Code(T.ROOT .. "sh_war_soldier.lua")
	T.eq(war:find('ents.Create("keyframe_rope")', 1, true) ~= nil, true, "the rope")
	T.eq(war:find("self:DeleteOnRemove(self.nsRope)", 1, true) ~= nil, true, "gone with the soldier")
	T.eq(war:find("if self.NSRappelling then self:NSRappelEnd(true) end", 1, true) ~= nil, true, "gone on landing")
	T.eq(war:find("if self.NSRappelling then self:NSRappelEnd(false) end", 1, true) ~= nil, true, "gone on death")
end)

T.test("a hard landing slows the body while it recovers", function()
	local base = Code(ADDON .. "lua/entities/base_nextsoldier.lua")
	local war = Code(T.ROOT .. "sh_war_soldier.lua")
	T.eq(base:find("Locomotion.Recovering(", 1, true) ~= nil, true, "its speed each tick")
	T.eq(war:find("if Noise.HardLanding(fall) then self:NSImpact() end", 1, true) ~= nil, true, "on a hard landing")
end)

T.finish()
