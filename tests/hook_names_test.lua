-- Every hook the addons listen on is one something fires: GMod's own (and
-- the libraries' and game events' below), or one of Sandcastle's, named WS
-- or run by name in the addons. A listener on a name nothing fires never
-- runs and raises no error: sv_hits on "PreEntityTakeDamage", which GMod
-- has not, took every hit sound, damage number and kill credit with it.
local T = dofile("tests/harness.lua")

-- The hooks GMod (and ULib, and gameevent.Listen's events) fire that the
-- addons listen on; a new one is added here once checked on the GMod wiki.
local FIRED_ELSEWHERE = {}
for _, name in ipairs({
	"AcceptInput", "CalcView", "CreateClientsideRagdoll", "CreateEntityRagdoll", "EntityFireBullets",
	"EntityKeyValue", "EntityNetworkedVarChanged", "EntityRemoved", "EntityTakeDamage", "GetFallDamage",
	"HUDPaint", "InitPostEntity", "KeyPress", "OnContextMenuOpen", "OnEntityCreated", "OnScreenSizeChanged",
	"PlayerBindPress", "PlayerDeath", "PlayerDeathSound", "PlayerDeathThink", "PlayerDisconnected",
	"PlayerEndVoice", "PlayerFootstep", "PlayerHurt", "PlayerInitialSpawn", "PlayerLoadout",
	"PlayerRequestTeam", "PlayerSpawn", "PlayerStartVoice", "PopulateMenuBar", "PopulateToolMenu",
	"PostCleanupMap", "PostDrawTranslucentRenderables", "PostEntityTakeDamage", "PostPlayerDeath",
	"PostPlayerDraw", "PostRender", "PreCleanupMap", "PreDrawHUD", "PreDrawViewModel", "PreRender",
	"RenderScreenspaceEffects", "SetupMove", "SetupPlayerVisibility", "ShouldCollide", "ShowSpare2",
	"ShowTeam", "ShutDown", "StartCommand", "Think", "Tick", "TranslateActivity",
	"UCLAuthed", -- ULib
	"player_disconnect", -- a game event (gameevent.Listen)
}) do
	FIRED_ELSEWHERE[name] = true
end

local function Lines(command)
	local pipe = assert(io.popen(command))
	local lines = {}
	for line in pipe:lines() do lines[#lines + 1] = line end
	pipe:close()
	return lines
end

local function Read(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

-- name -> the first file listening on it, and the names run by name.
local listened, run = {}, {}
for _, path in ipairs(Lines("find addons -name '*.lua' -not -path '*/vendor/*'")) do
	local text = Read(path)
	for name in text:gmatch('hook%.Add%(%s*"([^"]+)"') do listened[name] = listened[name] or path end
	for name in text:gmatch('hook%.Run%(%s*"([^"]+)"') do run[name] = true end
	for name in text:gmatch('hook%.Call%(%s*"([^"]+)"') do run[name] = true end
end

local function Fired(name)
	return FIRED_ELSEWHERE[name] or run[name] or name:find("^WS") ~= nil
end

T.test("every hook listened on is one something fires", function()
	local names = {}
	for name in pairs(listened) do names[#names + 1] = name end
	table.sort(names)
	T.eq(#names > 0, true, "the scan found listeners")
	for _, name in ipairs(names) do
		T.eq(Fired(name), true, name .. " (" .. listened[name] .. ")")
	end
end)

T.test("a name GMod has not is caught", function()
	T.eq(Fired("PreEntityTakeDamage"), false, "PreEntityTakeDamage")
end)

T.finish()
