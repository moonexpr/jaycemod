-- The payload scenario (features.aiwar.scenario): the war fought over
-- carts, single or racing. Its doctrine is features.aiwar.orders'
-- PAYLOAD, and it allocates as the aiwar controller always has, undamped:
-- war:Assign on each team's cart (features.aiwar.model's Stance).
--
-- field.carts: team -> { track (foundation.aiwar.track), distance along
-- it, pos, nextCheckpoint (distance along it, nil after the last) }.
local max, pairs = math.max, pairs
local AiWar = require("features.aiwar.model")
local Teams = gameplay.teams
local Orders = require("features.aiwar.orders")
local Base = require("features.aiwar.scenario")
module(...)

MODE = "payload"

Scenario = Base.Scenario:Extend(MODE)

function Scenario:Brief(field, now)
	-- explore is every doctrine's job: its board on the field
	self:Explore(field)
	field.doctrine = Orders.PAYLOAD
end

function Scenario:Allocate(war, field, now)
	war:Assign(self:CartTeams(field.carts))
end

-- Where a cart heads: its next checkpoint, else its track's end.
local function Target(cart)
	return cart.nextCheckpoint or cart.track:Length()
end

-- The teams with a cart, how far along its track each cart is, and whether
-- it is close to its next checkpoint (features.aiwar.model's CartClose, whose
-- hysteresis memory.cartClose keeps across ticks and rounds): what each
-- team's defense share and stance are made of.
function Scenario:CartTeams(carts)
	local teams, close = {}, {}
	local wasClose = self.memory.cartClose or {}
	for team, cart in pairs(carts) do
		close[team] = AiWar.CartClose(wasClose[team], Target(cart) - cart.distance)
		teams[team] = {
			close = close[team],
			progress = cart.distance / max(cart.track:Length(), 1),
		}
	end
	self.memory.cartClose = close
	return teams
end

-- The team's lanes lead to its own cart, else the enemy's.
function Scenario:Front(field, team)
	local cart = field.carts[team] or field.carts[Teams.EnemyOf(team)]
	return cart and cart.pos
end

-- A team with a cart the enemy lacks attacks: in setup it comes out through
-- the gates toward its cart's next checkpoint.
function Scenario:SetupAttacks(field)
	local attacks = {}
	for team, cart in pairs(field.carts) do
		if not field.carts[Teams.EnemyOf(team)] then attacks[team] = cart.track:PointAt(Target(cart)) end
	end
	return attacks
end
