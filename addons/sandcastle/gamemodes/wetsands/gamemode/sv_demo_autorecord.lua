-- Playtest demos on the server: sv_demo_autorecord 1 records every map
-- through SourceTV, every player in the one demo, starting at once and as
-- each map loads; 0 stops. A map's end ends its demo. SourceTV must be up from
-- the server's start (srcds.py start --sourcetv). Demos land in the server's
-- garrysmod/, as playtest_<map>_<date>_<time>.dem (includes.demo_autorecord).
local Demo = WS.require ("includes.demo_autorecord")

-- SourceTV's master is up a moment after the map.
local RECORD_DELAY = 1

local enabled = CreateConVar ("sv_demo_autorecord", "0", FCVAR_ARCHIVE,
	"Record a SourceTV demo of every map (for playtests): 1 starts now, 0 stops. Needs tv_enable 1 from the server's start", 0, 1)

local recording = false

local function Apply ()
	local wanted = enabled:GetBool ()
	if wanted and not GetConVar ("tv_enable"):GetBool () then
		MsgN ("sv_demo_autorecord: SourceTV is off, so no demo is being recorded (start the server with --sourcetv)")
		return
	end
	local action = Demo.Action (wanted, recording)
	if action == Demo.RECORD then
		game.ConsoleCommand ("tv_record " .. Demo.Name (game.GetMap (), os.date (Demo.STAMP)) .. "\n")
	elseif action == Demo.STOP then
		game.ConsoleCommand ("tv_stoprecord\n")
	end
	recording = wanted
end

cvars.AddChangeCallback (enabled:GetName (), Apply, "ws_demo_autorecord")

hook.Add ("InitPostEntity", "ws_demo_autorecord", function ()
	timer.Simple (RECORD_DELAY, Apply)
end)

-- GMod spawns SourceTV's client with a body like any bot's, solid in the map.
hook.Add ("PlayerSpawn", "ws_demo_autorecord", function (ply)
	if not (ply:IsBot () and ply:Nick () == GetConVar ("tv_name"):GetString ()) then return end
	ply:Spectate (OBS_MODE_ROAMING)
	return true
end)
