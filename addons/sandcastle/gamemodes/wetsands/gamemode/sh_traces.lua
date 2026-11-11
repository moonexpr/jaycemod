-- Source's traces by shape as globals, on both realms (world.trace over the engine's own):
-- TraceCube(origin, size), TracePlayer(origin, scale), TraceSphere(origin, radius) and
-- TraceFrustum(origin, view), each then (mask, group, filter), MASK_NPCSOLID,
-- COLLISION_GROUP_NONE and nothing filtered by default. With no origin, each is a preset whose
-- :Each(origins) is a generator over them:
--   for tr, spot in TracePlayer(nil, 1):Each(spots) do ... end
local traces = world.trace.New (
	{
		Hull = util.TraceHull,
		Line = util.TraceLine,
		Vector = Vector,
		mask = MASK_NPCSOLID,
		group = COLLISION_GROUP_NONE
	}
)

TraceCube, TracePlayer, TraceSphere, TraceFrustum = traces.Cube, traces.Player, traces.Sphere, traces.Frustum
