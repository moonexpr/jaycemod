-- Draw callbacks named by dotted paths (game.match.team_scores.blue_score),
-- run in a fixed order (by order, a tie by path), each skipped while its
-- path or an ancestor's is hidden, or while its own condition fails.
-- Hiding has two sources kept apart: the code's (HideElements and
-- ShowElements: a win screen hiding the scores it replaces) and the
-- player's (SetHidden: a setting); either one hides. Adding a path again
-- replaces it, as hook.Add does, so a refreshed file re-adds its own. A
-- hidden path may name callbacks not added yet, or never: it hides them
-- once they are.
local find, gmatch, ipairs, pairs, setmetatable, sort, sub =
	string.find, string.gmatch, ipairs, pairs, setmetatable, table.sort, string.sub
module(...)

local List = {}
List.__index = List

function New()
	return setmetatable({ byName = {}, sorted = {}, hidden = {}, codeHidden = {} }, List)
end

-- A path and each of its ancestors: a.b.c -> a, a.b, a.b.c.
local function Lineage(path)
	local lineage, from = {}, 1
	while true do
		local dot = find(path, ".", from, true)
		if not dot then break end
		lineage[#lineage + 1] = sub(path, 1, dot - 1)
		from = dot + 1
	end
	lineage[#lineage + 1] = path
	return lineage
end

local function Before(a, b)
	if a.order ~= b.order then return a.order < b.order end
	return a.name < b.name
end

local function Resort(self)
	local sorted = {}
	for _, entry in pairs(self.byName) do sorted[#sorted + 1] = entry end
	sort(sorted, Before)
	self.sorted = sorted
end

-- draw(...) gets what Draw is given; when() -> whether to draw now (nil:
-- always).
function List:Add(path, order, draw, when)
	self.byName[path] = { name = path, lineage = Lineage(path), order = order, draw = draw, when = when }
	Resort(self)
end

-- The player's hides: path -> true.
function List:SetHidden(hidden)
	self.hidden = hidden
end

-- The code's hides: path and everything under it.
function List:HideElements(path)
	self.codeHidden[path] = true
end

function List:ShowElements(path)
	self.codeHidden[path] = nil
end

local function Hidden(self, entry)
	for _, path in ipairs(entry.lineage) do
		if self.hidden[path] or self.codeHidden[path] then return true end
	end
	return false
end

function List:Draw(...)
	for _, entry in ipairs(self.sorted) do
		if not Hidden(self, entry) and (entry.when == nil or entry.when()) then entry.draw(...) end
	end
end

-- Every callback in drawing order: { name, order, hidden }.
function List:Entries()
	local entries = {}
	for i, entry in ipairs(self.sorted) do
		entries[i] = { name = entry.name, order = entry.order, hidden = Hidden(self, entry) }
	end
	return entries
end

-- Paths as typed (a convar's text): spaces or commas between them, as a
-- set for SetHidden.
function ParseNames(text)
	local set = {}
	for name in gmatch(text, "[^%s,]+") do set[name] = true end
	return set
end
