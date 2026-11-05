-- The bench war (Controller:Start{ bench = true }): the war's models and orders for the Tactical
-- Behavior Tool's squad followers alone, without what brings soldiers or changes the game.
local T = dofile("tests/harness.lua")

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

local AIWAR = T.ROOT .. "features/aiwar/"
local war, bots, field, enlist = ReadFile(AIWAR .. "sv_war.lua"), ReadFile(AIWAR .. "sv_bots.lua"),
	ReadFile(AIWAR .. "sv_field.lua"), ReadFile(AIWAR .. "sv_enlist.lua")
local stool = ReadFile(T.ROOT .. "../entities/weapons/gmod_tool/stools/ns_tacticalbehavior.lua")
local follower = ReadFile(T.ROOT .. "../entities/entities/npc_squadfollower.lua")

T.test("a bench war is started as the war is, by its own call", function()
	T.eq(war:find("function Controller:Start(opts)", 1, true) ~= nil, true, "Start takes it")
	T.eq(war:find("self.bench = opts and opts.bench or nil", 1, true) ~= nil, true, "and keeps it")
end)

T.test("it leaves the gamemode, the map's other NPCs and the notices be", function()
	T.eq(war:find("if not self.bench then WS.Feature(\"gamemode\"):Request(", 1, true) ~= nil, true, "no gameplay request")
	T.eq(war:find("if not self.bench then self:Consider(ent) end", 1, true) ~= nil, true, "no NPC enlisted at the start")
	T.eq(enlist:find("if self.bench then return end", 1, true) ~= nil, true, "nor as they come")
end)

T.test("it brings no bots and drafts no waves", function()
	T.eq(bots:find("if not Controller.bench then\n\t\t\tController:MaintainBotQuota()", 1, true) ~= nil, true, "no quota")
	T.eq(field:find("if field.phase.reinforce and not self.bench then self:Reinforce(now) end", 1, true) ~= nil, true, "no waves")
end)

T.test("the tool starts one for its first squad follower, and the last one gone ends it", function()
	T.eq(stool:find("controller:Start({ bench = true })", 1, true) ~= nil, true, "started")
	T.eq(follower:find("WS.Feature(\"aiwar\"):EndBenchWhenEmpty(self)", 1, true) ~= nil, true, "ended")
	T.eq(war:find("function Controller:EndBenchWhenEmpty(leaving)", 1, true) ~= nil, true, "only a bench war")
end)

T.finish()
