-- The bench war (Controller:Start{ bench = true }): the war's models and orders for the path
-- followers the Path Follower tool puts in the war, without what brings soldiers or changes the game.
local T = dofile ("tests/harness.lua")

local function ReadFile (path)
	local f = assert (io.open (path, "r"))
	local text = f:read ("*a")
	f:close ()
	return text
end

local AIWAR = T.ROOT .. "features/aiwar/"
local war, bots, field, enlist = ReadFile (AIWAR .. "sv_war.lua"), ReadFile (AIWAR .. "sv_bots.lua"),
ReadFile (AIWAR .. "sv_field.lua"), ReadFile (AIWAR .. "sv_enlist.lua")
local follower = ReadFile (T.ROOT .. "../entities/entities/npc_pathfollower.lua")

T.test ("a bench war is started as the war is, by its own call", function ()
	T.eq (war:find ("function Controller:Start (opts)", 1, true) ~= nil, true, "Start takes it")
	T.eq (war:find ("self.bench = opts and opts.bench or nil", 1, true) ~= nil, true, "and keeps it")
end)

T.test ("it leaves the gamemode, the map's other NPCs and the notices be", function ()
	T.eq (war:find ("if not self.bench then WS.Feature (\"gamemode\"):Request (", 1, true) ~= nil, true, "no gameplay request")
	T.eq (war:find ("if not self.bench then self:Consider (ent) end", 1, true) ~= nil, true, "no NPC enlisted at the start")
	T.eq (enlist:find ("if self.bench then return end", 1, true) ~= nil, true, "nor as they come")
end)

T.test ("it brings no bots and drafts no waves", function ()
	T.eq (bots:find ("if not Controller.bench then\n\t\t\tController:MaintainBotQuota ()", 1, true) ~= nil, true, "no quota")
	T.eq (field:find ("if field.phase.reinforce and not self.bench then self:Reinforce (now) end", 1, true) ~= nil, true, "no waves")
end)

T.test ("a follower put in the war starts one when none runs, and the last soldier gone ends it", function ()
	T.eq (follower:find ("controller:Start ({ bench = true })", 1, true) ~= nil, true, "started")
	T.eq (follower:find ("controller:EndBenchWhenEmpty (self)", 1, true) ~= nil, true, "ended")
	T.eq (war:find ("function Controller:EndBenchWhenEmpty (leaving)", 1, true) ~= nil, true, "only a bench war")
	T.eq (war:find ("npc_squadfollower", 1, true), nil, "by its soldiers, of whatever class")
end)

T.finish ()
