-- game_events: local dispatch over a transport port (net2's in the game).
local T = dofile("tests/harness.lua")

dofile("addons/sandcastle/gamemodes/sandcastle/gamemode/includes/modules/game_events.lua")
local GameEvents = package.loaded.game_events

-- A port recording what it is asked, whose Send refuses fields.bad.
local function Port()
	local port = { sent = {}, receivers = {}, accepted = {}, reports = {}, firstTime = true }
	port.Send = function(name, fields, options)
		if fields.bad then error("bad_fields", 0) end
		port.sent[#port.sent + 1] = { name = name, fields = fields, options = options }

		return true
	end
	port.Receive = function(name, fn) port.receivers[name] = fn end
	port.Accept = function(name, rate) port.accepted[name] = rate end
	port.FirstTimePredicted = function() return port.firstTime end
	port.Report = function(text) port.reports[#port.reports + 1] = text end

	return port
end

T.test("Fire runs the realm's listeners at once, in the order added, and sends", function()
	local port = Port()
	local events = GameEvents.New(port)
	local order = {}
	events:Listen("e", "a", function() order[#order + 1] = "a" end)
	events:Listen("e", "b", function(fields) order[#order + 1] = "b" .. fields.n end)
	events:Listen("e", "a", function() order[#order + 1] = "a2" end)
	events:Fire("e", { n = 1 }, { to = 3 })
	T.eq(table.concat(order, ","), "a2,b1", "a replaced listener keeps its place")
	T.eq(port.sent[1].name, "e", "sent")
	T.eq(port.sent[1].options.to, 3, "with its options")
	events:Ignore("e", "a")
	events:Fire("e", { n = 2 })
	T.eq(table.concat(order, ","), "a2,b1,b2", "an ignored one no longer runs")
end)

T.test("fields the wire cannot carry stop the event before any listener runs", function()
	local port = Port()
	local events = GameEvents.New(port)
	local ran = false
	events:Listen("e", "a", function() ran = true end)
	T.eq(pcall(events.Fire, events, "e", { bad = true }), false, "raised")
	T.eq(ran, false, "no listener ran")
end)

T.test("a listener that raises is reported, and the others still run", function()
	local port = Port()
	local events = GameEvents.New(port)
	local ran = false
	events:Listen("e", "a", function() error("boom") end)
	events:Listen("e", "b", function() ran = true end)
	events:Fire("e", {})
	T.eq(ran, true, "the next ran")
	T.eq(#port.reports, 1, "reported")
end)

T.test("what the other realm sends reaches the listeners, with its sender", function()
	local port = Port()
	local events = GameEvents.New(port)
	local got
	events:Listen("e", "a", function(fields, ply) got = { fields.n, ply } end)
	port.receivers.e({ n = 7 }, "a player")
	T.eq(got[1], 7, "the fields")
	T.eq(got[2], "a player", "the sender")
	T.eq(#port.sent, 0, "and is not sent back")
end)

T.test("a predicted event runs the first time only", function()
	local port = Port()
	local events = GameEvents.New(port)
	local ran = 0
	events:Listen("shot", "a", function() ran = ran + 1 end)
	events:Fire("shot", {}, { predicted = true })
	port.firstTime = false
	events:Fire("shot", {}, { predicted = true })
	T.eq(ran, 1, "once")
	T.eq(#port.sent, 1, "handed to the transport once")
end)

T.test("Accept is the transport's", function()
	local port = Port()
	local rate = { count = 1, seconds = 1 }
	GameEvents.New(port):Accept("menu", rate)
	T.eq(port.accepted.menu, rate, "passed on")
end)

T.finish()
