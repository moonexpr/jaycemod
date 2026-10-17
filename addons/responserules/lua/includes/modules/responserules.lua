-- TF2's response rules (the Source engine's AI_ResponseSystem, documented
-- in TF2's scripts/talker/response_rules.txt): a speaker asked to speak a
-- concept gathers its criteria set (key -> value: its team role, class,
-- health, a random number, the contexts rules gave it), every rule is scored
-- by the criteria it matches, and the best rule's response group says one
-- of its lines. Game-agnostic: the content comes from script files
-- (responserules_script parses them into the defs System takes; the
-- addon's autorun loads them), and what a line does (speak a sound, print)
-- is the caller's. GMod's require("responserules") loads it.
--
-- System(defs) builds the rules once, refusing a definition that names
-- something it lacks; a speaker is { memory, contexts } (Memory(),
-- Contexts()), and speakers that share a memory share their groups'
-- repeats, as TF2's players do. Speak(speaker, concept, criteria, random,
-- now) -> { rule, response = { kind, value }, delay, soundLevel } or nil;
-- random is math.random's shape (random() in [0, 1), random(n) in 1..n).
local error, format, ipairs, pairs, setmetatable = error, string.format, ipairs, pairs, setmetatable
local lower, match, sort, tonumber, tostring, type = string.lower, string.match, table.sort, tonumber, tostring, type
module("responserules")

-- CAI_Expresser's weight for the concept in a speaker's criteria set: a
-- rule that matches it outranks one that only matches other criteria.
CONCEPT_WEIGHT = 5
-- FindBestMatchingRule's floor: a rule must score above it.
local MIN_SCORE = 0.001
-- Groups naming groups, and criteria holding criteria, this deep at most.
local MAX_DEPTH = 8

-- The kinds of line a response group holds (response_rules.txt's
-- responsetype): a sound to speak, text to print (a placeholder), another
-- group by name. TF2's scene and sentence are not played here.
KINDS = { speak = true, print = true, response = true }

-- soundflags.h's soundlevel_t names (SNDLVL_<n>dB is n).
SOUND_LEVELS = {
	SNDLVL_NONE = 0, SNDLVL_IDLE = 60, SNDLVL_STATIC = 66, SNDLVL_NORM = 75,
	SNDLVL_TALKING = 80, SNDLVL_GUNFIRE = 140,
}
-- A line's default (response_rules.txt: soundlevel, "default SNDLVL_TALKING").
local DEFAULT_SOUND_LEVEL = SOUND_LEVELS.SNDLVL_TALKING

local function Refuse(text, ...) error("response: " .. format(text, ...), 3) end

-- A sound level by name, or nil.
function SoundLevel(name)
	return SOUND_LEVELS[name] or tonumber(match(name, "^SNDLVL_(%d+)dB$"))
end

-- Criteria ---------------------------------------------------------------------

local Criterion_ = {}
Criterion_.__index = Criterion_

-- ResolveToken: "[enumeration::member]" is the member's number.
local function Resolve(token, enumerations)
	if token:sub(1, 1) ~= "[" then return token end
	local value = enumerations[lower(token)]
	if value == nil then Refuse("no enumeration member %s", token) end
	return tostring(value)
end

-- ComputeMatcher: ">" and "<" bound a number, with "=" inclusive (in either
-- order: TF2 writes "=>98"), "!" negates, a comma joins two bounds; anything
-- else is a number or a word to equal.
local function Matcher(text, enumerations)
	local m = {}
	for part in (text .. ","):gmatch("([^,]*),") do
		local gt, lt, eq, nt = part:find(">", 1, true), part:find("<", 1, true), part:find("=", 1, true), part:find("!", 1, true)
		local token = Resolve((part:gsub("[<>=!]", "")), enumerations)
		if gt then
			m.min, m.minEquals = tonumber(token), eq ~= nil
		elseif lt then
			m.max, m.maxEquals = tonumber(token), eq ~= nil
		else
			m.notEqual, m.token, m.number = nt ~= nil, lower(token), tonumber(token)
		end
	end
	return m
end

-- A match of key against value (response_rules.txt's criterion: weight,
-- default 1; required: a rule fails when it does not match); value may
-- name an enumeration's member.
function Criterion(key, value, options, enumerations)
	if type(key) ~= "string" or key == "" then Refuse("a criterion needs a key") end
	if type(value) ~= "string" or value == "" then Refuse("criterion %s needs a value to match", key) end
	options = options or {}
	return setmetatable({
		key = lower(key),
		matcher = Matcher(value, enumerations or {}),
		weight = options.weight or 1,
		required = options.required == true,
	}, Criterion_)
end

-- CompareUsingMatcher, value being what the speaker's set holds (nil: it
-- lacks the key).
function Criterion_:Matches(value)
	local m = self.matcher
	local text = value == nil and "" or lower(tostring(value))
	local number = tonumber(text) or 0
	if m.min or m.max then
		if m.min and (m.minEquals and number < m.min or not m.minEquals and number <= m.min) then return false end
		if m.max and (m.maxEquals and number > m.max or not m.maxEquals and number >= m.max) then return false end
		return true
	end
	if m.notEqual then
		if m.number then return number ~= m.number end
		return text ~= m.token
	end
	if m.number then return text ~= "" and number == m.number end
	return text == m.token
end

-- Contexts -----------------------------------------------------------------------

-- A rule's ApplyContext, "key:value" or "key:value:seconds" it lasts.
function Context(text)
	local key, value, rest = match(text, "^([^:]+):([^:]+):?(.*)$")
	if not key then Refuse("context %q is not key:value[:seconds]", text) end
	local duration = nil
	if rest ~= "" then
		duration = tonumber(rest)
		if not duration then Refuse("context %q lasts %q, no number of seconds", text, rest) end
	end
	return { key = lower(key), value = value, duration = duration }
end

-- A rule's contexts, written as TF2 joins them: comma separated.
function ContextList(text)
	local list = {}
	for part in text:gmatch("[^,]+") do list[#list + 1] = Context(part) end
	return list
end

local Contexts_ = {}
Contexts_.__index = Contexts_

-- A speaker's contexts: key -> { value, expires (nil: lasts) }.
function Contexts()
	return setmetatable({ held = {} }, Contexts_)
end

function Contexts_:Apply(contexts, now)
	for _, c in ipairs(contexts) do
		self.held[c.key] = { value = c.value, expires = c.duration and now + c.duration or nil }
	end
end

-- key -> value of the contexts not yet expired at now.
function Contexts_:Active(now)
	local active = {}
	for key, c in pairs(self.held) do
		if c.expires == nil or now < c.expires then active[key] = c.value end
	end
	return active
end

-- Response groups ------------------------------------------------------------------

-- What a set of speakers remembers of the groups: the lines said since a
-- group last started over, a sequential group's next line, the groups gone
-- silent (norepeat, speakonce), when a group may speak again
-- (respeakdelay), and the rules spent (matchonce).
function Memory()
	return { used = {}, cursor = {}, silent = {}, respeakAt = {}, spent = {} }
end

local function Line(name, i, entry)
	local kind, value = entry[1], entry[2]
	if not KINDS[kind] then Refuse("group %s line %d is a %s, which is not played here", name, i, tostring(kind)) end
	if type(value) ~= "string" or value == "" then Refuse("group %s line %d has no value", name, i) end
	return { kind = kind, value = value, weight = entry.weight or 1 }
end

-- An interval { min, max } in seconds.
local function Interval(name, what, interval)
	if interval == nil then return nil end
	if type(interval[1]) ~= "number" or type(interval[2]) ~= "number" or interval[2] < interval[1] then
		Refuse("group %s has a %s that is no interval of seconds", name, what)
	end
	return interval
end

-- The group's AI_ResponseParams: delay after speaking, odds out of 100 that
-- it says anything, soundlevel, respeakdelay, speakonce.
local function Params(name, params)
	params = params or {}
	local level = DEFAULT_SOUND_LEVEL
	if params.soundlevel ~= nil then
		level = SoundLevel(params.soundlevel) or Refuse("group %s has a sound level %s that is not named", name, tostring(params.soundlevel))
	end
	return {
		delay = Interval(name, "delay", params.delay),
		odds = params.odds,
		soundLevel = level,
		respeakDelay = Interval(name, "respeakdelay", params.respeakdelay),
		speakOnce = params.speakonce == true,
	}
end

local function Group(name, def)
	local group = { name = name, lines = {}, permitRepeats = def.permitrepeats == true,
		sequential = def.sequential == true, noRepeat = def.norepeat == true, params = Params(name, def.params) }
	for i, entry in ipairs(def) do group.lines[i] = Line(name, i, entry) end
	if #group.lines == 0 then Refuse("group %s has no lines", name) end
	return group
end

local function Draw(interval, random)
	if not interval then return 0 end
	return interval[1] + random() * (interval[2] - interval[1])
end

-- SelectWeightedResponseFromResponseGroup: a line not said since the group
-- last started over (any line when it permits repeats), by weight, or the
-- next in order; once every line is said it starts over, or a norepeat
-- group falls silent.
local function Pick(group, memory, random)
	local used = memory.used[group.name] or {}
	memory.used[group.name] = used
	local lines = group.lines
	local fresh = 0
	for i = 1, #lines do if not used[i] then fresh = fresh + 1 end end
	if fresh == 0 then
		if group.noRepeat then
			memory.silent[group.name] = true
			return nil
		end
		used = {}
		memory.used[group.name] = used
	end
	local pick
	if group.sequential then
		local cursor = memory.cursor[group.name] or 1
		pick = cursor
		memory.cursor[group.name] = cursor % #lines + 1
	else
		local total = 0
		for i, line in ipairs(lines) do
			if group.permitRepeats or not used[i] then total = total + line.weight end
		end
		local at = random() * total
		for i, line in ipairs(lines) do
			if group.permitRepeats or not used[i] then
				pick = i
				at = at - line.weight
				if at < 0 then break end
			end
		end
	end
	used[pick] = true
	return lines[pick]
end

-- The group's line, if it may speak now (not silent, its respeakdelay past,
-- its odds met), its params applied to the memory.
local function Say(group, memory, random, now)
	if memory.silent[group.name] or now < (memory.respeakAt[group.name] or now) then return nil end
	local params = group.params
	if params.odds and random() * 100 >= params.odds then return nil end
	local line = Pick(group, memory, random)
	if not line then return nil end
	if params.speakOnce then memory.silent[group.name] = true end
	if params.respeakDelay then memory.respeakAt[group.name] = now + Draw(params.respeakDelay, random) end
	return line
end

-- Systems ---------------------------------------------------------------------------

local System_ = {}
System_.__index = System_

local function Criteria(defs)
	local enumerations = defs.enumerations or {}
	local criteria = {}
	for name, def in pairs(defs.criteria or {}) do
		if def.subcriteria then
			criteria[name] = { subcriteria = def.subcriteria, weight = def.weight or 1, required = def.required == true }
		else
			criteria[name] = Criterion(def[1], def[2], def, enumerations)
		end
	end
	-- a criterion of criteria holds them, but none comes back round to itself
	local function Link(name, depth)
		local c = criteria[name]
		if not c.subcriteria or c.held then return end
		if depth > MAX_DEPTH then Refuse("criterion %s holds criteria more than %d deep, or itself", name, MAX_DEPTH) end
		local held = {}
		for i, sub in ipairs(c.subcriteria) do
			held[i] = criteria[sub] or Refuse("criterion %s holds criterion %s, which is not defined", name, sub)
			Link(sub, depth + 1)
		end
		c.held = held
	end
	for name in pairs(criteria) do Link(name, 1) end
	return criteria
end

-- defs (as responserules_script's Load gives them) = {
-- enumerations = "[name::member]" -> number, criteria = name -> { key,
-- value, weight, required } or { subcriteria = { names }, weight, required },
-- responses = name -> group { [i] = { kind, value, weight }, permitrepeats,
-- sequential, norepeat, params = { delay, odds, soundlevel, respeakdelay,
-- speakonce } }, rules = name -> { criteria = { names }, responses = {
-- names }, applyContext = { "key:value[:seconds],..." }, matchonce } }.
function System(defs)
	local criteria, groups, rules = Criteria(defs), {}, {}
	for name, def in pairs(defs.responses or {}) do groups[name] = Group(name, def) end
	-- a group may name another, but no group may come back round to itself
	local function Check(name, depth, seen)
		if seen[name] then Refuse("group %s names itself, through the groups it names", name) end
		if depth > MAX_DEPTH then Refuse("group %s names groups more than %d deep", name, MAX_DEPTH) end
		seen[name] = true
		for _, line in ipairs(groups[name].lines) do
			if line.kind == "response" then
				if not groups[line.value] then Refuse("group %s names group %s, which is not defined", name, line.value) end
				Check(line.value, depth + 1, seen)
			end
		end
		seen[name] = nil
	end
	for name in pairs(groups) do Check(name, 1, {}) end
	for name, def in pairs(defs.rules or {}) do
		local rule = { name = name, criteria = {}, groups = {}, contexts = {}, matchOnce = def.matchonce == true }
		for i, c in ipairs(def.criteria or {}) do
			rule.criteria[i] = criteria[c] or Refuse("rule %s names criterion %s, which is not defined", name, c)
		end
		for i, g in ipairs(def.responses or {}) do
			rule.groups[i] = groups[g] or Refuse("rule %s names group %s, which is not defined", name, g)
		end
		if #rule.groups == 0 then Refuse("rule %s names no group", name) end
		for _, text in ipairs(def.applyContext or {}) do
			for _, c in ipairs(ContextList(text)) do rule.contexts[#rule.contexts + 1] = c end
		end
		rules[#rules + 1] = rule
	end
	-- by name, so a tie is broken the same way for the same random draw
	sort(rules, function(a, b) return a.name < b.name end)
	return setmetatable({ rules = rules, groups = groups }, System_)
end

-- How many rules, groups the system holds.
function System_:Counts()
	local groups = 0
	for _ in pairs(self.groups) do groups = groups + 1 end
	return #self.rules, groups
end

-- ScoreCriteriaAgainstRuleCriteria: a criterion's score (its weight times
-- the set's weight for its key) when it matches, else 0; and whether a
-- required one failed. A criterion of criteria scores theirs, times its
-- weight, and fails required when they score nothing.
local function ScoreOne(c, set, weights)
	if c.held then
		local score = 0
		for _, sub in ipairs(c.held) do score = score + (ScoreOne(sub, set, weights)) end
		return score * c.weight, c.required and score == 0
	end
	if c:Matches(set[c.key]) then return c.weight * (weights[c.key] or 1), false end
	return 0, c.required
end

-- ScoreCriteriaAgainstRule: the criteria's scores, or nil when a required
-- one fails.
local function Score(rule, set, weights)
	local score = 0
	for _, c in ipairs(rule.criteria) do
		local s, failed = ScoreOne(c, set, weights)
		if failed then return nil end
		score = score + s
	end
	return score
end

-- The speaker's set: its criteria (keys in any case), its contexts, and
-- the concept.
local function CriteriaSet(concept, criteria, contexts)
	local set = {}
	for key, value in pairs(criteria) do set[lower(key)] = value end
	for key, value in pairs(contexts) do set[key] = value end
	set.concept = concept
	return set
end

-- FindBestMatchingRule over the speaker's set; a tie is broken at random.
function System_:Best(set, memory, random)
	local weights = { concept = CONCEPT_WEIGHT }
	local best, bestScore = {}, MIN_SCORE
	for _, rule in ipairs(self.rules) do
		local score = not memory.spent[rule.name] and Score(rule, set, weights) or nil
		if score and score >= bestScore then
			if score > bestScore then best, bestScore = {}, score end
			best[#best + 1] = rule
		end
	end
	if #best == 0 then return nil end
	return best[#best == 1 and 1 or random(#best)]
end

-- The speaker speaks concept: the best rule's line (from one of its groups
-- at random; a group naming another says one of that one's), its contexts
-- applied to the speaker; nil when no rule matches or its group says
-- nothing. delay: the seconds it waits after the line (its group's, drawn
-- from the interval); soundLevel: how loud.
function System_:Speak(speaker, concept, criteria, random, now)
	local set = CriteriaSet(concept, criteria, speaker.contexts:Active(now))
	local memory = speaker.memory
	local rule = self:Best(set, memory, random)
	if not rule then return nil end
	if rule.matchOnce then memory.spent[rule.name] = true end
	speaker.contexts:Apply(rule.contexts, now)
	local group = rule.groups[#rule.groups == 1 and 1 or random(#rule.groups)]
	local line = Say(group, memory, random, now)
	while line and line.kind == "response" do
		group = self.groups[line.value]
		line = Say(group, memory, random, now)
	end
	if not line then return nil end
	return {
		rule = rule.name,
		response = { kind = line.kind, value = line.value },
		delay = Draw(group.params.delay, random),
		soundLevel = group.params.soundLevel,
	}
end
