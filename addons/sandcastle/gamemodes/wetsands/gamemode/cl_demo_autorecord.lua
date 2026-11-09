-- Playtest demos: cl_demo_autorecord 1 records this client's game, starting
-- at once and on every map it joins while on; 0 stops. Demos land in
-- garrysmod/, as playtest_<map>_<date>_<time>.dem (includes.demo_autorecord).
local Demo = WS.require("includes.demo_autorecord")

-- A map's first moments are the client's signon, when record refuses.
local RECORD_DELAY = 1

local enabled = CreateClientConVar("cl_demo_autorecord", "0", true, false,
	"Record a demo of every map you play (for playtests): 1 starts now, 0 stops", 0, 1)

local function Apply()
	local action = Demo.Action(enabled:GetBool(), engine.IsRecordingDemo())
	if action == Demo.RECORD then
		RunConsoleCommand("record", Demo.Name(game.GetMap(), os.date(Demo.STAMP)))
	elseif action == Demo.STOP then
		RunConsoleCommand("stop")
	end
end

cvars.AddChangeCallback(enabled:GetName(), Apply, "ws_demo_autorecord")

-- Only when on: a demo the player began by hand is left alone.
hook.Add("InitPostEntity", "ws_demo_autorecord", function()
	timer.Simple(RECORD_DELAY, function()
		if enabled:GetBool() then Apply() end
	end)
end)
