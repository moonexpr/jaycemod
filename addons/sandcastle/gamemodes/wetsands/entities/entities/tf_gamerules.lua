-- tf_gamerules: TF2's gamerules proxy (CTFGameRulesProxy): Sandcastle's
-- gamerules (ws_gamerules), running rounds from the start, as on any TF2
-- map. A map's own, or the one the rounds controller makes on a map with
-- an objective and none (features/rounds/sv.lua's EnsureProxy).
ENT.Type = "point"
ENT.Base = "ws_gamerules"
ENT.RunsRounds = true
