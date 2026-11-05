-- The assessment of bot players on the engine's statechart, as data a map change does
-- not lose: on a CTF map, mp_winlimit 1, tf_flag_caplimit 1 and one player, a NextSoldier
-- on BLU, it plays the round. Each change of its stack, of the flag and of the round is written to
-- data/ns_round_check.txt as it happens.
--   dt gmod lua_run instance=N code="$(cat .devtools/bin/next_soldier_round_check.lua)"
local E = nextsoldier.engine
RunConsoleCommand("mp_winlimit", "1")
RunConsoleCommand("tf_flag_caplimit", "1")
RunConsoleCommand("mp_timelimit", "0")
RunConsoleCommand("mp_maxrounds", "0")
local FILE = "ns_round_check.txt"
file.Write(FILE, "")
local report = { log = {}, wins = {} }
NSRoundCheck = report
local began = CurTime()
local function Note(text)
	local line = string.format("%6.1f %s", CurTime() - began, text)
	report.log[#report.log + 1] = line
	file.Append(FILE, line .. "\n")
end

local bot = WS.AddNextSoldier(WS.TEAM_BLUE, "BLU NextSoldier")
report.bot = bot
Note("added " .. tostring(bot) .. " team " .. bot:Team() .. ", players on the server " .. #player.GetAll())

hook.Add("WSRoundWin", "ns_round_check", function(winner, reason)
	report.wins[#report.wins + 1] = { winner = winner, reason = tostring(reason) }
	Note("ROUND WON by team " .. tostring(winner) .. " (BLU is " .. WS.TEAM_BLUE .. "), reason " .. tostring(reason))
end)
hook.Add("WSMatchWin", "ns_round_check", function(winner)
	Note("MATCH WON by team " .. tostring(winner))
end)

gameevent.Listen("player_disconnect")
hook.Add("player_disconnect", "ns_round_check", function(data)
	Note("left: " .. tostring(data.name) .. ", " .. tostring(data.reason))
end)

local function Shape(frames)
	local parts = {}
	for _, frame in ipairs(frames) do parts[#parts + 1] = frame.name .. (frame.suspended and "(s)" or "") end
	return table.concat(parts, " > ")
end

local lastStack, lastFlag, lastRound, lastAlive
local nextPos = 0
hook.Add("Tick", "ns_round_check", function()
	if not IsValid(bot) then return end
	local shape = Shape(E.Stack(bot))
	if shape ~= lastStack then lastStack = shape Note(shape) end
	local flags = {}
	for _, ent in ipairs(ents.FindByClass("item_teamflag")) do
		local model = ent.flag:FlagAt(ent)
		flags[#flags + 1] = "team" .. model:Team() .. ":" .. model:State()
	end
	local state = table.concat(flags, " ")
	if state ~= lastFlag then lastFlag = state Note("flags " .. state .. " at " .. tostring(bot:GetPos())) end
	local round = tostring(WS.State())
	if round ~= lastRound then lastRound = round Note("round state " .. round .. ", gameplay stopped " .. tostring(WS.GameplayStopped())) end
	if bot:Alive() ~= lastAlive then lastAlive = bot:Alive() Note("alive " .. tostring(lastAlive) .. " at " .. tostring(bot:GetPos())) end
	if CurTime() >= nextPos then
		nextPos = CurTime() + 5
		Note(string.format("at %s speed %.0f", tostring(bot:GetPos()), bot:GetVelocity():Length2D()))
	end
end)

return "started"
