-- foundation/'s, games/', nextsoldier/'s and wartactics/' layers
-- (docs/research/foundation-admission-rule.md): every module is in one of
-- five categories, ranked bottom-up, or is pending a move out of
-- foundation. A category may require only itself and the categories below
-- it, in any tree, and no tree requires a feature or a ws/ file.
local T = dofile("tests/harness.lua")

local FOUNDATION = T.ROOT .. "foundation/"
local FOUNDATION_PREFIX = "^foundation%."
local OUTSIDE_PREFIXES = { "^features%.", "^ws%." }

local RANK = {
	structures = 1,
	formalisms = 2,
	gameplay = 3,
	nextsoldier = 4,
	wartactics = 5,
}

-- The modules that stay, by category.
local CATEGORY = {
	["graph/pathfinder"] = "structures",
	["tree/heap"] = "structures",
	["encoding/consolecfg"] = "structures",
	["encoding/cvarfile"] = "structures",
	["analysis/analytics"] = "structures",
	["analysis/memory"] = "structures",
	["list/ring"] = "structures",
	["math/stats"] = "structures",
	["world/lease"] = "structures",
	["world/grid"] = "structures",
	["graph/search"] = "structures",
	["math/weighted"] = "structures",
	["math/polynomial"] = "structures",
	["math/matrix"] = "structures",
	["file/buffer"] = "structures",
	["encoding/gma"] = "structures",
	["encoding/utf16"] = "structures",
	["encoding/keyvalues"] = "structures",
	["encoding/cursor"] = "structures",
	["math/polyline"] = "structures",
	["list/queue"] = "structures",
	["tree/avl"] = "structures",
	["world/pairmap"] = "structures",
	["world/bucket"] = "structures",
	["math/scalar"] = "structures",
	["math/interval"] = "structures",
	["math/box"] = "structures",
	["math/choice"] = "formalisms",
	["list/schedule"] = "formalisms",
	["list/select"] = "formalisms",
	["list/window"] = "structures",
	["math/geometry"] = "structures",
	["transaction"] = "structures",
	["configstore"] = "structures",
	["nodegraph"] = "structures",
	["world/sets"] = "structures",
	["core/port"] = "structures",
	["core/namespace"] = "structures",
	["core/class"] = "structures",
	["core/constants"] = "structures",
	["core/enum"] = "structures",
	["list/slots"] = "structures",
	["list/chain"] = "structures",
	["cache/base"] = "structures",
	["cache/lru"] = "structures",
	["cache/expiring"] = "structures",
	["cache/memo"] = "structures",

	["generator/state_machine"] = "formalisms",
	["generator/state_chart"] = "formalisms",

	-- foundation.wetsands: systems moved out of games/ for native backing
	-- (docs/native-foundation-plan.md), the one part that names game things.
	["wetsands/path"] = "nextsoldier",
	["wetsands/path/ground"] = "nextsoldier",
	["wetsands/path/hl2"] = "nextsoldier",
	["wetsands/path/scatter"] = "nextsoldier",
	["wetsands/path/tfbot"] = "nextsoldier",
	["wetsands/navsearch"] = "nextsoldier",
}

-- games/'s modules, by the same categories (docs/foundation-game-split-plan.md).
local GAMES = {
	["timer/countdown"] = "structures",
	["timer/interval"] = "structures",
	["world/snapshot"] = "structures",
	["world/nav_attributes"] = "structures",

	["list/drawlist"] = "formalisms",
	["world/io"] = "formalisms",
	["generator/hfsm"] = "formalisms",
	["gameplay/tactics"] = "formalisms",
	["gameplay/rounds"] = "formalisms",
	["gameplay/rounds/state"] = "formalisms",
	-- teams is a label here, not a classification. There is no file-level
	-- cycle (rounds -> teams -> rounds/state); the categories are ranked
	-- whole, and rounds reads team vocabulary and one TF2 team rule,
	-- Teams.ScrambleDue, so teams sits a rank below gameplay types until the
	-- CS:S split separates team identity from TF2's team rules
	-- (docs/research/foundation-admission-rule.md, Amendment 2).
	["gameplay/teams"] = "formalisms",
	["npc/nextbot"] = "formalisms",
	["npc/actor"] = "formalisms",
	["npc/combatant"] = "formalisms",
	["system/events"] = "formalisms",
	["system/features"] = "formalisms",
	["system/gamemode"] = "formalisms",
	["system/idle"] = "formalisms",
	["system/spawn_manager"] = "formalisms",
	["system/play_mode"] = "formalisms",
	["system/permissions"] = "formalisms",
	["system/local_player"] = "formalisms",
	["system/local_player"] = "formalisms",

	["gameplay/players"] = "gameplay",
	["gameplay/players/attributes"] = "gameplay",
	["gameplay/players/condition_effects"] = "gameplay",
	["gameplay/kill_icons"] = "gameplay",
	["gameplay/kill_credit"] = "gameplay",
	["gameplay/player_analytics"] = "gameplay",
	["gameplay/respawn_modifiers"] = "gameplay",
	["gameplay/spawn"] = "gameplay",
	["gameplay/spectate"] = "gameplay",
	["gameplay/economy"] = "gameplay",
	["gameplay/arrivals"] = "gameplay",
	["gameplay/reports"] = "gameplay",
	["gameplay/vote"] = "gameplay",
	["gameplay/handicap"] = "gameplay",
	["gameplay/capabilities"] = "gameplay",
	["gameplay/loadout"] = "gameplay",
	["gameplay/combat"] = "gameplay",
	["gameplay/combat/weapon_mimic"] = "gameplay",
	["gameplay/combat/weapon_slot_filter"] = "gameplay",
	["gameplay/combat/fixed_spread"] = "gameplay",
	["gameplay/combat/combat_text"] = "gameplay",
	["gameplay/combat/hit_sound"] = "gameplay",
	["gameplay/combat/weapon_balance"] = "gameplay",
	["gameplay/combat/bullet_steps"] = "gameplay",
	["gameplay/combat/crit_effects"] = "gameplay",
	["gameplay/combat/impact"] = "gameplay",
	["gameplay/projectile"] = "gameplay",
	["gameplay/projectile/rocket"] = "gameplay",
	["gameplay/projectile/grenade"] = "gameplay",
	["gameplay/projectile/pipe"] = "gameplay",
	["gameplay/projectile/jar"] = "gameplay",
	["gameplay/capture"] = "gameplay",
	["gameplay/capture/area"] = "gameplay",
	["gameplay/capture/master"] = "gameplay",
	["gameplay/capture/point_timer"] = "gameplay",
	["gameplay/rounds/timer"] = "gameplay",
	["gameplay/rounds/limits"] = "gameplay",
	["npc/targeting"] = "gameplay",
}

-- nextsoldier/'s modules: NextSoldier, the soldier itself (its body,
-- movement, senses and behaviours), a subsystem of its own on foundation
-- and games, that runs without the war's tactics engine.
local NEXTSOLDIER = {
	["base"] = "nextsoldier",
	["soldier"] = "nextsoldier",
	["chart"] = "nextsoldier",
	["behaviors"] = "nextsoldier",
	["relations"] = "nextsoldier",
	["intention"] = "nextsoldier",
	["weapons"] = "nextsoldier",
	["monitor"] = "nextsoldier",
	["speech"] = "nextsoldier",
	["hearing"] = "nextsoldier",
	["route_record"] = "nextsoldier",
	["reach_memo"] = "nextsoldier",
	["leap"] = "nextsoldier",
	["detour"] = "nextsoldier",
	["noise"] = "nextsoldier",
	["doors"] = "nextsoldier",
	["portal"] = "nextsoldier",
	["probe"] = "nextsoldier",
	["rappel"] = "nextsoldier",
	["brushes"] = "nextsoldier",
	["clip"] = "nextsoldier",
	["nav_gaps"] = "nextsoldier",
	["vision"] = "nextsoldier",
	["player_body"] = "nextsoldier",
	["route_walk"] = "nextsoldier",
}

-- wartactics/'s modules: the AI war's tactics engine, the strategy its
-- soldiers are organised by (fire teams, squads, lanes, posts, the
-- scenarios), on NextSoldier and never under it.
local WARTACTICS = {
	["fireteam"] = "wartactics",
	["scenarios"] = "wartactics",
	["squad"] = "wartactics",
	["lanes"] = "wartactics",
	["explore"] = "wartactics",
	["hunt"] = "wartactics",
	["posts"] = "wartactics",
	["zone"] = "wartactics",
	["tuning"] = "wartactics",
	["bot_quota"] = "wartactics",
}

-- The modules still to move, and where each goes: none. A module bound out
-- of foundation is listed here, with its destination, until it moves.
local PENDING = {}

-- Edges that break the order today.
-- None today; a future inversion needs an entry here, and a reason.
local KNOWN_INVERSIONS = {}

-- A namespace's index (sh_index.lua and its realm's) publishes modules and
-- is not one (tests/foundation_index_test.lua).
local INDEX = "_index%.lua$"

-- A games tree's init (sh_init.lua) publishes modules and is not one.
local INIT = "_init%.lua$"

-- The trees: where each lives, the dotted prefix of its module names, and
-- its categories.
local TREES = {
	{ dir = FOUNDATION, prefix = FOUNDATION_PREFIX, category = CATEGORY, pending = PENDING },
	{ dir = T.ROOT .. "games/", prefix = "^games%.", category = GAMES, pending = {} },
	{ dir = T.ROOT .. "nextsoldier/", prefix = "^nextsoldier%.", category = NEXTSOLDIER, pending = {} },
	{ dir = T.ROOT .. "wartactics/", prefix = "^wartactics%.", category = WARTACTICS, pending = {} },
}

local function Modules(tree)
	local list = assert(io.popen("find " .. tree.dir .. " -name '*.lua'"))
	local modules = {}
	for path in list:lines() do
		if not path:match(INDEX) and not path:match(INIT) then
			modules[path:sub(#tree.dir + 1, -#".lua" - 1)] = true
		end
	end
	list:close()
	return modules
end

local function Exists(tree, module)
	local file = io.open(tree.dir .. module .. ".lua")
	if file then file:close() end
	return file ~= nil
end

-- The modules a module uses: by require, or by reading its global.
local function Requires(tree, module)
	local file = assert(io.open(tree.dir .. module .. ".lua"))
	local text = file:read("*a")
	file:close()
	return T.Uses(text)
end

-- A required name's tree and its module there, or nil for no tree's.
local function Place(name)
	for _, tree in ipairs(TREES) do
		if name:match(tree.prefix) then
			return tree, (name:gsub(tree.prefix, ""):gsub("%.", "/"))
		end
	end
end

T.test("every module is categorised or pending a move, and every entry exists", function()
	for _, tree in ipairs(TREES) do
		for module in pairs(Modules(tree)) do
			local places = (tree.category[module] and 1 or 0) + (tree.pending[module] and 1 or 0)
			T.eq(places, 1, tree.dir .. module .. " is in exactly one of its categories and PENDING")
		end
		for module, category in pairs(tree.category) do
			T.eq(Exists(tree, module), true, tree.dir .. module .. " exists")
			T.eq(RANK[category] ~= nil, true, module .. "'s category " .. category .. " is ranked")
		end
		for module in pairs(tree.pending) do
			T.eq(Exists(tree, module), true, "PENDING entry " .. module .. " exists")
		end
	end
end)

T.test("foundation, games, nextsoldier and wartactics require nothing from features or ws", function()
	for _, tree in ipairs(TREES) do
		for module in pairs(Modules(tree)) do
			for _, name in ipairs(Requires(tree, module)) do
				for _, prefix in ipairs(OUTSIDE_PREFIXES) do
					T.eq(name:match(prefix), nil, tree.dir .. module .. " requires " .. name)
				end
			end
		end
	end
end)

T.test("a categorised module requires only categorised modules at its rank or below", function()
	for _, tree in ipairs(TREES) do
		for module, category in pairs(tree.category) do
			local allowed = KNOWN_INVERSIONS[module] or {}
			for _, name in ipairs(Requires(tree, module)) do
				local required, path = Place(name)
				if required then
					local rank = RANK[required.category[path]]
					local ordered = rank ~= nil and rank <= RANK[category]
					T.eq(ordered or allowed[path] == true, true,
						module .. " (" .. category .. ") requires " .. name
							.. " (" .. tostring(required.category[path] or required.pending[path]) .. ")")
				end
			end
		end
	end
end)

T.finish()
