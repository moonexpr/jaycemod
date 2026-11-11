-- Clip brushes (nextsoldier.world): the AI war's soldiers stand in for
-- players, so on a map made for players (TF2's, CS:S's) they stand on the
-- player clips players stand on (arena_well's gap round its point,
-- pl_goldrush's second stage), and on any other map they keep the NPC's.
local T = dofile ("tests/harness.lua")
local World = nextsoldier.world

T.test ("a map with TF2's gamerules is a players' map", function ()
	T.eq (World.ClipFor ({ "worldspawn", "tf_gamerules", "team_control_point" }), World.CLIP_PLAYER)
end)

T.test ("a map with only TF2's team spawns is a players' map", function ()
	T.eq (World.ClipFor ({ "worldspawn", "info_player_teamspawn" }), World.CLIP_PLAYER)
end)

T.test ("a CS:S map, by its team spawns, is a players' map", function ()
	T.eq (World.ClipFor ({ "info_player_terrorist" }),        World.CLIP_PLAYER)
	T.eq (World.ClipFor ({ "info_player_counterterrorist" }), World.CLIP_PLAYER)
end)

T.test ("any other map keeps the NPC's clips", function ()
	T.eq (World.ClipFor ({ "worldspawn", "info_player_start", "npc_combine_s" }), World.CLIP_NPC)
	T.eq (World.ClipFor ({}), World.CLIP_NPC, "no entities at all")
end)

T.finish ()
