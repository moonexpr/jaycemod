-- A census of who gets stuck, for `dt lua [--instance N] -f
-- .devtools/bin/stuck_census.lua`: installs (again: starts over) a sampler
-- that every SAMPLE seconds looks at each bot soldier with a route to walk
-- and each hostage following a rescuer farther than FOLLOW_FAR, and records
-- one that moved less than MOVED in WINDOW seconds, with where. Read it with
-- .devtools/bin/stuck_report.lua.
local SAMPLE, WINDOW, MOVED, FOLLOW_FAR = 2, 8, 32, 150

StuckCensus = { started = CurTime(), events = {}, rounds = 0, map = game.GetMap() }
local census = StuckCensus
local history = {} -- ent -> { { t, pos }, ... } over the last WINDOW
local stuck = {} -- ent -> the event it is in, while it stays stuck

local function Track(ent, kind, name, busy)
	local now, pos = CurTime(), ent:GetPos()
	local h = history[ent] or {}
	history[ent] = h
	if not busy then
		for i = #h, 1, -1 do h[i] = nil end
		stuck[ent] = nil
		return
	end
	h[#h + 1] = { t = now, pos = pos }
	while #h > 1 and now - h[1].t > WINDOW do table.remove(h, 1) end
	local first = h[1]
	if now - first.t < WINDOW - SAMPLE then return end
	if first.pos:Distance(pos) < MOVED then
		local event = stuck[ent]
		if event then
			event.until_ = now
		else
			event = { kind = kind, name = name, from = now - WINDOW, until_ = now,
				pos = { math.Round(pos.x), math.Round(pos.y), math.Round(pos.z) },
				area = (function() local a = navmesh.GetNearestNavArea(pos, false, 64) return a and a:GetID() end)() }
			stuck[ent] = event
			census.events[#census.events + 1] = event
		end
	else
		stuck[ent] = nil
	end
end

-- Only while a round runs: before it, and while the round's start holds
-- players frozen (ply:Freeze), no one is stuck.
local RUNNING = { [7] = true, [4] = true } -- STALEMATE (arena, hostage), RND_RUNNING

timer.Create("stuck_census", SAMPLE, 0, function()
	local running = RUNNING[WS.Feature("rounds"):State()] == true
	for ent, entry in pairs(WS.Feature("aiwar").soldiers or {}) do
		if IsValid(ent) and ent:IsPlayer() and ent:Alive() then
			local soldier = entry.soldier
			local walk = soldier.walk
			local busy = running and not ent:IsFrozen() and walk ~= nil and not walk:Done() and soldier.moveTarget ~= nil
				and soldier.pin == nil
			Track(ent, "bot", ent:Nick(), busy)
		end
	end
	for _, h in ipairs(ents.FindByClass("hostage_entity")) do
		local leader = h.leader
		local busy = running and not h.rescued and IsValid(leader) and h:GetPos():Distance(leader:GetPos()) > FOLLOW_FAR
		Track(h, "hostage", "hostage " .. h:EntIndex(), busy)
	end
end)

hook.Add("WSRoundActivate", "stuck_census", function() census.rounds = census.rounds + 1 end)

-- What became of the armed hostage's pistol: each change of hands, in order.
census.pistols = {}
local lastPistol
timer.Create("stuck_census_pistol", 0.5, 0, function()
	local pistol = WS.Feature("hostage").pistol
	local now = pistol and (pistol:Holder() and ("held by " .. pistol:Holder()) or "lying") or "none"
	if now ~= lastPistol then
		lastPistol = now
		census.pistols[#census.pistols + 1] = string.format("%.0f s: %s", CurTime() - census.started, now)
	end
end)

return "census started on " .. census.map
