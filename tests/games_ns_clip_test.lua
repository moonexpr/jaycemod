-- Clip brushes (games.ns.clip): the AI war's soldiers stand in for
-- players, so on a map made for players (TF2's, CS:S's) they stand on the
-- player clips players stand on (arena_well's gap round its point,
-- pl_goldrush's second stage), and on any other map they keep the NPC's.
local T = dofile("tests/harness.lua")
local Clip = T.require("games.ns.clip")

T.test("a map with TF2's gamerules is a players' map", function()
	T.eq(Clip.For({ "worldspawn", "tf_gamerules", "team_control_point" }), Clip.PLAYER)
end)

T.test("a map with only TF2's team spawns is a players' map", function()
	T.eq(Clip.For({ "worldspawn", "info_player_teamspawn" }), Clip.PLAYER)
end)

T.test("a CS:S map, by its team spawns, is a players' map", function()
	T.eq(Clip.For({ "info_player_terrorist" }), Clip.PLAYER)
	T.eq(Clip.For({ "info_player_counterterrorist" }), Clip.PLAYER)
end)

T.test("any other map keeps the NPC's clips", function()
	T.eq(Clip.For({ "worldspawn", "info_player_start", "npc_combine_s" }), Clip.NPC)
	T.eq(Clip.For({}), Clip.NPC, "no entities at all")
end)

T.finish()
