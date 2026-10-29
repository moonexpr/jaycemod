-- The map's own saved data, and going on to the next map, for systems that
-- keep something per map without reading the map's name themselves (the
-- AI war's nav hazards: features/aiwar/sv_hazards.lua).
--
-- WS.MapData.Read(folder) -> the table saved for this map under
-- data/<folder>, or nil; WS.MapData.Write(folder, data) saves it as JSON.
WS.MapData = {}

local function MapFile(folder)
	return folder .. game.GetMap() .. ".json"
end

function WS.MapData.Read(folder)
	local text = file.Read(MapFile(folder), "DATA")
	return text and util.JSONToTable(text) or nil
end

function WS.MapData.Write(folder, data)
	file.CreateDir(folder)
	file.Write(MapFile(folder), util.TableToJSON(data, true))
end

-- The map cycle's next map, now (a match the gamerules cannot close).
function WS.ChangeToNextMap()
	hook.Run("WSChangeLevel")
	RunConsoleCommand("changelevel", game.GetMapNext())
end
