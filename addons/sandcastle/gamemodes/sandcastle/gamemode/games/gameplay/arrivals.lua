-- The players expected from the previous map (their SteamID64s), and the
-- file that carries them across a map change: written as a map ends (Write),
-- read as the next loads (Read). A file older than MAX_AGE seconds was left
-- by a server stopped between maps, and expects nobody. New(ids) tracks
-- them in: Done once each has arrived (their client loaded) or left.
local concat, gmatch, ipairs, match, next, setmetatable, tonumber = table.concat, string.gmatch, ipairs, string.match, next, setmetatable, tonumber
module(...)

MAX_AGE = 300

local HEADER = "arrivals "

-- ids written at time now (os.time()), the file's text.
function Write(ids, now)
	return HEADER .. now .. "\n" .. concat(ids, "\n")
end

-- The ids in text, read at time now; none from a stale file or one not
-- written by Write.
function Read(text, now)
	local written = tonumber(match(text, "^" .. HEADER .. "(%d+)\n"))
	if not written or now - written > MAX_AGE then return {} end
	local ids = {}
	for id in gmatch(text, "\n(%d+)") do ids[#ids + 1] = id end
	return ids
end

local Arrivals = {}
Arrivals.__index = Arrivals

function New(ids)
	local waiting = {}
	for _, id in ipairs(ids) do waiting[id] = true end
	return setmetatable({ waiting = waiting }, Arrivals)
end

function Arrivals:Arrived(id)
	self.waiting[id] = nil
end

function Arrivals:Left(id)
	self.waiting[id] = nil
end

function Arrivals:Done()
	return next(self.waiting) == nil
end
