-- actor.body, actor.vision and actor.intention (addons/nextsoldier/native, actor_bind.rs) on a
-- live server with the binary in lua/bin, as returned data, on any gamemode (sandbox will do):
--   dt gmod/mcp lua_run instance=N code='return dev.probe("nextsoldier_components_check")'
--   (wait five seconds, while the path followers walk and their visions scan)
--   dt gmod lua_run instance=N code='return util.TableToJSON (NextSoldierComponentsCheck.Finish ())'
-- Two bare NextBots that follow paths from nav area to nav area (GMod's own MoveToPos, the
-- simplest path follower), spawned in sight of each other, and a NextSoldier bot player. Start
-- returns the checks that need no time; Finish what their visions came to know, then whether a
-- removed actor is refused rather than read, and removes everything it made.
require ("nextsoldier")
local E = nextsoldier.engine
if E.refused then return "refused: " .. E.refused end
if not E.Components then return "components refused: " .. tostring (E.componentsRefused) end

local CLASS = "ns_components_check"
local WANDER = 600
local APART = 250

local checks = {}
local function Check (name, held, detail)
	checks [#checks + 1] = { name = name, held = held and true or false, detail = detail }
end
local function Refused (fn, ...)
	local ok, why = pcall (fn, ...)
	return not ok, tostring (why)
end

scripted_ents.Register (
	{
		Base = "base_nextbot",
		Type = "nextbot",
		Initialize = function (self)
			self:SetModel ("models/kleiner.mdl")
			E.Components (self)
			self.nsStart = self:GetPos ()
			self.nsWalks = 0
		end,
		RunBehaviour = function (self)
			while true do
				local areas = navmesh.Find (self:GetPos (), WANDER, 64, 64)
				local area = areas [math.random (#areas)]
				if area and area:GetCenter ():Distance (self:GetPos ()) > 100 then
					self:StartActivity (ACT_WALK)
					self.loco:SetDesiredSpeed (100)
					local result = self:MoveToPos (area:GetCenter (), { maxage = 4 })
					self.nsWalks = self.nsWalks + 1
					self.nsLastWalk = result
				end
				self:StartActivity (ACT_IDLE)
				coroutine.wait (0.5)
			end
		end
	},
	CLASS
)

local function Spawn (at)
	local bot = ents.Create (CLASS)
	bot:SetPos (at)
	bot:Spawn ()
	return bot
end

-- two places on different nav areas, APART to twice that apart, each in sight of the other at
-- eye height
local EYE = Vector (0, 0, 64)
local function Pair ()
	for _, area in ipairs (navmesh.GetAllNavAreas ()) do
		local from = area:GetCenter ()
		for _, other in ipairs (navmesh.Find (from, APART * 2, 32, 32)) do
			local to = other:GetCenter ()
			local apart = from:Distance (to)
			if other ~= area and apart >= APART and apart <= APART * 2
				and not util.TraceLine ({ start = from + EYE, endpos = to + EYE, mask = MASK_SOLID }).Hit then
				return from, to
			end
		end
	end
end
local here, there = Pair ()
if not here then return "no two nav areas in sight of each other on " .. game.GetMap () end
local a, b = Spawn (here), Spawn (there)
a:SetAngles ((there - here):Angle ())
b:SetAngles ((here - there):Angle ())
local soldier = player.CreateNextSoldier ("NextSoldierComponentsCheck")

-- what each object is
for _, bot in ipairs ({ a, soldier }) do
	local what = bot:IsPlayer () and "player" or "bot"
	Check (what .. " has its components", bot.body and bot.vision and bot.intention,
		tostring (bot.body) .. " " .. tostring (bot.vision) .. " " .. tostring (bot.intention))
end

-- the body: the engine's, its head a stub where it is not ours
local body = a.body
local mins, maxs = body:GetHullMins (), body:GetHullMaxs ()
Check ("a hull, from the engine", maxs.z > mins.z and body:GetHullWidth () > 0,
	tostring (mins) .. " " .. tostring (maxs) .. " w " .. body:GetHullWidth () .. " h " .. body:GetHullHeight ())
Check ("its eyes are the entity's", body:GetEyePosition ():DistToSqr (a:EyePos ()) < 1,
	tostring (body:GetEyePosition ()) .. " vs " .. tostring (a:EyePos ()))
Check ("a solid mask and a collision group", body:GetSolidMask () ~= 0,
	body:GetSolidMask () .. " " .. body:GetCollisionGroup ())
Check ("the engine's head is steady, as its stub always is", body:IsHeadSteady () == true)
local refused, why = Refused (body.AimHeadTowards, body, b, "Looking at threat")
Check ("a bot with no head of ours is refused a head aim", refused, why)

-- the vision: the engine's IVision
local vision = a.vision
local fov = vision:GetFieldOfView ()
Check ("a field of view", fov > 0, fov .. " of " .. vision:GetDefaultFieldOfView ())
vision:SetFieldOfView (120)
Check ("the field of view is set", math.abs (vision:GetFieldOfView () - 120) < 0.01, vision:GetFieldOfView ())
local range = vision:GetMaxVisionRange ()
vision:SetMaxVisionRange (3000)
local ranged = vision:GetMaxVisionRange ()
Check ("a CLuaNextBot's range is set", math.abs (ranged - 3000) < 0.01, range .. " -> " .. ranged)
refused, why = Refused (soldier.vision.SetMaxVisionRange, soldier.vision, 3000)
Check ("a bot player's range is refused", refused, why)
refused, why = Refused (vision.IsAbleToSee, vision, NULL)
Check ("NULL is refused, not read as the world", refused,                                        why)
Check ("a point in front can be seen",           vision:IsAbleToSee (there + Vector (0, 0, 40)), tostring (there))
Check ("the line to it is clear",                         vision:IsLineOfSightClear (there + Vector (0, 0, 40)))
Check ("the other bot, placed facing it, is in its view", vision:IsInFieldOfView (b))
Check ("it is able to see the other bot",                 vision:IsAbleToSee (b))
Check ("and is looking at it",                            vision:IsLookingAt (b, 0.9))

-- the intention: engine.* with the actor as itself
local stack = a.intention:Stack ()
Check ("its intention answers Stack", istable (stack), stack and #stack)
Check ("a soldier's intention answers Stack", istable (soldier.intention:Stack ()))

NextSoldierComponentsCheck =
{
	Finish = function ()
		local function known (bot, other)
			local entry = bot.vision:GetKnown (other)
			if not entry then return "unknown" end
			return { visible = entry.visible, sinceBecameKnown = entry.sinceBecameKnown, pos = tostring (entry.pos) }
		end
		local list = a.vision:GetKnownEntities ()
		local names = {}
		for _, ent in ipairs (list) do names [#names + 1] = tostring (ent) end
		Check ("its vision recognized the other bot", table.HasValue (list, b),        table.concat (names, ", "))
		Check ("it counts what it knows",             a.vision:GetKnownCount () >= 1,  a.vision:GetKnownCount ())
		Check ("it knows the other by entity",        istable (a.vision:GetKnown (b)), known (a, b))
		Check ("its line of sight to the other is clear", a.vision:IsLineOfSightClearToEntity (b))
		Check ("the closest it knows", IsValid (a.vision:GetClosestKnown ()), tostring (a.vision:GetClosestKnown ()))
		Check ("the soldier's vision answers", isnumber (soldier.vision:GetKnownCount ()), soldier.vision:GetKnownCount ())
		Check ("its primary threat (the engine's teams)", true, tostring (a.vision:GetPrimaryKnownThreat ()))
		Check ("the path followers walked", a.nsWalks + b.nsWalks > 0 and a:GetPos ():Distance (a.nsStart) > 1,
			a.nsWalks .. " and " .. b.nsWalks .. " walks, " .. math.Round (a:GetPos ():Distance (a.nsStart)) .. " units, "
				.. tostring (a.nsLastWalk))

		local gone = b.vision
		b:Remove ()
		timer.Simple (0.2, function ()
			local refusedGone, whyGone = Refused (gone.GetKnownCount, gone)
			NextSoldierComponentsCheck.removal = { refused = refusedGone, why = whyGone }
			if IsValid (a) then a:Remove () end
			if IsValid (soldier) then soldier:Kick ("check done") end
		end)
		local held = 0
		for _, check in ipairs (checks) do if check.held then held = held + 1 end end
		return { held = held, of = #checks, checks = checks }
	end
}

local held = 0
for _, check in ipairs (checks) do if check.held then held = held + 1 end end
return util.TableToJSON ({ held = held, of = #checks, checks = checks })
