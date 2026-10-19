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

T.test("a soldier does not say a concept again in its role for 10 seconds", function()
	local speaker = Speaker()
	local set = Speech.Criteria(Voices.For("models/player/group03/female_02.mdl"), Speech.OFFENSE, SURE, false)
	T.eq(system:Speak(speaker, Payload.CONCEPT_CART_MOVING_FORWARD, set, First, 0) ~= nil, true, "once")
	T.eq(system:Speak(speaker, Payload.CONCEPT_CART_MOVING_FORWARD, set, First, 9), nil, "not yet")
	T.eq(system:Speak(speaker, Payload.CONCEPT_CART_STOP, set, First, 1) ~= nil, true, "another concept still")
	T.eq(system:Speak(speaker, Payload.CONCEPT_CART_MOVING_FORWARD, set, First, 10) ~= nil, true, "again")
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

-- Battle stances: in setup, a soldier settling into its stance where it
-- rests says it is ready.

T.test("every voice says it is ready as it takes its battle stance, in either role", function()
	for _, voice in ipairs(VOICES) do
		for _, role in ipairs({ Speech.OFFENSE, Speech.DEFENSE }) do
			T.eq(Say(voice, role, Speech.CONCEPT_BATTLE_STANCE, false) ~= nil, true, voice.name .. " on " .. role)
		end
	end
end)

T.test("a voice's own ready lines outscore its side's, and a voice with none uses its side's", function()
	local cop = Say(Voices.For("models/player/police.mdl"), Speech.DEFENSE, Speech.CONCEPT_BATTLE_STANCE, false)
	T.eq(cop.rule, "BattleStanceCombineMetrocop", "the metrocop's own")
	T.eq(cop.response.kind, "speak", "a sound")
	local alyx = Say(Voices.For("models/player/alyx.mdl"), Speech.OFFENSE, Speech.CONCEPT_BATTLE_STANCE, false)
	T.eq(alyx.rule, "BattleStanceRebel", "the rebels'")
end)

T.test("three soldiers in four announce their stance, so a squad is heard but not a chorus", function()
	local male = Voices.For("models/player/group03/male_04.mdl")
	local function Draw(n)
		return system:Speak(Speaker(), Speech.CONCEPT_BATTLE_STANCE, Speech.Criteria(male, Speech.OFFENSE, n, false), First, 0)
	end
	T.eq(Draw(25), nil, "not this time")
	T.eq(Draw(26) ~= nil, true, "this time")
end)

-- Greetings and contacts: a soldier greets a teammate player walking past
-- (heard by that player alone), and calls out an enemy it has just spotted
-- (heard by all near).

T.test("every voice greets a player passing by and calls out an enemy it spots, in either role", function()
	for _, voice in ipairs(VOICES) do
		for _, role in ipairs({ Speech.OFFENSE, Speech.DEFENSE }) do
			for _, concept in ipairs({ Speech.CONCEPT_PLAYER_PASSING, Speech.CONCEPT_ENEMY_SPOTTED }) do
				T.eq(Say(voice, role, concept, false) ~= nil, true, voice.name .. " on " .. role .. ": " .. concept)
			end
		end
	end
end)

T.test("a voice's own greetings and contact lines outscore its side's; a voice with none uses its side's", function()
	local cop = Say(Voices.For("models/player/police.mdl"), Speech.DEFENSE, Speech.CONCEPT_PLAYER_PASSING, false)
	T.eq(cop.rule, "PlayerPassingCombineMetrocop", "the metrocop's own greeting")
	local alyx = Say(Voices.For("models/player/alyx.mdl"), Speech.OFFENSE, Speech.CONCEPT_ENEMY_SPOTTED, false)
	T.eq(alyx.rule, "EnemySpottedRebelAlyx", "Alyx's own contact lines")
	T.eq(Say(Voices.For("models/player/alyx.mdl"), Speech.OFFENSE, Speech.CONCEPT_PLAYER_PASSING, false).rule,
		"PlayerPassingRebel", "no greeting of her own: the rebels'")
end)

T.test("three soldiers in four greet; every one calls out a contact", function()
	local male = Voices.For("models/player/group03/male_04.mdl")
	local function Draw(concept, n)
		return system:Speak(Speaker(), concept, Speech.Criteria(male, Speech.OFFENSE, n, false), First, 0)
	end
	T.eq(Draw(Speech.CONCEPT_PLAYER_PASSING, 25), nil, "no greeting this time")
	T.eq(Draw(Speech.CONCEPT_PLAYER_PASSING, 26) ~= nil, true, "a greeting")
	T.eq(Draw(Speech.CONCEPT_ENEMY_SPOTTED, 0) ~= nil, true, "a callout, whatever the draw")
end)

T.test("a soldier greets at most once in 20 seconds, and calls out contacts at most once in 5", function()
	local set = Speech.Criteria(Voices.For("models/player/combine_soldier.mdl"), Speech.OFFENSE, SURE, false)
	local speaker = Speaker()
	T.eq(system:Speak(speaker, Speech.CONCEPT_PLAYER_PASSING, set, First, 0) ~= nil, true, "a greeting")
	T.eq(system:Speak(speaker, Speech.CONCEPT_PLAYER_PASSING, set, First, 19), nil, "not yet")
	T.eq(system:Speak(speaker, Speech.CONCEPT_PLAYER_PASSING, set, First, 20) ~= nil, true, "again")
	T.eq(system:Speak(speaker, Speech.CONCEPT_ENEMY_SPOTTED, set, First, 0) ~= nil, true, "a callout")
	T.eq(system:Speak(speaker, Speech.CONCEPT_ENEMY_SPOTTED, set, First, 4), nil, "not yet")
	T.eq(system:Speak(speaker, Speech.CONCEPT_ENEMY_SPOTTED, set, First, 5) ~= nil, true, "again")
end)

T.test("a player is passing a soldier when moving within GREET_RANGE of it", function()
	T.eq(Speech.Passes(Speech.GREET_RANGE, Speech.PASS_SPEED), true, "at the edge, walking")
	T.eq(Speech.Passes(Speech.GREET_RANGE + 1, Speech.PASS_SPEED), false, "too far")
	T.eq(Speech.Passes(Speech.GREET_RANGE / 2, Speech.PASS_SPEED - 1), false, "standing about, not passing")
end)

T.test("a soldier does not announce a stance again for 15 seconds", function()
	local speaker = Speaker()
	local set = Speech.Criteria(Voices.For("models/player/combine_soldier.mdl"), Speech.OFFENSE, SURE, false)
	T.eq(system:Speak(speaker, Speech.CONCEPT_BATTLE_STANCE, set, First, 0) ~= nil, true, "once")
	T.eq(system:Speak(speaker, Speech.CONCEPT_BATTLE_STANCE, set, First, 14), nil, "not at its next rest")
	T.eq(system:Speak(speaker, Speech.CONCEPT_BATTLE_STANCE, set, First, 15) ~= nil, true, "again")
end)

-- Squad chatter: a soldier says so when it kills an enemy, when a teammate
-- falls near it, and when an enemy it fought slips out of sight; between
-- fights, one soldier of a squad at a time talks on the radio.
local CHATTER = { Speech.CONCEPT_ENEMY_KILLED, Speech.CONCEPT_ALLY_DOWN, Speech.CONCEPT_CONTACT_LOST, Speech.CONCEPT_IDLE }

T.test("every voice has something to say for each kind of squad chatter, in either role", function()
	for _, voice in ipairs(VOICES) do
		for _, role in ipairs({ Speech.OFFENSE, Speech.DEFENSE }) do
			for _, concept in ipairs(CHATTER) do
				T.eq(Say(voice, role, concept, false) ~= nil, true, voice.name .. " on " .. role .. ": " .. concept)
			end
		end
	end
end)

T.test("a Combine soldier says every kind of chatter in its own voice, and so does a metrocop", function()
	for _, concept in ipairs(CHATTER) do
		local soldier = Say(Voices.For("models/player/combine_soldier.mdl"), Speech.OFFENSE, concept, false)
		T.eq(soldier.rule:find("CombineSoldier$") ~= nil, true, concept .. ": the soldier's own (" .. soldier.rule .. ")")
		T.eq(soldier.response.kind, "speak", concept .. ": a line")
		local cop = Say(Voices.For("models/player/police.mdl"), Speech.OFFENSE, concept, false)
		T.eq(cop.rule:find("CombineMetrocop$") ~= nil, true, concept .. ": the metrocop's own (" .. cop.rule .. ")")
	end
end)

T.test("rebels kill, mourn and pass the time in their own voices", function()
	for _, model in ipairs({ "models/player/group03/male_04.mdl", "models/player/group03/female_02.mdl", "models/vortigaunt.mdl" }) do
		for _, concept in ipairs({ Speech.CONCEPT_ENEMY_KILLED, Speech.CONCEPT_ALLY_DOWN, Speech.CONCEPT_IDLE }) do
			T.eq(Say(Voices.For(model), Speech.DEFENSE, concept, false).response.kind, "speak", model .. ": " .. concept)
		end
	end
	T.eq(Say(Voices.For("models/player/alyx.mdl"), Speech.DEFENSE, Speech.CONCEPT_ALLY_DOWN, false).response.kind, "speak", "Alyx mourns")
end)

T.test("a teammate down is always said; a kill and a lost contact three times in four; idle talk one time in two", function()
	local cop = Voices.For("models/player/police.mdl")
	local function Draw(concept, n)
		return system:Speak(Speaker(), concept, Speech.Criteria(cop, Speech.OFFENSE, n, false), First, 0)
	end
	T.eq(Draw(Speech.CONCEPT_ALLY_DOWN, 0) ~= nil, true, "a teammate down, whatever the draw")
	T.eq(Draw(Speech.CONCEPT_ENEMY_KILLED, 25), nil, "no kill line this time")
	T.eq(Draw(Speech.CONCEPT_ENEMY_KILLED, 26) ~= nil, true, "a kill line")
	T.eq(Draw(Speech.CONCEPT_CONTACT_LOST, 25), nil, "no lost contact this time")
	T.eq(Draw(Speech.CONCEPT_CONTACT_LOST, 26) ~= nil, true, "a lost contact")
	T.eq(Draw(Speech.CONCEPT_IDLE, 50), nil, "no idle talk this time")
	T.eq(Draw(Speech.CONCEPT_IDLE, 51) ~= nil, true, "idle talk")
end)

T.test("a soldier says a kill or a teammate down at most every 6 seconds, a lost contact every 15, idle talk every 30", function()
	local set = Speech.Criteria(Voices.For("models/player/combine_soldier.mdl"), Speech.DEFENSE, SURE, false)
	for concept, wait in pairs({ [Speech.CONCEPT_ENEMY_KILLED] = 6, [Speech.CONCEPT_ALLY_DOWN] = 6,
		[Speech.CONCEPT_CONTACT_LOST] = 15, [Speech.CONCEPT_IDLE] = 30 }) do
		local speaker = Speaker()
		T.eq(system:Speak(speaker, concept, set, First, 0) ~= nil, true, concept .. ": once")
		T.eq(system:Speak(speaker, concept, set, First, wait - 1), nil, concept .. ": not yet")
		T.eq(system:Speak(speaker, concept, set, First, wait) ~= nil, true, concept .. ": again")
	end
end)

T.test("a teammate's fall is heard by soldiers within ALLY_DOWN_RANGE of it", function()
	T.eq(Speech.WitnessesFall(Speech.ALLY_DOWN_RANGE), true, "at the edge")
	T.eq(Speech.WitnessesFall(Speech.ALLY_DOWN_RANGE + 1), false, "too far")
end)

-- The Combine soldiers speak Half-Life: Alyx's voice (the gamemode's
-- content/sound/npc/combine_soldier): every line their rules speak is one
-- of its recordings.
T.test("every Combine soldier line the rules speak is in the gamemode's voice pack", function()
	local text = Read("responserules/combine.txt")
	local count = 0
	for path in text:gmatch('"(npc/combine_soldier/[^"]+)"') do
		count = count + 1
		local f = io.open("addons/sandcastle/gamemodes/sandcastle/content/sound/" .. path, "rb")
		T.eq(f ~= nil, true, path)
		if f then f:close() end
	end
	T.eq(count >= 50, true, "the soldiers' lines were found: " .. count)
end)

-- Falling back to cover and leaving it for a kit (foundation.aiwar.orders'
-- RetreatToCover and FindHealth, through the soldier port's Announce).
T.test("every voice calls out falling back to cover and going for health, each voice with lines its own", function()
	local OWN = { combine = "CombineSoldier", metrocop = "CombineMetrocop", male = "RebelMale", female = "RebelFemale" }
	for _, voice in ipairs(VOICES) do
		for concept, name in pairs({ [Speech.CONCEPT_RETREAT_TO_COVER] = "RetreatToCover", [Speech.CONCEPT_GET_HEALTH] = "GetHealth" }) do
			local said = Say(voice, Speech.DEFENSE, concept)
			T.eq(said ~= nil, true, voice.name .. ": " .. concept)
			if OWN[voice.name] then
				T.eq(said.rule, name .. OWN[voice.name], voice.name .. "'s own")
				T.eq(said.response.kind, "speak", "a sound")
			end
		end
	end
end)

T.test("a soldier calls out falling back once in a while, not on every retreat", function()
	local speaker, soldier = Speaker(), Voices.For("models/player/combine_soldier.mdl")
	T.eq(Say(soldier, Speech.DEFENSE, Speech.CONCEPT_RETREAT_TO_COVER, false, speaker) ~= nil, true)
	T.eq(Say(soldier, Speech.DEFENSE, Speech.CONCEPT_RETREAT_TO_COVER, false, speaker), nil, "said within 10 s")
end)

T.finish()
