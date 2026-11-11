-- games.system.names: bot players' names, after the games and shows they come
-- from, a bot taking one no player on the server has.
local T = dofile ("tests/harness.lua")
local Names = system.names

-- Source keeps a player's name in 32 bytes, its terminator among them.
local MAX_NAME_BYTES = 31

local function First (low, high) return low end
local function Last (low, high) return high end

T.test ("every franchise names bots, and BOT_NAMES is all of theirs", function ()
	local total = 0
	for _, franchise in ipairs (Names.FRANCHISES) do
		T.eq (type (franchise.name) == "string" and #franchise.name > 0, true, "a franchise is named")
		T.eq (#franchise.names > 0,                                      true, franchise.name .. " names some bots")
		total = total + #franchise.names
	end
	T.eq (#Names.BOT_NAMES, total, "BOT_NAMES holds every franchise's names")
end)

T.test ("the franchises are the seven the names come from", function ()
	local named = {}
	for _, franchise in ipairs (Names.FRANCHISES) do named [franchise.name] = true end
	for _, name in ipairs (
		{
			"Undertale",
			"Deltarune",
			"Steven Universe",
			"Team Fortress 2",
			"Left 4 Dead 2",
			"Stardew Valley",
			"Code Lyoko"
		}
	) do
		T.eq (named [name], true, name .. " is among the franchises")
	end
end)

T.test ("no name is given twice", function ()
	local seen = {}
	for _, name in ipairs (Names.BOT_NAMES) do
		T.eq (not seen [name], true, name .. " appears once")
		seen [name] = true
	end
end)

T.test ("every name is one Source keeps whole", function ()
	for _, name in ipairs (Names.BOT_NAMES) do
		T.eq (#name > 0 and #name <= MAX_NAME_BYTES, true, name .. " fits a player's name")
		T.eq (not name:find ("[^ -~]"),              true, name .. " is printable ASCII")
		T.eq (name:sub (1, 1) ~= "#",                true, name .. " is not read as a localization token")
		T.eq (not name:find ("%%"),                  true, name .. " holds no format character")
		T.eq (name,                                  name:match ("^%s*(.-)%s*$"), name .. " has no space at its ends")
	end
end)

T.test ("a pick is drawn from the names not taken", function ()
	local taken = { [Names.BOT_NAMES [1]] = true }
	T.eq (Names.Pick (taken, First), Names.BOT_NAMES [2],                "the lowest draw: the first name free")
	T.eq (Names.Pick (taken, Last),  Names.BOT_NAMES [#Names.BOT_NAMES], "the highest draw: the last name free")
	T.eq (Names.Pick ({}, First),    Names.BOT_NAMES [1],                "nothing taken: every name is free")
end)

T.test ("a pick never gives a name a player has", function ()
	local taken = {}
	for _ = 1, #Names.BOT_NAMES do
		local name = Names.Pick (taken, Last)
		T.eq (not taken [name], true, name .. " was free")
		taken [name] = true
	end
end)

T.test ("with every name taken, there is none to pick", function ()
	local taken = {}
	for _, name in ipairs (Names.BOT_NAMES) do taken [name] = true end
	T.eq (Names.Pick (taken, First), nil, "nothing free")
end)

T.finish ()
