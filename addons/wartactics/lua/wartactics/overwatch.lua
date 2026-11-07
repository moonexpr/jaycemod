-- Overwatch: what a squad's director answers its leader's request to vacate the place it holds (a
-- guard gone missing, the squad stacked up to go and see), from the squad's situation:
--   contact          an enemy met: DEFEND, lying in wait for it (plan AMBUSH)
--   too few          fewer than VACATE_FLOOR left: STANDBY, the squad standing down where it is
--   lost again       ATTACK_AFTER guards or more lost: ATTACK where the enemy comes from (target),
--                    or with nowhere known, DEFEND in ambush
--   else             VACATE: clear to go and see
-- Decide(situation) -> { kind, plan?, target? }; situation: { size (the squad placed), lost (its
-- casualties), missing (guards lost holding this place, this one counted), contact (an enemy met),
-- target (where to strike, or nil) }. The answer is the squad's; the mode hosting it gives the
-- order that comes with DEFEND or ATTACK.
module(...)

VACATE_FLOOR, ATTACK_AFTER = 3, 2

function Decide(situation)
	if situation.contact then return { kind = "DEFEND", plan = "AMBUSH" } end
	if situation.size - situation.lost < VACATE_FLOOR then return { kind = "STANDBY" } end
	if situation.missing >= ATTACK_AFTER then
		if situation.target then return { kind = "ATTACK", target = situation.target } end
		return { kind = "DEFEND", plan = "AMBUSH" }
	end
	return { kind = "VACATE" }
end
