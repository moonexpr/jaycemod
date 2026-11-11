-- The Path Follower stool's Tactical mode on a live server, read back as data: followers put in
-- the war on BLU start a bench war; they form one squad with its feet held; it is given a lane job,
-- a contact, its lanes off and on, a post and a rally marked; back on their legs, the last out ends the war.
-- Leaves nothing behind. Run it, wait, then read the result:
--   python3 .devtools/bin/instances.py MAP - < .devtools/bin/tactical_behavior_check.lua
--   python3 .devtools/bin/instances.py MAP 'return NSTacticalCheck'
local STEP = 3
local COUNT = 3
-- a lane job on any map's scenario (wartactics.lanes.JOBS): CTF has no escorts
local JOB = "explore"

local Controller = WS.Feature ("aiwar")
local Marks = WS.require ("features.aiwar.marks")
local Tactics = wartactics.fireteam
local team = WS.TEAM_BLUE

RunConsoleCommand ("mp_winlimit",  "0")
RunConsoleCommand ("mp_timelimit", "0")
RunConsoleCommand ("mp_maxrounds", "0")

local lines, followers = {}, {}
local function Note (text) lines [#lines + 1] = text end

local function Spot ()
	local spawns = ents.FindByClass ("info_player_teamspawn")
	for _, spawn in ipairs (spawns) do
		if spawn:GetInternalVariable ("TeamNum") == team then
			local area = navmesh.GetNearestNavArea (spawn:GetPos ())
			if IsValid (area) then return area:GetCenter () end
		end
	end
	return navmesh.GetAllNavAreas () [1]:GetCenter ()
end

local function Members ()
	local out = {}
	for i, ent in ipairs (followers) do
		local entry = IsValid (ent) and Controller.soldiers [ent]
		local member = entry and Controller.war and Controller.war:Member (ent)
		local soldier = entry and entry.soldier
		local fireTeam = member and member.fireTeam
		local target = soldier and soldier.moveTarget
		local path = IsValid (ent) and ent:GetPath ()
		out [i] = string.format ("#%d role %s squad %s lane %s lanesOff %s | target %s | moved %.0f | held %s path %s",
			IsValid (ent) and ent:EntIndex () or -1, tostring (member and member.role), tostring (fireTeam and fireTeam.index),
			tostring (fireTeam and fireTeam.lane and fireTeam.lane.kind), tostring (fireTeam and fireTeam.lanesOff),
			target and string.format ("%.0f,%.0f,%.0f", target.x, target.y, target.z) or "none",
			IsValid (ent) and ent:GetPos ():Distance (ent.nsCheckFrom) or -1, tostring (IsValid (ent) and ent.NSFeetHeld),
			tostring (path and path:IsValid ()))
	end
	return table.concat (out, "\n")
end

local function FireTeam ()
	local member = Controller.war:Member (followers [1])
	return member and member.fireTeam
end

NSTacticalCheck = "running"
local at = Spot ()
local steps =
{
	function ()
		-- the dev server's server.cfg starts a war on every map: a bench war starts only with none
		Note ("war before: " .. tostring (Controller.war ~= nil))
		if Controller.war then Controller:End () end
		-- the war's orders run only while a round does; an empty server's waits between rounds,
		-- so the round is put running as a scenario's restore puts it
		if WS.Active () and WS.State () ~= 4 then
			dev.harness.enable (true)
			dev.harness.set_round_state ("RND_RUNNING")
			dev.harness.enable (false)
		end
		Note ("round state " .. tostring (WS.State ()))
		for i = 1, COUNT do
			local ent = ents.Create ("npc_pathfollower")
			ent.NSToolManaged = true
			ent:SetPos (at + Vector (i * 60, 0, 1))
			ent:Spawn ()
			ent:Activate ()
			ent.nsCheckFrom = ent:GetPos ()
			ent:NSSetTeam (team)
			-- the first into the war starts a bench war
			local ok, why = ent:NSSetDriver ("war")
			if i == 1 then
				Note (string.format ("into the war: %s %s; bench %s; bots %d", tostring (ok), tostring (why), tostring (Controller.bench), #player.GetBots ()))
			end
			ent:NSHoldFeet (true)
			followers [i] = ent
		end
	end,
	function ()
		local indexes = {}
		for i, ent in ipairs (followers) do indexes [i] = ent:EntIndex () end
		Note ("squad: " .. table.concat (Controller:FormSquadOf (indexes), "; "))
		Note ("job: " .. table.concat (Controller:AssignJob (JOB, indexes), "; "))
	end,
	function () Note (JOB .. ", LANES ON\n" .. Members ()) FireTeam ().lanesOff = true end,
	function ()
		Note ("LANES OFF\n" .. Members ())
		FireTeam ().lanesOff = nil
		local enemy = at + Vector (900, 0, 0)
		Tactics.Report (FireTeam (), { x = enemy.x, y = enemy.y, z = enemy.z }, CurTime ())
	end,
	function ()
		Note ("CONTACT\n" .. Members ())
		Controller:Mark (Marks.POST,  team, { x = at.x, y = at.y + 300, z = at.z })
		Controller:Mark (Marks.RALLY, team, { x = at.x - 200, y = at.y, z = at.z })
		wartactics.mission.Recall (FireTeam (), wartactics.mission.CASUALTIES)
	end,
	function ()
		local field = Controller.war:Field ()
		Note (string.format ("MARKED: field posts %s, rallies %s\n%s",
			tostring (field.posts [team] and #field.posts [team]), tostring (field.rallies [team] and #field.rallies [team]), Members ()))
		Controller:Unmark ({ x = at.x, y = at.y + 300, z = at.z }, 64)
		Controller:Unmark ({ x = at.x - 200, y = at.y, z = at.z }, 64)
		-- out of the war again: the last out ends the bench war
		for _, ent in ipairs (followers) do ent:NSSetDriver ("legs") end
		Note (string.format ("all to their legs: war %s, drivers %s, stacks %s", tostring (Controller.war ~= nil),
			followers [1]:NSDriver (), (function ()
				local names = {}
				for i, frame in ipairs (nextsoldier.engine.Stack (followers [1])) do names [i] = frame.name end
				return table.concat (names, " > ")
			end) ()))
		for _, ent in ipairs (followers) do ent:Remove () end
	end,
	function ()
		Note (string.format ("all removed: war %s, bench %s, bots %d", tostring (Controller.war ~= nil),
			tostring (Controller.bench), #player.GetBots ()))
		NSTacticalCheck = table.concat (lines, "\n\n")
	end
}
for i, step in ipairs (steps) do timer.Simple (i * STEP, function ()
	local ok, err = pcall (step)
	if not ok then Note ("STEP " .. i .. " FAILED: " .. tostring (err)) NSTacticalCheck = table.concat (lines, "\n\n") end
end) end
return "started at " .. tostring (at) .. " on " .. game.GetMap ()
