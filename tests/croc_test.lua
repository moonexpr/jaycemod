local T = dofile("tests/harness.lua")
local Hazards = T.require("foundation.hazards")
local Croc = T.require("foundation.hazards.croc")
local Teams = T.require("foundation.teams")
local Actor = T.require("foundation.npc.actor")

local NONE, ANIMATE, HURT = Hazards.NONE, Hazards.ANIMATE, Hazards.HURT

local SPAWN_TIME = 10
local HALF_DELAY = Croc.ATTACK_DELAY / 2

local function NewCroc(config)
	config = config or {}
	return Hazards.New(Croc, {
		team = config.team or Teams.UNASSIGNED,
		model = config.model,
	}, SPAWN_TIME)
end

local function Enter(target, team, now)
	return {
		target = target,
		team = team,
		projectile = false,
		triggerHurt = false,
		leaving = false,
		now = now,
	}
end

local function Leave(target)
	return {
		target = target,
		leaving = true,
	}
end

local function OutputsOf(outcome, target)
	for _, hit in ipairs(outcome.hits) do
		if hit.target == target then return table.concat(hit.outputs, ",") end
	end
	return nil
end

T.test("a player walking in raises a croc playing its attack at their feet", function()
	local croc = NewCroc()
	local outcome = croc:Touch(Enter("red", Teams.RED, SPAWN_TIME))
	T.eq(outcome.kind, ANIMATE, "kind")
	T.eq(outcome.model, Croc.MODEL, "model")
	T.eq(outcome.sequence, Croc.ATTACK_SEQUENCE, "sequence")
	T.eq(outcome.target, "red", "at the toucher")
end)

T.test("croc_model replaces the crocodile", function()
	local model = "models/props_island/crocodile/crocodile_big.mdl"
	local croc = NewCroc({ model = model })
	T.eq(croc:Touch(Enter("red", Teams.RED, SPAWN_TIME)).model, model, "model")
end)

T.test("a RED player still inside after 0.1 s is eaten, with OnEat and OnEatRed", function()
	local croc = NewCroc()
	croc:Touch(Enter("red", Teams.RED, SPAWN_TIME))
	T.eq(croc:Tick(SPAWN_TIME + HALF_DELAY).kind, NONE, "not before the delay")
	local outcome = croc:Tick(SPAWN_TIME + Croc.ATTACK_DELAY)
	T.eq(outcome.kind, HURT, "kind")
	T.eq(outcome.damage, Croc.DAMAGE, "damage")
	T.eq(outcome.dmgType, Actor.DMG_CRUSH, "crush")
	T.eq(#outcome.hits, 1, "one victim")
	T.eq(OutputsOf(outcome, "red"), "OnEat,OnEatRed", "outputs")
end)

T.test("a BLU player eaten fires OnEat and OnEatBlue", function()
	local croc = NewCroc()
	croc:Touch(Enter("blu", Teams.BLUE, SPAWN_TIME))
	T.eq(OutputsOf(croc:Tick(SPAWN_TIME + Croc.ATTACK_DELAY), "blu"), "OnEat,OnEatBlue", "outputs")
end)

T.test("a player on neither team eaten fires only OnEat", function()
	local croc = NewCroc()
	croc:Touch(Enter("ghost", Teams.UNASSIGNED, SPAWN_TIME))
	T.eq(OutputsOf(croc:Tick(SPAWN_TIME + Croc.ATTACK_DELAY), "ghost"), "OnEat", "outputs")
end)

T.test("a player who got out within 0.1 s is not eaten", function()
	local croc = NewCroc()
	croc:Touch(Enter("red", Teams.RED, SPAWN_TIME))
	T.eq(croc:Touch(Leave("red")).kind, NONE, "leaving does nothing")
	T.eq(croc:Tick(SPAWN_TIME + Croc.ATTACK_DELAY).kind, NONE, "escaped")
end)

T.test("each touch bites once: staying inside is not eaten again", function()
	local croc = NewCroc()
	croc:Touch(Enter("red", Teams.RED, SPAWN_TIME))
	T.eq(croc:Tick(SPAWN_TIME + Croc.ATTACK_DELAY).kind, HURT, "eaten")
	T.eq(croc:Tick(SPAWN_TIME + 2 * Croc.ATTACK_DELAY).kind, NONE, "once")
end)

T.test("two players jumping in together are both eaten on the same tick", function()
	local croc = NewCroc()
	croc:Touch(Enter("red", Teams.RED, SPAWN_TIME))
	croc:Touch(Enter("blu", Teams.BLUE, SPAWN_TIME))
	local outcome = croc:Tick(SPAWN_TIME + Croc.ATTACK_DELAY)
	T.eq(#outcome.hits, 2, "both")
	T.eq(OutputsOf(outcome, "red"), "OnEat,OnEatRed", "red")
	T.eq(OutputsOf(outcome, "blu"), "OnEat,OnEatBlue", "blu")
end)

T.test("the croc keeps eating: a later victim is bitten on their own delay", function()
	local croc = NewCroc()
	croc:Touch(Enter("red", Teams.RED, SPAWN_TIME))
	croc:Tick(SPAWN_TIME + Croc.ATTACK_DELAY)
	local later = SPAWN_TIME + 5
	T.eq(croc:Touch(Enter("blu", Teams.BLUE, later)).kind, ANIMATE, "a new croc")
	T.eq(croc:Tick(later + HALF_DELAY).kind, NONE, "not yet")
	T.eq(OutputsOf(croc:Tick(later + Croc.ATTACK_DELAY), "blu"), "OnEat,OnEatBlue", "eaten")
	T.eq(croc:IsFinished(), false, "never spent")
end)

-- CrocAttack asks IsTouching when it bites, not whether the touch it came
-- from lasted.
T.test("one who stepped out and back within 0.1 s is bitten by the first croc", function()
	local croc = NewCroc()
	croc:Touch(Enter("red", Teams.RED, SPAWN_TIME))
	croc:Touch(Leave("red"))
	local back = SPAWN_TIME + HALF_DELAY
	T.eq(croc:Touch(Enter("red", Teams.RED, back)).kind, ANIMATE, "a second croc")
	T.eq(OutputsOf(croc:Tick(SPAWN_TIME + Croc.ATTACK_DELAY), "red"), "OnEat,OnEatRed", "the first bites")
	croc:Touch(Leave("red")) -- dead players leave every trigger
	T.eq(croc:Tick(back + Croc.ATTACK_DELAY).kind, NONE, "the second finds nobody")
end)

T.test("the croc keeps its TeamNum, and takes no inputs of its own", function()
	local croc = NewCroc({ team = Teams.BLUE })
	T.eq(croc:Team(), Teams.BLUE, "team")
	T.eq(croc:Accepts("enable"), false, "Enable is the trigger's")
	T.eq(croc:Accepts("kill"), false, "Kill is the engine's")
end)

-- Package W8's bindings, all loaded lazily.

local ENTITIES = "addon/gamemodes/sandcastle/entities/entities/"
local W8_BINDINGS = {
	"func_croc.lua",
	"halloween_fortune_teller.lua",
	"tf_point_weapon_mimic.lua",
	"tf_projectile_pipe.lua",
	"filter_tf_damaged_by_weapon_in_slot.lua",
	"trigger_add_or_remove_tf_player_attributes.lua",
	"merasmus.lua",
	"tf_halloween_minigame.lua",
	"tf_logic_minigames.lua",
	"wetsand_stub_point.lua",
}

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

-- A load inside a function is indented or on a one-line function.
local function LoadsAtTopLevel(line)
	if line:match("^%s") or line:match("^function ") then return false end
	return line:find("WETSAND.require", 1, true) ~= nil or line:find("WETSAND.Feature", 1, true) ~= nil
end

T.test("the W8 bindings load nothing at top level", function()
	for _, file in ipairs(W8_BINDINGS) do
		for line in ReadFile(ENTITIES .. file):gmatch("[^\n]+") do
			T.eq(LoadsAtTopLevel(line), false, file .. ": " .. line)
		end
	end
end)

T.finish()
