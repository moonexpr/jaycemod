-- Hearing gunfire (TF2's CTFBot::OnWeaponFired): a soldier who hears a shot
-- within RANGE (tf_bot_notice_gunfire_range) turns to look, and its own
-- sight does the rest. An enemy's shot, or one from no side: at the
-- shooter. An ally's: AIM_REACH along its aim, toward what it fights.
-- A listener is { team, pos }; a shot is { team (nil: no side), pos, dir
-- (a unit vector) }.
module(...)

RANGE = 3000
AIM_REACH = 1000

-- Where the listener looks on hearing the shot, or nil when out of earshot.
function LookAt(listener, shot)
	local dx, dy, dz = shot.pos.x - listener.pos.x, shot.pos.y - listener.pos.y, shot.pos.z - listener.pos.z
	if dx * dx + dy * dy + dz * dz > RANGE * RANGE then return nil end
	if shot.team == nil or shot.team ~= listener.team then return shot.pos end
	return {
		x = shot.pos.x + shot.dir.x * AIM_REACH,
		y = shot.pos.y + shot.dir.y * AIM_REACH,
		z = shot.pos.z + shot.dir.z * AIM_REACH,
	}
end
