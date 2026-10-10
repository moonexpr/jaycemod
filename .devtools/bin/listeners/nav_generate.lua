-- Follows mp_nav_generate (wetsand/sv_nav.lua) to its end: opening the
-- doors (its wetsand_nav_generate timer runs), generating (navmesh says so),
-- then done, with the areas it made. Arm it before running the command:
--   server_watch.py --listen nav_generate --run mp_nav_generate
local POLL = "wetsand_nav_generate" -- sv_nav.lua's timer, from the command until it is done
local began = false

Watch.Task("nav_generate", {
	every = 2,
	timeout = 1800,
	progress = function()
		if navmesh.IsGenerating() then
			began = true
			return "generating"
		end
		if timer.Exists(POLL) then
			began = true
			return "opening doors"
		end
		return began and "finishing" or "waiting for mp_nav_generate"
	end,
	done = function()
		if not began or navmesh.IsGenerating() or timer.Exists(POLL) then return false end
		return true, navmesh.GetNavAreaCount() .. " areas, saved as maps/" .. game.GetMap() .. ".nav"
	end,
})
