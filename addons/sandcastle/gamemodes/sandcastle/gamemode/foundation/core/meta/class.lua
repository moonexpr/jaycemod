-- Classes: single inheritance by metatable. A class is the metatable of its
-- instances and of its subclasses, and looks up what it lacks on its parent.
--
-- Extend(parent, fields) -> a class made of fields (or a new table), set
--   past any guard, inheriting from parent (nil for a root class) and
--   carrying parent's guard
-- New(class, fields) -> an instance: fields (or a new table) of class
-- IsA(value, class) -> whether class is value's class or one of its ancestors
-- Guard(class, check) -> class: each new key assigned on its subclasses
--   (at any depth) or their instances is first put to check(key, value),
--   which refuses it by returning why; the class's own keys are its own
local error, getmetatable, pairs, rawget, rawset, setmetatable, type = error, getmetatable, pairs, rawget, rawset, setmetatable, type
module(...)

-- A guard's refusal blames the assignment.
local ASSIGNER = 2

function Extend(parent, fields)
	local class = {}
	for key, value in pairs(fields or {}) do class[key] = value end
	class.__index = class
	if parent then class.__newindex = rawget(parent, "__newindex") end
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
