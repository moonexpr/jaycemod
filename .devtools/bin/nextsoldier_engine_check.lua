-- What the engine does with Actions native/nextsoldier builds, checked on a live
-- server with its binary in lua/bin (`gmsv_<module>_win64.dll`), as returned data:
--   dt gmod lua_run instance=N code="$(cat .devtools/bin/nextsoldier_engine_check.lua)"
--   (wait five seconds)
--   dt gmod lua_run instance=N code='return NSEngineCheck.Finish()'
-- Finish returns every check with whether it held and removes its bots; half a
-- second on, NSEngineCheck.removal says whether the removed one's actions ended,
-- and how many the engine deleted (the Doomed bot's 2 and the soldier's).
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

-- On base_nextsoldier where the server has it (the gamemode loads it), which
-- resets as it starts; on a bare NextBot where it runs no game (--gamemode base).
local ON_SOLDIER = nextsoldier.host ~= nil
scripted_ents.Register({
	Base = ON_SOLDIER and "base_nextsoldier" or "base_nextbot",
	Type = "nextbot",
	Initialize = not ON_SOLDIER and function(self) self:SetModel("models/kleiner.mdl") end or nil,
	BehaveStart = function(self)
		if ON_SOLDIER then self:Reset() end
		E.Insert(self, self.Plan())
	end,
	BehaveUpdate = function(self) self.behaved = (self.behaved or 0) + 1 end,
	RunBehaviour = function() while true do coroutine.yield() end end,
}, CLASS)

local AREA = navmesh.GetAllNavAreas()[1]
local FROM = (AREA and AREA:GetCenter() or ents.FindByClass("info_player_start")[1]:GetPos()) + Vector(0, 0, 16)
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

-- An event from Lua, through the engine's own path: its arguments reach the innermost
-- action and its container, and its change is made at the next update.
Bot("Told", {
	InitialContainedAction = function()
		return Action("Listener", {
			OnThing = function(_, _, word, number)
				Note("Listener thing " .. word .. " " .. number)
				return { type = CHANGE_TO, action = Action("Changed", { OnStart = function() Note("Changed start") return { type = CONTINUE } end }), reason = "told", priority = 1 }
			end,
			Which = function(_, _, word) return word .. "!" end,
			Undecided = function() return UNDEFINED end,
			Update = function() return { type = CONTINUE } end,
		})
	end,
	OnThing = function(_, _, word) Note("Teller thing " .. word) return { type = CONTINUE } end,
	Undecided = function() return "the container's" end,
	Update = function() return { type = CONTINUE } end,
})
timer.Simple(3, function() E.Event(bots.Told, "OnThing", "one", 2) end)

-- What chart actions read of their links, and a new tree over an ended one.
local below, buriedName, suspendedSeen
Bot("Linked", {
	InitialContainedAction = function()
		return Action("Under", {
			Whose = function() return "below" end,
			Update = function() return { type = CONTINUE } end,
		})
	end,
	Update = function(self, me)
		below = self:QueryBelow(me, "Whose")
		if not self.covered then
			self.covered = true
			return { type = SUSPEND_FOR, action = Action("Cover", {
				Update = function(cover)
					local under = cover:GetActionBuriedUnderMe()
					buriedName = under and under.name
					suspendedSeen = under and under:IsSuspended()
					return { type = CONTINUE }
				end,
			}), reason = "covered" }
		end
		return { type = CONTINUE }
	end,
})
local secondLife
Bot("Reborn", {
	Update = function() return { type = CONTINUE } end,
})
timer.Simple(4, function()
	E.End(bots.Reborn)
	E.Insert(bots.Reborn, Action("Second", { OnStart = function() secondLife = true return { type = CONTINUE } end, Update = function() return { type = CONTINUE } end }))
end)

-- engine.End: each OnEnd now, innermost first, and not again as the bot goes.
local endings = 0
local endingWhole
Bot("Ending", {
	InitialContainedAction = function()
		return Action("EndingInner", {
			Update = function() return { type = CONTINUE } end,
			OnEnd = function(_, me)
				endings = endings + 1
				endingWhole = IsValid(me)
			end,
		})
	end,
	Update = function() return { type = CONTINUE } end,
	OnEnd = function() endings = endings + 1 end,
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

-- A NextSoldier: a player bot on the engine's statechart, with no CLuaBehaviour.
local CoverP = {
	OnStart = function(_, _, prior) Note("P Cover start after " .. tostring(prior and prior.name)) return { type = CONTINUE } end,
	Update = function() return { type = DONE, reason = "uncovered" } end,
	OnEnd = function(_, _, following) Note("P Cover end for " .. tostring(following and following.name)) end,
}
local HurtP = {
	OnStart = function() Note("P Hurt start") return { type = CONTINUE } end,
	Update = function() return { type = CONTINUE } end,
	ShouldHurry = function() return YES end,
	OnEnd = function() Note("P Hurt end") end,
}
local InnerP = {
	OnStart = function(self, me) self.n = 0 Note("P Inner start, me the player " .. tostring(me == NSEngineSoldier)) return { type = CONTINUE } end,
	Update = function(self)
		self.n = self.n + 1
		if self.n == 1 then return { type = SUSPEND_FOR, action = Action("Cover", CoverP), reason = "cover" } end
		return { type = CONTINUE }
	end,
	OnSuspend = function(_, _, other) Note("P Inner suspend for " .. tostring(other and other.name)) return { type = CONTINUE } end,
	OnResume = function(_, _, other) Note("P Inner resume from " .. tostring(other and other.name)) return { type = CONTINUE } end,
	OnInjured = function() Note("P Inner injured") return { type = CHANGE_TO, action = Action("Hurt", HurtP), reason = "ow", priority = 2 } end,
	ShouldHurry = function() return NO end,
}
NSEngineSoldier = player.CreateNextSoldier("NSEngineSoldier")
-- A dead body runs no actions: once a game is on, a new player unassigned to a team dies
-- and stays so, and every soldier_ check after this one fails for that reason.
E.Insert(NSEngineSoldier, Action("Outer", {
	InitialContainedAction = function() return Action("Inner", InnerP) end,
	OnStart = function() Note("P Outer start") return { type = CONTINUE } end,
	Update = function() return { type = CONTINUE } end,
	OnEnd = function(_, me) Note("P Outer end, its player whole " .. tostring(IsValid(me))) end,
}))
local plainBot = player.CreateNextBot("NSEnginePlain")
local plainRefused = not pcall(E.Stack, plainBot)
timer.Simple(2, function()
	if IsValid(NSEngineSoldier) then
		NSEngineSoldier:SetHealth(1000)
		NSEngineSoldier:TakeDamage(1, game.GetWorld())
	end
end)

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
	E.End(bots.Ending)
	local endedOnce = endings == 2
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
		soldier_stayed_alive = NSEngineSoldier:Alive(),
		soldier_suspends_and_resumes = Has("P Inner suspend for Cover") and Has("P Cover start after Inner") and Has("P Inner resume from Cover"),
		soldier_me_is_the_player = Has("P Inner start, me the player true"),
		soldier_hears_damage = Has("P Inner injured") and Has("P Hurt start"),
		soldier_query_walks = E.ShouldHurry(NSEngineSoldier) == YES,
		a_plain_bot_is_refused = plainRefused,
		end_runs_each_ending_once = endedOnce,
		end_finds_its_bot_whole = endingWhole,
		chart_query_below_reads_the_engine = below == "below",
		chart_buried_reads_the_engine = buriedName ~= nil,
		chart_suspended_reads_the_engine = suspendedSeen == true,
		a_new_tree_replaces_an_ended_one = secondLife == true,
		event_carries_its_arguments = Has("Listener thing one 2"),
		event_reaches_the_container = Has("Teller thing one"),
		event_changes_at_the_next_update_too = Has("Changed start"),
		query_answers_with_its_arguments = E.Query(bots.Told, "Undecided") == "the container's",
		query_nobody_answers_is_nil = E.Query(bots.Told, "Nobody") == nil,
	}
	local live = E.Live()
	bots.Doomed:Remove()
	NSEngineSoldier:Kick("the check is over")
	plainBot:Kick("the check is over")
	timer.Simple(0.5, function()
		NSEngineCheck.removal = { ended_again = endings ~= 2, ended = doomedEnded, deleted = live - E.Live(), soldier_ended = Has("P Hurt end") and Has("P Outer end, its player whole true") }
		for _, bot in pairs(bots) do
			if IsValid(bot) then bot:Remove() end
		end
	end)
	return util.TableToJSON({ checks = checks, live = live, log = log })
end

return "started"
