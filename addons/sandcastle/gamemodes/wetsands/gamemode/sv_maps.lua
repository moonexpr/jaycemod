-- The map's own saved data, and going on to the next map, for systems that
-- keep something per map without reading the map's name themselves (the
-- AI war's nav hazards and squads' musters: features/aiwar).
--
-- WS.MapData.Read(section) -> the table saved for this map under section,
-- or nil; WS.MapData.Write(section, data) saves it. A map's sections are one
-- file, data/sandcastle/maps/<map>.json, read once a map. A section saved
-- in a file of its own before (data/sandcastle/<section>/<map>.json) is read
-- from there until it is written again.
WS.MapData = {}

local FOLDER = "sandcastle/maps/"
local sections

local function MapFile(folder)
	return folder .. game.GetMap() .. ".json"
end

local function ReadJson(path)
	local text = file.Read(path, "DATA")
	return text and util.JSONToTable(text) or nil
end

local function Sections()
	if not sections then sections = ReadJson(MapFile(FOLDER)) or {} end
	return sections
end

function WS.MapData.Read(section)
	local all = Sections()
	if all[section] == nil then all[section] = ReadJson(MapFile("sandcastle/" .. section .. "/")) end
	return all[section]
end

function WS.MapData.Write(section, data)
	local all = Sections()
	all[section] = data
	file.CreateDir(FOLDER)
	file.Write(MapFile(FOLDER), util.TableToJSON(all, true))
end

-- The map cycle's next map, now (a match the gamerules cannot close).
function WS.ChangeToNextMap()
	hook.Run("WSChangeLevel")
	RunConsoleCommand("changelevel", game.GetMapNext())
end
