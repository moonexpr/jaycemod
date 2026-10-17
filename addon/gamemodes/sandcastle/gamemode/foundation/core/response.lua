-- TF2's response rules (the Source engine's AI_ResponseSystem, documented
-- in TF2's scripts/talker/response_rules.txt): a speaker asked to speak a
-- concept gathers its criteria set (key -> value: its team role, class,
-- health, a random number, the contexts rules gave it), every rule is scored
-- by the criteria it matches, and the best rule's response group says one
-- of its lines. Game-agnostic: the content (criteria, responses, rules) and
-- what a line does (speak a sound, print) belong to the caller.
--
-- System(defs) builds the rules once, refusing a definition that names
-- something it lacks; a speaker is { memory, contexts } (Memory(),
-- Contexts()), and speakers that share a memory share their groups'
-- repeats, as TF2's players do. Speak(speaker, concept, criteria, random,
-- now) -> { rule, response = { kind, value } } or nil.
local error, format, ipairs, pairs, setmetatable = error, string.format, ipairs, pairs, setmetatable
local lower, match, sort, tonumber, tostring, type = string.lower, string.match, table.sort, tonumber, tostring, type
module(...)

-- CAI_Expresser's weight for the concept in a speaker's criteria set: a
-- rule that matches it outranks one that only matches other criteria.
CONCEPT_WEIGHT = 5
-- FindBestMatchingRule's floor: a rule must score above it.
local MIN_SCORE = 0.001
-- Response groups that name groups that name groups... this deep at most.
local MAX_DEPTH = 8

-- The kinds of line a response group holds (response_rules.txt's
-- responsetype): a sound to speak, text to print (a placeholder), another
-- group by name. TF2's scene and sentence are not played here.
KINDS = { speak = true, print = true, response = true }

local function Refuse(text, ...) error("response: " .. format(text, ...), 3) end

-- Criteria ---------------------------------------------------------------------

local Criterion_ = {}
Criterion_.__index = Criterion_

-- ComputeMatcher: ">" and "<" bound a number, with "=" inclusive (in either
-- order: TF2 writes "=>98"), "!" negates, a comma joins two bounds; anything
-- else is a number or a word to equal.
local function Matcher(text)
	local m = {}
	for part in (text .. ","):gmatch("([^,]*),") do
		local gt, lt, eq, nt = part:find(">", 1, true), part:find("<", 1, true), part:find("=", 1, true), part:find("!", 1, true)
		local token = part:gsub("[<>=!]", "")
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
-- default 1; required: a rule fails when it does not match).
function Criterion(key, value, options)
	if type(key) ~= "string" or key == "" then Refuse("a criterion needs a key") end
	if type(value) ~= "string" or value == "" then Refuse("criterion %s needs a value to match", key) end
	options = options or {}
	return setmetatable({
		key = lower(key),
		matcher = Matcher(value),
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
-- silent (norepeat) and the rules spent (matchonce).
function Memory()
	return { used = {}, cursor = {}, silent = {}, spent = {} }
end

local function Line(name, i, entry)
	local kind, value = entry[1], entry[2]
	if not KINDS[kind] then Refuse("group %s line %d is a %s, which is not played here", name, i, tostring(kind)) end
	if type(value) ~= "string" or value == "" then Refuse("group %s line %d has no value", name, i) end
	return { kind = kind, value = value, weight = entry.weight or 1 }
end

local function Group(name, def)
	local group = { name = name, lines = {}, permitRepeats = def.permitrepeats == true,
		sequential = def.sequential == true, noRepeat = def.norepeat == true }
	for i, entry in ipairs(def) do group.lines[i] = Line(name, i, entry) end
	if #group.lines == 0 then Refuse("group %s has no lines", name) end
	return group
end

-- SelectWeightedResponseFromResponseGroup: a line not said since the group
-- last started over (any line when it permits repeats), by weight, or the
-- next in order; once every line is said it starts over, or a norepeat
-- group falls silent.
local function Pick(group, memory, random)
	if memory.silent[group.name] then return nil end
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

-- Systems ---------------------------------------------------------------------------

local System_ = {}
System_.__index = System_

-- defs = { criteria = name -> { key, value, weight, required },
-- responses = name -> group { [i] = { kind, value, weight }, permitrepeats,
-- sequential, norepeat }, rules = name -> { criteria = { names }, response
-- = name, applyContext = { "key:value[:seconds]" }, matchonce } }.
function System(defs)
	local criteria, groups, rules = {}, {}, {}
	for name, def in pairs(defs.criteria or {}) do
		criteria[name] = Criterion(def[1], def[2], def)
	end
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
		local rule = { name = name, criteria = {}, contexts = {}, matchOnce = def.matchonce == true }
		for i, c in ipairs(def.criteria or {}) do
			rule.criteria[i] = criteria[c] or Refuse("rule %s names criterion %s, which is not defined", name, c)
		end
		rule.group = groups[def.response] or Refuse("rule %s names group %s, which is not defined", name, tostring(def.response))
		for i, text in ipairs(def.applyContext or {}) do rule.contexts[i] = Context(text) end
		rules[#rules + 1] = rule
	end
	-- by name, so a tie is broken the same way for the same random draw
	sort(rules, function(a, b) return a.name < b.name end)
	return setmetatable({ rules = rules, groups = groups }, System_)
end

-- ScoreCriteriaAgainstRule: the weights of the criteria matched (times the
-- set's weight for that key), or nil when a required one fails.
local function Score(rule, set, weights)
	local score = 0
	for _, c in ipairs(rule.criteria) do
		if c:Matches(set[c.key]) then
			score = score + c.weight * (weights[c.key] or 1)
		elseif c.required then
			return nil
		end
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

-- The speaker speaks concept: the best rule's line (a group naming another
-- says one of that one's), its contexts applied to the speaker; nil when no
-- rule matches or its group is silent.
function System_:Speak(speaker, concept, criteria, random, now)
	local set = CriteriaSet(concept, criteria, speaker.contexts:Active(now))
	local rule = self:Best(set, speaker.memory, random)
	if not rule then return nil end
	if rule.matchOnce then speaker.memory.spent[rule.name] = true end
	speaker.contexts:Apply(rule.contexts, now)
	local line = Pick(rule.group, speaker.memory, random)
	while line and line.kind == "response" do line = Pick(self.groups[line.value], speaker.memory, random) end
	if not line then return nil end
	return { rule = rule.name, response = { kind = line.kind, value = line.value } }
end
