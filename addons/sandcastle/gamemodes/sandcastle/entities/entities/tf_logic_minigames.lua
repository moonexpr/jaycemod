-- tf_logic_minigames (CTFMinigameLogic): a stub. It sends players into and
-- out of tf_halloween_minigame arenas, which are themselves stubs (no karts,
-- no minigame mode), so a teleport would strand players in an arena with
-- nothing running. The stub accepts TeleportToMinigame, SetAdvantageTeam,
-- TeleportToRandomMinigame and ReturnFromMinigame and does nothing.
ENT.Type = "point"
ENT.Base = "ws_stub_point"

ENT.StubReason = "minigames are not supported; inputs accepted and ignored"
ENT.StubInputs = {
	teleporttominigame = true,
	setadvantageteam = true,
	teleporttorandomminigame = true,
	returnfromminigame = true,
}
