-- Team Tint's shared state: its pure modules and the networked override.
require("teamtint_catalog")
require("teamtint_resolve")
require("teamtint_tuning")

TeamTint = TeamTint or {}
TeamTint.Catalog = teamtint_catalog
TeamTint.Resolve = teamtint_resolve
TeamTint.Tuning = teamtint_tuning

-- The tool's override on a body: teamtint_resolve's ToNetwork value, 0 for none.
TeamTint.NW = "teamtint"

-- The tool's A/B pairs (Sandbox's cleanup menu).
if cleanup then cleanup.Register("teamtint") end

function TeamTint.Override(ent)
	return TeamTint.Resolve.FromNetwork(ent:GetNW2Int(TeamTint.NW, TeamTint.Resolve.NO_OVERRIDE))
end
