-- An AI war round on a CTF map as data a map change does not lose: BLU's bots against nobody,
-- to one capture. Written to data/ns_war_round.txt as it happens: the flags, each bot held still
-- and what it was running, each recovery, and the win.
--   dt gmod lua_run instance=N code="$(cat .devtools/bin/war_round_check.lua)"
local BLU_SIZE = 8
local FILE = "ns_war_round.txt"
local STILL_SPEED, STILL_SECONDS, HELD_SECONDS = 30, 3, 5

local War = WS.Feature ("aiwar")
RunConsoleCommand ("mp_winlimit",      "1")
RunConsoleCommand ("tf_flag_caplimit", "1")
RunConsoleCommand ("mp_timelimit",     "0")
RunConsoleCommand ("mp_maxrounds",     "0")
War:SetSlotCount (WS.TEAM_RED,  0)
War:SetSlotCount (WS.TEAM_BLUE, BLU_SIZE)
War.hazardWatch:Model ()
RunConsoleCommand ("ns_hazards_clear", "all")

file.Write (FILE, "")
local began = CurTime ()
local function Note (text)
	file.Append (FILE, string.format ("%6.1f %s\n", CurTime () - began, text))
end
Note (game.GetMap () .. " started")

-- Where its orders send it, and the point its body makes for.
local function Going (bot)
	local entry = War.soldiers [bot]
	local soldier = entry and entry.soldier
	if not soldier then return "not enlisted" end
	local target, steer = soldier.moveTarget, soldier.steer
	return string.format ("target %s steer %s", target and string.format ("%.0f,%.0f,%.0f", target.x, target.y, target.z) or "none",
		steer and string.format ("%.0f,%.0f,%.0f", steer.x, steer.y, steer.z) or "none")
end

local function Terminal (bot)
	local name = "?"
	local ok, frames = pcall (nextsoldier.engine.Stack, bot)
	if ok then
		for _, frame in ipairs (frames) do
			if not frame.suspended then name = frame.name end
		end
	end
	return name
end

hook.Add ("WSRoundWin", "ns_war_round", function (winner, reason)
	Note ("ROUND WON by team " .. tostring (winner) .. ", reason " .. tostring (reason))
end)
hook.Add ("WSMatchWin", "ns_war_round", function (winner) Note ("MATCH WON by team " .. tostring (winner)) end)

-- Each recovery, as the hazards' part notes it (an override on the live object, gone with the map).
local Hazards = War.hazardWatch
local NoteHazard = Hazards.Note
function Hazards:Note (ent, cause)
	Note (string.format ("recovered %s at %s, from %s, %s", tostring (cause), tostring (ent:GetPos ()), Terminal (ent), Going (ent)))
	return NoteHazard (self, ent, cause)
end

-- Why a bot is held: its route, the nearest of its team, and what its body meets on its way.
local function Held (bot)
	local entry = War.soldiers [bot]
	local soldier = entry and entry.soldier
	if not soldier then return "not enlisted" end
	local pos = bot:GetPos ()
	local nearest, near = math.huge, "nobody"
	for _, other in ipairs (player.GetBots ()) do
		if other ~= bot and other:Alive () and pos:Distance (other:GetPos ()) < nearest then
			nearest, near = pos:Distance (other:GetPos ()), other:Nick ()
		end
	end
	local met = "no steer"
	local steer = soldier.steer
	if steer then
		local mins, maxs = bot:GetHull ()
		local lift = Vector (0, 0, 20)
		local to = Vector (steer.x, steer.y, pos.z)
		local trace = util.TraceHull (
			{
				start = pos + lift,
				endpos = pos + (to - pos):GetNormalized () * 40 + lift,
				mins = Vector (mins.x, mins.y, 0),
				maxs = Vector (maxs.x, maxs.y, 36),
				mask = MASK_PLAYERSOLID,
				filter = bot
			}
		)
		met = trace.Hit and ("meets " .. tostring (trace.Entity)) or "way clear"
	end
	local walk = soldier.walk
	local points = walk and walk.points
	local navigator = soldier:Navigator ()
	local goal = soldier.moveTarget
	local fresh, found = "-", "-"
	if goal then
		local route, ok = navigator:PlanRoute (Vector (goal.x, goal.y, goal.z), soldier:RouteCost ())
		fresh, found = route and #route or "none", tostring (ok)
	end
	return string.format ("nearest %s %.0f | %s | walk %s/%s done %s settled %s in %.1f | fresh %s found %s | ground %s use %s",
		near, nearest, met, tostring (walk and walk.index), tostring (points and #points), tostring (walk and walk:Done ()),
		tostring (navigator:Settled ()), (soldier.nextPlan or 0) - CurTime (), tostring (fresh), found,
		tostring (bot:OnGround ()), tostring (soldier.doorAhead))
end

local flags, round, held = {}, nil, setmetatable ({}, { __mode = "k" })
hook.Add ("Tick", "ns_war_round", function ()
	for _, ent in ipairs (ents.FindByClass ("item_teamflag")) do
		local model = ent.flag:FlagAt (ent)
		local team, state = model:Team (), model:State ()
		if flags [team] ~= state then
			flags [team] = state
			Note (string.format ("flag of team %d %s at %s", team, tostring (state), tostring (ent:GetPos ())))
		end
	end
	local state = WS.State ()
	if state ~= round then
		round = state
		Note ("round state " .. tostring (state))
	end
	if state ~= 4 then return end
	for _, bot in ipairs (player.GetBots ()) do
		local still = bot:Alive () and bot:GetVelocity ():Length2D () < STILL_SPEED
		local since = held [bot]
		if still and not since then
			held [bot] = { at = CurTime (), pos = bot:GetPos () }
		elseif still and not since.told and CurTime () - since.at >= HELD_SECONDS then
			since.told = true
			Note (string.format ("%s HELD at %s, %s, %s, %s", bot:Nick (), tostring (bot:GetPos ()), Terminal (bot), Going (bot), Held (bot)))
		elseif not still and since then
			if CurTime () - since.at >= STILL_SECONDS then
				Note (string.format ("%s still %.1f s at %s, %s, %s", bot:Nick (), CurTime () - since.at, tostring (since.pos), Terminal (bot), Going (bot)))
			end
			held [bot] = nil
		end
	end
end)

NSWarRound = {}

-- Who is where now, and what each is running.
function NSWarRound.Now ()
	local lines = { string.format ("%.0f s, state %s, bots %d", CurTime () - began, tostring (WS.State ()), #player.GetBots ()) }
	for _, bot in ipairs (player.GetBots ()) do
		local since = held [bot]
		lines [#lines + 1] = string.format ("%s team %d %s %.0f u/s %s%s", bot:Nick (), bot:Team (), tostring (bot:GetPos ()),
			bot:GetVelocity ():Length2D (), Terminal (bot), since and string.format (" STILL %.0f s", CurTime () - since.at) or "")
	end
	return table.concat (lines, "\n")
end

return "started on " .. game.GetMap ()
