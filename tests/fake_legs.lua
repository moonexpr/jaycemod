-- A squad member as its leggings see it (nextsoldier.squad's actions): told an order and its place
-- in it, sensing its group each update, heading where they say; where it stands, its clock, the
-- map's word on a spot, an enemy it sees, a hurt, its name on the radio and what it says are the
-- test's. Member(order, place) -> me; OnOrder(order, place) -> me, the action its order's runs
-- first, the order's own action (from ease, as the leggings take an order up).
local GIB = nextsoldier.behavior.gib_behaviors
local F = {}

function F.Member (order, place)
	local me = { order = order, place = place or { x = 100, y = 0, z = 0 }, now = 0, said = {}, calls = {} }
	function me:NSLegsOrder () return self.order end
	function me:NSLegsSense () end
	function me:NSLegsPlace () return self.place end
	function me:NSLegsAt () return self.at or self.place end
	function me:Now () return self.now end
	function me:NSLegsDraw () return 0.5 end
	function me:NSLegsAdmit () return self.admit or function (spot) return spot end end
	function me:NSLegsSeats () return {} end
	function me:NSLegsHeadFor (spot, gait) self.spot, self.gait = spot, gait end
	function me:NSLegsSay (line, call)
		self.said [#self.said + 1] = line
		self.calls [#self.calls + 1] = call
	end
	function me:NSLegsDanger () return self.danger end
	function me:NSLegsContact () return self.contact == true end
	function me:NSLegsEnemyAt () return self.enemyAt end
	function me:NSLegsHurt () return self.hurt == true end
	function me:NSLegsNameOf (other) return other.name or "?" end
	return me
end

function F.OnOrder (order, place)
	local me = F.Member (order, place)
	local orders = GIB.LegsAtEase:New ():Update (me).action
	return me, orders:InitialContainedAction (me), orders
end

-- The calls me made of one kind.
function F.Calls (me, call)
	local found = {}
	for _, entry in ipairs (me.calls) do
		if entry and entry.call == call then found [#found + 1] = entry end
	end
	return found
end

return F
