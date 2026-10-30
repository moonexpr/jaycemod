-- features.defuse.hud: what the defuse HUD shows, from what the defuse
-- controller publishes. It is CTF's flag panel with a fillable middle: the
-- bomb site's control point inside the flag's capture zone. The middle fills
-- red as RED plants, stays full and flashes yellow once the bomb is planted
-- (with its seconds left), and fills blue as BLU defuses.
local T = dofile("tests/harness.lua")
local Hud = T.require("features.defuse.hud")
local Defuse = T.require("features.defuse.model")
local Teams = gameplay.teams

local RED, BLUE, NOBODY = Teams.RED, Teams.BLUE, 0

T.defined(Hud.FLASH_HZ, "FLASH_HZ")

local function Site(name, owner, capping, progress)
	return { name = name, owner = owner, capping = capping or NOBODY, progress = progress or 0 }
end

local function Panel(over)
	local t = { state = Defuse.CARRIED, sites = { Site("A", BLUE), Site("B", BLUE) }, planted = 0, explodeAt = 0, now = 0 }
	for k, v in pairs(over or {}) do t[k] = v end
	return Hud.Panel(t)
end

T.test("nothing planted and nobody planting: the middle is empty", function()
	local p = Panel()
	T.eq(p.fill, 0, "empty")
	T.eq(p.tint, nil, "no tint")
	T.eq(p.seconds, nil, "no timer")
end)

T.test("RED planting at a site fills the middle red with its capture", function()
	local p = Panel({ sites = { Site("A", BLUE), Site("B", BLUE, RED, 0.6) } })
	T.eq(p.fill, 0.6, "as far as the capture")
	T.eq(p.tint, Hud.RED_FILL, "red")
	T.eq(p.site, "B", "at B")
end)

T.test("planted: full, flashing yellow, with the bomb's seconds left", function()
	local sites = { Site("A", RED), Site("B", BLUE) }
	local on = Panel({ state = Defuse.PLANTED, sites = sites, planted = 1, explodeAt = 45, now = 10 })
	T.eq(on.fill, 1, "full")
	T.eq(on.tint, Hud.YELLOW_FILL, "yellow")
	T.eq(on.seconds, 35, "35 s left")
	T.eq(on.site, "A", "at A")
	local half = 1 / (2 * Hud.FLASH_HZ)
	local off = Panel({ state = Defuse.PLANTED, sites = sites, planted = 1, explodeAt = 45, now = 10 + half })
	T.eq(on.lit ~= off.lit, true, "it flashes, half a period apart")
	T.eq(Panel({ state = Defuse.PLANTED, sites = sites, planted = 1, explodeAt = 45, now = 44.2 }).seconds, 1, "seconds round up")
end)

T.test("BLU defusing fills the middle blue with its capture", function()
	local p = Panel({ state = Defuse.PLANTED, sites = { Site("A", RED, BLUE, 0.3), Site("B", BLUE) }, planted = 1, explodeAt = 45, now = 10 })
	T.eq(p.fill, 0.3, "as far as the defuse")
	T.eq(p.tint, Hud.BLUE_FILL, "blue")
	T.eq(p.seconds, 35, "the timer still shown")
end)

T.test("over: defused full blue, exploded full red, nothing flashing", function()
	local defused = Panel({ state = Defuse.DEFUSED, planted = 1 })
	T.eq(defused.fill == 1 and defused.tint == Hud.BLUE_FILL and not defused.lit, true, "defused")
	local exploded = Panel({ state = Defuse.EXPLODED, planted = 2 })
	T.eq(exploded.fill == 1 and exploded.tint == Hud.RED_FILL and not exploded.lit, true, "exploded")
end)

T.test("each site shows in its state: defended, being planted, planted", function()
	local p = Panel({ state = Defuse.PLANTED, sites = { Site("A", RED), Site("B", BLUE) }, planted = 1, explodeAt = 45, now = 10 })
	T.eq(p.sites[1].name, "A", "A first")
	T.eq(p.sites[1].tint, Hud.YELLOW_FILL, "A planted")
	T.eq(p.sites[2].tint, Hud.BLUE_FILL, "B defended")
	local planting = Panel({ sites = { Site("A", BLUE, RED, 0.5), Site("B", BLUE) } })
	T.eq(planting.sites[1].tint, Hud.RED_FILL, "A being planted")
end)

T.finish()
