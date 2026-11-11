-- wartactics.room_hints: a mapper's word on the rooms the war finds (info_room): a room's label,
-- its class and its holder, which may follow a control point's owner.
local T = dofile ("tests/harness.lua")
local Hints = wartactics.room_hints
local Classes = wartactics.classes

local function At (x) return { x = x, y = 0, z = 0 } end

T.test ("a hint is made from what the map says, or refused", function ()
	local hint = Hints.Hint ({ name = "red_stronghold", label = "RED stronghold", class = "stronghold", team = 2,
		point = "cp_red", pos = At (1) })
	T.eq (hint.class, Classes.STRONGHOLD, "its class, the war's own")
	T.eq (hint.team, 2, "its holder")
	T.eq (hint.point, "cp_red", "its control point")
	T.eq (Hints.Hint ({ name = "plain", pos = At (1) }).class, nil, "a class may be left to the war")
	T.eq (pcall (Hints.Hint, { name = "bad", class = "kitchen", pos = At (1) }), false, "an unknown class, refused")
	T.eq (pcall (Hints.Hint, { name = "nowhere" }), false, "a hint stands somewhere")
	T.eq (Hints.Hint ({ name = "blank", class = "", team = 0, point = "", pos = At (1) }).class, nil,
		"the map's empty values are none")
end)

T.test ("each hint is placed in the room it stands in; more than one in a room, or none, is told", function ()
	local a, b = { id = 1 }, { id = 2 }
	local function RoomAt (pos) return (pos.x < 10 and a) or (pos.x < 20 and b) or nil end
	local placed, trouble = Hints.Place (
		{
			Hints.Hint ({ name = "one", pos = At (1) }),
			Hints.Hint ({ name = "two", pos = At (12) }),
			Hints.Hint ({ name = "again", pos = At (2) }),
			Hints.Hint ({ name = "outside", pos = At (50) })
		}, RoomAt)
	T.eq (placed [a].name, "one",                                     "the first in its room")
	T.eq (placed [b].name, "two",                                     "another room's")
	T.eq (trouble [1],     "again: a second hint in the room of one", "a second told, the first kept")
	T.eq (trouble [2],     "outside: in no room",                     "one in no room told")
end)

T.test ("a hint's class and holder stand over the war's own; its label goes with the room", function ()
	local hall, yard = { id = 1 }, { id = 2 }
	local classed =
	{
		[hall] = { cls = Classes.COMMONS, gradient = 0.4 },
		[yard] = { cls = Classes.WILDS, gradient = 0 }
	}
	local placed = { [hall] = Hints.Hint ({ name = "hall", label = "Great hall", class = "stronghold", team = 3, pos = At (1) }) }
	local out = Hints.Override (classed, placed, function () return nil end)
	T.eq (out [hall].cls,     Classes.STRONGHOLD, "its class")
	T.eq (out [hall].team,    3,                  "its holder")
	T.eq (out [hall].label,   "Great hall",       "its label")
	T.eq (out [yard],         classed [yard],     "a room with no hint as the war found it")
	T.eq (classed [hall].cls, Classes.COMMONS,    "the war's own left as it was")
end)

T.test ("tied to a control point, a room is held by the point's owner, none while it has none", function ()
	local hall = { id = 1 }
	local classed = { [hall] = { cls = Classes.COMMONS, gradient = 0.5 } }
	local placed = { [hall] = Hints.Hint ({ name = "hall", team = 2, point = "cp_mid", pos = At (1) }) }
	local owners = { cp_mid = 3 }
	local function Owner (point) return owners [point] end
	T.eq (Hints.Override (classed, placed, Owner) [hall].team, 3, "the point's owner over the map's team")
	owners.cp_mid = nil
	T.eq (Hints.Override (classed, placed, Owner) [hall].team, nil,             "the point neutral: held by none")
	T.eq (Hints.Override (classed, placed, Owner) [hall].cls,  Classes.COMMONS, "its class the war's while none is given")
end)

T.finish ()
