-- Bot navigation bench (the operator's): a bot soldier is set down at an
-- errand's start and sent (its pin: ns_bots_goto's) to its goal over hard
-- ground: static props' logs and pipes, jumps, drops. Each errand passes
-- when the bot comes within ARRIVE of the goal in its time, and says how
-- long it took and how near it got. The bot cannot be hurt meanwhile; the
-- war goes on around it. Bots join with no human on the server, and the
-- server does not go idle, while it runs.
-- args: { errand = one errand's name, else every one of the map's }
local ARRIVE = 64
local START_TIMEOUT = 40
-- convar -> its value while the bench runs, put back after
local CONVARS = { tf_bot_join_after_player = "0", sv_idle_delay = "86400" }

-- The map's errands: name, from (where the bot is set down), to (its
-- goal), time (seconds it has).
local ERRANDS = {
	arena_watchtower = {
		{ name = "east health pack, up from the ground", from = Vector(1212, 12, 8), to = Vector(1238, -16, 816), time = 60 },
		{ name = "west health pack, up the logs", from = Vector(-1213, 13, 0), to = Vector(-1250, 8, 832), time = 60 },
		{ name = "west pipe to the point, by the stairway", from = Vector(-1250, 8, 848), to = Vector(-2, 1, 760), time = 45 },
	},
}

local function Bot(aiwar)
	for ent, entry in pairs(aiwar.soldiers) do
		if IsValid(ent) and ent:IsPlayer() and ent:Alive() and entry.soldier.Pin then return ent, entry.soldier end
	end
	return nil
end

return function(t)
	local errands = ERRANDS[game.GetMap()]
	if not errands then return t:Skip("no bot navigation errands on " .. game.GetMap()) end
	local saved = {}
	for name, value in pairs(CONVARS) do
		saved[name] = GetConVarString(name)
		RunConsoleCommand(name, value)
	end
	local function Restore()
		for name, value in pairs(saved) do RunConsoleCommand(name, value) end
	end
	if not WS.Feature("aiwar").war then game.ConsoleCommand("mp_aiwar_start\n") end
	local aiwar = t:WaitFor(START_TIMEOUT, function()
		local feature = WS.Feature("aiwar")
		return feature.war and Bot(feature) and feature
	end)
	t:Check("the war has a bot soldier", aiwar ~= nil, "")
	if not aiwar then return Restore() end
	for _, errand in ipairs(errands) do
		if t.args.errand == nil or t.args.errand == errand.name then
			local bot, soldier = Bot(aiwar)
			if not bot then
				t:Check(errand.name, false, "no bot soldier alive")
			else
				bot:GodEnable()
				bot:SetPos(errand.from)
				bot:SetVelocity(-bot:GetVelocity())
				soldier:Pin({ x = errand.to.x, y = errand.to.y, z = errand.to.z })
				local nearest = math.huge
				local arrived, waited = t:WaitFor(errand.time, function()
					if not (IsValid(bot) and bot:Alive()) then return false end
					local d = bot:GetPos():Distance(errand.to)
					if d < nearest then nearest = d end
					return d <= ARRIVE
				end)
				if IsValid(bot) then
					soldier:Unpin()
					bot:GodDisable()
				end
				t:Check(errand.name, arrived ~= nil, string.format("%s in %.1f s; nearest %.0f units", arrived and "arrived" or "not there",
					waited, nearest))
			end
		end
	end
	Restore()
end
