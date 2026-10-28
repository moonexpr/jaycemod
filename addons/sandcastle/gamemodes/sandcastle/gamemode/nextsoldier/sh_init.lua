-- NextSoldier: the soldier itself, which runs without the war's tactics
-- engine (wartactics/): how a soldier moves (doors, leaps, rappels, its
-- route), what it senses (sight, hearing), its body, voice and behaviours,
-- each loaded the first time it is read; the path costs it moves by are
-- foundation.wetsands.path. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local nextsoldier = Namespace("nextsoldier")
Defer(nextsoldier, "base", "nextsoldier.base")
Defer(nextsoldier, "speech", "nextsoldier.speech")
Defer(nextsoldier, "hearing", "nextsoldier.hearing")
Defer(nextsoldier, "nav_gaps", "nextsoldier.nav_gaps")
Defer(nextsoldier, "brushes", "nextsoldier.brushes")
Defer(nextsoldier, "clip", "nextsoldier.clip")
Defer(nextsoldier, "detour", "nextsoldier.detour")
Defer(nextsoldier, "doors", "nextsoldier.doors")
Defer(nextsoldier, "leap", "nextsoldier.leap")
Defer(nextsoldier, "noise", "nextsoldier.noise")
Defer(nextsoldier, "portal", "nextsoldier.portal")
Defer(nextsoldier, "probe", "nextsoldier.probe")
Defer(nextsoldier, "rappel", "nextsoldier.rappel")
Defer(nextsoldier, "reach_memo", "nextsoldier.reach_memo")
Defer(nextsoldier, "route_record", "nextsoldier.route_record")
Defer(nextsoldier, "vision", "nextsoldier.vision")
Defer(nextsoldier, "monitor", "nextsoldier.monitor")
Defer(nextsoldier, "player_body", "nextsoldier.player_body")
Defer(nextsoldier, "route_walk", "nextsoldier.route_walk")
