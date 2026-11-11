-- The gamemode's content/ (the kill icon sheets, the sound pack): GMod mounts
-- it as game content on the server alone, so every file under it is sent to
-- clients to download as they join, at its path under content/. A client
-- downloads only what it does not have, so a file that changes takes a new
-- name (.devtools/bin/kill_icons_art.py names its sheets for what they hold).
local ROOT = "gamemodes/" .. GM.FolderName .. "/content/"

function GM:GetDownloadsList (dir, downloads)
	dir, downloads = dir or "", downloads or {}
	local files, dirs = file.Find (ROOT .. dir .. "*", "GAME")
	for _, name in ipairs (files) do downloads [#downloads + 1] = dir .. name end
	for _, name in ipairs (dirs) do self:GetDownloadsList (dir .. name .. "/", downloads) end
	return downloads
end

function GM:SendDownloadsList ()
	for _, path in ipairs (self:GetDownloadsList ()) do resource.AddFile (path) end
end

GM:SendDownloadsList ()
