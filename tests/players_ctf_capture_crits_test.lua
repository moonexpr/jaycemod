-- CTFGameRules::HandleCTFCaptureBonus: a flag captured, the capturing team
-- is crit-boosted (TF_COND_CRITBOOSTED_CTF_CAPTURE) for tf_ctf_bonus_time
-- seconds, which CTFPlayerShared::IsCritBoosted counts.
local T = dofile("tests/harness.lua")
local P = gameplay.players

T.test("the CTF capture's crit boost is TF2's condition 39", function()
	T.eq(P.COND.CRITBOOSTED_CTF_CAPTURE, 39, "TF_COND_CRITBOOSTED_CTF_CAPTURE")
end)

T.test("the capture's crits boost every hit while they last, then go", function()
	local capper = {}
	P.AddCond(capper, P.COND.CRITBOOSTED_CTF_CAPTURE, 10, 0)
	T.eq(P.CritBoosted(capper, 5), true, "five seconds in")
	T.eq(P.CritBoosted(capper, 11), false, "after ten")
end)

T.finish()
