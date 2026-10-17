-- The AI war's soldiers on the payload cart: their criteria set
-- (foundation.aiwar.speech) against the rules in the responserules addon
-- (addons/responserules/scripts/responserules/: response_rules.txt and the
-- affiliation files it includes), as the server loads them: what they say
-- when the cart moves, stops, rolls back or is cut off by the enemy, by the
-- side their model belongs to, as TF2's rules have its classes say it.
local T = dofile("tests/harness.lua")
local Response = T.require("responserules")
local Script = T.require("responserules_script")
local Speech = T.require("foundation.aiwar.speech")
local Voices = T.require("foundation.npc.voices")
local Payload = T.require("foundation.payload")

local SCRIPTS = "addons/responserules/scripts/"
local ROOT = "responserules/response_rules.txt"

local function Read(path)
	local f = io.open(SCRIPTS .. path, "r")
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	return text
end

local system = Response.System(Script.Load(ROOT, Read))

local function First(n) if n then return 1 end return 0 end
local function Speaker() return { memory = Response.Memory(), contexts = Response.Contexts() } end
local CONCEPTS = { Payload.CONCEPT_CART_MOVING_FORWARD, Payload.CONCEPT_CART_MOVING_BACKWARD, Payload.CONCEPT_CART_STOP }
local SURE = 100 -- a randomnum past any chance
-- the war's voices, by a model of each
local VOICES = {}
for _, model in ipairs({ "models/player/group03/male_04.mdl", "models/player/group03/female_02.mdl", "models/player/alyx.mdl",
	"models/player/combine_soldier.mdl", "models/player/police.mdl", "models/vortigaunt.mdl" }) do
	VOICES[#VOICES + 1] = Voices.For(model)
end

local function Say(voice, role, concept, blocked, speaker)
	return system:Speak(speaker or Speaker(), concept, Speech.Criteria(voice, role, SURE, blocked), First, 0)
end

T.test("every voice says something for every cart concept, in either role", function()
	for _, voice in ipairs(VOICES) do
		for _, role in ipairs({ Speech.OFFENSE, Speech.DEFENSE }) do
			for _, concept in ipairs(CONCEPTS) do
				for _, blocked in ipairs({ false, true }) do
					T.eq(Say(voice, role, concept, blocked) ~= nil, true,
						string.format("%s on %s: %s%s", voice.name, role, concept, blocked and ", blocked" or ""))
				end
			end
		end
	end
end)

-- Mixed models: a team may wear either side's, so a soldier answers by its
-- own model's affiliation, whichever team it is on.
T.test("a soldier answers by its model's affiliation, not its team", function()
	local combine = Voices.For("models/player/combine_soldier.mdl")
	local rebel = Voices.For("models/player/group03/male_04.mdl")
	local said = Say(combine, Speech.OFFENSE, Payload.CONCEPT_CART_MOVING_FORWARD, false)
	T.eq(said.rule:find("Combine") ~= nil, true, "a Combine soldier, the Combine's rule")
	said = Say(rebel, Speech.OFFENSE, Payload.CONCEPT_CART_MOVING_FORWARD, false)
	T.eq(said.rule:find("Rebel") ~= nil, true, "a rebel on the same team, the rebels'")
end)

T.test("a voice with lines of its own outscores its affiliation's", function()
	local said = Say(Voices.For("models/player/police.mdl"), Speech.OFFENSE, Payload.CONCEPT_CART_MOVING_FORWARD, false)
	T.eq(said.rule, "CartMovingForwardOffenseCombineMetrocop", "the metrocop's own")
	T.eq(said.response.kind, "speak", "a sound")
end)

T.test("a new model of a side speaks by its affiliation's rules", function()
	local elite = { name = "combine_elite", affiliation = Voices.COMBINE }
	local said = Say(elite, Speech.DEFENSE, Payload.CONCEPT_CART_STOP, false)
	T.eq(said.rule, "CartMovingStoppedDefenseCombine", "the Combine's")
end)

T.test("a cart cut off by the enemy has its own lines, even over a voice's plain stop", function()
	local metrocop = Voices.For("models/player/police.mdl")
	local stop = Say(metrocop, Speech.DEFENSE, Payload.CONCEPT_CART_STOP, false)
	local cut = Say(metrocop, Speech.DEFENSE, Payload.CONCEPT_CART_STOP, true)
	T.eq(stop.rule:find("Blocked"), nil, "a plain stop")
	T.eq(cut.rule:find("Blocked") ~= nil, true, "cut off")
	-- the vortigaunt has no cut-off lines of its own
	local vort = Say(Voices.For("models/vortigaunt.mdl"), Speech.OFFENSE, Payload.CONCEPT_CART_STOP, true)
	T.eq(vort.rule, "CartBlockedOffenseRebel", "the rebels' cut-off rule")
end)

T.test("every soldier waits TF2's defaultdelay after its line", function()
	for _, voice in ipairs(VOICES) do
		local said = Say(voice, Speech.DEFENSE, Payload.CONCEPT_CART_STOP, true)
		T.eq(said.delay >= Script.DEFAULT_DELAY[1] and said.delay <= Script.DEFAULT_DELAY[2], true, voice.name .. ": its delay")
	end
end)

T.test("a soldier speaks a concept three times in four", function()
	local male = Voices.For("models/player/group03/male_04.mdl")
	local function Draw(n)
		return system:Speak(Speaker(), Payload.CONCEPT_CART_STOP, Speech.Criteria(male, Speech.OFFENSE, n, false), First, 0)
	end
	T.eq(Draw(25), nil, "not this time")
	T.eq(Draw(26) ~= nil, true, "this time")
end)

T.test("a soldier does not say a concept again in its role for 20 seconds", function()
	local speaker = Speaker()
	local set = Speech.Criteria(Voices.For("models/player/group03/female_02.mdl"), Speech.OFFENSE, SURE, false)
	T.eq(system:Speak(speaker, Payload.CONCEPT_CART_MOVING_FORWARD, set, First, 0) ~= nil, true, "once")
	T.eq(system:Speak(speaker, Payload.CONCEPT_CART_MOVING_FORWARD, set, First, 19), nil, "not yet")
	T.eq(system:Speak(speaker, Payload.CONCEPT_CART_STOP, set, First, 1) ~= nil, true, "another concept still")
	T.eq(system:Speak(speaker, Payload.CONCEPT_CART_MOVING_FORWARD, set, First, 20) ~= nil, true, "again")
end)

T.test("a model of no side says nothing", function()
	T.eq(Say({ name = "kleiner" }, Speech.OFFENSE, Payload.CONCEPT_CART_STOP, false), nil, "nothing")
end)

T.test("the criteria name the side, the voice, the role, the draw and whether the cart is cut off", function()
	local set = Speech.Criteria(Voices.For("models/player/police.mdl"), Speech.DEFENSE, 42, true)
	T.eq(set.affiliation, Voices.COMBINE, "the side")
	T.eq(set.voice, "metrocop", "the voice")
	T.eq(set.teamrole, Speech.DEFENSE, "the role")
	T.eq(set.randomnum, 42, "the draw")
	T.eq(set.cartblocked, 1, "cut off")
end)

T.finish()
