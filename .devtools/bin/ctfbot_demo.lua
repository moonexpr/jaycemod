-- npc_ctfbot to watch in game, on a server on an MvM map: it is spawned by the bomb,
-- carries it to the zone, and after a pause does it again, each change of its engine
-- stack and the capture said in chat. Sandbox mode, so a watcher can fly: no round or
-- wave comes between it and the bomb.
--   dt gmod lua_run instance=N code="$(cat .devtools/bin/ctfbot_demo.lua)"
--   dt gmod lua_run instance=N code='NSCtfbotDemo.Stop() return "stopped"'
if NSCtfbotDemo then NSCtfbotDemo.Stop () end
local PAUSE = 6
local HOOK = "ns_ctfbot_demo"
local E = nextsoldier.engine
RunConsoleCommand ("sv_gameplay_enabled", "0")
RunConsoleCommand ("mp_timelimit", "0")
RunConsoleCommand ("mp_winlimit", "0")
RunConsoleCommand ("mp_maxrounds", "0")

local demo = { runs = 0, captures = 0, log = {} }
NSCtfbotDemo = demo

local function Say (text)
	demo.log [#demo.log + 1] = string.format ("%.1f %s", CurTime (), text)
	PrintMessage (HUD_PRINTTALK, "[ctfbot] " .. text)
end

local function Shape (frames)
	local parts = {}
	for _, frame in ipairs (frames) do
		if frame.name ~= "CLuaBehaviour" then parts [#parts + 1] = frame.name .. (frame.suspended and "(suspended)" or "") end
	end
	return table.concat (parts, " > ")
end

local bot, last, startedAt, nextRun, taunted, zoneEnt
local TAUNT_AFTER = 6

local function WatchZone ()
	zoneEnt = ents.FindByClass ("func_capturezone") [1]
	if zoneEnt.nsDemoWatched then return end
	zoneEnt.nsDemoWatched = true
	local TriggerOutput = zoneEnt.TriggerOutput
	function zoneEnt:TriggerOutput (name, activator, ...)
		if name == "OnCapture" and activator == bot then
			demo.captures = demo.captures + 1
			Say (string.format ("Bomb delivered in %.0f s. Again in %d s.", CurTime () - startedAt, PAUSE))
			nextRun = CurTime () + PAUSE
		end
		return TriggerOutput (self, name, activator, ...)
	end
end

local function Run ()
	if IsValid (bot) then bot:Remove () end
	WatchZone ()
	local flag = ents.FindByClass ("item_teamflag") [1]
	bot = ents.Create ("npc_ctfbot")
	bot:SetPos (navmesh.GetNearestNavArea (flag:GetPos (), true, 20000, false, false):GetCenter () + Vector (0, 0, 8))
	bot:Spawn ()
	demo.bot = bot
	demo.runs = demo.runs + 1
	startedAt, nextRun, last, taunted = CurTime (), nil, nil, false
	Say ("Run " .. demo.runs .. ": spawned at " .. tostring (bot:GetPos ()))
end

hook.Add ("Tick", HOOK, function ()
	if nextRun and CurTime () >= nextRun then Run () return end
	if not IsValid (bot) then
		if not nextRun then nextRun = CurTime () + 1 end
		return
	end
	local shape = Shape (E.Stack (bot))
	if shape ~= last then
		last = shape
		Say (shape)
	end
	if not taunted and CurTime () - startedAt >= TAUNT_AFTER then
		taunted = true
		E.Command (bot, "taunt")
		Say ("Sent the command: taunt")
	end
end)

function demo.Stop ()
	hook.Remove ("Tick", HOOK)
	if IsValid (bot) then bot:Remove () end
	NSCtfbotDemo = nil
end

nextRun = CurTime () + 1
return "started"
