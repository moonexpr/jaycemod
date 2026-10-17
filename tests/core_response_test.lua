-- foundation.core.response: TF2's response rules (the Source engine's
-- AI_ResponseSystem): criteria over a speaker's criteria set, rules scored by
-- the criteria they match, response groups, and contexts a rule applies.
local T = dofile("tests/harness.lua")
local Response = T.require("foundation.core.response")

T.defined(Response.CONCEPT_WEIGHT, "CONCEPT_WEIGHT")

-- A random source as math.random: random() a float in [0, 1), random(n) an
-- integer in 1..n; these always take the first.
local function First(n) if n then return 1 end return 0 end
local function Last(n) if n then return n end return 0.999 end

local function Speaker() return { memory = Response.Memory(), contexts = Response.Contexts() } end

-- Criteria -------------------------------------------------------------------

T.test("a criterion matches a word without regard to case", function()
	local c = Response.Criterion("concept", "TLK_CART_STOP")
	T.eq(c:Matches("tlk_cart_stop"), true, "the same word")
	T.eq(c:Matches("TLK_CART_MOVING_FORWARD"), false, "another")
	T.eq(c:Matches(nil), false, "no value")
end)

T.test("a criterion compares numbers: above, at least, a range, not equal", function()
	T.eq(Response.Criterion("randomnum", ">25"):Matches(26), true, "above")
	T.eq(Response.Criterion("randomnum", ">25"):Matches(25), false, "not above")
	T.eq(Response.Criterion("randomnum", "=>98"):Matches(98), true, "TF2's at least, written =>")
	T.eq(Response.Criterion("randomnum", ">=98"):Matches(97), false, "under it")
	local range = Response.Criterion("health", ">10,<=50")
	T.eq(range:Matches(50), true, "the top of the range")
	T.eq(range:Matches(10), false, "below the range")
	T.eq(Response.Criterion("said", "!=1"):Matches(1), false, "equal")
	T.eq(Response.Criterion("said", "!=1"):Matches("0"), true, "not equal")
end)

-- TF2's "not said yet" criteria rely on this: a key the speaker lacks is not
-- 1, but neither is it 0.
T.test("a key the speaker lacks is no number, and is not equal to one", function()
	T.eq(Response.Criterion("said", "!=1"):Matches(nil), true, "not equal")
	T.eq(Response.Criterion("said", "0"):Matches(nil), false, "not zero")
end)

T.test("a criterion with no value to match is refused", function()
	T.eq(pcall(Response.Criterion, "concept", ""), false, "empty")
	T.eq(pcall(Response.Criterion, "", "x"), false, "no key")
end)

-- A system -------------------------------------------------------------------

local function Cart(extra)
	local defs = {
		criteria = {
			ConceptCartStop = { "concept", "TLK_CART_STOP", required = true },
			IsOnOffense = { "teamrole", "offense", required = true },
			IsOnDefense = { "teamrole", "defense", required = true },
			NotSaidStop = { "SaidStop", "!=1", required = true, weight = 0 },
			Blocked = { "cartblocked", "1", required = true },
		},
		responses = {
			StopOffense = { { "print", "the cart stopped" } },
			BlockedOffense = { { "print", "they cut the cart off" } },
			StopDefense = { { "print", "we stopped it" } },
		},
		rules = {
			StopOffense = { criteria = { "ConceptCartStop", "IsOnOffense", "NotSaidStop" }, response = "StopOffense",
				applyContext = { "SaidStop:1:20" } },
			BlockedOffense = { criteria = { "ConceptCartStop", "IsOnOffense", "NotSaidStop", "Blocked" }, response = "BlockedOffense",
				applyContext = { "SaidStop:1:20" } },
			StopDefense = { criteria = { "ConceptCartStop", "IsOnDefense" }, response = "StopDefense" },
		},
	}
	for k, v in pairs(extra or {}) do
		for name, def in pairs(v) do defs[k][name] = def end
	end
	return Response.System(defs)
end

T.test("the rule matching the most criteria answers", function()
	local system, speaker = Cart(), Speaker()
	local said = system:Speak(speaker, "TLK_CART_STOP", { teamrole = "offense", cartblocked = 1 }, First, 0)
	T.eq(said.rule, "BlockedOffense", "blocked outscores a plain stop")
	T.eq(said.response.kind, "print", "a print")
	T.eq(said.response.value, "they cut the cart off", "its line")
end)

T.test("a rule whose required criterion fails is out", function()
	local said = Cart():Speak(Speaker(), "TLK_CART_STOP", { teamrole = "defense", cartblocked = 1 }, First, 0)
	T.eq(said.rule, "StopDefense", "only the defense's rule")
end)

T.test("no rule matching is nothing said", function()
	T.eq(Cart():Speak(Speaker(), "TLK_CART_MOVING_FORWARD", { teamrole = "offense" }, First, 0), nil, "nothing")
end)

-- TF2 (CAI_Expresser) gives the concept CONCEPT_WEIGHT in the criteria set.
T.test("the concept weighs more than any other criterion", function()
	local system = Response.System({
		criteria = {
			Concept = { "concept", "TLK_A" },
			X = { "x", "1" },
			Y = { "y", "1" },
		},
		responses = { A = { { "print", "a" } }, B = { { "print", "b" } } },
		rules = {
			A = { criteria = { "Concept" }, response = "A" },
			B = { criteria = { "X", "Y" }, response = "B" },
		},
	})
	T.eq(system:Speak(Speaker(), "TLK_A", { x = 1, y = 1 }, First, 0).rule, "A", "the concept's rule")
end)

T.test("rules tied on score are picked among at random", function()
	local system = Response.System({
		criteria = { Concept = { "concept", "TLK_A", required = true } },
		responses = { A = { { "print", "a" } }, B = { { "print", "b" } } },
		rules = {
			A = { criteria = { "Concept" }, response = "A" },
			B = { criteria = { "Concept" }, response = "B" },
		},
	})
	T.eq(system:Speak(Speaker(), "TLK_A", {}, First, 0).rule, "A", "the first by name")
	T.eq(system:Speak(Speaker(), "TLK_A", {}, Last, 0).rule, "B", "the last by name")
end)

-- Contexts ---------------------------------------------------------------------

T.test("a rule's context holds the speaker back until it expires", function()
	local system, speaker = Cart(), Speaker()
	local set = { teamrole = "offense" }
	T.eq(system:Speak(speaker, "TLK_CART_STOP", set, First, 0).rule, "StopOffense", "said once")
	T.eq(system:Speak(speaker, "TLK_CART_STOP", set, First, 19), nil, "not again within 20 s")
	T.eq(system:Speak(speaker, "TLK_CART_STOP", set, First, 20).rule, "StopOffense", "again once it expired")
end)

T.test("a context is the speaker's own", function()
	local system = Cart()
	local set = { teamrole = "offense" }
	system:Speak(Speaker(), "TLK_CART_STOP", set, First, 0)
	T.eq(system:Speak(Speaker(), "TLK_CART_STOP", set, First, 1).rule, "StopOffense", "another speaker still may")
end)

T.test("a context without a duration lasts", function()
	local contexts = Response.Contexts()
	contexts:Apply({ Response.Context("Met:1") }, 0)
	T.eq(contexts:Active(1e9).met, "1", "still there")
end)

T.test("a malformed context is refused", function()
	T.eq(pcall(Response.Context, "nokey"), false, "no value")
	T.eq(pcall(Response.Context, "k:v:soon"), false, "a duration that is no number")
end)

-- Response groups ----------------------------------------------------------------

local function Lines(group)
	return Response.System({
		criteria = { Concept = { "concept", "TLK_A", required = true } },
		responses = { Lines = group },
		rules = { Lines = { criteria = { "Concept" }, response = "Lines" } },
	})
end

local function Said(system, speaker, random)
	local said = system:Speak(speaker, "TLK_A", {}, random or First, 0)
	return said and said.response.value
end

T.test("a group says every line before it repeats one", function()
	local system, speaker = Lines({ { "print", "a" }, { "print", "b" }, { "print", "c" } }), Speaker()
	local seen = {}
	for _ = 1, 3 do seen[Said(system, speaker)] = true end
	T.eq(seen.a and seen.b and seen.c, true, "all three in three")
	T.eq(Said(system, speaker) ~= nil, true, "then it starts over")
end)

T.test("a group that permits repeats may say a line again at once", function()
	local system, speaker = Lines({ permitrepeats = true, { "print", "a" }, { "print", "b" } }), Speaker()
	T.eq(Said(system, speaker), "a", "a")
	T.eq(Said(system, speaker), "a", "a again")
end)

T.test("a sequential group says its lines in order", function()
	local system, speaker = Lines({ sequential = true, { "print", "a" }, { "print", "b" } }), Speaker()
	T.eq(Said(system, speaker, Last), "a", "first")
	T.eq(Said(system, speaker, Last), "b", "second")
	T.eq(Said(system, speaker, Last), "a", "and round again")
end)

T.test("a norepeat group falls silent once it has said every line", function()
	local system, speaker = Lines({ norepeat = true, { "print", "a" } }), Speaker()
	T.eq(Said(system, speaker), "a", "once")
	T.eq(Said(system, speaker), nil, "then never")
end)

T.test("weights favour a line", function()
	local system = Lines({ { "print", "light", weight = 1 }, { "print", "heavy", weight = 3 } })
	-- 0.5 of the total weight 4 is 2, past the light line's 1
	T.eq(Said(system, Speaker(), function(n) if n then return 1 end return 0.5 end), "heavy", "the heavier")
end)

T.test("a response may name another group", function()
	local system = Response.System({
		criteria = { Concept = { "concept", "TLK_A", required = true } },
		responses = { Outer = { { "response", "Inner" } }, Inner = { { "speak", "vo/line.wav" } } },
		rules = { Outer = { criteria = { "Concept" }, response = "Outer" } },
	})
	local said = system:Speak(Speaker(), "TLK_A", {}, First, 0)
	T.eq(said.response.kind, "speak", "the inner group's line")
	T.eq(said.response.value, "vo/line.wav", "its sound")
end)

T.test("a matchonce rule answers once", function()
	local system = Response.System({
		criteria = { Concept = { "concept", "TLK_A", required = true } },
		responses = { A = { { "print", "a" } } },
		rules = { A = { criteria = { "Concept" }, response = "A", matchonce = true } },
	})
	local speaker = Speaker()
	T.eq(system:Speak(speaker, "TLK_A", {}, First, 0) ~= nil, true, "once")
	T.eq(system:Speak(speaker, "TLK_A", {}, First, 1), nil, "not again")
end)

-- The factory ----------------------------------------------------------------------

T.test("a system naming what it does not define is refused", function()
	local function Build(rule, responses)
		return pcall(Response.System, {
			criteria = { Concept = { "concept", "TLK_A" } },
			responses = responses or { A = { { "print", "a" } } },
			rules = { A = rule },
		})
	end
	T.eq((Build({ criteria = { "Missing" }, response = "A" })), false, "an unknown criterion")
	T.eq((Build({ criteria = { "Concept" }, response = "Missing" })), false, "an unknown response")
	T.eq((Build({ criteria = { "Concept" }, response = "A" }, { A = { { "scene", "x.vcd" } } })), false, "a kind it cannot play")
	T.eq((Build({ criteria = { "Concept" }, response = "A" }, { A = { { "response", "A" } } })), false, "a group naming itself")
	T.eq((Build({ criteria = { "Concept" }, response = "A" }, { A = {} })), false, "an empty group")
end)

T.finish()
