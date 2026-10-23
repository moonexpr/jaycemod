-- The gamerules harness. With dev_gamerules_harness 1, a dev_tf_gamerules
-- takes the map's gamerules' targetname, and the real gamerules (bound to
-- the rounds, WS.Rules) are renamed <name>__real. Every input the map sends
-- the name reaches the harness, which traces it and forwards it to the real
-- gamerules, drops it, or queues it (sandcastle_dev_harness). The round's
-- effects, outputs among them, are traced as the rounds controller applies
-- them. With it on, gameplay can also be frozen (the engine's time scale at
-- 0: timers, physics, NPCs and every think stop, and the luadev socket still
-- answers), stepped, and its round state, timers and wins set by hand.
--
-- With it 0 nothing of this exists: the gamerules keep their name, no
-- method is wrapped and no entity is made (dev.harness.check_off proves it).
-- A round's map cleanup removes the harness (it keeps only the gamerules'
-- classes), so it takes the name again at PostCleanupMap.
local Harness = dev.require("sandcastle_dev_harness")

local CLASS = "dev_tf_gamerules"
local REAL_SUFFIX = "__real"
local CONVAR = "dev_gamerules_harness"
local TRACE_CAPACITY = 2000
local STEP_HOOK = "sandcastle_dev_step"
local FROZEN_SCALE, RUNNING_SCALE = 0, 1
-- The rounds controller's methods the harness wraps while on.
local WRAPPED = { "Apply", "SetWinningTeam", "SetStalemate", "GameRoundWin" }
local WINS = {
	SetWinningTeam = true,
	SetStalemate = true,
	GameRoundWin = true,
}

dev.harness = dev.harness or {}
local H = dev.harness
-- Kept across a reload of the workbench: what the harness holds now.
H.live = H.live or {
	model = Harness.New(TRACE_CAPACITY),
	on = false,
	name = nil, -- the map's gamerules' targetname
	real = NULL,
	ent = NULL,
	originals = {}, -- the rounds controller's own methods, while wrapped
	suppressWins = false,
	frozen = false,
	stepping = 0,
}
local live = H.live

local convar = CreateConVar(CONVAR, "0", FCVAR_NONE,
	"1: a dev_tf_gamerules takes the gamerules' targetname, traces map I/O and allows freezing (dev workbench)", 0, 1)

local function Require()
	if not live.on then dev.Fail(CONVAR .. " is 0: turn the harness on with dev.harness.enable(true)") end
end

local function Note(kind, fields)
	return live.model:Record(kind, fields or {}, CurTime())
end

-- The input or effect fields a trace keeps: plain values only.
local function Plain(t)
	local copy = {}
	for k, v in pairs(t) do
		local kind = type(v)
		if kind == "string" or kind == "number" or kind == "boolean" then copy[k] = v end
	end
	return copy
end

local function Forward(input)
	if not IsValid(live.real) then
		Note("error", { message = "no real gamerules to forward " .. input.name .. " to" })
		return false
	end
	return live.real:Input(input.name, input.activator, input.callerEnt, input.value)
end

scripted_ents.Register({
	Type = "point",
	Base = "base_point",
	UpdateTransmitState = function() return TRANSMIT_NEVER end,
	AcceptInput = function(_, name, activator, caller, value)
		local input = {
			name = name,
			value = value or "",
			caller = dev.Describe(caller),
			activator = activator,
			callerEnt = caller,
		}
		if live.model:Input(input, CurTime()) == Harness.FORWARD then Forward(input) end
		return true
	end,
}, CLASS)

-- Wrapping -------------------------------------------------------------------------

local function Wrapper(method, original)
	if method == "Apply" then
		return function(self, effects)
			for _, e in ipairs(effects or {}) do
				local fields = Plain(e)
				fields.kind = nil
				fields.effect = e.kind
				Note(e.kind == "output" and "output" or "effect", fields)
			end
			return original(self, effects)
		end
	end
	return function(self, ...)
		if live.suppressWins then
			Note("win_suppressed", { method = method })
			return
		end
		Note("win", {
			method = method,
			team = select(1, ...) ~= nil and tostring(select(1, ...)) or nil,
		})
		return original(self, ...)
	end
end

local function Wrap()
	local rounds = dev.Rounds()
	for _, method in ipairs(WRAPPED) do
		local original = rawget(rounds, method)
		if not original then dev.Fail("the rounds controller has no " .. method .. " to wrap") end
		live.originals[method] = original
		rounds[method] = Wrapper(method, original)
	end
end

local function Unwrap()
	local rounds = WS and WS.Feature("rounds")
	for method, original in pairs(live.originals) do
		if rounds then rounds[method] = original end
	end
	live.originals = {}
end

-- The rounds controller's own method, wrapped or not.
local function Original(method)
	return live.originals[method] or dev.Rounds()[method]
end

-- Taking the name ------------------------------------------------------------------

local function Reindex(ent)
	if WS.MapIO then WS.MapIO:Reindex(ent) end
end

-- The real gamerules renamed, and a harness under their name. Again after
-- a cleanup, which removed the harness and kept the real ones.
local function Take()
	local real = dev.Rounds():Proxy()
	if not IsValid(real) then dev.Fail("no gamerules are bound to the rounds (WS.Rules); the map has not set up yet") end
	local name = real:GetName()
	if string.EndsWith(name, REAL_SUFFIX) then
		name = string.sub(name, 1, #name - #REAL_SUFFIX)
	elseif name == "" then
		dev.Fail("the gamerules have no targetname, so no map input can reach them")
	end
	live.name, live.real = name, real
	if real:GetName() ~= name .. REAL_SUFFIX then
		real:SetName(name .. REAL_SUFFIX)
		Reindex(real)
	end
	if not IsValid(live.ent) then
		local ent = ents.Create(CLASS)
		ent:SetName(name)
		ent:Spawn()
		live.ent = ent
		Reindex(ent)
	end
end

-- The harness loses its name before it goes: Remove takes effect at the
-- frame's end, and until then it would still answer to it.
local function Give()
	if IsValid(live.ent) then
		live.ent:SetName("")
		Reindex(live.ent)
		live.ent:Remove()
	end
	live.ent = NULL
	if IsValid(live.real) and live.name then
		live.real:SetName(live.name)
		Reindex(live.real)
	end
end

local function Freeze(on)
	hook.Remove("Tick", STEP_HOOK)
	live.stepping = 0
	live.frozen = on
	game.SetTimeScale(on and FROZEN_SCALE or RUNNING_SCALE)
end

-- The surface ----------------------------------------------------------------------

-- A compact summary, for an agent's context.
function H.status()
	local state = {
		on = live.on,
		mode = live.model:Mode(),
		rules = live.model:Rules(),
		queued = live.model:QueuedCount(),
		frozen = live.frozen,
		stepping = live.stepping,
		time_scale = game.GetTimeScale(),
		suppress_wins = live.suppressWins,
		trace_seq = live.model:LastSeq(),
	}
	if live.on then
		state.name = live.name
		state.real = dev.Describe(live.real)
		state.harness = dev.Describe(live.ent)
	end
	return state
end

function H.enable(on)
	on = on == true or on == 1 or on == "1"
	if on == live.on then return H.status() end
	if on then
		Take()
		Wrap()
		live.on = true
		Note("harness", { on = true, name = live.name })
	else
		local dropped = live.model:QueuedCount()
		live.model:TakeQueued()
		if live.frozen or live.stepping > 0 then Freeze(false) end
		Unwrap()
		Give()
		live.on, live.suppressWins = false, false
		Note("harness", {
			on = false,
			dropped_queued = dropped,
		})
	end
	if convar:GetBool() ~= on then RunConsoleCommand(CONVAR, on and "1" or "0") end
	return H.status()
end

cvars.AddChangeCallback(CONVAR, function(_, _, value)
	local ok, err = pcall(H.enable, value == "1")
	if not ok then ErrorNoHalt(tostring(err) .. "\n") end
end, "sandcastle_dev_harness")

hook.Add("PostCleanupMap", "sandcastle_dev_harness", function()
	if not live.on then return end
	live.ent = NULL
	local ok, err = pcall(Take)
	Note(ok and "harness" or "error", ok and { retaken = live.name } or { message = tostring(err) })
end)

-- mode: forward | intercept | queue; rules: { [input] = action | false }.
function H.mode(mode, rules)
	Require()
	if mode then live.model:SetMode(mode) end
	for input, action in pairs(rules or {}) do live.model:SetRule(input, action or nil) end
	return H.status()
end

-- The queued inputs forwarded now, in order.
function H.release()
	Require()
	local released = {}
	for _, input in ipairs(live.model:TakeQueued()) do
		Forward(input)
		released[#released + 1] = input.name .. "(" .. input.value .. ")"
		Note("released", {
			name = input.name,
			value = input.value,
		})
	end
	return { released = released }
end

-- The trace since seq (0: all it holds); kinds limits it, limit keeps the newest.
function H.trace(opts)
	opts = opts or {}
	local entries = live.model:Since(opts.since or 0)
	if opts.kinds then entries = Harness.Of(entries, opts.kinds) end
	local limit = opts.limit or 50
	local first = math.max(1, #entries - limit + 1)
	local list = {}
	for i = first, #entries do list[#list + 1] = entries[i] end
	return {
		entries = list,
		omitted = first - 1,
		dropped = live.model:Dropped(),
		last_seq = live.model:LastSeq(),
	}
end

function H.pause()
	Require()
	Freeze(true)
	Note("freeze", { on = true })
	return H.status()
end

function H.resume()
	Require()
	Freeze(false)
	Note("freeze", { on = false })
	return H.status()
end

-- n ticks run, then frozen again; returns at once (status().stepping counts down).
function H.step(n)
	Require()
	n = tonumber(n) or 1
	if n < 1 then dev.Fail("step takes a number of ticks of at least 1") end
	if not live.frozen then dev.Fail("step needs the game frozen first: dev.harness.pause()") end
	live.stepping = n
	game.SetTimeScale(RUNNING_SCALE)
	hook.Add("Tick", STEP_HOOK, function()
		live.stepping = live.stepping - 1
		if live.stepping > 0 then return end
		hook.Remove("Tick", STEP_HOOK)
		game.SetTimeScale(FROZEN_SCALE)
		Note("stepped", { ticks = n })
	end)
	Note("step", { ticks = n })
	return H.status()
end

local function StateNumber(state)
	if type(state) == "number" then return state end
	local number = WS.STATE[string.upper(tostring(state))]
	if type(number) ~= "number" then
		local names = {}
		for name, value in pairs(WS.STATE) do
			if type(value) == "number" then names[#names + 1] = name end
		end
		table.sort(names)
		dev.Fail("no round state " .. tostring(state) .. "; one of " .. table.concat(names, ", "))
	end
	return number
end

-- The round put in a state as a restore does: no enter handler runs, the
-- clients are told. For the real path use force_win or restart_round.
function H.set_round_state(state)
	Require()
	local rounds = dev.Rounds()
	local to, now = StateNumber(state), CurTime()
	local from = rounds.round:State()
	local snapshot = rounds.round:Snapshot(now)
	snapshot.states = to
	rounds.round:Restore(snapshot, now)
	Original("Apply")(rounds, { {
		kind = "state",
		from = from,
		to = to,
		preroundEnd = rounds.round:PreroundEnd(),
	} })
	return {
		from = from,
		to = rounds.round:State(),
	}
end

local function Timer(name)
	local rounds = dev.Rounds()
	if name == nil then
		local hud = rounds:HudTimer()
		if not IsValid(hud) then dev.Fail("no HUD timer; name one: " .. table.concat(H.timers(), ", ")) end
		return hud
	end
	for ent in pairs(rounds.timers) do
		if IsValid(ent) and ent:GetName() == name then return ent end
	end
	dev.Fail("no team_round_timer named " .. tostring(name) .. "; the timers: " .. table.concat(H.timers(), ", "))
end

function H.timers()
	local names = {}
	for ent in pairs(dev.Rounds().timers) do
		if IsValid(ent) then names[#names + 1] = ent:GetName() ~= "" and ent:GetName() or dev.Describe(ent) end
	end
	table.sort(names)
	return names
end

local function TimerState(ent)
	local timer = dev.Rounds().timers[ent]
	return {
		timer = dev.Describe(ent),
		left = timer:TimeRemaining(CurTime()),
		paused = timer:Paused(),
		disabled = timer:Disabled(),
		setup = timer:InSetup(),
	}
end

-- Any team_round_timer input (settime, pause, resume, enable, addtime...)
-- on a timer (the HUD's when name is nil); the timer as it is after.
function H.timer(name, input, value)
	Require()
	local ent = Timer(name)
	input = string.lower(input)
	if dev.Rounds().timers[ent]:Disabled() and input ~= "enable" then
		dev.Fail(dev.Describe(ent) .. " is disabled, so " .. input .. " does nothing; enable it first: dev.harness.timer("
			.. string.format("%q", ent:GetName()) .. ", \"enable\")")
	end
	if not dev.Rounds():TimerInput(ent, input, value ~= nil and tostring(value) or nil) then
		dev.Fail("team_round_timer has no input " .. input)
	end
	return TimerState(ent)
end

function H.set_timer(seconds, name) return H.timer(name, "settime", seconds) end
function H.pause_timer(name) return H.timer(name, "pause") end
function H.resume_timer(name) return H.timer(name, "resume") end

local TEAMS = {
	red = "TEAM_RED",
	blue = "TEAM_BLUE",
}

-- who: red | blue | stalemate. Goes through even with wins suppressed.
function H.force_win(who)
	Require()
	local rounds = dev.Rounds()
	local Rounds = gameplay.rounds
	if who == "stalemate" then
		Original("SetStalemate")(rounds, Rounds.STALEMATE.ADMIN, true, false)
	elseif TEAMS[who] then
		Original("SetWinningTeam")(rounds, WS[TEAMS[who]], Rounds.WINREASON.NONE, true, false, false)
	else
		dev.Fail("force_win takes red, blue or stalemate, not " .. tostring(who))
	end
	return {
		state = rounds.round:State(),
		winner = rounds.round:Winner(),
	}
end

-- While on, every win and stalemate the map or the objectives ask for is
-- dropped (and traced), so the round runs on.
function H.suppress_wins(on)
	Require()
	live.suppressWins = on == true
	Note("suppress_wins", { on = live.suppressWins })
	return H.status()
end

function H.restart_round()
	Require()
	dev.Rounds():RestartRound()
	return { state = dev.Rounds().round:State() }
end

-- Proof that the harness off leaves the gamerules as they were: the bound
-- rules keep the map's name and class, nothing of the harness exists, and
-- every method the harness wraps is the rounds controller's own.
function H.check_off()
	local problems = {}
	if live.on then problems[#problems + 1] = "the harness is on" end
	local remaining = 0
	for _, ent in ipairs(ents.FindByClass(CLASS)) do
		if not ent:IsMarkedForDeletion() then remaining = remaining + 1 end
	end
	if remaining > 0 then problems[#problems + 1] = remaining .. " " .. CLASS .. " exist" end
	local rounds = dev.Rounds()
	local real = rounds:Proxy()
	if not IsValid(real) then
		problems[#problems + 1] = "no gamerules are bound"
	elseif string.EndsWith(real:GetName(), REAL_SUFFIX) then
		problems[#problems + 1] = "the gamerules are still named " .. real:GetName()
	end
	for _, method in ipairs(WRAPPED) do
		if live.originals[method] then problems[#problems + 1] = method .. " is still wrapped" end
	end
	if live.frozen or game.GetTimeScale() ~= RUNNING_SCALE then problems[#problems + 1] = "time scale is " .. game.GetTimeScale() end
	if hook.GetTable().Tick and hook.GetTable().Tick[STEP_HOOK] then problems[#problems + 1] = "the step hook is installed" end
	return {
		ok = #problems == 0,
		problems = problems,
		gamerules = dev.Describe(real),
	}
end

-- The inputs the stock TF2 maps send their gamerules (every one of the 242
-- maps' entity lumps counted), with values a map sends. PlayVO is left out:
-- it plays to every player.
local MAP_INPUTS = {
	{ "SetRedTeamRespawnWaveTime", "9" },
	{ "setblueteamrespawnwavetime", "4" },
	{ "AddRedTeamRespawnWaveTime", "2" },
	{ "addblueteamrespawnwavetime", "3" },
	{ "SetRedTeamGoalString", "#dev_red_goal" },
	{ "SetBlueTeamGoalString", "#dev_blue_goal" },
	{ "SetRedTeamRole", "1" },
	{ "SetBlueTeamRole", "2" },
	{ "SetStalemateOnTimelimit", "1" },
	{ "SetRoundRespawnFreezeEnabled", "0" },
	{ "HandleMapEvent", "" },
	{ "SetCTFCaptureBonusTime", "10" },
	{ "SetMapForcedTruceDuringBossFight", "0" },
}
local GOAL_GLOBALS = { "ws_round_goal_", "ws_round_role_" }

local function Globals()
	local values = {}
	for _, prefix in ipairs(GOAL_GLOBALS) do
		for _, t in ipairs({ WS.TEAM_RED, WS.TEAM_BLUE }) do values[prefix .. t] = GetGlobal2Var(prefix .. t) end
	end
	return values
end

local function Observed(rounds)
	local seen = { round = rounds.round:Snapshot(CurTime()) }
	for key, value in pairs(Globals()) do seen[key] = tostring(value) end
	seen.restart_freeze = WS.RestartFreeze:GetString()
	return seen
end

local function Diff(a, b, path, out)
	if type(a) == "table" and type(b) == "table" then
		local keys = {}
		for k in pairs(a) do keys[k] = true end
		for k in pairs(b) do keys[k] = true end
		for k in pairs(keys) do Diff(a[k], b[k], path .. "." .. tostring(k), out) end
	elseif a ~= b then
		out[#out + 1] = path .. ": " .. tostring(a) .. " vs " .. tostring(b)
	end
	return out
end

local function SendAll(name)
	local target = ents.FindByName(name)
	if #target ~= 1 then dev.Fail(#target .. " entities answer to " .. name .. ", not 1") end
	for _, input in ipairs(MAP_INPUTS) do target[1]:Input(input[1], NULL, NULL, input[2]) end
	return target[1]:GetClass()
end

-- Proof that the harness changes nothing the map can see: from one saved
-- round, every map input sent through the harness (forwarding) and sent
-- with it off leave the same round and the same HUD globals; the round is
-- put back after, the harness left as it was found, and check_off run.
function H.check_equivalence()
	local rounds = dev.Rounds()
	local wasOn = live.on
	if wasOn then H.enable(false) end
	local own = {}
	for _, method in ipairs(WRAPPED) do own[method] = rawget(rounds, method) end
	local now = CurTime()
	local saved = rounds.round:Snapshot(now)
	local savedGlobals, savedFreeze = Globals(), WS.RestartFreeze:GetString()
	local before = Observed(rounds)
	local name = rounds:Proxy():GetName()

	H.enable(true)
	local mode, rules = live.model:Mode(), live.model:Rules()
	live.model:SetMode(Harness.FORWARD)
	for input in pairs(rules) do live.model:SetRule(input, nil) end
	local onTarget = SendAll(name)
	local withHarness = Observed(rounds)
	live.model:SetMode(mode)
	for input, action in pairs(rules) do live.model:SetRule(input, action) end
	H.enable(false)

	rounds.round:Restore(saved, now)
	local offTarget = SendAll(name)
	local without = Observed(rounds)
	rounds.round:Restore(saved, now)
	for key, value in pairs(savedGlobals) do SetGlobal2Var(key, value) end
	WS.RestartFreeze:SetString(savedFreeze)

	local identical = {}
	for _, method in ipairs(WRAPPED) do
		if rawget(rounds, method) ~= own[method] then identical[#identical + 1] = method .. " is not the controller's own" end
	end
	local off = H.check_off()
	if wasOn then H.enable(true) end
	local differences = Diff(withHarness, without, "", {})
	return {
		ok = #differences == 0 and off.ok and #identical == 0,
		inputs = #MAP_INPUTS,
		sent_to = {
			on = onTarget,
			off = offTarget,
		},
		differences = differences,
		changed_by_inputs = #Diff(before, without, "", {}),
		methods = identical,
		check_off = off,
	}
end

dev.WhenReady("harness", function()
	if convar:GetBool() and not live.on then H.enable(true) end
end)

-- Console commands: the same functions, their tables printed as JSON.
dev.Command("dev_harness_status", function() return H.status() end, "The gamerules harness's state")
dev.Command("dev_harness_mode", function(args)
	local rules = {}
	for i = 2, #args, 2 do rules[args[i]] = args[i + 1] ~= "clear" and args[i + 1] or false end
	return H.mode(args[1] ~= "" and args[1] or nil, rules)
end, "dev_harness_mode <forward|intercept|queue> [input action|clear ...]")
dev.Command("dev_harness_release", function() return H.release() end, "Forward the queued inputs")
dev.Command("dev_harness_trace", function(args) return H.trace({ since = tonumber(args[1]), limit = tonumber(args[2]) }) end,
	"dev_harness_trace [since] [limit]")
dev.Command("dev_pause", function() return H.pause() end, "Freeze gameplay (time scale 0)")
dev.Command("dev_resume", function() return H.resume() end, "Unfreeze gameplay")
dev.Command("dev_step", function(args) return H.step(tonumber(args[1]) or 1) end, "dev_step [ticks]: run ticks, then freeze")
dev.Command("dev_round_state", function(args) return H.set_round_state(tonumber(args[1]) or args[1]) end,
	"dev_round_state <state name or number>")
dev.Command("dev_timer_set", function(args) return H.set_timer(tonumber(args[1]), args[2]) end, "dev_timer_set <seconds> [timer name]")
dev.Command("dev_timer", function(args) return H.timer(args[1] ~= "-" and args[1] or nil, args[2], args[3]) end,
	"dev_timer <name|-> <input> [value]: any team_round_timer input")
dev.Command("dev_force_win", function(args) return H.force_win(args[1]) end, "dev_force_win red|blue|stalemate")
dev.Command("dev_suppress_wins", function(args) return H.suppress_wins(args[1] == "1") end, "dev_suppress_wins 0|1")
dev.Command("dev_harness_check_off", function() return H.check_off() end, "Prove the harness off left the gamerules as they were")
dev.Command("dev_harness_check_equivalence", function() return H.check_equivalence() end,
	"Prove map inputs do the same with the harness on and off")
