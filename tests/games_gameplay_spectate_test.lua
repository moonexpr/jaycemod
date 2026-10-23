local T = dofile("tests/harness.lua")
local S = gameplay.spectate
local Teams = gameplay.teams

local NOBODY, SPEC, RED, BLU = Teams.UNASSIGNED, Teams.SPECTATOR, Teams.RED, Teams.BLUE
local TIMES = S.TIMES

-- Death phases (CTFPlayer::StateThinkDYING) ------------------------------------

T.test("deathcam for the death animation", function()
	T.eq(S.DeathPhase(10, 10, true, false), "deathcam")
	T.eq(S.DeathPhase(11.99, 10, true, false), "deathcam")
end)

T.test("freezecam on the killer after the death animation", function()
	T.eq(S.DeathPhase(12, 10, true, false), "freezecam")
	T.eq(S.DeathPhase(16.39, 10, true, false), "freezecam")
end)

T.test("observer once the freezecam is over", function()
	T.eq(S.DeathPhase(16.4, 10, true, false), "observer")
end)

T.test("no freezecam without a killer: deathcam until the freeze would have ended", function()
	T.eq(S.DeathPhase(13, 10, false, false), "deathcam")
	T.eq(S.DeathPhase(16.4, 10, false, false), "observer")
end)

T.test("an aborted freezecam goes straight to observer", function()
	T.eq(S.DeathPhase(13, 10, true, true), "observer")
end)

T.test("no death time means observing from the start (spectator team)", function()
	T.eq(S.DeathPhase(5, nil, false, false), "observer")
end)

T.test("freezecam may be aborted only after travel plus half a second", function()
	T.eq(S.CanAbortFreezeCam(12.89, 10), false)
	T.eq(S.CanAbortFreezeCam(12.9, 10), true)
end)

T.test("freezecam sound starts so it ends at lock-on", function()
	T.near(S.FreezeSoundTime(10), 12.1, 1e-9)
end)

T.test("times are TF2's", function()
	T.eq(TIMES.deathAnim, 2.0)
	T.eq(TIMES.freezeTravel, 0.4)
	T.eq(TIMES.freezeTime, 4.0)
end)

-- Mode cycling (spec_mode + CTFPlayer::SetObserverMode) --------------------------

T.test("team players cycle first person and third person", function()
	T.eq(S.NextMode("in_eye", false), "chase")
	T.eq(S.NextMode("chase", false), "in_eye")
end)

T.test("spectators also get free roam", function()
	T.eq(S.NextMode("in_eye", true), "chase")
	T.eq(S.NextMode("chase", true), "roaming")
	T.eq(S.NextMode("roaming", true), "in_eye")
end)

T.test("fixed moves on to first person", function()
	T.eq(S.NextMode("fixed", false), "in_eye")
	T.eq(S.NextMode("fixed", true), "in_eye")
end)

T.test("team players never keep roaming", function()
	T.eq(S.NextMode("roaming", false), "in_eye")
end)

-- The mode actually shown for a target ------------------------------------------

T.test("observer points are fixed cameras", function()
	T.eq(S.ViewMode("in_eye", "point"), "fixed")
	T.eq(S.ViewMode("chase", "point"), "fixed")
end)

T.test("roaming from an observer point flies free from it", function()
	T.eq(S.ViewMode("roaming", "point"), "roaming")
end)

T.test("non-player entities cannot be watched in first person", function()
	T.eq(S.ViewMode("in_eye", "entity"), "chase")
	T.eq(S.ViewMode("chase", "entity"), "chase")
end)

T.test("players keep the chosen mode", function()
	T.eq(S.ViewMode("in_eye", "player"), "in_eye")
	T.eq(S.ViewMode("chase", "player"), "chase")
	T.eq(S.ViewMode("roaming", "player"), "roaming")
end)

T.test("NPCs keep the chosen mode, first person too", function()
	T.eq(S.ViewMode("in_eye", "npc"), "in_eye")
	T.eq(S.ViewMode("chase", "npc"), "chase")
	T.eq(S.ViewMode("roaming", "npc"), "roaming")
end)

T.test("no target: roam if roaming, else hold a fixed view", function()
	T.eq(S.ViewMode("roaming", nil), "roaming")
	T.eq(S.ViewMode("chase", nil), "fixed")
	T.eq(S.ViewMode("in_eye", nil), "fixed")
end)

-- Valid targets (CTFPlayer::IsValidObserverTarget, CObserverPoint::CanUseObserverPoint)

local function rules(over)
	local r = { forcecamera = S.FORCE_TEAM, teamWin = false, now = 100 }
	for k, v in pairs(over or {}) do r[k] = v end
	return r
end
local redViewer = { id = "me", team = RED }
local specViewer = { id = "me", team = SPEC }

local function player(team, extra)
	local p = { id = {}, kind = "player", team = team, alive = true }
	for k, v in pairs(extra or {}) do p[k] = v end
	return p
end
local function point(extra)
	local p = { id = {}, kind = "point", team = NOBODY, enabled = true }
	for k, v in pairs(extra or {}) do p[k] = v end
	return p
end

T.test("nothing and yourself are never valid", function()
	T.eq(S.IsValidTarget(redViewer, nil, rules()), false)
	T.eq(S.IsValidTarget(redViewer, player(RED, { id = "me" }), rules()), false)
end)

T.test("mp_forcecamera 1 keeps dead players on their own team", function()
	T.eq(S.IsValidTarget(redViewer, player(RED), rules()), true)
	T.eq(S.IsValidTarget(redViewer, player(BLU), rules()), false)
end)

T.test("mp_forcecamera 0 allows the enemy", function()
	T.eq(S.IsValidTarget(redViewer, player(BLU), rules({ forcecamera = S.FORCE_ALL })), true)
end)

T.test("mp_forcecamera 2 allows no one", function()
	T.eq(S.IsValidTarget(redViewer, player(RED), rules({ forcecamera = S.FORCE_NONE })), false)
end)

T.test("spectators may watch anyone regardless of mp_forcecamera", function()
	T.eq(S.IsValidTarget(specViewer, player(BLU), rules({ forcecamera = S.FORCE_NONE })), true)
	T.eq(S.IsValidTarget(specViewer, player(RED), rules()), true)
end)

T.test("dead players stay watchable for 3 seconds after death", function()
	T.eq(S.IsValidTarget(redViewer, player(RED, { alive = false, deathTime = 97.5 }), rules()), true)
	T.eq(S.IsValidTarget(redViewer, player(RED, { alive = false, deathTime = 96.9 }), rules()), false)
end)

T.test("observers (spectators, long-dead players) are not watchable", function()
	T.eq(S.IsValidTarget(specViewer, player(SPEC, { alive = false }), rules()), false)
end)

local function npc(team, extra)
	local n = { id = {}, kind = "npc", team = team, alive = true }
	for k, v in pairs(extra or {}) do n[k] = v end
	return n
end

T.test("a living NPC of a team is watched as a player of it is, under mp_forcecamera", function()
	T.eq(S.IsValidTarget(redViewer, npc(RED), rules()), true, "own team")
	T.eq(S.IsValidTarget(redViewer, npc(BLU), rules()), false, "the enemy's")
	T.eq(S.IsValidTarget(redViewer, npc(BLU), rules({ forcecamera = S.FORCE_ALL })), true, "anyone's")
	T.eq(S.IsValidTarget(specViewer, npc(BLU), rules({ forcecamera = S.FORCE_NONE })), true, "a spectator, any")
end)

T.test("an NPC of no team is open to all but mp_forcecamera 2; a dead NPC to nobody", function()
	T.eq(S.IsValidTarget(redViewer, npc(NOBODY), rules()), true, "a monster")
	T.eq(S.IsValidTarget(redViewer, npc(NOBODY), rules({ forcecamera = S.FORCE_NONE })), false, "forcecamera 2")
	T.eq(S.IsValidTarget(specViewer, npc(RED, { alive = false }), rules()), false, "dead")
end)

T.test("disabled observer points are not usable", function()
	T.eq(S.IsValidTarget(redViewer, point({ enabled = false }), rules()), false)
	T.eq(S.IsValidTarget(specViewer, point({ enabled = false }), rules()), false)
end)

T.test("an observer point on a control point the team does not own is closed to it", function()
	local p = point({ associatedTeam = BLU })
	T.eq(S.IsValidTarget(redViewer, p, rules()), false)
	T.eq(S.IsValidTarget({ id = "me", team = BLU }, p, rules()), true)
end)

T.test("associated ownership is ignored during a team win", function()
	T.eq(S.IsValidTarget(redViewer, point({ associatedTeam = BLU }), rules({ teamWin = true })), true)
end)

T.test("associated ownership is ignored with mp_forcecamera 0", function()
	T.eq(S.IsValidTarget(redViewer, point({ associatedTeam = BLU }), rules({ forcecamera = S.FORCE_ALL })), true)
end)

T.test("spectators may use any enabled point", function()
	T.eq(S.IsValidTarget(specViewer, point({ associatedTeam = BLU, team = BLU }), rules()), true)
end)

T.test("a point's own TeamNum limits it to that team under mp_forcecamera 1", function()
	T.eq(S.IsValidTarget(redViewer, point({ team = BLU }), rules()), false)
	T.eq(S.IsValidTarget(redViewer, point({ team = RED }), rules()), true)
	T.eq(S.IsValidTarget(redViewer, point({ team = NOBODY }), rules()), true)
end)

T.test("the payload cart is not watchable during a team win", function()
	local cart = { id = {}, kind = "entity", team = NOBODY, train = true }
	T.eq(S.IsValidTarget(redViewer, cart, rules()), true)
	T.eq(S.IsValidTarget(redViewer, cart, rules({ teamWin = true })), false)
end)

-- Target cycling (CTFPlayer::FindNextObserverTarget) -------------------------------

local function always() return true end
local function only(set) return function(c) return set[c] == true end end

T.test("next wraps around the list", function()
	local list = { "a", "b", "c" }
	T.eq(S.FindNext(list, 1, false, always), 2)
	T.eq(S.FindNext(list, 3, false, always), 1)
end)

T.test("previous wraps around the list", function()
	local list = { "a", "b", "c" }
	T.eq(S.FindNext(list, 1, true, always), 3)
	T.eq(S.FindNext(list, 2, true, always), 1)
end)

T.test("with no current target, next starts at the first and previous at the last", function()
	local list = { "a", "b", "c" }
	T.eq(S.FindNext(list, nil, false, always), 1)
	T.eq(S.FindNext(list, nil, true, always), 3)
end)

T.test("invalid entries are skipped", function()
	local list = { "a", "b", "c", "d" }
	T.eq(S.FindNext(list, 1, false, only({ d = true, a = true })), 4)
	T.eq(S.FindNext(list, 4, false, only({ d = true, a = true })), 1)
end)

T.test("the current target is found again when it is the only valid one", function()
	local list = { "a", "b" }
	T.eq(S.FindNext(list, 1, false, only({ a = true })), 1)
end)

T.test("nothing valid gives nil", function()
	T.eq(S.FindNext({ "a", "b" }, 1, false, only({})), nil)
	T.eq(S.FindNext({}, nil, false, always), nil)
end)

-- Initial target (CTFPlayer::FindNearestObservableTarget) ---------------------------

T.test("the nearest valid candidate wins", function()
	local list = { { dist = 50, ok = false }, { dist = 90, ok = true }, { dist = 70, ok = true } }
	T.eq(S.Nearest(list, function(c) return c.ok end), 3)
end)

T.test("no valid candidate gives nil", function()
	T.eq(S.Nearest({ { dist = 1 } }, function() return false end), nil)
end)

-- Welcome point (CTFPlayer::PickWelcomeObserverPoint) ------------------------------

T.test("the default welcome point is the first view", function()
	local points = { { welcome = false }, { welcome = true }, { welcome = false } }
	T.eq(S.WelcomePoint(points, always), 2)
end)

T.test("an unusable welcome point falls back to the last usable point before it", function()
	local points = { { welcome = false, ok = true }, { welcome = true, ok = false }, { welcome = false, ok = true } }
	T.eq(S.WelcomePoint(points, function(p) return p.ok end), 1)
end)

T.test("without a welcome point, the last usable point", function()
	local points = { { welcome = false, ok = true }, { welcome = false, ok = true }, { welcome = false, ok = false } }
	T.eq(S.WelcomePoint(points, function(p) return p.ok end), 2)
end)

T.test("no usable points gives nil", function()
	T.eq(S.WelcomePoint({ { welcome = true } }, function() return false end), nil)
end)

-- Watching an NPC: the camera centres on its model, not its origin at its feet

local function V(x, y, z) return { x = x, y = y, z = z } end
local function Text(v) return string.format("%g %g %g", v.x, v.y, v.z) end

T.test("a camera watching an NPC looks at the middle of its bounds", function()
	T.eq(Text(S.NpcFocus(V(-16, -16, 0), V(16, 16, 72))), "0 0 36", "a soldier standing at the origin")
	T.eq(Text(S.NpcFocus(V(84, -16, 10), V(116, 16, 82))), "100 0 46", "anywhere")
end)

T.test("first person on an NPC is just below the top of its bounds, over its middle", function()
	T.eq(Text(S.NpcEye(V(-16, -16, 0), V(16, 16, 72))), "0 0 " .. (72 - S.NPC_EYE_BELOW_TOP), "eye height")
end)

T.test("third person on an NPC looks over its shoulder: pivoting at shoulder height, behind and to the right", function()
	local mins, maxs = V(-16, -16, 0), V(16, 16, 72)
	local pivot = S.ShoulderPivot(mins, maxs)
	T.eq(Text(pivot), "0 0 " .. (72 - S.NPC_EYE_BELOW_TOP - S.SHOULDER_BELOW_EYE), "shoulder height, over its middle")
	-- looking along +x, the right is -y
	local origin = S.ShoulderOrigin(pivot, V(1, 0, 0), V(0, -1, 0))
	T.eq(Text(origin), string.format("%g %g %g", -S.SHOULDER_DISTANCE, -S.SHOULDER_RIGHT, pivot.z), "back and right")
end)

T.finish()
