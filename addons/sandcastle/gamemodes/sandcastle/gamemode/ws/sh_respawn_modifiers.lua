-- Respawn modifiers' event, shared. What moved a dead player's respawn
-- (foundation.respawn_modifiers; ws/sv_respawn_modifiers.lua works it out),
-- told to them as they die: each reason, the seconds the respawn moved in
-- all, and whether a limit cut them. ws/cl_spawn_manager.lua shows them
-- under the bar.
local E = WS.Events
local MODIFIER_COUNT_BITS = 4 -- up to 15 reasons
E.Define("game_respawn_modifiers", {
	modifiers = E.List(E.Record({
		reason = E.String(),
		count = E.UInt(8),
		seconds = E.Float(),
	}), MODIFIER_COUNT_BITS),
	total = E.Float(),
	limited = E.Bool(),
})
