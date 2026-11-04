-- What the engine does with Actions native/nextsoldier builds, checked on a live
-- server with its binary in lua/bin (`gmsv_<module>_win64.dll`), as returned data:
--   dt gmod lua_run instance=N code="$(cat .devtools/bin/nextsoldier_engine_check.lua)"
--   (wait five seconds)
--   dt gmod lua_run instance=N code='return NSEngineCheck.Finish()'
-- Finish returns every check with whether it held and removes its bots; half a
-- second on, NSEngineCheck.removal says whether the removed one's actions ended,
-- and how many the engine deleted (2).
local MODULE = NS_ENGINE_MODULE or "nextsoldier"
require(MODULE)
local E = nextsoldier.engine
if E.refused then return "refused: " .. E.refused end

local CONTINUE, CHANGE_TO, SUSPEND_FOR, DONE = 0, 1, 2, 3
local CLASS = "ns_engine_check"
local YES, NO, UNDEFINED = 1, 0, 2

local log, bots = {}, {}
local function Note(entry) log[#log + 1] = entry end
local function Action(name, hooks) return setmetatable({ name = name }, { __index = hooks }) end

scripted_ents.Register({
	Base = "base_nextbot",
	Type = "nextbot",
	Initialize = function(self) self:SetModel("models/kleiner.mdl") end,
	BehaveStart = function(self) E.Insert(self, self.Plan()) end,
	BehaveUpdate = function(self) self.behaved = (self.behaved or 0) + 1 end,
	RunBehaviour = function() while true do coroutine.yield() end end,
}, CLASS)

local FROM = navmesh.GetAllNavAreas()[1]:GetCenter()
local function Bot(name, hooks)
	local bot = ents.Create(CLASS)
	bot.Plan = function() return Action(name, hooks) end
	bot:SetPos(FROM + Vector(math.random(-80, 80), math.random(-80, 80), 16))
	bot:Spawn()
	bot:SetHealth(1000)
	bots[name] = bot
	return bot
end

-- Containment, a suspension and a change, each hook writing to the log.
local Second = {
	OnStart = function(_, _, prior) Note("Second start after " .. tostring(prior and prior.name)) return { type = CONTINUE } end,
	Update = function() return { type = DONE, reason = "second done" } end,
	OnEnd = function() Note("Second end") end,
}
local Cover = {
	OnStart = function(_, _, prior) Note("Cover start after " .. tostring(prior and prior.name)) return { type = CONTINUE } end,
	Update = function() return { type = DONE, reason = "uncovered" } end,
	OnEnd = function(_, _, following) Note("Cover end for " .. tostring(following and following.name)) end,
}
local Inner = {
	OnStart = function(self) self.n = 0 Note("Inner start") return { type = CONTINUE } end,
	Update = function(self)
		self.n = self.n + 1
		if self.n == 1 then return { type = SUSPEND_FOR, action = Action("Cover", Cover), reason = "cover" } end
		if self.n == 2 then return { type = CHANGE_TO, action = Action("Second", Second), reason = "next" } end
		return { type = CONTINUE }
	end,
	OnSuspend = function(_, _, other) Note("Inner suspend for " .. tostring(other and other.name)) return { type = CONTINUE } end,
	OnResume = function(_, _, other) Note("Inner resume from " .. tostring(other and other.name)) return { type = CONTINUE } end,
	OnEnd = function(_, _, following) Note("Inner end for " .. tostring(following and following.name)) end,
}
Bot("Outer", {
	InitialContainedAction = function() return Action("Inner", Inner) end,
	OnStart = function() Note("Outer start") return { type = CONTINUE } end,
	Update = function() return { type = CONTINUE } end,
})

-- The engine's query walk, from the innermost out.
Bot("Asking", {
	InitialContainedAction = function()
		return Action("Answer", { ShouldHurry = function() return YES end, Update = function() return { type = CONTINUE } end })
	end,
	ShouldHurry = function() return NO end,
	Update = function() return { type = CONTINUE } end,
})

-- A damage event fired inside a hook: stored, and its change made at the next update.
local Hurt = { OnStart = function() Note("Hurt start") return { type = CONTINUE } end, Update = function() return { type = CONTINUE } end }
Bot("Calm", {
	Update = function(self, me)
		if not self.hit then
			self.hit = true
			me:TakeDamage(1, game.GetWorld())
			Note("Calm back from the hit")
		end
		return { type = CONTINUE }
	end,
	OnInjured = function() Note("Calm injured") return { type = CHANGE_TO, action = Action("Hurt", Hurt), reason = "ow", priority = 2 } end,
	OnEnd = function(_, _, following) Note("Calm end for " .. tostring(following and following.name)) end,
})

-- A hook that fails: reported, and the tree goes on.
local failing = 0
Bot("Failing", {
	Update = function()
		failing = failing + 1
		if failing == 2 then error("a behaviour failing on purpose") end
		return { type = CONTINUE }
	end,
})

-- A bot removed while it runs: its actions end, and the engine deletes them.
local doomedEnded = false
Bot("Doomed", {
	InitialContainedAction = function() return Action("DoomedChild", { Update = function() return { type = CONTINUE } end }) end,
	Update = function() return { type = CONTINUE } end,
	OnEnd = function() doomedEnded = true end,
})

local function Has(entry)
	for _, seen in ipairs(log) do
		if seen == entry then return true end
	end
	return false
end

local function Depth(bot)
	local names = {}
	for _, frame in ipairs(E.Stack(bot)) do names[#names + 1] = frame.name end
	return table.concat(names, "/")
end

NSEngineCheck = {}

function NSEngineCheck.Finish()
	local checks = {
		child_starts_before_its_container = Has("Inner start") and Has("Outer start"),
		suspends_for_cover = Has("Inner suspend for Cover") and Has("Cover start after Inner"),
		done_resumes_the_buried = Has("Cover end for Inner") and Has("Inner resume from Cover"),
		change_takes_its_place = Has("Inner end for Second") and Has("Second start after Inner"),
		done_child_leaves_the_container = Depth(bots.Outer) == "CLuaBehaviour/Outer",
		query_walks_from_the_innermost = E.ShouldHurry(bots.Asking) == YES,
		event_in_a_hook_comes_back = Has("Calm injured") and Has("Calm back from the hit"),
		event_changes_at_the_next_update = Has("Calm end for Hurt") and Has("Hurt start"),
		failing_hook_goes_on = failing > 2,
		lua_behaviour_still_runs = (bots.Outer.behaved or 0) > 0,
	}
	local live = E.Live()
	bots.Doomed:Remove()
	timer.Simple(0.5, function()
		NSEngineCheck.removal = { ended = doomedEnded, deleted = live - E.Live() }
		for _, bot in pairs(bots) do
			if IsValid(bot) then bot:Remove() end
		end
	end)
	return util.TableToJSON({ checks = checks, live = live, log = log })
end

return "started"
