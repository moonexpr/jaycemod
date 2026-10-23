-- Live tuning of NextSoldier's tactics (ns_tactics_tune): the constants
-- of the tactic modules that their functions read at each call, so a new
-- value takes effect at the soldiers' next think. Each is kept within the
-- range it may sensibly take; a Tuner remembers the defaults it found, to
-- list what changed and put it back.
--
-- A lanes constant shapes the lanes when they are planned, so changing one
-- asks for new lanes (Replans). Constants a controller keeps in locals, or
-- that feed a cache (the posts), are not here.
local ipairs, setmetatable, tonumber = ipairs, setmetatable, tonumber
local floor, format, lower, sort = math.floor, string.format, string.lower, table.sort
module(...)

TUNABLES = {}
local byName = {}

local function Add(module, key, min, max, whole, help)
	local tunable = {
		name = module .. "." .. key,
		module = module,
		key = key,
		min = min,
		max = max,
		whole = whole,
		help = help,
	}
	TUNABLES[#TUNABLES + 1] = tunable
	byName[lower(tunable.name)] = tunable
end

local function Real(module, key, min, max, help) Add(module, key, min, max, false, help) end
local function Whole(module, key, min, max, help) Add(module, key, min, max, true, help) end

-- games.nextsoldier.tactics: contact, bounding overwatch, flanking, falling back
Real("tactics", "CONTACT_MEMORY", 0, 60, "seconds a fire team remembers where it last saw the enemy")
Real("tactics", "BOUND_DISTANCE", 0, 4096, "how far a bounding element moves toward the objective")
Real("tactics", "BOUND_TIME", 0.5, 60, "seconds before the elements swap, arrived or not")
Real("tactics", "FLANK_OFFSET", 0, 4096, "how far beside the enemy a flanking team swings out")
Real("tactics", "FALLBACK_STEP", 0, 4096, "how far one step of falling back takes a team from its post")
Whole("tactics", "FALLBACK_STEPS", 0, 10, "the most steps a team falls back")
Whole("tactics", "FALLBACK_MEMBERS", 0, 16, "a team down to this many falls back")
Real("tactics", "FALLBACK_RANGE", 0, 4096, "an enemy this near a team's post makes it fall back")
Real("tactics", "FALLBACK_INTERVAL", 0, 120, "seconds between two steps back")
-- features.aiwar.orders: formation, bounds, cover, the defenders' rows
Real("orders", "REGROUP_RANGE", 0, 8192, "a member farther than this from its leader in a fight regroups on it")
Real("orders", "SQUAD_SPACING", 0, 1024, "the gap between members on a bound line, and regrouping")
Real("orders", "FOLLOW_SPACING", 0, 1024, "the gap per place behind the leader when following")
Real("orders", "FOLLOW_SLACK", 0, 1024, "how far off its follow spot a member may drift")
Real("orders", "BOUND_RADIUS", 0, 2048, "how far from its bound spot a member looks for cover")
Real("orders", "COVER_RADIUS", 0, 2048, "how far from its post a defender looks for cover")
Real("orders", "COVER_CLAIM", 0, 120, "seconds a cover spot stays claimed")
Real("orders", "FLANK_TIME", 0, 120, "seconds a team gives its flank before it bounds anyway")
Real("orders", "FLANK_ARRIVE", 0, 1024, "how near the flank point counts as there")
Real("orders", "ROAM_REST", 0, 120, "seconds an offensive squad rests at each spot of its objective")
Real("orders", "ESCORT_LEAD", 0, 4096, "how far ahead of their cart escorts stand")
Real("orders", "DEFEND_LEAD", 0, 4096, "how far ahead of the enemy cart defenders stand, without posts")
Real("orders", "DEFEND_DEPTH", 0, 2048, "the gap between the defenders' rows, without posts")
Whole("orders", "DEFEND_ROWS", 1, 8, "the defenders' rows, without posts")
Real("orders", "LATERAL", 0, 1024, "the gap between columns across a line")
Real("orders", "SUPPORT_BEHIND", 0, 4096, "how far behind its line support stands")
Real("orders", "RAID_SHIFT", 0, 4096, "how far the enemy's line moves before raiders go round again")
-- games.nextsoldier.lanes: planning lanes, and walking them
Real("lanes", "LANE_PENALTY", 1, 100, "how much more an area in an earlier lane's band costs")
Real("lanes", "LANE_SPREAD", 0, 4096, "how far either side of a lane its band reaches")
Real("lanes", "FLANK_RADIUS", 0, 4096, "how far beside the objective a fixed flank ends, where the ground has no flank pair")
Real("lanes", "FLANK_MIN", 0, 4096, "the nearest to the objective a flank's ground may be")
Real("lanes", "FLANK_MAX", 0, 8192, "the farthest from the objective a flank's ground may be")
Real("lanes", "WAYPOINT_SPACING", 16, 4096, "the gap between a lane's waypoints")
Real("lanes", "WAYPOINT_REACH", 0, 2048, "how near a waypoint counts as reached")
Whole("lanes", "LOOKAHEAD", 0, 8, "waypoints ahead a leader may skip to")
-- games.nextsoldier.squad: claims
Real("squad", "CLAIM_GRID", 1, 1024, "spots this close share one claim")

-- The tunable of that name, whatever its case, or nil.
function Find(name)
	return byName[lower(name)]
end

-- Whether changing it asks for the lanes to be planned again.
function Replans(tunable)
	return tunable.module == "lanes"
end

Tuner = {}
Tuner.__index = Tuner

-- modules: short name -> the module table ("tactics" -> games.nextsoldier.tactics).
function Tuner.New(modules)
	local defaults = {}
	for _, tunable in ipairs(TUNABLES) do defaults[tunable.name] = modules[tunable.module][tunable.key] end
	return setmetatable({
		modules = modules,
		defaults = defaults,
	}, Tuner)
end

function Tuner:Value(tunable)
	return self.modules[tunable.module][tunable.key]
end

-- Sets it from text: true and the tunable, or false and why not.
function Tuner:Set(name, text)
	local tunable = Find(name)
	if not tunable then return false, format("no tunable named '%s'; ns_tactics_list lists them", name) end
	local value = tonumber(text)
	if not value then return false, format("'%s' is not a number", text) end
	if value < tunable.min or value > tunable.max then
		return false, format("%s must be between %s and %s", tunable.name, tunable.min, tunable.max)
	end
	if tunable.whole and value ~= floor(value) then return false, tunable.name .. " must be a whole number" end
	self.modules[tunable.module][tunable.key] = value
	return true, tunable
end

-- Puts one back: true and the tunable, or false and why not.
function Tuner:Reset(name)
	local tunable = Find(name)
	if not tunable then return false, format("no tunable named '%s'", name) end
	self.modules[tunable.module][tunable.key] = self.defaults[tunable.name]
	return true, tunable
end

function Tuner:ResetAll()
	for _, tunable in ipairs(TUNABLES) do self.modules[tunable.module][tunable.key] = self.defaults[tunable.name] end
end

function Tuner:Changed(tunable)
	return self:Value(tunable) ~= self.defaults[tunable.name]
end

-- "tactics.BOUND_DISTANCE = 400 (default 320): how far ..."
function Tuner:Line(tunable)
	local default = self:Changed(tunable) and format("(default %s)", self.defaults[tunable.name]) or "(default)"
	return format("%s = %s %s: %s", tunable.name, self:Value(tunable), default, tunable.help)
end

-- A Line for each tunable whose name holds filter (any case), the changed
-- ones first, then by name.
function Tuner:Lines(filter)
	local wanted = lower(filter)
	local shown = {}
	for _, tunable in ipairs(TUNABLES) do
		if lower(tunable.name):find(wanted, 1, true) then shown[#shown + 1] = tunable end
	end
	sort(shown, function(a, b)
		local ca, cb = self:Changed(a), self:Changed(b)
		if ca ~= cb then return ca end
		return a.name < b.name
	end)
	local lines = {}
	for i, tunable in ipairs(shown) do lines[i] = self:Line(tunable) end
	return lines
end
