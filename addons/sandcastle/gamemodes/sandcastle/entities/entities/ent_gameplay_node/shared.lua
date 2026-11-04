-- The Trolley tool's track node: a path_track, and the rails on to the next, which
-- stand through the game under the cart.
local Model = WS.require("features.builder.model")

ENT.Type = "anim"
ENT.Base = "base_gameplay_piece"
ENT.PrintName = "Track Node"
ENT.Kind = Model.NODE
ENT.MarkerModel = "models/props_mining/track_tie.mdl"
ENT.Properties = {
	{ name = "Speed", key = "speed", type = "Float", title = "New Train Speed", default = 0, min = 0, max = 1000 },
	{ name = "Disabled", flag = 1, type = "Bool", title = "Disabled", default = false },
	{ name = "Uphill", flag = 32, type = "Bool", title = "Part of an uphill path", default = false },
	{ name = "Downhill", flag = 64, type = "Bool", title = "Part of a downhill path", default = false },
}
ENT.WirePorts = { inputs = { "Enabled" }, outputs = {} }
ENT.WireCommands = { Enabled = Model.WireSwitch("EnablePath", "DisablePath") }

-- TF2's straight rails, longest first; all but the shortest run along their Y.
local RAILS = {
	{ length = 256, model = "models/props_mining/track_straight_256.mdl", alongY = true },
	{ length = 128, model = "models/props_mining/track_straight_128.mdl", alongY = true },
	{ length = 64, model = "models/props_mining/track_straight_64.mdl", alongY = true },
	{ length = 32, model = "models/props_mining/track_straight_32.mdl", alongY = false },
}
-- A gap shorter than this is left: the rail would overrun the node by more.
local RAIL_MIN_GAP = 16

-- The rails from a to b: { model, pos (its center), alongY }s.
function ENT.TrackSegments(a, b)
	local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
	local total = (dx * dx + dy * dy + dz * dz) ^ 0.5
	local segments, laid = {}, 0
	while total - laid >= RAIL_MIN_GAP do
		local rail = RAILS[#RAILS]
		for _, candidate in ipairs(RAILS) do
			if candidate.length <= total - laid then
				rail = candidate
				break
			end
		end
		local at = (laid + rail.length / 2) / total
		segments[#segments + 1] = {
			model = rail.model,
			pos = Vector(a.x + dx * at, a.y + dy * at, a.z + dz * at),
			alongY = rail.alongY,
		}
		laid = laid + rail.length
	end
	return segments
end
