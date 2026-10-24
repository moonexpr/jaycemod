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
| `nextsoldier.bot_quota` | `games/nextsoldier/bot_quota.lua` | TF2's quota rules: bots wanted, add or kick one, the team to kick from |
| `nextsoldier.vision` | `games/nextsoldier/vision.lua` | TF2's IVision: an enemy seen at once, recognized after the reaction time, remembered where last seen for a while; the most dangerous recognized one is the contact. Its events are the orders' (`OnSight`, `OnLostSight`, `OnContact`, `OnContactLost`) |
| `nextsoldier.player_body` | `games/nextsoldier/player_body.lua` | TF2's PlayerBody and PlayerLocomotion: from target, gait, look, aim and weapon to a command (move yaw, eye angles turned at `TURN_RATE`, walk, duck, jump, use, attack, reload); crouch jumps when stuck, jumps a low obstacle, ducks under a high one, uses a door ahead (GLambda Players' checks); sent nowhere, closes on or backs off its enemy to its weapon's chase and avoid ranges (DrGBase's own fighting) |
| `BotSoldier` | `features/aiwar/sv_bot_soldier.lua` | The soldier port over a bot player, a subclass of the DrGBase one: no route planning of its own (`PlansRoutes` false, so the orders walk the route), routes stale when the nav blockers changed, hops only where a crouch jump clears, no seats or poses |
| Controller part | `features/aiwar/sv_bots.lua` | Keeps the quota, enlists bots as they spawn and discharges them as they die, kits them (`KitBot`: model, loadout, ammunition, health), looks every 0.2 s (field of view, line of sight, attackers and anyone within earshot), asks the orders `ShouldAttack` and `SelectMoreDangerousThreat`, and writes each bot's keys in `StartCommand` |

The rest of the controller treats a bot as a player: the engine and
DrGBase relate to it by its team, so the relationship passes, factions,
`SetAIDisabled` and the team-member registry skip it; the rounds' rules
(freezes, stuns, humiliation) reach its keys through `GM:StartCommand`.

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
about 1 ms a tick for 30 bots with the JIT off. The look (every 0.2 s) is
about 0.15 ms a tick for six bots.

## Not yet

- Bots have no voice lines (the speech reads a DrGBase soldier's
  `NSVoiceLines`), so they call nothing out.
- They do not sit on the cart, strike poses, or follow it; the kit's
  `damage` and `runSpeed` (DrGBase's) are not applied.
- A Resistance medic's kit (the vortigaunt's) has no arms: a bot given that
  role keeps what it carried.
- Their routes use the HL2 soldiers' cost (`path/hl2`); TF2's bots'
  (`path/tfbot`) may suit a player's body better.
- TF NextBot monsters are not in their sight.
- Ladders and doors that open by +use alone are untested.
- `Drive` allocates a few tables a tick: a weapon record per weapon and a
  reused command would cut it.
