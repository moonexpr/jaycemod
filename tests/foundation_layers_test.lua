-- foundation/'s layers (docs/research/foundation-admission-rule.md): every
-- module is in one of four categories, ranked bottom-up, or is pending a move
-- out of foundation. A category may require only itself and the categories
-- below it, and foundation never requires a feature or a ws/ file.
local T = dofile("tests/harness.lua")

local FOUNDATION = T.ROOT .. "foundation/"
local REQUIRE = "require%(%s*[\"']([%w_.]+)[\"']"
local FOUNDATION_PREFIX = "^foundation%."
local OUTSIDE_PREFIXES = { "^features%.", "^ws%." }

local RANK = {
	structures = 1,
	formalisms = 2,
	gameplay = 3,
	ns = 4,
}

-- The modules that stay, by category.
local CATEGORY = {
	["core/pathfinder"] = "structures",
	["core/structs/heap"] = "structures",
	["pathfinder/astar"] = "structures",
	["core/parsers/consolecfg"] = "structures",
	["core/parsers/cvarfile"] = "structures",
	["core/analytics"] = "structures",
	["core/memory"] = "structures",
	["core/structs/ring"] = "structures",
	["core/math/stats"] = "structures",
	["core/structs/lease"] = "structures",
	["core/structs/grid"] = "structures",
	["core/graph"] = "structures",
	["core/math/random"] = "structures",
	["core/math/polynomial"] = "structures",
	["core/math/matrix"] = "structures",
	["core/buffer"] = "structures",
	["core/gma"] = "structures",
	["core/parsers/utf16"] = "structures",
	["core/parsers/keyvalues"] = "structures",
	["core/parsers/cursor"] = "structures",
	["core/structs/polyline"] = "structures",
	["core/structs/queue"] = "structures",
	["core/structs/tree"] = "structures",
	["core/timers"] = "structures",
	["core/scheduler"] = "formalisms",
	["core/drawlist"] = "formalisms",
	["core/math/geometry"] = "structures",
	["core/transaction"] = "structures",
	["core/structs/sets"] = "structures",
	["core/meta/port"] = "structures",
	["core/meta/class"] = "structures",
	["core/tactics"] = "formalisms",

	["core/cfsm"] = "formalisms",
	["core/hfsm"] = "formalisms",
	["core/map_io"] = "formalisms",
	["rounds"] = "formalisms",
	["rounds/state"] = "formalisms",
	-- teams is a label here, not a classification. There is no file-level
	-- cycle (rounds -> teams -> rounds/state); the categories are ranked
	-- whole, and rounds reads team vocabulary and one TF2 team rule,
	-- Teams.ScrambleDue, so teams sits a rank below gameplay types until the
	-- CS:S split separates team identity from TF2's team rules
	-- (docs/research/foundation-admission-rule.md, Amendment 2).
	["teams"] = "formalisms",
	["npc"] = "formalisms",
	["npc/actor"] = "formalisms",
	["npc/combatant"] = "formalisms",
	["events"] = "formalisms",
	["features"] = "formalisms",
	["gamemode"] = "formalisms",
	["idle"] = "formalisms",
	["spawn_manager"] = "formalisms",
	["play_mode"] = "formalisms",
	["permissions"] = "formalisms",

	["players"] = "gameplay",
	["players/attributes"] = "gameplay",
	["players/condition_effects"] = "gameplay",
	["kill_icons"] = "gameplay",
	["spawn"] = "gameplay",
	["spectate"] = "gameplay",
	["economy"] = "gameplay",
	["arrivals"] = "gameplay",
	["reports"] = "gameplay",
	["vote"] = "gameplay",
	["loadout"] = "gameplay",
	["combat"] = "gameplay",
	["combat/weapon_mimic"] = "gameplay",
	["combat/weapon_slot_filter"] = "gameplay",
	["combat/fixed_spread"] = "gameplay",
	["combat/combat_text"] = "gameplay",
	["combat/hit_sound"] = "gameplay",
	["combat/weapon_balance"] = "gameplay",
	["combat/bullet_steps"] = "gameplay",
	["projectile"] = "gameplay",
	["projectile/rocket"] = "gameplay",
	["projectile/grenade"] = "gameplay",
	["projectile/pipe"] = "gameplay",
	["projectile/jar"] = "gameplay",
	["capture"] = "gameplay",
	["capture/area"] = "gameplay",
	["capture/master"] = "gameplay",
	["capture/point_timer"] = "gameplay",
	["rounds/timer"] = "gameplay",
	["rounds/limits"] = "gameplay",
	["npc/targeting"] = "gameplay",

	["wartactics"] = "ns",
	["aiwar/squad"] = "ns",
	["aiwar/lanes"] = "ns",
	["aiwar/speech"] = "ns",
	["aiwar/hearing"] = "ns",
	["aiwar/explore"] = "ns",
	["aiwar/hunt"] = "ns",
	["aiwar/posts"] = "ns",
	["aiwar/zone"] = "ns",
	["ns/tuning"] = "ns",
	["npc/path"] = "ns",
	["npc/path/ground"] = "ns",
	["npc/path/hl2"] = "ns",
	["npc/leap"] = "ns",
	["npc/noise"] = "ns",
	["npc/path/scatter"] = "ns",
	["npc/path/tfbot"] = "ns",
	["npc/doors"] = "ns",
	["npc/portal"] = "ns",
	["npc/brushes"] = "ns",
	["npc/clip"] = "ns",
	["nav_gaps"] = "ns",
}

-- The modules still to move, and where each goes.
local PENDING = {
	["holiday"] = "features/holiday",
	["holiday/fortune"] = "features/holiday",
	["holiday/gift"] = "features/holiday",
	["holiday/halloween"] = "features/holiday",
	["holiday/wheel"] = "features/wheel",

	["payload"] = "features/payload",
	["payload/hud"] = "features/payload",
	["payload/race"] = "features/payload",
	["rounds/payload"] = "features/payload",
	["rounds/arena"] = "features/arena",
	["rounds/control_points"] = "features/rounds",
	["rounds/destruction"] = "features/rounds",
	["rounds/text"] = "features/rounds",
	["capture/hud"] = "features/capture",

	["spells"] = "features/spells",
	["spells/athletic"] = "features/spells",
	["spells/bats"] = "features/spells",
	["spells/blastjump"] = "features/spells",
	["spells/caster"] = "features/spells",
	["spells/fireball"] = "features/spells",
	["spells/halloween"] = "features/spells",
	["spells/lightning"] = "features/spells",
	["spells/meteor"] = "features/spells",
	["spells/mirv"] = "features/spells",
	["spells/overheal"] = "features/spells",
	["spells/skeleton_horde"] = "features/spells",
	["spells/spawn_boss"] = "features/spells",
	["spells/stealth"] = "features/spells",
	["spells/teleport"] = "features/spells",
	["projectile/orb"] = "features/spells",

	["hazards"] = "features/hazards",
	["hazards/croc"] = "features/hazards",
	["hazards/generic_bomb"] = "features/hazards",
	["hazards/ignite"] = "features/hazards",
	["hazards/pumpkin_bomb"] = "features/hazards",
	["hazards/zapper"] = "features/hazards",

	["npc/merasmus"] = "features/haunting",
	["npc/eyeball_boss"] = "features/haunting",
	["npc/headless_hatman"] = "features/haunting",
	["npc/halloween_boss"] = "features/haunting",
	["npc/ghost"] = "features/haunting",
	["npc/zombie"] = "features/haunting",
	["npc/hover"] = "features/haunting",

	["npc/boss_events"] = "features/npc",

	["npc/debug"] = "features/nbdebug",
	["aiwar/overlay"] = "features/nbdebug",
	["ns/overlay"] = "features/nbdebug",

	["aiwar"] = "features/aiwar",
	["aiwar/slots"] = "features/aiwar",
	["aiwar/spawns"] = "features/aiwar",
	["aiwar/scenario"] = "features/aiwar",
	["aiwar/scenario/arena"] = "features/aiwar",
	["aiwar/scenario/control_points"] = "features/aiwar",
	["aiwar/scenario/ctf"] = "features/aiwar",
	["aiwar/scenario/deathmatch"] = "features/aiwar",
	["aiwar/health"] = "features/aiwar",
	["aiwar/marksmanship"] = "features/aiwar",
	["aiwar/arms"] = "features/aiwar",
	["aiwar/scenario/freeform"] = "features/aiwar",
	["aiwar/scenario/koth"] = "features/aiwar",
	["aiwar/scenario/mvm"] = "features/aiwar",
	["aiwar/scenario/payload"] = "features/aiwar",
	["ns/inspect"] = "features/aiwar",
	-- an AI war soldier's orders, with payload woven into its behaviour
	-- tree: mode policy, not an NS type (admission rule, Amendment 4)
	["aiwar/orders"] = "features/aiwar",
	["aiwar/soldier"] = "features/aiwar",
	["kill_feed"] = "features/aiwar",

	["nodegraph"] = "features/nodegraph",

	["settings"] = "ws/settings",
	["replicated"] = "ws/replicated",
	["factions"] = "ws/factions",
	["scoreboard"] = "ws/scoreboard",
	["nav_progress"] = "ws/nav_progress",
	["admin_notices"] = "ws/admin_notices",
	["npc/ragdoll"] = "ws/ragdoll",
	["npc/voices"] = "ws/voices",
	["localization"] = "ws/localization",
}

-- Edges that break the order today.
-- None today (orders and soldier are pending to features/aiwar, Amendment
-- 4); a future inversion needs an entry here, and a reason.
local KNOWN_INVERSIONS = {}

local function FoundationModules()
	local list = assert(io.popen("find " .. FOUNDATION .. " -name '*.lua'"))
	local modules = {}
	for path in list:lines() do
		modules[path:sub(#FOUNDATION + 1, -#".lua" - 1)] = true
	end
	list:close()
	return modules
end

local function Exists(module)
	local file = io.open(FOUNDATION .. module .. ".lua")
	if file then file:close() end
	return file ~= nil
end

local function Requires(module)
	local file = assert(io.open(FOUNDATION .. module .. ".lua"))
	local text = file:read("*a")
	file:close()
	local names = {}
	for name in text:gmatch(REQUIRE) do
		names[#names + 1] = name
	end
	return names
end

local function ModuleOf(name)
	return (name:gsub(FOUNDATION_PREFIX, ""):gsub("%.", "/"))
end

T.test("every foundation file is categorised or pending a move, and every entry exists", function()
	local modules = FoundationModules()
	for module in pairs(modules) do
		local places = (CATEGORY[module] and 1 or 0) + (PENDING[module] and 1 or 0)
		T.eq(places, 1, module .. " is in exactly one of CATEGORY and PENDING")
	end
	for module, category in pairs(CATEGORY) do
		T.eq(Exists(module), true, "CATEGORY entry " .. module .. " exists")
		T.eq(RANK[category] ~= nil, true, module .. "'s category " .. category .. " is ranked")
	end
	for module in pairs(PENDING) do
		T.eq(Exists(module), true, "PENDING entry " .. module .. " exists")
	end
end)

T.test("foundation requires nothing from features or ws", function()
	for module in pairs(FoundationModules()) do
		for _, name in ipairs(Requires(module)) do
			for _, prefix in ipairs(OUTSIDE_PREFIXES) do
				T.eq(name:match(prefix), nil, module .. " requires " .. name)
			end
		end
	end
end)

T.test("a categorised module requires only categorised modules at its rank or below", function()
	for module, category in pairs(CATEGORY) do
		local allowed = KNOWN_INVERSIONS[module] or {}
		for _, name in ipairs(Requires(module)) do
			if name:match(FOUNDATION_PREFIX) then
				local required = ModuleOf(name)
				local rank = RANK[CATEGORY[required]]
				local ordered = rank ~= nil and rank <= RANK[category]
				T.eq(ordered or allowed[required] == true, true,
					module .. " (" .. category .. ") requires " .. required
						.. " (" .. tostring(CATEGORY[required] or PENDING[required]) .. ")")
			end
		end
	end
end)

T.finish()
