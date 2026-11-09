-- tf_logic_medieval (CMedievalLogic, tf_gamerules.cpp): a stub. In TF2 it
-- puts the game in medieval mode (melee and medieval weapons only, the
-- auto-RP chat), which is about TF2's classes and loadouts; GMod has
-- neither, so cp_degrootkeep and cp_burghausen play with whatever players
-- carry. It has no keyvalues, inputs or outputs of its own.
ENT.Type = "point"
ENT.Base = "ws_stub_point"

ENT.StubReason = "medieval mode's weapon rules are not supported; ignored"
