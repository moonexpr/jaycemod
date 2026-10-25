-- Classes: single inheritance by metatable. A class is the metatable of its
-- instances and of its subclasses, and looks up what it lacks on its parent.
--
-- Extend(parent, fields) -> a class made of fields (or a new table), set
--   past any guard, inheriting from parent (nil for a root class) and
--   carrying parent's metamethods (its guard among them) and an __index
--   function of its own, unless fields give their own; such a function
--   must find methods along the instance's line, not on its own class
-- New(class, fields) -> an instance: fields (or a new table) of class
-- Construct(class, ...) -> a new instance, each class in its line that
--   defines an Init of its own running it, base first, with (instance, ...)
-- Destroy(instance, ...) runs each class's own Destroy, most derived first
--   (both find the methods as they are now, so a reloaded one takes effect)
-- IsA(value, class) -> whether class is value's class or one of its ancestors
-- Guard(class, check) -> class: each new key assigned on its subclasses
--   (at any depth) or their instances is first put to check(key, value),
--   which refuses it by returning why; the class's own keys are its own
-- Core-rule exception: stays Lua. A metatable mechanism over Lua tables;
-- nothing to gain natively.
local error, getmetatable, ipairs, pairs, rawget, rawset, setmetatable, type = error, getmetatable, ipairs, pairs, rawget, rawset, setmetatable, type
module(...)

-- A guard's refusal blames the assignment.
local ASSIGNER = 2

-- Lua reads an instance's metamethods from its class alone, never through
-- __index, so a subclass takes a copy of each of its parent's.
local INHERITED = {
	__newindex = true,
	__call = true,
	__tostring = true,
	__len = true,
	__eq = true,
	__lt = true,
	__le = true,
	__concat = true,
	__unm = true,
	__add = true,
	__sub = true,
	__mul = true,
	__div = true,
	__mod = true,
	__pow = true,
}

function Extend(parent, fields)
	local class = {}
	if parent then
		for key, value in pairs(parent) do
			if INHERITED[key] then class[key] = value end
		end
		local index = rawget(parent, "__index")
		if index ~= parent then class.__index = index end
	end
	for key, value in pairs(fields or {}) do class[key] = value end
	if rawget(class, "__index") == nil then class.__index = class end
	return setmetatable(class, parent)
end

function New(class, fields)
	return setmetatable(fields or {}, class)
end

function IsA(value, class)
	if type(value) ~= "table" then return false end
	local ancestor = getmetatable(value)
	while ancestor do
		if ancestor == class then return true end
		ancestor = getmetatable(ancestor)
	end
	return false
end

function Guard(class, check)
	rawset(class, "__newindex", function(target, key, value)
		local why = check(key, value)
		if why then error(why, ASSIGNER) end
		rawset(target, key, value)
	end)
	return class
end

-- The own methods called `name` along value's line of classes, most derived first.
local function Line(class, name)
	local methods = {}
	while class do
		local method = rawget(class, name)
		if method then methods[#methods + 1] = method end
		class = getmetatable(class)
	end
	return methods
end

function Construct(class, ...)
	local instance = setmetatable({}, class)
	local inits = Line(class, "Init")
	for i = #inits, 1, -1 do inits[i](instance, ...) end
	return instance
end

function Destroy(instance, ...)
	for _, destroy in ipairs(Line(getmetatable(instance), "Destroy")) do destroy(instance, ...) end
end
