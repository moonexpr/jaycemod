-- Which of a body's materials a team is painted on, and how. A material is
-- known by its path (as IMaterial:GetName gives it): its folder says whose
-- it is (the Combine's armour, a rebel's clothes), a part of its name says
-- what it covers (a face, an eye), and the class both give says whether it
-- takes a team colour. How it takes it comes from the material's own facts,
-- read in the game: a tint mask in its base alpha ($blendtintbybasealpha,
-- the PlayerColor proxy's) takes the colour at run time; without one, a
-- team texture baked by .devtools/bin/teamtint_bake.py replaces its base;
-- unbaked, it takes TF2's shading and keeps its colours. GMod's
-- require("teamtint_catalog") loads it.
--
-- The folders are the AI war's bodies, under the NPC's folder or the
-- player model's (models/player/...). Which of them carry a mask is
-- teamtint_census' to say, not this file's: nothing here assumes it.
local ipairs, lower = ipairs, string.lower
module("teamtint_catalog")

-- How a material is themed (Strategy).
PROXY = "proxy" -- the team colour through its tint mask ($color2)
BAKED = "baked" -- its base texture swapped for the team's
SHADE = "shade" -- TF2's shading terms, its own colours
NONE = "none" -- left as it is

-- tint: whether it takes a team colour; a class that does not still takes
-- the shading.
CLASSES = {
	armor = { tint = true },
	cloth = { tint = true },
	gear = { tint = true },
	hide = { tint = true }, -- a creature's skin that carries its side (the vortigaunt's)
	skin = { tint = false },
	hair = { tint = false },
	eyes = { tint = false, untouched = true },
	teeth = { tint = false, untouched = true },
}

-- Whose a material is, by its folder, after models/player/ is read as models/.
FOLDERS = {
	{ pattern = "^models/combine_soldier/", class = "armor" },
	{ pattern = "^models/combine_super_soldier/", class = "armor" },
	{ pattern = "^models/police/", class = "armor" },
	{ pattern = "^models/humans/", class = "cloth" },
	{ pattern = "^models/alyx/", class = "cloth" },
	{ pattern = "^models/barney/", class = "cloth" },
	{ pattern = "^models/vortigaunt/", class = "hide" },
}

-- What a material covers, by a part of its name; the first that matches
-- wins over its folder's class.
PARTS = {
	{ pattern = "eyeball", class = "eyes" },
	{ pattern = "pupil", class = "eyes" },
	{ pattern = "cornea", class = "eyes" },
	{ pattern = "teeth", class = "teeth" },
	{ pattern = "mouth", class = "teeth" },
	{ pattern = "tongue", class = "teeth" },
	{ pattern = "face", class = "skin" },
	{ pattern = "hand", class = "skin" },
	{ pattern = "hair", class = "hair" },
}

-- A path as the catalog compares it: lower case, forward slashes, without
-- materials/ or .vmt.
function Normalize(path)
	path = lower(path):gsub("\\", "/")
	return (path:gsub("^materials/", ""):gsub("%.vmt$", ""))
end

-- The rule a material falls under ({ pattern, class }), or nil for one in
-- no folder of the catalog's.
function Classify(path)
	path = Normalize(path):gsub("^models/player/", "models/")
	local folder
	for _, rule in ipairs(FOLDERS) do
		if path:find(rule.pattern) then
			folder = rule
			break
		end
	end
	if not folder then return nil end
	local name = path:match("[^/]*$")
	for _, rule in ipairs(PARTS) do
		if name:find(rule.pattern, 1, true) then return rule end
	end
	return folder
end

-- How a material of class is themed, from its facts: shader (its
-- IMaterial:GetShader), tintMask (it has $blendtintbybasealpha), baked (a
-- team texture exists for its base texture).
function Strategy(class, facts)
	local kind = CLASSES[class]
	if not kind or kind.untouched then return NONE end
	if not (facts.shader or ""):find("^VertexLitGeneric") then return NONE end
	if not kind.tint then return SHADE end
	if facts.tintMask then return PROXY end
	if facts.baked then return BAKED end
	return SHADE
end

-- The texture baked for team ("red", "blu") from a base texture, or nil for
-- no team.
function BakedTexture(team, base)
	if team ~= "red" and team ~= "blu" then return nil end
	return "teamtint/" .. team .. "/" .. Normalize(base)
end
