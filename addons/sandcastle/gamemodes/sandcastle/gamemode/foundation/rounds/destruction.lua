-- Player and Robot Destruction (TF_GAMETYPE_PD, TF_GAMETYPE_RD): their
-- logic (tf_logic_player_destruction, tf_logic_robot_destruction) makes the
-- map theirs, as CTFGameRules::Activate settles the game type after the
-- train watchers and KOTH, arena last. So pd_watergate's UFO, which rides a
-- team_train_watcher, makes no payload map and shows no cart HUD.
-- Sandcastle plays no destruction scoring yet: a stand-in mode without an
-- objective, whose rounds the round limits decide (foundation.rounds.limits).
local Rounds = require("foundation.rounds")
module(...)

Mode = Rounds.Mode:Extend("destruction")
-- Above payload (2) and KOTH (3), under arena (4).
Mode.PRIORITY = 3.5
Mode.HUD = Rounds.HUD_NONE
