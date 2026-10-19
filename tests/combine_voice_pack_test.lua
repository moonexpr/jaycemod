-- The Combine soldiers speak with the gamemode's voice pack (content/sound/
-- npc/combine_soldier, shadowing HL2's files of the same names), so every
-- soldier line the Combine's response rules speak is one the pack has: a
-- line it lacks would play HL2's own voice.
local T = dofile("tests/harness.lua")

local RULES = "addons/responserules/scripts/responserules/combine.txt"
local PACK = T.ROOT .. "../content/sound/"

local function Read(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

T.test("every Combine soldier line the rules speak is in the voice pack", function()
	local lines = 0
	for path in Read(RULES):gmatch('speak%s+"(npc/combine_soldier/[^"]+)"') do
		lines = lines + 1
		local f = io.open(PACK .. path, "rb")
		T.eq(f ~= nil, true, "in the pack: " .. path)
		if f then f:close() end
	end
	T.eq(lines > 0, true, "the rules speak soldier lines")
end)

T.finish()
