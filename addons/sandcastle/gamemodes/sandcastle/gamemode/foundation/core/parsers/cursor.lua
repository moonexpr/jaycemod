-- A cursor: a position in text that a hand-written parser moves along,
-- taking what stands there or leaving the position as it was.
--   New(text)
--   c:Literal(s[, ignoreCase]) -> s as written, or nil
--   c:Pattern(p) -> its captures (the whole match when it has none), or nil,
--     matched where the cursor stands
--   c:Peek(p) -> the same, without moving
--   c:Whitespace() -> the blank space skipped, or nil
--   c:Save(), c:Restore() (back to the saved position), c:Commit() (keep it)
--   c:Position(), c:AtEnd(), c:Rest()
local find, lower, select, setmetatable, sub, unpack = string.find, string.lower, select, setmetatable, string.sub, unpack
module(...)

local BLANK = "^[ \t\r\n]+"

local Cursor = {}
Cursor.__index = Cursor

function New(text)
	return setmetatable({
		text = text,
		at = 1,
		saved = {},
	}, Cursor)
end

function Cursor:Literal(s, ignoreCase)
	local here = sub(self.text, self.at, self.at + #s - 1)
	if here == s or (ignoreCase and lower(here) == lower(s)) then
		self.at = self.at + #s
		return here
	end
	return nil
end

-- The match at the cursor: its end, then the captures or the whole match.
local function Match(self, p)
	local result = { find(self.text, "^" .. p, self.at) }
	local first, last = result[1], result[2]
	if not first then return nil end
	if #result == 2 then return last, sub(self.text, first, last) end
	return last, select(3, unpack(result))
end

function Cursor:Pattern(p)
	local captures = { Match(self, p) }
	if not captures[1] then return nil end
	self.at = captures[1] + 1
	return select(2, unpack(captures))
end

function Cursor:Peek(p)
	local captures = { Match(self, p) }
	if not captures[1] then return nil end
	return select(2, unpack(captures))
end

function Cursor:Whitespace()
	local first, last = find(self.text, BLANK, self.at)
	if not first then return nil end
	self.at = last + 1
	return sub(self.text, first, last)
end

function Cursor:Save()
	self.saved[#self.saved + 1] = self.at
end

function Cursor:Restore()
	self.at = self.saved[#self.saved]
	self.saved[#self.saved] = nil
end

function Cursor:Commit()
	self.saved[#self.saved] = nil
end

function Cursor:Position() return self.at end
function Cursor:AtEnd() return self.at > #self.text end
function Cursor:Rest() return sub(self.text, self.at) end
