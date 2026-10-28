local T = dofile("tests/harness.lua")
local Base = nextsoldier.base

local GAMEMODE = T.ROOT
local ENTITIES = "addons/sandcastle/gamemodes/sandcastle/entities/entities/"
-- The war's soldier classes, on NextSoldier's base.
local SOLDIER_CLASSES = { "npc_nextsoldier", "npc_path_probe" }

local function Read(path)
	local file = assert(io.open(path))
	local text = file:read("*a")
	file:close()
	return (text:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", ""))
end

local function Lines(command)
	local list, lines = assert(io.popen(command)), {}
	for line in list:lines() do lines[#lines + 1] = line end
	list:close()
	return lines
end

-- What GMod gives every scripted entity, which no base declares.
local GMOD = {
	Base = true, Type = true, PrintName = true, Category = true, Spawnable = true, AdminOnly = true,
	Author = true, Purpose = true, Instructions = true, RenderGroup = true, AutomaticFrameAdvance = true,
	Initialize = true, Think = true, Draw = true, OnRemove = true,
	GetGroundEntity = true,
}

-- Ours: the soldier's own methods and settings.
local function Ours(name) return name:match("^NS") ~= nil or name:match("^WS") ~= nil end

T.test("a name is declared by one component only", function()
	local seen = {}
	for _, component in ipairs(Base.COMPONENTS) do
		for _, set in ipairs({ component.methods:Methods(), Base.Hooks(component), Base.Fields(component) }) do
			for _, name in ipairs(set) do
				T.eq(seen[name], nil, name .. " is " .. component.name .. "'s and " .. tostring(seen[name]) .. "'s")
				seen[name] = component.name
			end
		end
	end
end)

T.test("the base port is every required component's methods, in order", function()
	local methods = {}
	for _, component in ipairs(Base.COMPONENTS) do
		if not component.optional then
			for _, name in ipairs(component.methods:Methods()) do methods[#methods + 1] = name end
		end
	end
	T.eq(table.concat(Base.METHODS:Methods(), " "), table.concat(methods, " "))
end)

T.test("an optional component's methods are not required, and a body without them is still a base", function()
	T.eq(Base.POSTURE.optional, true)
	T.eq(Base.METHODS:Methods()[1] ~= nil, true)
	for _, name in ipairs(Base.POSTURE.methods:Methods()) do
		for _, required in ipairs(Base.METHODS:Methods()) do T.eq(required ~= name, true, name .. " is not required") end
	end
end)

T.test("a soldier has an optional component whole or not at all", function()
	local whole, none, half = {}, {}, {}
	for _, name in ipairs(Base.POSTURE.methods:Methods()) do whole[name] = function() end end
	half[Base.POSTURE.methods:Methods()[1]] = function() end
	T.eq(Base.Has(whole, Base.POSTURE), true)
	T.eq(Base.Has(none, Base.POSTURE), false)
	local ok = pcall(Base.Has, half, Base.POSTURE)
	T.eq(ok, false, "half a component is refused")
end)

T.test("each name's component is TF2's (INextBot and its ILocomotion, IBody, IVision, IIntention)", function()
	T.eq(Base.ComponentOf("FollowPath").name, "locomotion")
	T.eq(Base.ComponentOf("OnSpotted").name, "vision")
	T.eq(Base.ComponentOf("SpawnHealth").name, "nextbot")
	T.eq(Base.ComponentOf("Disposition").name, "nextbot")
	T.eq(Base.ComponentOf("GetEnemy").name, "intention")
	T.eq(Base.ComponentOf("SelectWeapon").name, "body")
	T.eq(Base.ComponentOf("SetCrouching").name, "posture")
	T.eq(Base.ComponentOf("NSKit"), nil)
end)

T.test("no coroutine: the behaviour coroutine's names are replaced, by Reset and locomotion's ticked processes", function()
	for _, name in ipairs({ "BehaveStart", "YieldCoroutine", "PauseCoroutine" }) do
		T.eq(Base.ComponentOf(name), nil, name .. " is no component's")
		T.eq(type(Base.REPLACED[name]), "string", name .. " is replaced")
	end
end)

T.test("every hook the soldier defines on the base is declared", function()
	local text = Read(GAMEMODE .. "ws/sh_war_soldier.lua")
	for _, name in ipairs(SOLDIER_CLASSES) do text = text .. Read(ENTITIES .. name .. ".lua") end
	for name in text:gmatch("function%s+ENT:([%w_]+)%s*%(") do
		T.eq(Ours(name) or GMOD[name] == true or Base.HOOKS:Has(name), true, "ENT:" .. name .. " is a declared hook")
	end
end)

T.test("every setting the soldier classes and profiles give the base is declared", function()
	for _, class in ipairs(SOLDIER_CLASSES) do
		local path = ENTITIES .. class .. ".lua"
		for name in Read(path):gmatch("\n%s*ENT%.([%w_]+)%s*=") do
			T.eq(Ours(name) or GMOD[name] == true or Base.FIELDS:Has(name), true, path .. ": ENT." .. name .. " is a declared field")
		end
	end
	-- a profile's fields are set on the soldier as it spawns (npc_nextsoldier's NSProfile)
	local profiles = Read(GAMEMODE .. "features/aiwar/profiles.lua"):match("PROFILES = (%b{})")
	for name in profiles:gmatch("[{,]%s*(%u[%w_]*)%s*=") do
		T.eq(Ours(name) or GMOD[name] == true or Base.FIELDS:Has(name), true, "profile field " .. name .. " is declared")
	end
end)

T.test("a name the base replaces is declared by none", function()
	for name in pairs(Base.REPLACED) do T.eq(Base.ComponentOf(name), nil, name) end
end)

T.finish()
