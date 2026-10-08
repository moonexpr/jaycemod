-- Game events v2 research, questions 2 and 3 (server side), part 2 of 2:
-- writes what reload_arm.lua logged since it was armed, then calls the real
-- AddCSLuaFile once after start-up, to see whether a late call is refused.
local NAME = "reload_report"
local G = WETSAND_GEV2
local lines = {}
if not G then
	lines[1] = "reload_arm.lua has not run"
else
	for i, line in ipairs(G.log) do lines[i] = line end
	local ok, err = pcall(G.orig_AddCSLuaFile, "sandcastle/gamemode/foundation/teams.lua")
	lines[#lines + 1] = "late AddCSLuaFile ok=" .. tostring(ok) .. " err=" .. tostring(err)
	G.log = {}
end
file.CreateDir("wetsand_tests/gev2/out")
file.Write("wetsand_tests/gev2/out/" .. NAME .. ".txt", table.concat(lines, "\n") .. "\n")
print("wetsand_tests: gev2 " .. NAME .. " done")
