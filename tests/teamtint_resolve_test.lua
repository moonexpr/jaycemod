-- teamtint_resolve (addons/teamtint): which team a body shows, from a debug
-- override, a team the body is given in code (a ragdoll), and the team the
-- gamemode says it fights for.
local T = dofile("tests/harness.lua")
local Resolve = T.require("teamtint_resolve")

T.test("an override stored on the network reads back as the representation it holds", function()
	for _, rep in ipairs({ Resolve.RED, Resolve.BLU, Resolve.ORIGINAL }) do
		T.eq(Resolve.FromNetwork(Resolve.ToNetwork(rep)), rep, rep)
	end
	T.eq(Resolve.ToNetwork(nil), Resolve.NO_OVERRIDE, "no override")
	T.eq(Resolve.FromNetwork(Resolve.NO_OVERRIDE), nil, "none stored")
	T.eq(Resolve.FromNetwork(99), nil, "a number from nowhere")
end)

T.test("an override beats a given team, which beats the gamemode's", function()
	T.eq(Resolve.Representation({ override = Resolve.RED, given = Resolve.BLU, team = Resolve.BLU }), Resolve.RED, "override")
	T.eq(Resolve.Representation({ given = Resolve.BLU, team = Resolve.RED }), Resolve.BLU, "given")
	T.eq(Resolve.Representation({ team = Resolve.RED }), Resolve.RED, "the gamemode's")
	T.eq(Resolve.Representation({}), Resolve.ORIGINAL, "nobody says: as it was made")
end)

T.test("an override to ORIGINAL shows the body as made even on a team", function()
	T.eq(Resolve.Representation({ override = Resolve.ORIGINAL, team = Resolve.RED }), Resolve.ORIGINAL, "original")
end)

T.test("an answer that is no team is no answer", function()
	T.eq(Resolve.Representation({ team = "spectator" }), Resolve.ORIGINAL, "a team the addon has no colours for")
	T.eq(Resolve.Representation({ override = "green", team = Resolve.BLU }), Resolve.BLU, "a bad override is ignored")
end)

T.test("the overlay says where the representation came from", function()
	T.eq(Resolve.Source({ override = Resolve.BLU, team = Resolve.RED }), "override", "an override")
	T.eq(Resolve.Source({ given = Resolve.RED }), "given", "given in code")
	T.eq(Resolve.Source({ team = Resolve.RED }), "team", "the gamemode")
	T.eq(Resolve.Source({}), "none", "nobody")
end)

T.finish()
