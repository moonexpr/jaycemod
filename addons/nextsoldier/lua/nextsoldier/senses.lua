-- What a soldier senses: its part vision; here, hearing gunfire.
module ("nextsoldier.senses")

-- Hearing gunfire (TF2's CTFBot::OnWeaponFired): a soldier who hears a shot
-- within HEARING_RANGE (tf_bot_notice_gunfire_range) turns to look, and its
-- own sight does the rest. An enemy's shot, or one from no side: at the
-- shooter. An ally's: HEARING_AIM_REACH along its aim, toward what it fights.
-- A listener is { team, pos }; a shot is { team (nil: no side), pos, dir
-- (a unit vector) }.
HEARING_RANGE = 3000
HEARING_AIM_REACH = 1000

-- Where the listener looks on hearing the shot, or nil when out of earshot.
function HeardLookAt (listener, shot)
	local dx, dy, dz = shot.pos.x - listener.pos.x, shot.pos.y - listener.pos.y, shot.pos.z - listener.pos.z
	if dx * dx + dy * dy + dz * dz > HEARING_RANGE * HEARING_RANGE then return nil end
	if shot.team == nil or shot.team ~= listener.team then return shot.pos end
	return
	{
		x = shot.pos.x + shot.dir.x * HEARING_AIM_REACH,
		y = shot.pos.y + shot.dir.y * HEARING_AIM_REACH,
		z = shot.pos.z + shot.dir.z * HEARING_AIM_REACH
	}
end
