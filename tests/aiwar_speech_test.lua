-- foundation.aiwar.speech: what the AI war's soldiers say when the cart
-- moves, stops, rolls back or is cut off by the enemy, as TF2's response
-- rules have its classes say it (scripts/talker: TLK_CART_*), in HL2's
-- voices.
local T = dofile("tests/harness.lua")
local Response = T.require("foundation.core.response")
local Speech = T.require("foundation.aiwar.speech")

T.defined(Speech.SAID_SECONDS, "SAID_SECONDS")
T.defined(Speech.CHANCE, "CHANCE")

local function First(n) if n then return 1 end return 0 end
local function Speaker() return { memory = Response.Memory(), contexts = Response.Contexts() } end
local CONCEPTS = { Speech.CONCEPT_CART_MOVING_FORWARD, Speech.CONCEPT_CART_MOVING_BACKWARD, Speech.CONCEPT_CART_STOP }
local SURE = 100 -- a randomnum past any chance

T.test("every voice says something for every cart concept, in either role", function()
	local system = Speech.System()
	for _, voice in ipairs(Speech.VOICES) do
		for _, role in ipairs({ Speech.OFFENSE, Speech.DEFENSE }) do
			for _, concept in ipairs(CONCEPTS) do
				for _, blocked in ipairs({ false, true }) do
					local said = system:Speak(Speaker(), concept, Speech.Criteria(role, voice, SURE, blocked), First, 0)
					T.eq(said ~= nil, true, string.format("%s on %s: %s%s", voice, role, concept, blocked and ", blocked" or ""))
				end
			end
		end
	end
end)

T.test("a cart cut off by the enemy has its own lines", function()
	local system = Speech.System()
	local stop = system:Speak(Speaker(), Speech.CONCEPT_CART_STOP, Speech.Criteria(Speech.OFFENSE, "combine", SURE, false), First, 0)
	local cut = system:Speak(Speaker(), Speech.CONCEPT_CART_STOP, Speech.Criteria(Speech.OFFENSE, "combine", SURE, true), First, 0)
	T.eq(cut.rule ~= stop.rule, true, "another rule")
	T.eq(cut.rule:find("Blocked") ~= nil, true, "the blocked one")
end)

T.test("a soldier speaks a concept only by chance", function()
	local system = Speech.System()
	local unlucky = 100 - Speech.CHANCE
	T.eq(system:Speak(Speaker(), Speech.CONCEPT_CART_STOP, Speech.Criteria(Speech.OFFENSE, "male", unlucky, false), First, 0), nil, "not this time")
	T.eq(system:Speak(Speaker(), Speech.CONCEPT_CART_STOP, Speech.Criteria(Speech.OFFENSE, "male", unlucky + 1, false), First, 0) ~= nil, true, "this time")
end)

T.test("a soldier does not say a concept again in its role until SAID_SECONDS have passed", function()
	local system, speaker = Speech.System(), Speaker()
	local set = Speech.Criteria(Speech.OFFENSE, "female", SURE, false)
	T.eq(system:Speak(speaker, Speech.CONCEPT_CART_MOVING_FORWARD, set, First, 0) ~= nil, true, "once")
	T.eq(system:Speak(speaker, Speech.CONCEPT_CART_MOVING_FORWARD, set, First, Speech.SAID_SECONDS - 1), nil, "not yet")
	T.eq(system:Speak(speaker, Speech.CONCEPT_CART_STOP, set, First, 1) ~= nil, true, "another concept still")
	T.eq(system:Speak(speaker, Speech.CONCEPT_CART_MOVING_FORWARD, set, First, Speech.SAID_SECONDS) ~= nil, true, "again")
end)

T.test("a voice with no rules says nothing", function()
	local set = Speech.Criteria(Speech.OFFENSE, "kleiner", SURE, false)
	T.eq(Speech.System():Speak(Speaker(), Speech.CONCEPT_CART_STOP, set, First, 0), nil, "nothing")
end)

T.test("the criteria name the role, the voice, the draw and whether the cart is cut off", function()
	local set = Speech.Criteria(Speech.DEFENSE, "metrocop", 42, true)
	T.eq(set.teamrole, Speech.DEFENSE, "the role")
	T.eq(set.voice, "metrocop", "the voice")
	T.eq(set.randomnum, 42, "the draw")
	T.eq(set.cartblocked, 1, "cut off")
	T.eq(Speech.Criteria(Speech.DEFENSE, "metrocop", 42, false).cartblocked, 0, "not")
end)

T.finish()
