-- Leases: keys each held by one holder for a time, as soldiers claim spots
-- so no two take the same. A lease runs from when it is taken for its term;
-- its holder may renew it, nobody else may take it until it expires or is
-- released. Time is passed in.
--   New()
--   leases:Holder(key, now) -> the holder, or nil
--   leases:FreeFor(key, holder, now) -> unheld, expired, or the holder's own
--   leases:Take(key, holder, now, term) -> true, or false when another holds it
--   leases:Release(key, holder), leases:ReleaseAll(holder): only its own
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local pairs, setmetatable = pairs, setmetatable
module(...)

local Leases = {}
Leases.__index = Leases

function New()
	return setmetatable({ held = {} }, Leases) -- key -> { holder, expires }
end

function Leases:Holder(key, now)
	local lease = self.held[key]
	if lease and now < lease.expires then return lease.holder end
	return nil
end

function Leases:FreeFor(key, holder, now)
	local other = self:Holder(key, now)
	return other == nil or other == holder
end

function Leases:Take(key, holder, now, term)
	if not self:FreeFor(key, holder, now) then return false end
	self.held[key] = {
		holder = holder,
		expires = now + term,
	}
	return true
end

function Leases:Release(key, holder)
	local lease = self.held[key]
	if lease and lease.holder == holder then self.held[key] = nil end
end

function Leases:ReleaseAll(holder)
	for key, lease in pairs(self.held) do
		if lease.holder == holder then self.held[key] = nil end
	end
end
