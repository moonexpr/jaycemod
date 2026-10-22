-- A port: an interface, as the methods a value must have. A model that
-- reaches an actor, an engine or the world through a port names every
-- method it may call, and refuses a value missing one where it is handed
-- over rather than at the first call.
--
-- New(name, methods) refuses a port without a name or methods, or one that
-- names a method twice or a non-name. The port:
--   port:Check(value)   value, or an error naming every method it lacks,
--                       blamed on the caller of the function that checks
--   port:Facade(value)  a table of only the port's methods, each looked up
--                       on value at call time, so a reloaded class takes
--                       effect at once
--   port:Methods()      the method names in order, a fresh list
--   port:Name()         what errors call it
-- Is(value) says whether value is a port.
local Sets = require("foundation.map.sets")
local error, getmetatable, ipairs, setmetatable, tostring, type = error, getmetatable, ipairs, setmetatable, tostring, type
local concat = table.concat
module(...)

-- Check blames the function that called the one checking.
local CALLER_OF_CHECKER = 3

local Port = {}
Port.__index = Port

function New(name, methods)
	if type(name) ~= "string" or name == "" then error("a port needs a name, not " .. tostring(name), 2) end
	if type(methods) ~= "table" then error("port " .. name .. " needs a list of methods", 2) end
	for _, method in ipairs(methods) do
		if type(method) ~= "string" then error("port " .. name .. " has a non-name: " .. tostring(method), 2) end
	end
	if #methods == 0 then error("port " .. name .. " declares no methods", 2) end
	return setmetatable({
		name = name,
		methods = Sets.Named("port " .. name, methods),
	}, Port)
end

function Is(value)
	return getmetatable(value) == Port
end

function Port:Check(value)
	local missing = {}
	for _, method in ipairs(self.methods:Members()) do
		if type(value[method]) ~= "function" then missing[#missing + 1] = method end
	end
	if #missing > 0 then
		error("value is not a " .. self.name .. ": no " .. concat(missing, ", "), CALLER_OF_CHECKER)
	end
	return value
end

function Port:Facade(value)
	local facade = {}
	for _, method in ipairs(self.methods:Members()) do
		facade[method] = function(_, ...) return value[method](value, ...) end
	end
	return facade
end

function Port:Methods()
	return self.methods:Members()
end

function Port:Name()
	return self.name
end
