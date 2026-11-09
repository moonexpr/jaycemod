-- What the defuse HUD shows (features/defuse/cl.lua draws it), from what the
-- defuse controller publishes: CTF's flag panel, its middle a fillable bar,
-- the bomb site's control point inside the flag's capture zone. The middle
-- fills red as RED plants; once the bomb is planted it stays full and
-- flashes yellow, the bomb's seconds left on it, and fills blue as BLU
-- defuses; when the round is decided it stays full in the winner's colour.
-- Each site shows its state: blue defended, red being planted, yellow planted.
local ceil, floor, ipairs = math.ceil, math.floor, ipairs
local Teams = gameplay.teams
local Defuse = require("features.defuse.model")
module(...)

local RED, BLUE = Teams.RED, Teams.BLUE

RED_FILL, BLUE_FILL, YELLOW_FILL = "red", "blue", "yellow"
-- The planted bomb's flash: on and off this many times a second.
FLASH_HZ = 2

local function Lit(now) return floor(now * FLASH_HZ * 2) % 2 == 0 end

local function SiteTint(site)
	if site.owner == RED then return YELLOW_FILL end
	if site.capping == RED then return RED_FILL end
	return BLUE_FILL
end

-- t = { state (the bomb's), sites = { { name, owner, capping, progress }... },
-- planted (the planted site's index, 0 for none), explodeAt, now }.
-- Returns { fill (0..1), tint (or nil), lit (the flash's phase), seconds (or
-- nil), site (the site's name the middle shows, or nil), sites = { { name, tint } } }.
function Panel(t)
	local panel = { fill = 0, tint = nil, lit = false, seconds = nil, site = nil, sites = {} }
	local planted = t.sites[t.planted]
	for i, site in ipairs(t.sites) do
		panel.sites[i] = { name = site.name, tint = SiteTint(site) }
	end
	if t.state == Defuse.DEFUSED then
		panel.fill, panel.tint, panel.site = 1, BLUE_FILL, planted and planted.name
	elseif t.state == Defuse.EXPLODED then
		panel.fill, panel.tint, panel.site = 1, RED_FILL, planted and planted.name
	elseif t.state == Defuse.PLANTED then
		panel.site = planted.name
		panel.seconds = ceil(t.explodeAt - t.now)
		if planted.capping == BLUE then
			panel.fill, panel.tint = planted.progress, BLUE_FILL
		else
			panel.fill, panel.tint, panel.lit = 1, YELLOW_FILL, Lit(t.now)
		end
	else
		for _, site in ipairs(t.sites) do
			if site.capping == RED then
				panel.fill, panel.tint, panel.site = site.progress, RED_FILL, site.name
			end
		end
	end
	return panel
end
