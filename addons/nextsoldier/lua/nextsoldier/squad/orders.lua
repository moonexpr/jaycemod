-- The seam between a soldier's leggings (TacticalLeggings: behavior.group_identity's orders,
-- behavior.gib_behaviors' actions) and the squad above them (nextsoldier.squad). The leggings know
-- their own orders (Muster, FallBack, Assault); a kind of order the squad adds registers here its
-- leggings' action, which they look up for a kind of their own they do not know. Any kind may
-- register its mission's rules: whether its squad awaits its leader's word (its members holding
-- their fire, nextsoldier.squad.behaviors.member) and whether it is under way.
--
-- Register{ kind, action? (the leggings' action class an order of it runs), awaiting?(order),
-- underway?(order) } (a kind again replaces it); Action(kind) (an unknown kind is our bug, refused);
-- Awaiting(order), Underway(order) (false for none, or a kind without them).
--
-- A kind's order is the base's own Order, its places and steps its own: Kind() -> a class on the
-- base's Order, New(class, fields) -> an order of it (fields.point its squad's point).
local GroupIdentity
local error, pairs, tostring, setmetatable, getmetatable = error, pairs, tostring, setmetatable, getmetatable
local nextsoldier = nextsoldier
module("nextsoldier.squad.orders")

local kinds = {}

function Register(entry)
	if not entry.kind then error("a squad order kind is registered by its kind", 2) end
	kinds[entry.kind] = { action = entry.action, awaiting = entry.awaiting, underway = entry.underway }
end

function Action(kind)
	local entry = kinds[kind]
	if not (entry and entry.action) then error("no leggings' action for the order kind " .. tostring(kind), 2) end
	return entry.action
end

function Awaiting(order)
	local entry = order and kinds[order.kind]
	return entry ~= nil and entry.awaiting ~= nil and entry.awaiting(order) == true
end

function Underway(order)
	local entry = order and kinds[order.kind]
	return entry ~= nil and entry.underway ~= nil and entry.underway(order) == true
end

-- The base's Order, as a muster's class extends it.
local function Base()
	GroupIdentity = GroupIdentity or nextsoldier.behavior.group_identity
	return getmetatable(getmetatable(GroupIdentity.Muster({ x = 0, y = 0, z = 0 })))
end

function Kind()
	local class = setmetatable({}, Base())
	class.__index = class
	return class
end

-- A muster's fields (its mode, size, losses and seats) at fields.point, with fields, as class.
function New(class, fields)
	GroupIdentity = GroupIdentity or nextsoldier.behavior.group_identity
	local order = GroupIdentity.Muster(fields.point)
	for key, value in pairs(fields) do order[key] = value end
	return setmetatable(order, class)
end
