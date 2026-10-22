-- TF2's fixed weapon spread (tf_use_fixed_weaponspreads; tf_fx_shared.cpp's
-- g_vecFixedWpnSpreadPellets): with it on, the pellets of a multi-pellet
-- shot land in a fixed pattern rather than at random. The first and the
-- tenth go down the middle, the rest in a cross and a square around it,
-- each offset scaled by SCALE of the weapon's spread.
module(...)

SCALE = 0.5

PATTERN = {
	{ 0, 0 },
	{ 1, 0 },
	{ -1, 0 },
	{ 0, -1 },
	{ 0, 1 },
	{ 0.85, -0.85 },
	{ 0.85, 0.85 },
	{ -0.85, -0.85 },
	{ -0.85, 0.85 },
	{ 0, 0 },
}

-- Pellet i's (1-based) offset across and up, in units of the spread.
function Offset(i)
	local p = PATTERN[(i - 1) % #PATTERN + 1]
	return p[1] * SCALE, p[2] * SCALE
end
