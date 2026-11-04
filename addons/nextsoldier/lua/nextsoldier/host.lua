-- What a soldier needs of the mode hosting it, which NextSoldier does not read
-- for itself: the mode installs a host as it loads, before any soldier is made.
--   Movement() -> stepHeight, jumpHeight: how a soldier's body steps and jumps
--   PlayerFactions(ply) -> the factions a player is in, a list
--   FactionEnemy(faction) -> the faction this one is hostile to on sight, or nil
--   PathClearance(bot) -> the hull's clearance a path is priced by (the
--     navigation's: whether the body fits each area and opening)
--   PathDebug() -> what records a watched path search: NewCostRecorder(),
--     NewPathReport(report)
--   GazeUpdate(ent, facing, fighting, hint, team, urgent): turn a head (client)
--   SolidMask() -> what a body collides with on this map, player clips or not
local Port = core.port
module("nextsoldier.host")

PORT = Port.New("NextSoldier host", {
	"Movement",
	"PlayerFactions",
	"FactionEnemy",
	"PathClearance",
	"PathDebug",
	"GazeUpdate",
	"SolidMask",
})

-- The installed host, read as nextsoldier.host.current.
function Install(host)
	current = PORT:Check(host)
	return current
end
