-- foundation.refusal: the one shape of a refusal, a request the domain
-- declines (the caller's mistake), told apart from our own bugs by a marker
-- only refusal.lua sets, compared by value so it survives any reload.
local T = dofile("tests/harness.lua")
local Refusal = T.require("foundation.refusal")

local KIND = "unknown weapon"
local OTHER_KIND = "bad catalog"
local KINDS = { [KIND] = true }

local function Raised(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raised")
	return err
end

T.test("a raised refusal carries its kind and detail and is recognised", function()
	local err = Raised(Refusal.Raise, KIND, "bfg")
	T.eq(err.kind, KIND)
	T.eq(err.detail, "bfg")
	T.eq(Refusal.Is(err, KINDS), true)
end)

T.test("a refusal of a kind not asked about is not recognised", function()
	T.eq(Refusal.Is(Raised(Refusal.Raise, OTHER_KIND, "x"), KINDS), false)
end)

T.test("our bugs are never refusals", function()
	local events_style = {
		kind = KIND,
		message = "an events.lua error with a kind the caller would accept",
	}
	T.eq(Refusal.Is(events_style, KINDS), false, "an events-style error")
	T.eq(Refusal.Is({
		refusal = KIND,
		kind = KIND,
		detail = "x",
	}, KINDS), false, "a marker that is not refusal.lua's value")
	T.eq(Refusal.Is("attempt to index a nil value", KINDS), false, "a runtime error")
	T.eq(Refusal.Is(nil, KINDS), false, "error(nil)")
end)

T.test("a refusal reads as its kind and detail", function()
	T.eq(Refusal.Message(Raised(Refusal.Raise, KIND, "bfg")), "unknown weapon: bfg")
end)

T.test("explaining a refusal of an accepted kind gives its message", function()
	T.eq(Refusal.Explain(Raised(Refusal.Raise, KIND, "bfg"), KINDS), "unknown weapon: bfg")
end)

T.test("explaining anything else rethrows it unchanged", function()
	local events_style = {
		kind = KIND,
		message = "ours",
	}
	T.eq(rawequal(Raised(Refusal.Explain, events_style, KINDS), events_style), true, "an events-style error")
	local other = Raised(Refusal.Raise, OTHER_KIND, "x")
	T.eq(rawequal(Raised(Refusal.Explain, other, KINDS), other), true, "a refusal of another kind")
	T.eq(Raised(Refusal.Explain, "boom", KINDS), "boom", "a runtime error, without a position added")
end)

T.test("a refusal raised before a rerun of refusal.lua is recognised by the new code", function()
	local err = Raised(Refusal.Raise, KIND, "bfg")
	package.loaded["foundation.refusal"] = nil
	local Rerun = T.require("foundation.refusal")
	T.eq(Rerun.Is(err, KINDS), true)
end)

T.finish()
