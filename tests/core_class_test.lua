-- foundation.core.class: single inheritance by metatable.
local T = dofile("tests/harness.lua")
local Class = core.class

local function Raises(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raises")
	return tostring(err)
end

local function Animal()
	local base = Class.Extend(nil, { legs = 4 })
	function base:Speak() return "..." end
	function base:Describe() return self:Speak() .. " on " .. self.legs .. " legs" end
	return base
end

T.test("a subclass overrides what it defines and inherits the rest", function()
	local Base = Animal()
	local Bird = Class.Extend(Base, { legs = 2 })
	function Bird:Speak() return "tweet" end
	local bird = Class.New(Bird)
	T.eq(bird:Describe(), "tweet on 2 legs", "its own Speak and legs, the base's Describe")
	T.eq(Class.New(Base):Describe(), "... on 4 legs", "the base is untouched")
end)

T.test("a subclass's instances keep the metamethods of its ancestors", function()
	local Base = Animal()
	Base.__tostring = function(self) return "an animal on " .. self.legs .. " legs" end
	Base.__call = function(self, word) return self:Speak() .. " " .. word end
	local Bird = Class.Extend(Base, { legs = 2 })
	local Robin = Class.Extend(Bird, {
		__call = function(_, word) return "chirp " .. word end,
	})
	T.eq(tostring(Class.New(Bird)), "an animal on 2 legs", "__tostring, a level down")
	T.eq(Class.New(Bird)("hello"), "... hello", "__call, a level down")
	T.eq(tostring(Class.New(Robin)), "an animal on 2 legs", "two levels down")
	T.eq(Class.New(Robin)("hello"), "chirp hello", "unless the subclass defines its own")
end)

T.test("a class's own __index function is its subclasses' too", function()
	local Base = Class.Extend(nil, { Name = function() return "method" end })
	Base.__index = function(_, key)
		local method = rawget(Base, key)
		if method ~= nil then return method end
		return "looked up " .. key
	end
	local Sub = Class.Extend(Base)
	local sub = Class.New(Sub)
	T.eq(sub.anything, "looked up anything", "the lookup reaches the subclass's instances")
	T.eq(sub:Name(), "method", "and still finds the methods")
end)

T.test("an instance starts from the fields it is given", function()
	local Base = Animal()
	local pet = Class.New(Base, { legs = 3, name = "Tripod" })
	T.eq(pet.name, "Tripod", "its own field")
	T.eq(pet:Describe(), "... on 3 legs", "its own legs")
end)

T.test("an instance is a member of its class and every ancestor", function()
	local Base = Animal()
	local Bird = Class.Extend(Base)
	local Other = Animal()
	local bird = Class.New(Bird)
	T.eq(Class.IsA(bird, Bird), true, "its class")
	T.eq(Class.IsA(bird, Base), true, "an ancestor")
	T.eq(Class.IsA(Class.New(Base), Bird), false, "not a descendant")
	T.eq(Class.IsA(bird, Other), false, "an unrelated class")
	T.eq(Class.IsA(Bird, Base), true, "a subclass is one too")
	T.eq(Class.IsA(5, Base), false, "a number")
end)

T.test("a guard refuses new keys on a class's subclasses and their instances", function()
	local Base = Animal()
	Class.Guard(Base, function(key)
		if key == "Fly" then return "nothing here flies" end
	end)
	local Bird = Class.Extend(Base, { legs = 2 })
	local err = Raises(function() Bird.Fly = function() end end)
	T.eq(err:find("nothing here flies", 1, true) ~= nil, true, "the guard's reason")
	local Chick = Class.Extend(Bird)
	Raises(function() Chick.Fly = function() end end)
	function Bird:Sing() return "la" end
	T.eq(Bird:Sing(), "la", "other keys pass")
	local bird = Class.New(Bird)
	Raises(function() bird.Fly = true end)
	bird.mood = "happy"
	T.eq(bird.mood, "happy", "an instance's other keys pass")
end)

T.test("the fields a class is built with are set past its parent's guard", function()
	local Base = Animal()
	Class.Guard(Base, function(key)
		if key == "name" then return "no names" end
	end)
	local Named = Class.Extend(Base, { name = "named" })
	T.eq(Named.name, "named", "set raw")
end)

T.test("constructing runs each class's own Init, base first, with the arguments", function()
	local log = {}
	local Base = Class.Extend(nil)
	function Base:Init(name) log[#log + 1] = "base " .. name; self.name = name end
	local Mid = Class.Extend(Base) -- no Init of its own: nothing runs twice
	local Leaf = Class.Extend(Mid)
	function Leaf:Init(name) log[#log + 1] = "leaf " .. self.name end
	local leaf = Class.Construct(Leaf, "x")
	T.eq(table.concat(log, ", "), "base x, leaf x", "in order, once each")
	T.eq(Class.IsA(leaf, Base), true, "an instance")
end)

T.test("destroying runs each class's own Destroy, most derived first", function()
	local log = {}
	local Base = Class.Extend(nil)
	function Base:Destroy() log[#log + 1] = "base" end
	local Leaf = Class.Extend(Base)
	function Leaf:Destroy() log[#log + 1] = "leaf" end
	Class.Destroy(Class.Construct(Leaf))
	T.eq(table.concat(log, ", "), "leaf, base", "reverse order")
end)

T.test("an Init replaced after classes are made takes effect at the next construct", function()
	local Base = Class.Extend(nil)
	function Base:Init() self.version = 1 end
	local Leaf = Class.Extend(Base)
	T.eq(Class.Construct(Leaf).version, 1, "first")
	function Base:Init() self.version = 2 end
	T.eq(Class.Construct(Leaf).version, 2, "reloaded")
end)

T.finish()
