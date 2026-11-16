-- gesture: classes a player starts and ends, as drive's (Sandcastle's base gamemode).
local T = dofile ("tests/harness.lua")

-- What the library reads as it loads: GMod's baseclass, net2 and the realm.
local classes = {}
baseclass = baseclass or
	{
		Get = function (name) classes [name] = classes [name] or {}; return classes [name] end,
		Set = function (name, t) classes [name] = t end
	}
local sent = {}
net2 =
{
	Send    = function (name, payload) sent [#sent + 1] = { name = name, payload = payload } end,
	Receive = function () end
}
SERVER, CLIENT = true, nil
IsValid = function (v) return v ~= nil and v.valid ~= false end

dofile ("addons/sandcastle/gamemodes/sandcastle/gamemode/includes/modules/gesture.lua")
local Gesture = package.loaded.gesture

local log = {}
Gesture.Register ("gesture_base", { Start = function () end, End = function () end })
Gesture.Register (
	"wave",
	{
		Duration = 2,
		Start    = function (self, data) log [#log + 1] = "start " .. data.n end,
		End      = function (self) log [#log + 1] = "end " .. self.Data.n end,
		Shout    = function (self, word) return word .. self.Data.n end
	},
	"gesture_base"
)
Gesture.Register ("hold", {}, "gesture_base")

T.test ("a gesture starts with its data, runs, and ends once", function ()
	local ply = {}
	log = {}
	Gesture.PlayerStart (ply, "wave", { n = 1 }, 10)
	T.eq (Gesture.Get (ply, "wave").Data.n, 1,   "running")
	T.eq (Gesture.Get (ply, "wave").Player, ply, "knows its player")
	Gesture.PlayerEnd (ply, "wave")
	Gesture.PlayerEnd (ply, "wave")
	T.eq (Gesture.Get (ply, "wave"), nil,              "ended")
	T.eq (table.concat (log, ", "),  "start 1, end 1", "transitions, once each")
end)

T.test ("a gesture started again ends first", function ()
	local ply = {}
	log = {}
	Gesture.PlayerStart (ply, "wave", { n = 1 }, 10)
	Gesture.PlayerStart (ply, "wave", { n = 2 }, 11)
	T.eq (table.concat (log, ", "), "start 1, end 1, start 2", "out, then in")
end)

T.test ("a gesture with a duration ends when it is spent; one without runs until ended", function ()
	local ply = {}
	log = {}
	Gesture.PlayerStart (ply, "wave", { n = 1 }, 10)
	Gesture.PlayerStart (ply, "hold", {},        10)
	Gesture.Think (11.9)
	T.eq (Gesture.Get (ply, "wave") ~= nil, true, "not yet")
	Gesture.Think (12)
	T.eq (Gesture.Get (ply, "wave"),        nil,  "spent")
	T.eq (Gesture.Get (ply, "hold") ~= nil, true, "held")
	Gesture.PlayerEnd (ply, "hold")
end)

T.test ("a hook reaches the running gestures that answer it, the first answer kept", function ()
	local ply = {}
	Gesture.PlayerStart (ply, "hold", {}, 10)
	T.eq (Gesture.Call (ply, "Shout", "hey"), nil, "none answers")
	Gesture.PlayerStart (ply, "wave", { n = 3 }, 10)
	T.eq (Gesture.Call (ply, "Shout", "hey"), "hey3", "the one that does")
	Gesture.PlayerEnd (ply, "wave")
	Gesture.PlayerEnd (ply, "hold")
end)

T.test ("the server tells every client of a start and an end", function ()
	local ply = {}
	sent = {}
	Gesture.PlayerStart (ply, "hold", { x = 1 }, 10)
	Gesture.PlayerEnd (ply, "hold")
	T.eq (#sent,                   2,      "two messages")
	T.eq (sent [1].payload.name,   "hold", "the start names it")
	T.eq (sent [1].payload.data.x, 1,      "with its data")
	T.eq (sent [2].payload.player, ply,    "the end names its player")
end)

T.test ("an unknown gesture is our bug", function ()
	T.eq (pcall (Gesture.PlayerStart, {}, "nothing", {}, 10), false, "refused")
end)

T.test ("a player gone ends their gestures", function ()
	local ply = {}
	log = {}
	Gesture.PlayerStart (ply, "wave", { n = 1 }, 10)
	ply.valid = false
	Gesture.Think (10.5)
	T.eq (Gesture.Get (ply, "wave"), nil, "gone")
end)

T.finish ()
