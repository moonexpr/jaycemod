-- npc_ctfbot on a live server on an MvM map, as returned data: it is spawned by the
-- bomb and given it, its engine stack recorded each time it changes, told to taunt
-- partway, and watched to the capture.
--   dt gmod lua_run instance=N code="$(cat .devtools/bin/ctfbot_check.lua)"
--   dt gmod lua_run instance=N code='return NSCtfbotCheck.Report()'
local E = nextsoldier.engine
local flagEnt = ents.FindByClass("item_teamflag")[1]
local zoneEnt = ents.FindByClass("func_capturezone")[1]
local flagFeature = flagEnt.flag
local goal = zoneEnt:LocalToWorld(zoneEnt:OBBCenter())
local TAUNT_AFTER = 6

local report = { stacks = {}, flag = {}, captured = false, taunted = false, travelled = 0, seen = {} }
NSCtfbotCheck = report

local area = navmesh.GetNearestNavArea(flagEnt:GetPos(), true, 20000, false, false)
local bot = ents.Create("npc_ctfbot")
bot:SetPos(area:GetCenter() + Vector(0, 0, 8))
bot:Spawn()
NSCtfbot = bot
report.from = tostring(bot:GetPos())
report.start_distance = bot:GetPos():Distance(goal)

local function Shape(frames)
	local parts = {}
	for _, frame in ipairs(frames) do
		parts[#parts + 1] = string.rep(">", frame.depth - 1) .. frame.name .. (frame.suspended and "(s)" or "")
	end
	return table.concat(parts, " ")
end

-- the capture itself: the zone firing its output, not the flag going home
local TriggerOutput = zoneEnt.TriggerOutput
function zoneEnt:TriggerOutput(name, activator, ...)
	if name == "OnCapture" then report.captured = activator == bot end
	return TriggerOutput(self, name, activator, ...)
end
local spawned, last, lastFlag, lastPos = CurTime(), nil, nil, bot:GetPos()
hook.Add("Tick", "ns_ctfbot_check", function()
	if not IsValid(bot) then hook.Remove("Tick", "ns_ctfbot_check") return end
	local now = CurTime() - spawned
	local shape = Shape(E.Stack(bot))
	if shape ~= last then
		last = shape
		report.stacks[#report.stacks + 1] = string.format("%.1f %s", now, shape)
	end
	local model = flagFeature:FlagAt(flagEnt)
	local state = model:State() .. (model:Carrier() == bot and " by the bot" or "")
	if state ~= lastFlag then
		lastFlag = state
		report.flag[#report.flag + 1] = string.format("%.1f %s, %.0f from the zone", now, state, bot:GetPos():Distance(goal))
	end
	report.travelled = report.travelled + bot:GetPos():Distance(lastPos)
	lastPos = bot:GetPos()
	report.at, report.distance, report.seconds = tostring(bot:GetPos()), bot:GetPos():Distance(goal), now
	if not report.taunted and now >= TAUNT_AFTER then
		report.taunted = true
		E.Command(bot, "taunt")
	end
end)

function report.Report()
	return util.TableToJSON({
		stacks = report.stacks, flag = report.flag, captured = report.captured, taunted = report.taunted,
		from = report.from, at = report.at, start_distance = report.start_distance, distance = report.distance,
		travelled = report.travelled, seconds = report.seconds, live = E.Live(), hurry = IsValid(bot) and E.ShouldHurry(bot),
	})
end

return "started"
