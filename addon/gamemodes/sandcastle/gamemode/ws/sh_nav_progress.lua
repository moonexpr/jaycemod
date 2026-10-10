-- The nav mesh progress box while mp_nav_generate runs (ws/sv_nav.lua):
-- the server tells every client the stage (foundation.nav_progress), when
-- it began and, done, the areas made; each client shows a WS.UI dialog
-- in the middle of its screen (ws/cl_nav_progress.lua, a cl_ module so
-- it loads after cl_ui). The engine's own progress box (CNavProgress) still
-- opens beside it: GMod gives Lua no hold on it.
local E = WS.Events

local AREA_BITS = 16

E.Define("nav_progress", {
	stage = E.UInt(2),
	started = E.Float(),
	areas = E.UInt(AREA_BITS),
})

if SERVER then
	function WS.NavProgress(stage, started, areas)
		E.Fire("nav_progress", { stage = stage, started = started, areas = areas or 0 })
	end
end
