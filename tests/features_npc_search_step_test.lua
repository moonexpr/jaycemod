-- features.npc.search_step: how many areas a route search expands between looks at the clock. A
-- search priced from data alone takes several, so it is not spent crossing into the module; one
-- that asks Lua a rule an area takes one, so no step runs far past the searches' slice.
local T = dofile ("tests/harness.lua")
local SearchStep = T.require ("features.npc.search_step")

T.defined (SearchStep.MESH, "the expansions a step of a search on data alone")

T.test ("a search on data alone takes several areas a step", function ()
	T.eq (SearchStep.Expansions ({}), SearchStep.MESH, "the mesh's own step")
	T.eq (SearchStep.MESH > 1,        true,            "more than one, or it would cross into the module for each")
end)

T.test ("a search asking whether a body fits takes one area a step", function ()
	T.eq (SearchStep.Expansions ({ body = true }), 1, "a hull trace an area and a link")
end)

T.test ("the watched Lua search takes one area a step", function ()
	T.eq (SearchStep.Expansions ({ watched = true }), 1, "up to 100 us an expansion")
end)

T.test ("the doors a request avoids are no reason to take less", function ()
	T.eq (SearchStep.Expansions ({ avoid = true }), SearchStep.MESH, "a table read an area")
end)

T.finish ()
