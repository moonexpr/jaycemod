-- The round states of TF2's gamerules (gamerules_roundstate_t,
-- teamplayroundbased_gamerules.h), with TF2's values, which the server
-- replicates as ws_round_state. A part of its own because the team rules read it
-- too, and the round rules read the team numbers.
module(...)

INIT = 0
PREGAME = 1
STARTGAME = 2
PREROUND = 3
RND_RUNNING = 4
TEAM_WIN = 5
RESTART = 6
STALEMATE = 7
GAME_OVER = 8
BONUS = 9
BETWEEN_RNDS = 10
