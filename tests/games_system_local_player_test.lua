-- system.local_player: the local player's soundscapes, soundscript names
-- precached once and played on the local player through the engine's port.
local T = dofile("tests/harness.lua")
local LocalPlayer = system.local_player

-- An engine that knows some soundscripts, keeps what was precached and
-- what played, in order.
local function Engine(known)
	local engine = { known = {}, precached = {}, played = {} }
	for _, name in ipairs(known) do engine.known[name] = true end
	function engine:Exists(name) return self.known[name] == true end
	function engine:Precache(name) self.precached[#self.precached + 1] = name end
	function engine:Emit(name) self.played[#self.played + 1] = name end
	return engine
end

T.test("a soundscript precached is the engine's, once, and plays on the local player", function()
	local engine = Engine({ "Announcer.CompGameBeginsFight" })
	local sounds = LocalPlayer.New(engine)
	T.eq(sounds:Precache("Announcer.CompGameBeginsFight"), "Announcer.CompGameBeginsFight", "its name back")
	sounds:Precache("Announcer.CompGameBeginsFight")
	T.eq(table.concat(engine.precached, " "), "Announcer.CompGameBeginsFight", "precached once")
	T.eq(sounds:Has("Announcer.CompGameBeginsFight"), true, "held")
	sounds:Play("Announcer.CompGameBeginsFight")
	T.eq(table.concat(engine.played, " "), "Announcer.CompGameBeginsFight", "played")
end)

T.test("a name no soundscript has is refused, and never precached", function()
	local engine = Engine({})
	local sounds = LocalPlayer.New(engine)
	T.eq(sounds:Precache("Announcer.Typo"), nil, "nil")
	T.eq(#engine.precached, 0, "not precached")
	T.eq(sounds:Has("Announcer.Typo"), false, "not held")
end)

-- A line the preload missed still plays, precached as it does (it may
-- hitch the first time), and is told among the late, so the list can
-- take it.
T.test("a soundscript never precached is precached as it plays, and counted late", function()
	local engine = Engine({ "Game.Overtime" })
	local sounds = LocalPlayer.New(engine)
	sounds:Play("Game.Overtime")
	T.eq(table.concat(engine.precached, " "), "Game.Overtime", "precached")
	T.eq(table.concat(engine.played, " "), "Game.Overtime", "played")
	T.eq(table.concat(sounds:Late(), " "), "Game.Overtime", "late")
	sounds:Play("Game.Overtime")
	T.eq(#engine.precached, 1, "once")
	T.eq(#sounds:Late(), 1, "late once")
end)

-- A name no soundscript has is our bug (a typo, a script not loaded):
-- refused, naming it, not played.
T.test("playing a name no soundscript has is refused, naming it", function()
	local engine = Engine({})
	local sounds = LocalPlayer.New(engine)
	local ok, err = pcall(sounds.Play, sounds, "Announcer.Typo")
	T.eq(ok, false, "refused")
	T.eq(tostring(err):find("Announcer.Typo", 1, true) ~= nil, true, "names it: " .. tostring(err))
	T.eq(#engine.played, 0, "not played")
end)

T.finish()
