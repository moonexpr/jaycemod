-- tf_halloween_minigame (CTFHalloweenMinigame): a stub. Its minigames are
-- kart games in arenas reached from Hell, and Sandcastle has neither karts
-- nor the minigame mode (pl_rumble_event's soccer is the only one). The
-- stub accepts every keyvalue (MinigameType, RedSpawn, BlueSpawn, MaxScore,
-- ScoreType, SuddenDeathTime, InRandomPool, hud_res_file and the score
-- sounds) and input in the FGD and C++, stores its outputs
-- (OnRedHitMaxScore, OnBlueHitMaxScore, OnAllRedDead, OnAllBlueDead,
-- OnTeleportToMinigame, OnReturnFromMinigame, OnSuddenDeathStart), and
-- fires none: no score is kept, so none can honestly be reached.
ENT.Type = "point"
ENT.Base = "wetsand_stub_point"

ENT.StubReason = "kart minigames are not supported; inputs accepted and ignored"
ENT.StubInputs = {
	scoreteamred = true,
	scoreteamblue = true,
	changehudresfile = true,
	returnfromminigame = true,
	kartwinanimationred = true,
	kartwinanimationblue = true,
	kartloseanimationred = true,
	kartloseanimationblue = true,
	enablespawnboss = true,
	disablespawnboss = true,
}
