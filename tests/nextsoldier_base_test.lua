local T = dofile("tests/harness.lua")
local Base = nextsoldier.base

local GAMEMODE = T.ROOT
local ENTITIES = "addons/sandcastle/gamemodes/sandcastle/entities/entities/"

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

T.test("the base port is every component's methods, in order", function()
	local methods = {}
	for _, component in ipairs(Base.COMPONENTS) do
		for _, name in ipairs(component.methods:Methods()) do methods[#methods + 1] = name end
	end
	T.eq(table.concat(Base.METHODS:Methods(), " "), table.concat(methods, " "))
end)

T.test("each name's component is found", function()
	T.eq(Base.ComponentOf("FollowPath").name, "locomotion")
	T.eq(Base.ComponentOf("OnSpotted").name, "senses")
	T.eq(Base.ComponentOf("SpawnHealth").name, "life")
	T.eq(Base.ComponentOf("NSRest"), nil)
end)

T.test("every hook the soldier defines on the base is declared", function()
	local text = Read(GAMEMODE .. "ws/sh_drg_soldier.lua")
	for _, path in ipairs(Lines("ls " .. ENTITIES .. "ws_drg_*.lua")) do text = text .. Read(path) end
	for name in text:gmatch("function%s+ENT:([%w_]+)%s*%(") do
		T.eq(Ours(name) or GMOD[name] == true or Base.HOOKS:Has(name), true, "ENT:" .. name .. " is a declared hook")
	end
end)

T.test("every setting the soldier classes give the base is declared", function()
	for _, path in ipairs(Lines("ls " .. ENTITIES .. "ws_drg_*.lua")) do
		for name in Read(path):gmatch("\n%s*ENT%.([%w_]+)%s*=") do
			T.eq(Ours(name) or GMOD[name] == true or Base.FIELDS:Has(name), true, path .. ": ENT." .. name .. " is a declared field")
		end
	end
end)

T.test("a name the base replaces is declared by none", function()
	for name in pairs(Base.REPLACED) do T.eq(Base.ComponentOf(name), nil, name) end
end)

T.finish()
