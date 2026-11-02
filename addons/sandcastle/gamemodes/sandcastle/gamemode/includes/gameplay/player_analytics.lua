-- Player analytics: players' joins, leaves and victories, kept as a log of
-- events, and what the log says about them.
--   Join(id, at), Leave(id, at), Victory(kind, ids, at): the events; id a
--     SteamID64, at Unix seconds, kind KILL (an enemy killed), CAPTURE (a
--     point or flag captured) or ROUND (a round won)
--   Encode(event) -> a log line; Parse(line, number) -> the event, or an
--     error naming the line
--   Excluded(text) -> the set of SteamID64s a list names (developers);
--     Exclude(event, excluded) -> the event without them, or nil
--   Players(events, now[, excluded]) -> id -> { firstSeen, sessions, playSeconds, days,
--     victories = kind -> count, first = kind -> { at, playSeconds,
--     sessions, wallSeconds } }, ANY the first victory of any kind; the
--     excluded are left out, and taken out of victories they shared
--   Retention(players, now) -> each day's new players (UTC days) and how
--     many came back the next day (day1) and within seven (day7); nil while
--     that day has not ended yet
--   FirstVictory(players) -> kind -> { won, notYet, medianPlaySeconds,
--     medianSessions, medianWallSeconds }
-- A rejoin within SESSION_GAP of a leave continues the session (a map
-- change ends every session and starts it again). A session never left (the
-- server stopped without a leave) ends at the next join, or at now.
local error, ipairs, pairs, pcall, tonumber, tostring, type = error, ipairs, pairs, pcall, tonumber, tostring, type
local floor = math.floor
local concat, sort = table.concat, table.sort
local format = string.format
module(...)

JOIN, LEAVE, VICTORY = "join", "leave", "victory"
KILL, CAPTURE, ROUND = "kill", "capture", "round"
ANY = "any" -- a player's first victory of whatever kind
KINDS = { KILL, CAPTURE, ROUND }
SESSION_GAP = 120 -- s
DAY = 86400 -- s
WEEK_DAYS = 7

local IS_KIND = {}
for _, kind in ipairs(KINDS) do IS_KIND[kind] = true end

local SEPARATOR, ID_SEPARATOR = "\t", ","

local function Id(id)
	if type(id) ~= "string" or not id:match("^%d+$") then
		error("a player id is a SteamID64, digits only, not " .. tostring(id), 3)
	end
	return id
end

local function Time(at)
	if type(at) ~= "number" or at ~= at then error("a time is a number of Unix seconds, not " .. tostring(at), 3) end
	return at
end

function Join(id, at)
	return {
		kind = JOIN,
		id = Id(id),
		at = Time(at),
	}
end

function Leave(id, at)
	return {
		kind = LEAVE,
		id = Id(id),
		at = Time(at),
	}
end

function Victory(kind, ids, at)
	if not IS_KIND[kind] then error("a victory's kind is " .. concat(KINDS, ", ") .. ", not " .. tostring(kind), 2) end
	local list = {}
	for i, id in ipairs(ids) do list[i] = Id(id) end
	return {
		kind = VICTORY,
		victory = kind,
		ids = list,
		at = Time(at),
	}
end

function Encode(e)
	local at = format("%d", floor(e.at))
	if e.kind == VICTORY then return concat({ VICTORY, e.victory, at, concat(e.ids, ID_SEPARATOR) }, SEPARATOR) end
	return concat({ e.kind, e.id, at }, SEPARATOR)
end

local function Fields(line)
	local fields = {}
	for field in (line .. SEPARATOR):gmatch("([^" .. SEPARATOR .. "]*)" .. SEPARATOR) do fields[#fields + 1] = field end
	return fields
end

local function Ids(text)
	local ids = {}
	for id in text:gmatch("[^" .. ID_SEPARATOR .. "]+") do ids[#ids + 1] = id end
	return ids
end

local PARSE = {
	[JOIN] = function(f) return Join(f[2], tonumber(f[3])) end,
	[LEAVE] = function(f) return Leave(f[2], tonumber(f[3])) end,
	[VICTORY] = function(f) return Victory(f[2], Ids(f[4] or ""), tonumber(f[3])) end,
}

function Parse(line, number)
	local fields = Fields(line)
	local parse = PARSE[fields[1]]
	if not parse then error(format("line %d: not an event: %s", number, line), 2) end
	local ok, event = pcall(parse, fields)
	if not ok then error(format("line %d: %s", number, tostring(event)), 2) end
	return event
end

-- Reading the log ---------------------------------------------------------------------

local function Day(at) return floor(at / DAY) end

local function NewPlayer(at)
	return {
		firstSeen = at,
		sessions = 0,
		playSeconds = 0,
		open = nil, -- when the session in play started
		lastLeave = nil,
		days = {},
		victories = {},
		first = {},
	}
end

local function Close(p, at)
	p.playSeconds = p.playSeconds + (at - p.open)
	p.open = nil
	p.days[Day(at)] = true
end

local EVENTS = {
	[JOIN] = function(players, e)
		local p = players[e.id]
		if not p then
			p = NewPlayer(e.at)
			players[e.id] = p
		end
		if p.open then
			Close(p, e.at) -- never left: the server stopped
			p.lastLeave = nil
		end
		if not (p.lastLeave and e.at - p.lastLeave <= SESSION_GAP) then p.sessions = p.sessions + 1 end
		p.open = e.at
		p.days[Day(e.at)] = true
	end,
	[LEAVE] = function(players, e)
		local p = players[e.id]
		if not (p and p.open) then return end
		Close(p, e.at)
		p.lastLeave = e.at
	end,
	[VICTORY] = function(players, e)
		for _, id in ipairs(e.ids) do
			local p = players[id]
			if p then
				p.victories[e.victory] = (p.victories[e.victory] or 0) + 1
				for _, kind in ipairs({ e.victory, ANY }) do
					if not p.first[kind] then
						p.first[kind] = {
							at = e.at,
							playSeconds = p.playSeconds + (p.open and (e.at - p.open) or 0),
							sessions = p.sessions,
							wallSeconds = e.at - p.firstSeen,
						}
					end
				end
			end
		end
	end,
}

-- The ids a list names (SteamID64s, separated by commas or spaces), as a set.
function Excluded(text)
	local set = {}
	for id in text:gmatch("[^,%s]+") do set[Id(id)] = true end
	return set
end

-- The event with every excluded player taken out, or nil when none is left.
function Exclude(e, excluded)
	if e.kind ~= VICTORY then return not excluded[e.id] and e or nil end
	local ids = {}
	for _, id in ipairs(e.ids) do
		if not excluded[id] then ids[#ids + 1] = id end
	end
	return #ids > 0 and Victory(e.victory, ids, e.at) or nil
end

-- excluded: id -> true, players left out (developers), optional.
function Players(events, now, excluded)
	local players = {}
	for _, e in ipairs(events) do
		local kept = e
		if excluded then kept = Exclude(e, excluded) end
		if kept then EVENTS[kept.kind](players, kept) end
	end
	for _, p in pairs(players) do
		if p.open then Close(p, now) end
	end
	return players
end

function Retention(players, now)
	local today = Day(now)
	local byDay = {}
	for _, p in pairs(players) do
		local day = Day(p.firstSeen)
		local cohort = byDay[day]
		if not cohort then
			cohort = {
				day = day,
				new = 0,
				day1 = today > day + 1 and 0 or nil,
				day7 = today > day + WEEK_DAYS and 0 or nil,
			}
			byDay[day] = cohort
		end
		cohort.new = cohort.new + 1
		if cohort.day1 and p.days[day + 1] then cohort.day1 = cohort.day1 + 1 end
		if cohort.day7 then
			for d = day + 1, day + WEEK_DAYS do
				if p.days[d] then
					cohort.day7 = cohort.day7 + 1
					break
				end
			end
		end
	end
	local list = {}
	for _, cohort in pairs(byDay) do list[#list + 1] = cohort end
	sort(list, function(a, b) return a.day < b.day end)
	return list
end

local function Median(values)
	if #values == 0 then return nil end
	sort(values)
	local middle = floor((#values + 1) / 2)
	if #values % 2 == 1 then return values[middle] end
	return (values[middle] + values[middle + 1]) / 2
end

function FirstVictory(players)
	local result = {}
	for _, kind in ipairs({ KILL, CAPTURE, ROUND, ANY }) do
		local play, sessions, wall, notYet = {}, {}, {}, 0
		for _, p in pairs(players) do
			local first = p.first[kind]
			if first then
				play[#play + 1] = first.playSeconds
				sessions[#sessions + 1] = first.sessions
				wall[#wall + 1] = first.wallSeconds
			else
				notYet = notYet + 1
			end
		end
		result[kind] = {
			won = #play,
			notYet = notYet,
			medianPlaySeconds = Median(play),
			medianSessions = Median(sessions),
			medianWallSeconds = Median(wall),
		}
	end
	return result
end
