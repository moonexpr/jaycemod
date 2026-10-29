-- wartactics.hazards: the nav areas that keep forcing soldiers to respawn
-- (a fall, a pit, a recovery back to spawn), disabled for their routes
-- once they have done so THRESHOLD times, kept across maps until inspected.
local T = dofile("tests/harness.lua")
local Hazards = wartactics.hazards

T.defined(Hazards.THRESHOLD, "THRESHOLD")
T.defined(Hazards.VERSION, "VERSION")

local WHERE = { x = 10, y = 20, z = 30 }

T.test("an area is disabled once it has forced THRESHOLD respawns, and says so once", function()
	local hazards = Hazards.New()
	for i = 1, Hazards.THRESHOLD - 1 do
		T.eq(hazards:Record(7, Hazards.FELL, WHERE), false, "respawn " .. i .. ": not yet")
		T.eq(hazards:IsDisabled(7), false, "still open after " .. i)
	end
	T.eq(hazards:Record(7, Hazards.FELL, WHERE), true, "the last: disabled now")
	T.eq(hazards:IsDisabled(7), true, "disabled")
	T.eq(hazards:Record(7, Hazards.FELL, WHERE), false, "again: already disabled")
end)

T.test("each area counts its own respawns, and its causes", function()
	local hazards = Hazards.New()
	hazards:Record(1, Hazards.FELL, WHERE)
	hazards:Record(1, Hazards.RECOVERED, WHERE)
	hazards:Record(2, Hazards.FELL, WHERE)
	local entries = hazards:Entries()
	T.eq(#entries, 2, "two areas")
	T.eq(entries[1].id, 1, "in id order")
	T.eq(entries[1].count, 2, "area 1 twice")
	T.eq(entries[1].causes[Hazards.FELL], 1, "once by a fall")
	T.eq(entries[1].causes[Hazards.RECOVERED], 1, "once recovered")
	T.eq(entries[2].count, 1, "area 2 once")
end)

T.test("an unknown cause is our bug", function()
	T.eq(pcall(function() Hazards.New():Record(1, "bored", WHERE) end), false, "unknown cause")
end)

T.test("the disabled areas are given as a set the caller may keep", function()
	local hazards = Hazards.New()
	for _ = 1, Hazards.THRESHOLD do hazards:Record(3, Hazards.FELL, WHERE) end
	hazards:Record(4, Hazards.FELL, WHERE)
	local disabled = hazards:Disabled()
	T.eq(disabled[3], true, "3")
	T.eq(disabled[4], nil, "not 4")
	disabled[5] = true
	T.eq(hazards:IsDisabled(5), false, "a copy")
end)

T.test("inspected areas are cleared: one, or all", function()
	local hazards = Hazards.New()
	for _ = 1, Hazards.THRESHOLD do
		hazards:Record(1, Hazards.FELL, WHERE)
		hazards:Record(2, Hazards.FELL, WHERE)
	end
	T.eq(hazards:Clear(1), true, "cleared 1")
	T.eq(hazards:IsDisabled(1), false, "1 open again")
	T.eq(hazards:Record(1, Hazards.FELL, WHERE), false, "counted afresh")
	T.eq(hazards:Clear(9), false, "nothing to clear")
	hazards:ClearAll()
	T.eq(#hazards:Entries(), 0, "none left")
end)

T.test("saved and read back, the hazards are as they were", function()
	local hazards = Hazards.New()
	for _ = 1, Hazards.THRESHOLD do hazards:Record(12, Hazards.FELL, WHERE) end
	hazards:Record(13, Hazards.RECOVERED, { x = 1, y = 2, z = 3 })
	local back = Hazards.Decode(Hazards.Encode(hazards))
	T.eq(back:IsDisabled(12), true, "12 disabled")
	T.eq(back:IsDisabled(13), false, "13 open")
	local entries = back:Entries()
	T.eq(entries[1].count, Hazards.THRESHOLD, "its count")
	T.eq(entries[1].where.y, 20, "where it is")
	T.eq(entries[2].causes[Hazards.RECOVERED], 1, "its causes")
end)

T.test("a save of another version is refused", function()
	local data = Hazards.Encode(Hazards.New())
	data.version = Hazards.VERSION + 1
	T.eq(pcall(Hazards.Decode, data), false, "another version")
end)

-- Separated: a team whose spawns no longer reach the objective it fights
-- for, with the disabled areas closed; a team with no objective is not.
T.test("the war is separated when a team cannot reach its objective", function()
	T.eq(Hazards.Separated({ { team = 2, reaches = true }, { team = 3, reaches = true } }), false, "both reach")
	T.eq(Hazards.Separated({ { team = 2, reaches = true }, { team = 3, reaches = false } }), true, "one cut off")
	T.eq(Hazards.Separated({}), false, "no objective")
end)

T.finish()
