-- tf_bot_quota (features/aiwar/sv_bots.lua): with the war on, bot players
-- join to the quota, balanced between the teams; each is enlisted as a
-- soldier carrying its kit; under their orders they walk the map and fire
-- at enemies; a lower quota kicks them down to it, and 0 leaves none.
-- Needs DrGBase (the war's own soldiers fill the slots the bots leave).
-- args: { quota = bots to keep, timeout = seconds for them to move and fight }
local QUOTA = 6
local START_TIMEOUT, JOIN_TIMEOUT, ENLIST_TIMEOUT, KICK_TIMEOUT = 40, 30, 30, 30
local FIGHT_TIMEOUT = 180
-- A bot has moved once it has walked this far; a step longer than LEAP
-- between two polls is a respawn or a teleport, not walking.
local MOVED, LEAP = 300, 500
local LOWER = 2
local CONVARS = { "tf_bot_quota", "tf_bot_quota_mode", "tf_bot_join_after_player" }
local HOOK = "ws_test_aiwar_bots"

local function Bots(aiwar)
	local list = {}
	for bot in pairs(aiwar.bots) do
		if IsValid(bot) then list[#list + 1] = bot end
	end
	return list
end

return function(t)
	if DrGBase == nil then return t:Skip("DrGBase is not loaded on this server") end
	local quota = t.args.quota or QUOTA
	game.ConsoleCommand("mp_aiwar_start\n")
	local aiwar = t:WaitFor(START_TIMEOUT, function()
		local feature = t:Feature("aiwar")
		return feature and feature.war and feature
	end)
	t:Check("the war starts", aiwar ~= nil, "")
	if not aiwar then return end

	local saved = {}
	for _, name in ipairs(CONVARS) do saved[name] = GetConVarString(name) end
	local function Restore()
		hook.Remove("EntityFireBullets", HOOK)
		for name, value in pairs(saved) do RunConsoleCommand(name, value) end
	end
	RunConsoleCommand("tf_bot_join_after_player", "0")
	RunConsoleCommand("tf_bot_quota_mode", "normal")
	RunConsoleCommand("tf_bot_quota", tostring(quota))

	local joined, waited = t:WaitFor(JOIN_TIMEOUT, function() return #Bots(aiwar) == quota end)
	t:Check("the quota's bots join", joined ~= nil, string.format("%d of %d after %.1f s", #Bots(aiwar), quota, waited))
	if not joined then return Restore() end
	local onTeam = { [WS.TEAM_RED] = 0, [WS.TEAM_BLUE] = 0 }
	for _, bot in ipairs(Bots(aiwar)) do
		local team = WS.TeamOf(bot)
		if onTeam[team] then onTeam[team] = onTeam[team] + 1 end
	end
	t:Check("they are balanced between the teams", math.abs(onTeam[WS.TEAM_RED] - onTeam[WS.TEAM_BLUE]) <= 1,
		string.format("RED %d, BLU %d", onTeam[WS.TEAM_RED], onTeam[WS.TEAM_BLUE]))

	local enlisted = t:WaitFor(ENLIST_TIMEOUT, function()
		for _, bot in ipairs(Bots(aiwar)) do
			if bot:Alive() and not (aiwar.soldiers[bot] and aiwar.soldiers[bot].equipped ~= nil) then return false end
		end
		return true
	end)
	t:Check("every live bot is enlisted with its kit", enlisted ~= nil, "")
	local Arms = WS.require("features.aiwar.arms")
	local unarmed = {}
	for _, bot in ipairs(Bots(aiwar)) do
		local weapon = bot:GetActiveWeapon()
		if bot:Alive() and not (IsValid(weapon) and Arms.WEAPONS[weapon:GetClass()]) then unarmed[#unarmed + 1] = bot:Nick() end
	end
	t:Check("each holds a weapon of its kit", #unarmed == 0, table.concat(unarmed, ", "))

	local shots, walked, last = 0, {}, {}
	hook.Add("EntityFireBullets", HOOK, function(ent)
		local shooter = IsValid(ent) and ent:IsWeapon() and ent:GetOwner() or ent
		if aiwar.bots[shooter] then shots = shots + 1 end
	end)
	local function Walkers()
		local n = 0
		for _, bot in ipairs(Bots(aiwar)) do
			local pos = bot:GetPos()
			local step = last[bot] and pos:Distance(last[bot]) or 0
			if step < LEAP then walked[bot] = (walked[bot] or 0) + step end
			last[bot] = pos
			if (walked[bot] or 0) >= MOVED then n = n + 1 end
		end
		return n
	end
	local fought, fightTime = t:WaitFor(t.args.timeout or FIGHT_TIMEOUT, function()
		return Walkers() * 2 >= quota and shots > 0
	end)
	t:Check("at least half the bots walk under their orders", Walkers() * 2 >= quota,
		string.format("%d of %d walked %d units in %.0f s", Walkers(), quota, MOVED, fightTime))
	t:Check("the bots fire at enemies", shots > 0, string.format("%d bullets", shots))
	t:Info("fight_seconds", fightTime)
	hook.Remove("EntityFireBullets", HOOK)
	if not fought then return Restore() end

	RunConsoleCommand("tf_bot_quota", tostring(LOWER))
	local lowered = t:WaitFor(KICK_TIMEOUT, function() return #Bots(aiwar) == LOWER end)
	t:Check("a lower quota kicks bots down to it", lowered ~= nil, string.format("%d left", #Bots(aiwar)))
	RunConsoleCommand("tf_bot_quota", "0")
	local none = t:WaitFor(KICK_TIMEOUT, function() return #Bots(aiwar) == 0 end)
	t:Check("a quota of 0 leaves no bot", none ~= nil, string.format("%d left", #Bots(aiwar)))
	Restore()
end
