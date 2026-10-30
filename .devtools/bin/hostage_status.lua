-- The hostage rescue match at a glance, for `dt lua [--instance N] -f
-- .devtools/bin/hostage_status.lua`: the rounds state, each hostage's state,
-- place and rescuer, and each soldier of the war with its squad, the hostage
-- group the squad owns, its stage, where it is and where it is going.
local war = WS.Feature("aiwar").war
local snapshot = WS.Feature("hostage"):Snapshot()
local rounds = WS.Feature("rounds")

local function Where(p)
	if not p then return "-" end
	return string.format("(%d,%d)", p.x, p.y)
end

local hostages = {}
for _, h in ipairs(snapshot) do
	hostages[#hostages + 1] = string.format("%s %s %s%s", h.id, h.state, Where(h.pos),
		h.rescuer and (" led by " .. tostring(h.rescuer:Nick())) or "")
end

local soldiers = { red = 0, blu = 0 }
local members = {}
if war then
	local field = WS.Feature("aiwar"):Field("running", CurTime())
	WS.Feature("aiwar").scenario:Brief(field, CurTime())
	for _, m in ipairs(war:Members()) do
		local ent = m.handle
		local alive = IsValid(ent) and ent:Health() > 0
		if alive then
			if m.team == WS.TEAM_RED then soldiers.red = soldiers.red + 1 else soldiers.blu = soldiers.blu + 1 end
		end
		local role = field.doctrine and field.doctrine.ROLES[m.role]
		local ok, stage, goal = pcall(function()
			return role.Stage(field, m), role.Goal(field, m)
		end)
		members[#members + 1] = string.format("%s %s group=%s %s at %s stage=%s goal=%s speed=%d",
			m.team == WS.TEAM_RED and "RED" or "BLU", IsValid(ent) and ent:Nick() or "?",
			tostring(m.fireTeam and m.fireTeam.groupIndex), alive and "alive" or "dead",
			Where(IsValid(ent) and ent:GetPos()), ok and tostring(stage) or "?", ok and Where(goal) or "?",
			IsValid(ent) and ent:GetVelocity():Length() or 0)
	end
end

return util.TableToJSON({
	state = rounds:State(),
	winner = WS.Feature("aiwar").winner,
	reason = GetGlobal2Int("ws_round_win_reason", 0),
	hostages = hostages,
	alive = soldiers,
	members = members,
})
