-- The nav mesh progress box while mp_nav_generate runs (ws/sv_nav.lua):
-- the server tells every client the progress alone, the stage
-- (foundation.nav_progress) and, done, the areas made, and a client that
-- loads while it runs the stage it missed. Everything else is the
-- client's: each shows a WS.UI dialog in the middle of its screen
-- (ws/cl_nav_progress.lua, a cl_ module so it loads after cl_ui), timed by
-- its own clock, which hides the engine's own progress box (CNavProgress)
-- while it shows.
local E = WS.Events

local AREA_BITS = 16

E.Define("game_nav_progress", {
	stage = E.UInt(2),
	areas = E.UInt(AREA_BITS),
})

if SERVER then
	local P = WS.require("foundation.nav_progress")
	-- The stage last told, for a client that loads while it runs; kept on
	-- WS so a Lua refresh mid-run keeps it.
	function WS.NavProgress(stage, areas)
		local fields = { stage = stage, areas = areas or 0 }
		WS.NavProgressRunning = stage ~= P.DONE and fields or nil
		E.Fire("game_nav_progress", fields)
	end

	E.Listen("system_client_ready", "ws_nav_progress", function(_, ply)
		if WS.NavProgressRunning then E.Fire("game_nav_progress", WS.NavProgressRunning, ply) end
	end)
end
