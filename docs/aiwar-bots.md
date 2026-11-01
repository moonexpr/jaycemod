# AI war: bot players as soldiers

NextSoldier's orders can drive bot players (`player.CreateNextBot`) as well
as the DrGBase NextBot soldiers. Being players, the bots pass every map
trigger and filter written for players (TF2's maps filter most of theirs
for clients: spawn doors, teleports, kill triggers, `filter_activator_class
player`), move by player movement, and press keys as TF2's own bots do.
The DrGBase soldiers stay: the war's NPCs fill the slots the bots leave.

## Running it

While the war runs (`mp_aiwar_start`), TF2's quota convars keep the bots:

| Convar | Default | What |
|---|---|---|
| `tf_bot_quota` | `0` | How many bots, counted as the mode says |
| `tf_bot_quota_mode` | `normal` | `normal`: that many bots; `fill`: players on the game teams topped up to it; `match`: that many bots for each human |
| `tf_bot_join_after_player` | `1` | No bots until a human is on a game team (set `0` on a server with no humans) |
| `tf_bot_difficulty` | `1` | Their reaction time, aim error and spread, as the NPC soldiers' (`features.aiwar.marksmanship`) |

A bot joins the team a player would be auto-assigned to, spawns in its
team's respawn waves, and is enlisted as it spawns; one is added or kicked
a second (TF2's `MaintainBotQuota`), never taking the last free slot. The
war ending kicks them. An idle server (no humans for `sv_idle_delay`)
pauses the war, bots included.

Check it in game: `python3 .devtools/bin/ingame_one.py aiwar_bots` (on a
second server: `--instance 2`); it is in `ingame_tests.py`'s plan on
`pl_badwater`. `dt lua -f .devtools/bin/bot_status.lua` prints each bot's
role, weapon, target, speed and contact.

## How it is built

| Piece | Where | Job |
|---|---|---|
| `wartactics.bot_quota` | `wartactics/bot_quota.lua` | TF2's quota rules: bots wanted, add or kick one, the team to kick from |
| `nextsoldier.vision` | `nextsoldier/vision.lua` | TF2's IVision: an enemy seen at once, recognized after the reaction time, remembered where last seen for a while; the most dangerous recognized one is the contact. Its events are the orders' (`OnSight`, `OnLostSight`, `OnContact`, `OnContactLost`) |
| `nextsoldier.player_body` | `nextsoldier/player_body.lua` | TF2's PlayerBody and PlayerLocomotion: from target, gait, look, aim and weapon to a command (move yaw, eye angles turned at `TURN_RATE`, walk, duck, jump, use, attack, reload); crouch jumps when stuck, jumps a low obstacle, ducks under a high one, uses a door ahead (GLambda Players' checks); sent nowhere, closes on or backs off its enemy to its weapon's chase and avoid ranges (DrGBase's own fighting) |
| `nextsoldier.route_walk` | `nextsoldier/route_walk.lua` | A route walked waypoint by waypoint, as the orders walk theirs: a waypoint passed within `RADIUS` when the next is in a clear line, one round a corner only within `ON`, and the farthest of the next `LOOKAHEAD` in a clear line made for |
| `BotSoldier` | `features/aiwar/sv_bot_soldier.lua` | The soldier port over a bot player, a subclass of the DrGBase one. It plans its own way, as DrGBase does (`PlansRoutes` true: the orders give it the goal): its navigator computes the route with the engine's path search, priced by `RouteCost` (blocked and shut areas, enemy spawn rooms, a player's step, crouch jump and safe drop), planned again when the goal moves, the blockers change or the orders ask (`Repath`). Hops only where a crouch jump clears, no seats or poses |
| `ws_bot_navigator` | `entities/entities/ws_bot_navigator.lua` | A hidden NextBot per bot, standing where its bot stands, so `Path:Compute` (which needs a NextBot) can plan for a player, as GLambda Players' `glace_navigator` does |
| Controller part | `features/aiwar/sv_bots.lua` | Keeps the quota, enlists bots as they spawn and discharges them as they die, kits them (`KitBot`: model, loadout, ammunition, health), looks every 0.2 s (field of view, line of sight, attackers and anyone within earshot), asks the orders `ShouldAttack` and `SelectMoreDangerousThreat`, and writes each bot's keys in `StartCommand` |

The rest of the controller treats a bot as a player: the engine and
DrGBase relate to it by its team, so the relationship passes, factions,
`SetAIDisabled` and the team-member registry skip it; the rounds' rules
(freezes, stuns, humiliation) reach its keys through `GM:StartCommand`.
Bots pass through their teammates (`SetNoCollideWithTeammates`), as TF2's
teammates do: one held up behind another in a doorway crouch-jumped onto
its head and stayed there.

Freeform squads explore their lanes and waypoints without waiting for or
following any player.

Why the bots plan with the engine: the orders' own route walking
(`PlansRoutes` false, `Travel:FollowRoute`) asks the war's Lua route search,
whose queue the lane planning keeps 20 to 30 deep on `pl_upward`; a trip the
orders restart (a fire team's contact ends it) asked afresh and dropped the
search in flight, so bots stood for minutes. DrGBase soldiers never met it:
their engine plans their paths.

## What a bot player can be made to do

Measured on the dev server (`.devtools/bin/bot_probe.lua`):

- `StartCommand` runs for each bot every tick, and `SetupMove`, `Move`,
  `FinishMove`, `PlayerTick` too.
- A bot's command view angles are its **move** angles only; its eyes are
  `SetEyeAngles`, and its bullets follow its eyes. Walking one way and
  shooting another needs nothing more.
- Forward, side, walk, sprint, duck, jump, fire, reload, `SelectWeapon`,
  impulses (the flashlight) and +use all work. Mouse deltas do nothing, and
  `ConCommand` does not run for a bot (it has no client).
- The engine's own command for a bot holds `IN_DUCK` every tick: clear the
  buttons first.
- Just after `SetPos` a bot is not on the ground yet, and a jump is lost.
- A clients-only `trigger_teleport` sent the bot across the map; an
  `npc_citizen` put in the same trigger stayed.

## Cost

`Drive` (one bot's keys, per tick) on the dev server under CrossOver:
about 32 µs with `ws_jit_enabled 0`, about 126 µs with the JIT on, where the
JIT's default capacity thrashes (`docs/ns-performance-baseline.md`, H12):
about 1 ms a tick for 30 bots with the JIT off. The look (every 0.2 s, its
route planning included) averaged 0.25 ms a tick for six bots on
`pl_upward` with the JIT on, but a long route planned in one call took up
to 19 ms: the engine's search runs whole, its cost callback in Lua.
Spreading the plans out (one bot's a tick), or caching routes between
nearby starts and goals, is the next step if that hitch shows.

## Not yet

- Bots have no voice lines (the speech reads a DrGBase soldier's
  `NSVoiceLines`), so they call nothing out.
- They do not sit on the cart, strike poses, or follow it; the kit's
  `damage` and `runSpeed` (DrGBase's) are not applied.
- A Resistance medic's kit (the vortigaunt's) has no arms: a bot given that
  role keeps what it carried.
- Their route cost is a plain distance with a jump penalty; TF2's bots'
  (`path/tfbot`: spread over routes, the safest route when retreating) is
  not used yet.
- Names are the faction's at join time: after the sides trade, a bot
  called Combine fights for the Resistance.
- TF NextBot monsters are not in their sight.
- Ladders and doors that open by +use alone are untested.
- `Drive` allocates a few tables a tick: a weapon record per weapon and a
  reused command would cut it.
