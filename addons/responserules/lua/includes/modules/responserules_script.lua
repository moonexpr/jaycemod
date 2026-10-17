-- TF2's talker script files (scripts/talker/*.txt; the grammar
-- AI_ResponseSystem.cpp parses, documented in response_rules.txt) into the
-- definitions responserules builds a system from: #include,
-- enumeration, criterion (or criteria), response, rule. Keywords are in
-- any case; a word is quoted or bare; // comments to the end of the line;
-- and as in Source, a criterion's options, a response line's options, and
-- a rule's lists of criteria and groups end with their line (TokenWaiting).
--
-- Stricter than Source, which warns and goes on: whatever this engine
-- cannot play (a scene, predelay, world contexts), an unknown option, a
-- second definition of a name, or a file that cannot be read is refused,
-- naming the file and line. A file included twice is read once.
--
-- Load(path, read) -> defs; read(path) -> the file's text, or nil. Paths
-- are as #include writes them: relative to the scripts folder.
local error, format, lower, setmetatable, tonumber = error, string.format, string.lower, setmetatable, tonumber
-- GMod's require returns nothing: the module is the global module() made
require("responserules")
local Response = responserules
module("responserules_script")

-- defaultdelay: AIS_DEF_MIN_DELAY, AIS_DEF_MAX_DELAY.
DEFAULT_DELAY = { 2.8, 3.2 }

local ROOT = { ["#include"] = true, response = true, enumeration = true, criteria = true, criterion = true, rule = true }
-- response kinds and options known to Source that this engine does not play
local UNPLAYED_KINDS = { scene = true, sentence = true }
local UNPLAYED_OPTIONS = { predelay = true, weapondelay = true, stop_on_nonidle = true, displayfirst = true, displaylast = true }

-- Tokens --------------------------------------------------------------------------

-- The words of text: { text, line }, braces each a word of their own.
local function Tokens(text)
	local tokens, i, line, n = {}, 1, 1, #text
	while i <= n do
		local c = text:sub(i, i)
		if c == "\n" then
			line, i = line + 1, i + 1
		elseif c:match("%s") then
			i = i + 1
		elseif text:sub(i, i + 1) == "//" then
			local stop = text:find("\n", i, true) or n + 1
			i = stop
		elseif c == '"' then
			local stop = text:find('"', i + 1, true) or n + 1
			local word = text:sub(i + 1, stop - 1)
			tokens[#tokens + 1] = { text = word, line = line }
			for _ in word:gmatch("\n") do line = line + 1 end
			i = stop + 1
		elseif c == "{" or c == "}" then
			tokens[#tokens + 1] = { text = c, line = line }
			i = i + 1
		else
			local stop = i
			while stop <= n and not text:sub(stop, stop):match('[%s{}"]') and text:sub(stop, stop + 1) ~= "//" do stop = stop + 1 end
			tokens[#tokens + 1] = { text = text:sub(i, stop - 1), line = line }
			i = stop
		end
	end
	return tokens
end

-- A file's parse ---------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

function Parser:Fail(token, text, ...)
	local line = token and token.line or (self.tokens[#self.tokens] or { line = 1 }).line
	error(format("%s:%d: %s", self.path, line, format(text, ...)), 0)
end

-- The next word; at the end of the file, a refusal saying what was due.
function Parser:Next(due)
	local token = self.tokens[self.i]
	if not token and due then self:Fail(nil, "the file ends where %s is due", due) end
	self.i = self.i + 1
	return token
end

function Parser:Unget() self.i = self.i - 1 end

-- TokenWaiting: another word on the line of the last one read.
function Parser:Waiting()
	local last, next = self.tokens[self.i - 1], self.tokens[self.i]
	return last ~= nil and next ~= nil and next.line == last.line
end

local function IsRoot(token) return ROOT[lower(token.text)] == true end

function Parser:Number(due)
	local token = self:Next(due)
	return tonumber(token.text) or self:Fail(token, "%s is %q, no number", due, token.text)
end

-- An interval in seconds: "a,b" or "a".
function Parser:Interval(due)
	local token = self:Next(due)
	local a, b = token.text:match("^([^,]+),([^,]+)$")
	a, b = tonumber(a or token.text), tonumber(b or token.text)
	if not (a and b) or b < a then self:Fail(token, "%s is %q, no interval of seconds", due, token.text) end
	return { a, b }
end

function Parser:Define(kind, name, token, def)
	local into = self.defs[kind]
	if into[name] ~= nil then self:Fail(token, "%s %s is defined a second time", kind, name) end
	into[name] = def
end

-- ParseOneCriterion: a key and value, or { criteria }, then its options.
function Parser:Criterion(name, token)
	local c, body = {}, false
	while self:Waiting() or not body do
		local t = self:Next("criterion " .. name .. "'s body")
		if IsRoot(t) then
			self:Unget()
			break
		end
		local word = lower(t.text)
		if t.text == "{" then
			body, c.subcriteria = true, {}
			while true do
				local s = self:Next("criterion " .. name .. "'s }")
				if s.text == "}" then break end
				c.subcriteria[#c.subcriteria + 1] = s.text
			end
		elseif word == "required" then
			c.required = true
		elseif word == "weight" then
			c.weight = self:Number("criterion " .. name .. "'s weight")
		else
			c[1], c[2], body = t.text, self:Next("criterion " .. name .. "'s value").text, true
		end
	end
	if not body then self:Fail(token, "criterion %s has nothing to match", name) end
	self:Define("criteria", name, token, c)
end

-- An AI_ResponseParams option on a group's line: true when t was one.
function Parser:Option(t, params)
	local word = lower(t.text)
	if word == "nodelay" then
		params.delay = { 0, 0 }
	elseif word == "defaultdelay" then
		params.delay = { DEFAULT_DELAY[1], DEFAULT_DELAY[2] }
	elseif word == "delay" then
		params.delay = self:Interval("delay")
	elseif word == "respeakdelay" then
		params.respeakdelay = self:Interval("respeakdelay")
	elseif word == "odds" then
		local odds = self:Number("odds")
		params.odds = odds < 0 and 0 or odds > 100 and 100 or odds
	elseif word == "soundlevel" then
		local level = self:Next("soundlevel")
		if not Response.SoundLevel(level.text) then self:Fail(level, "sound level %q is not named", level.text) end
		params.soundlevel = level.text
	elseif word == "speakonce" then
		params.speakonce = true
	elseif word == "noscene" then
		-- no line here is a scene
	elseif UNPLAYED_OPTIONS[word] then
		self:Fail(t, "option %s is not played here", t.text)
	else
		return false
	end
	return true
end

-- ParseOneResponse: a kind and value, then its options to the end of the line.
function Parser:Line(t, group, name)
	local kind = lower(t.text)
	if UNPLAYED_KINDS[kind] then self:Fail(t, "group %s has a %s, which is not played here", name, t.text) end
	if not Response.KINDS[kind] then self:Fail(t, "group %s has %q where a response type is due", name, t.text) end
	local line = { kind, self:Next("the " .. kind .. "'s value").text }
	while self:Waiting() do
		local o = self:Next()
		-- a group closed on the line's own line: { speak "a.wav" }
		if o.text == "}" then
			self:Unget()
			break
		end
		if lower(o.text) == "weight" then
			line.weight = self:Number("weight")
		elseif not self:Option(o, group.params) then
			self:Fail(o, "%q is no option of a response line", o.text)
		end
	end
	group[#group + 1] = line
end

-- ParseResponse: { flags and lines }, or options and lines up to the next
-- definition.
function Parser:Response(name, token)
	local group = { params = {} }
	while true do
		local t = self:Next()
		if not t then break end
		if IsRoot(t) then
			self:Unget()
			break
		end
		if t.text == "{" then
			while true do
				local u = self:Next("group " .. name .. "'s }")
				if u.text == "}" then break end
				local word = lower(u.text)
				if word == "permitrepeats" or word == "sequential" or word == "norepeat" then
					group[word] = true
				else
					self:Line(u, group, name)
				end
			end
			break
		end
		if not self:Option(t, group.params) then self:Line(t, group, name) end
	end
	if #group == 0 then self:Fail(token, "group %s has no lines", name) end
	self:Define("responses", name, token, group)
end

-- The names to the end of the line, or to a } on it, into list.
function Parser:Names(list)
	while self:Waiting() do
		local t = self:Next()
		if t.text == "}" then
			self:Unget()
			return
		end
		list[#list + 1] = t.text
	end
end

-- ParseRule: { criteria, response, applyContext, matchonce, inline criteria }.
function Parser:Rule(name, token)
	local open = self:Next("rule " .. name .. "'s {")
	if open.text ~= "{" then self:Fail(open, "rule %s has %q where { is due", name, open.text) end
	local rule = { criteria = {}, responses = {}, applyContext = {} }
	while true do
		local t = self:Next("rule " .. name .. "'s }")
		if t.text == "}" then break end
		local word = lower(t.text)
		if word == "matchonce" then
			rule.matchonce = true
		elseif word == "applycontexttoworld" then
			self:Fail(t, "rule %s applies its context to the world, which is not played here", name)
		elseif word == "applycontext" then
			rule.applyContext[#rule.applyContext + 1] = self:Next("applyContext's context").text
		elseif word == "response" then
			self:Names(rule.responses)
		elseif word == "criteria" or word == "criterion" then
			self:Names(rule.criteria)
		else
			-- an inline criterion, named as Source names it
			self.load.inline = self.load.inline + 1
			local inline = format("[%s%03d]", name, self.load.inline)
			self:Unget()
			self:Criterion(inline, t)
			rule.criteria[#rule.criteria + 1] = inline
		end
	end
	self:Define("rules", name, token, rule)
end

-- ParseEnumeration: { member value ... }, as "[name::member]" in lower case.
function Parser:Enumeration(name)
	local open = self:Next("enumeration " .. name .. "'s {")
	if open.text ~= "{" then self:Fail(open, "enumeration %s has %q where { is due", name, open.text) end
	while true do
		local key = self:Next("enumeration " .. name .. "'s }")
		if key.text == "}" then break end
		local value = self:Number("member " .. key.text .. "'s value")
		local member = lower(format("[%s::%s]", name, key.text))
		if self.defs.enumerations[member] == nil then self.defs.enumerations[member] = value end
	end
end

function Parser:File()
	while true do
		local t = self:Next()
		if not t then return end
		local word = lower(t.text)
		if word == "#include" then
			self.load:File(self:Next("the file to include").text, t, self)
		elseif word == "response" then
			self:Response(self:Next("the group's name").text, t)
		elseif word == "criterion" or word == "criteria" then
			self:Criterion(self:Next("the criterion's name").text, t)
		elseif word == "rule" then
			self:Rule(self:Next("the rule's name").text, t)
		elseif word == "enumeration" then
			self:Enumeration(self:Next("the enumeration's name").text)
		else
			self:Fail(t, "%q is no command (#include, criterion, response, rule, enumeration)", t.text)
		end
	end
end

-- Loading ----------------------------------------------------------------------------

local Loader = {}
Loader.__index = Loader

function Loader:File(path, token, from)
	if self.reading[path] then from:Fail(token, "%s includes itself, through the files it includes", path) end
	if self.loaded[path] then return end
	local text = self.read(path)
	if text == nil then
		if from then from:Fail(token, "%s cannot be read", path) end
		error(format("%s cannot be read", path), 0)
	end
	self.reading[path] = true
	local parser = { tokens = Tokens(text), i = 1, path = path, defs = self.defs, load = self }
	Parser.File(setmetatable(parser, Parser))
	self.reading[path], self.loaded[path] = nil, true
end

function Load(path, read)
	local loader = setmetatable({
		read = read,
		reading = {},
		loaded = {},
		inline = 0,
		defs = { criteria = {}, responses = {}, rules = {}, enumerations = {} },
	}, Loader)
	loader:File(path)
	return loader.defs
end
