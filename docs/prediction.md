# Prediction and lag compensation

How GMod's prediction system and lag compensation work, what Sandcastle
does with them now, and where we might use them ourselves. Source: the
GMod wiki's [Prediction](https://wiki.facepunch.com/gmod/Prediction),
[Player:LagCompensation](https://wiki.facepunch.com/gmod/Player:LagCompensation),
[Entity:SetLagCompensated](https://wiki.facepunch.com/gmod/Entity:SetLagCompensated),
[Entity:SetPredictable](https://wiki.facepunch.com/gmod/Entity:SetPredictable),
[IsFirstTimePredicted](https://wiki.facepunch.com/gmod/Global.IsFirstTimePredicted)
and [SuppressHostEvents](https://wiki.facepunch.com/gmod/Global.SuppressHostEvents);
Valve's [Prediction](https://developer.valvesoftware.com/wiki/Prediction) and
[Lag compensation](https://developer.valvesoftware.com/wiki/Lag_compensation)
for the engine's side.

## The complaint

At the last playtest, shots that hit a soldier on the shooter's screen did
not register on the server. The cause: soldiers were not lag compensated.

A player sees every other entity where it was about `cl_interp` (100 ms by
default) plus their ping ago. When they fire, the server traces the shot
against the world as it is when the command arrives. To make the two agree,
the server moves every *lag-compensated* entity back to where that player
saw it, traces, then puts them back. GMod compensates players by default and
nothing else; an NPC or NextBot takes part only once it calls
`SetLagCompensated(true)`. DrGBase never does, so a soldier running across
the shooter's view at 220 u/s was about 33 units from where a player at
50 ms ping aimed (150 ms behind), which is more than its 32-unit-wide hull.

Checked on the dev server (pl_upward, 2026-10-27): before the fix, 0 of the
16 soldiers were lag compensated (`IsLagCompensated()`); after it, all 17
(Combine, rebels, the vortigaunt).

## What we did

`WS.WarSoldier`'s `CustomInitialize` (ws/sh_war_soldier.lua) calls
`self:SetLagCompensated(true)`, so every AI war soldier (`ws_drg_combine`,
`ws_drg_rebel`, `ws_drg_vortigaunt`, and `ws_drg_probe` through them) is
compensated from its first tick. A revived soldier (sv_reserve.lua) is the
same entity and keeps the flag. Test:
`tests/aiwar_soldier_lag_compensation_test.lua`.

Player guns need no change: they are HL2's engine weapons and fire through
`FireBullets`, which turns lag compensation on and off itself. The bullet
steps (ws/sh_bullets.lua, `EntityFireBullets`) and the fixed-spread pellets
they re-fire with `WS.FireBulletsAgain` also go through `FireBullets`.

Bot players (sv_bots.lua) are players, so they were always compensated.
They have no latency, so for them a rewind moves nothing.

## How prediction works

The client sends its commands (`CUserCmd`: buttons, view angles, movement)
to the server, and runs the same code on them at once instead of waiting for
the server's answer. When the server's result arrives, the client compares
its predicted state with it. If they match, nothing happens. If they don't,
it takes the server's state and replays the commands the server has not
answered yet: a *prediction error*.

That makes three rules for predicted code:

1. **Same inputs, same result on both realms.** Predicted hooks run shared:
   `StartCommand`, `SetupMove`, `Move`, `FinishMove`, `PlayerTick`, and a
   weapon's `PrimaryAttack`, `SecondaryAttack`, `Reload`, `Think`. Code that
   reads state only one realm has, or `math.random` without a shared seed,
   predicts wrong.
2. **Predicted state is networked state.** On a prediction error, only
   network vars (`Entity:NetworkVar`, DT vars) are rolled back and replayed.
   A plain Lua field (`self.NextFire`) or a `timer` is not, which is why a
   SWEP that keeps its fire time in a field stutters under lag. A non-weapon
   entity the player drives can join prediction with `SetPredictable(true)`
   (client side; it resets the DT vars, and a full update unmarks it, see
   `GM:NotifyShouldTransmit`).
3. **Effects once.** The client may run a command several times while
   replaying. `IsFirstTimePredicted()` is true only the first time (always
   on the server). `EmitSound` and `SendWeaponAnim` already check it; wrap
   your own `util.Effect` and similar calls in it. Set predicted *variables*
   on every run, never behind it.

On the server, effects made during a player's predicted command skip that
player (`SuppressHostEvents`), since their client already made its own copy.
Weapon hooks are wrapped in it already. `GetPredictionPlayer()` names the
player whose command is running.

Singleplayer has no prediction: predicted hooks run only on the server.

## How lag compensation works

`ply:LagCompensation(true)` moves every compensated entity back to where it
was at the tick `ply`'s current command was made (taking their interpolation
into account); `ply:LagCompensation(false)` puts them back. Limits:

- Only on the server, and only inside a predicted hook of that player (it
  needs their current command).
- It **must** be turned off again: left on, the moved entities stay moved.
- Pose parameters are not rewound (issue
  [3683](https://github.com/Facepunch/garrysmod-issues/issues/3683)). A
  soldier's aim (`aim_yaw`, `aim_pitch`) is pose parameters, so its upper
  body's hitboxes may sit where it aims now and not where it aimed then.
  Its position, angles and animation sequence are rewound.
- Don't compensate parented entities; they move back with their parent.
- It covers instant hits only. A projectile (the crossbow bolt, a rocket, a
  jar) is an entity of its own simulated on the server. TF2 doesn't
  compensate projectiles either.

## Where Sandcastle already meets prediction

| File | What |
|---|---|
| `ws/sh_bullets.lua` | The bullet steps run on both realms inside the predicted `FireBullets`, so a step must decide the same on both (fixed spread does: `FixedSpread.Offset(i)`, no randomness) |
| `ws/sh_footsteps.lua` | Footsteps play once: `if CLIENT and not IsFirstTimePredicted() then return true end` |
| `ws/sv_hits.lua` | A crit's tracer lifts `SuppressHostEvents` (`GetPredictionPlayer`) so the shooter sees their own crit |
| `ws/sh_war_soldier.lua` | Soldiers are lag compensated |

## Using it ourselves

What we could do with it next, most useful first.

1. **One helper for custom player traces.** Any hit our own code traces for a
   player, outside `FireBullets` (a melee swing, a Lua weapon's hitscan, a
   hit check in a spell), needs the rewind too. A `WS.LagCompensated(ply, fn)`
   in `ws/` that turns it on, runs `fn` and turns it off even when `fn`
   errors (`xpcall`, then rethrow), and does nothing for a non-player or
   outside a predicted hook, would make that one line and make it impossible
   to leave on. None of our code traces a player's hit by hand today, so this
   waits for the first one.
2. **Lua weapons predicted properly.** `tf_weapon_spellbook` and any TF2
   weapon we write as a SWEP: keep fire times, charges and clip state in
   `NetworkVar`s, run the attack shared, dispatch effects under
   `IsFirstTimePredicted`, and spawn projectiles on the server only.
   DrGBase's weapons (`drgbase_weapon/primary.lua`) keep the fire time in
   the engine's `SetNextPrimaryFire` and fire under `IsFirstTimePredicted`.
   Before writing a new hitscan SWEP, note that a `util.TraceLine` hit
   needs item 1; `FireBullets` does not.
3. **Movement modifiers in the move hooks.** Speed changes from conditions
   (games.gameplay.players.condition_effects), the cart pushing, a charge or
   a knockback: done in `SetupMove`/`Move` from networked state, the client
   predicts them and feels no rubber-banding. A modifier the server applies
   only on its own (a `SetVelocity` from a hook outside prediction) is
   corrected on the client a round trip later. Worth an audit of what we
   apply where.
4. **Seeing the rewind.** A debug layer (nbdebug) that, when a player fires,
   draws the soldier's hitboxes where they were rewound to next to where
   they are, as CS:S's `sv_showlagcompensation` does for players. That turns
   "my shot didn't count" into a picture.
5. **Not predicting what decides.** Damage, kills, crits and hit feedback stay
   the server's (sv_hits.lua): a client that predicted a hit the server then
   refused would show a hitmarker for nothing. Predict how things look
   (tracers, impacts, sounds), never what they decide.

## Still to check in game

- **A shot from a lagged client.** The flag is on (checked), but the hit
  itself is untested: on a client with `net_fakelag 150`, shoot a strafing
  soldier and compare hits with the soldier's flag on and off
  (`ent:SetLagCompensated(false)` through `dt lua`).
- **HL2 melee.** Whether GMod's `weapon_crowbar` and `weapon_stunstick`
  rewind for their swing (HL2MP's do; single-player HL2's did not). If not,
  a melee swing on a moving soldier misses the same way; the helper in item
  1, with a melee step, is the fix.
- **Pellets inside the hook.** `WS.FireBulletsAgain` calls `FireBullets`
  from inside another's `EntityFireBullets` hook. Each call rewinds and
  restores on its own; whether the outer call's rewind is already active
  inside the hook, and whether nesting restores cleanly, is not documented.
  A shotgun's pellets against a strafing soldier at 150 ms fake lag answer
  it.
- **Cost.** The server records a history for each compensated entity every
  tick, as it does for each player, and moves them back and forth on each
  player shot. With 30 soldiers that should be small, but it is on the main
  thread; the analytics tick pressure before and after would confirm it.
