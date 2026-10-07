# Sandcastle pass 3: Halloween payload maps

Pass 3 makes the 15 Halloween pl_/plr_ maps play as they do in TF2:
skeletons, bosses, bombs, gifts, spell pickups and a working spellbook, all
started by the maps' own entities and I/O. Everything in
`docs/pass2-contract.md` still holds: layout, "what the game gives you",
interfaces, conventions and commits.

`sdk/` below means `~/Repositories/source-sdk-2013/src/game/`. Map dumps come
from `.devtools/bin/bsp_entities.py "$TF2/tf/maps/<map>.bsp" --class C | --io`.

## 0. Decisions the operator should know

1. **The layers are Model, Controller, Entity and View.**
   - **Models** are foundation systems: stateful `module(...)` files that hold
     every rule. They do I/O only through ports and are passed time and
     randomness, so a whole scenario runs under LuaJIT.
   - **Controllers** are the server parts of `WETSAND.Feature(name)`. Each owns
     its system's model instances, feeds them engine events, and turns their
     results into engine effects.
   - **Entities** are thin bindings from keyvalues, inputs and outputs to
     controller calls. They hold no rules.
   - **Views** are the client parts of a feature, and render only what their
     controller networks.
2. **Loading is lazy and per map.** No new realm module is always loaded, and
   the WIP `sv_halloween.lua` is deleted. An entity file requires nothing at
   top level, because GMod registers every entity file on every map. Its
   `Initialize`, or its first input, calls `WETSAND.Feature("<system>")` and
   keeps the controller that call returns. A map without Halloween entities
   loads no Halloween code.
3. **Variation is a Strategy, never a branch.** A system declares an interface
   (section 1.3). The variants are its parts, chosen by map entities: NPC
   types over `foundation.npc`, bosses over the `halloween_boss` template,
   path costs over `foundation.npc.path`, spells over `foundation.spells`,
   holiday modes over `foundation.holiday`, and hazards over
   `foundation.hazards`. System code never contains `if type == X`.
4. **Everything is entity-driven.** Nothing checks the map name. TF2 does so
   in several places (`GetHalloweenScenario`, the eyeball's `PURGATORY_Z`,
   koth_slaughter in the generic bomb), and all of those branches are left out.
5. **Halloween mode is on** when the map's `tf_logic_holiday` has
   `holiday_type` = `HOLIDAY_HALLOWEEN` (2), or `tf_forced_holiday` is 2.
   There is no calendar check. It controls only what TF2 gates on it: gifts
   and the "you are IT" warnings. Skeletons, bosses, bombs and pickups work on
   any map, as they do in TF2.
6. **Spells are on** after `HalloweenSetUsingSpells 1`, which 9 maps send, or
   while `tf_spells_enabled` is 1. The convar is read once an entity has
   loaded the holiday controller. While spells are on, each RED or BLU player
   has `tf_weapon_spellbook` and casts with TF2's command
   `+use_action_slot_item` (`bind h +use_action_slot_item`). A king drops a
   rare spell only while spells are on (`CTFGameRules::DropSpellPickup`).
7. **Nav meshes.** All 15 maps embed `maps/<map>.nav` in the BSP pakfile, at
   version 16, sub-version 2. TF2 appends a u32 to each area, which GMod
   cannot read. GMod reads a loose `.nav` from the MOD path before the embedded
   one (`CNavMesh::GetNavDataFromFile`, `sdk/server/nav_file.cpp`), so a
   converter (W2) writes sub-version 0 files to `garrysmod/maps/`. With no
   usable mesh, the map logs one line and its NPCs stand still. TF2 behaves
   the same way: no path, and no chaseable victims. There is no straight-line
   fallback.
8. **GMod supplies the NextBot machinery**: `self.loco`, `Path("Follow")` with
   a Lua cost function, `navmesh`, activities and gestures, and the event
   hooks. Lua adds only what GMod lacks:
   - the Action/Behavior layer;
   - hover locomotion (the eyeball flies; `CEyeballBossLocomotion`);
   - no IVision helper, because TF2's Halloween actions only call
     `IsLineOfSightClear`, which is a port method.
9. **Left out, with reasons:**
   - The minigames are accept-and-ignore stubs (section 9). Merasmus is a
     full boss (section 6) without his econ rewards or the Wheel of Fate.
   - Econ features: pumpkin-head immunity, soul packs, gift rewards, achievements.
   - Karts, and the eyeball's purgatory stun.
   - The eyeball's per-weapon damage multipliers: GMod has no sentries or
     miniguns.
   - `Halloween2013TeleportToHell` logs once and does nothing.
10. **The WIP is replaced.** Its skeleton health, range and damage were right.
    Its cadence, range model, victim choice, mini skeletons (TF2 throws skull
    grenades), lifetime and owner rules were wrong. `halloween_zapper` dealt
    100 damage, but TF2's `CTFHellZap` only draws a beam. The packages rewrite
    every WIP file and delete `foundation/halloween.lua` and
    `tests/halloween_entities_test.lua`.

## 1. Architecture

### 1.1 Systems and their parts (models, pure, `foundation/`)

| system | parts (variants/strategies) | model it holds |
|---|---|---|
| `foundation.npc` | `.actor`, `.combatant` (port contracts); `.path` + `.path.ground`, `.path.scatter` (cost strategies); `.hover`; `.spawner`; `.tag`; variants `.zombie`, `.halloween_boss` (template) + `.headless_hatman`, `.eyeball_boss` | the Action/Behavior engine, timers, and an `Npc` (variant + state + Behavior) |
| `foundation.projectile` | `.rocket`, `.grenade` | a `Projectile` (fuse, touch, lifetime, detonation) |
| `foundation.combat` | none | an `Explosion` (who takes how much) |
| `foundation.holiday` | `.halloween` (mode: gifts, IT warnings), `.fortune` (P2) | a `Holiday` (map holiday, spells on/off, mode) |
| `foundation.spells` | `.caster` (port contract); set `.tf2`; strategies `.fireball`, `.bats`, `.overheal`, `.mirv`, `.blastjump`, `.stealth`, `.teleport`, `.lightning`, `.athletic`, `.meteor`, `.spawn_boss`, `.skeleton_horde` | a `SpellBook` (current spell, charges, roll, cast rules) |
| `foundation.hazards` | `.pumpkin_bomb`, `.generic_bomb`, `.zapper`, `.croc` | a `Hazard` (damage, touch and input into outcomes) |
| existing | `foundation.teams` (HALLOWEEN = 5 already), `foundation.players` (W3 adds COND/STUN names), `foundation.rounds` | |

**Engine-neutral** (grep-checked in section 11): `foundation.npc`, `.actor`,
`.path*`, `.hover`, `.spawner`, and `foundation.projectile`. The entities
`wetsand_nextbot` and `wetsand_projectile` are neutral too. The
`foundation.spells` flow is neutral except for its `.tf2` set and its spell
strategies. TF2 content lives in parts and data: a TF2 variant or set, and the
TF2 numbers inside a system's tables.

### 1.2 Controllers and views (`WETSAND.Feature`, built by a separate package)

`WETSAND.Feature(name)`:
- On the server, it requires the feature's server part, the controller, and
  returns it. It also tells clients to load the client part, the view.
- On the client, it requires the view when told.

The file location follows that package; `gamemode/features/<name>/{sv,cl}.lua`
is proposed. Each controller below lists what it owns and its methods.

| feature | controller owns | controller methods (server) | view (client) |
|---|---|---|---|
| `npc` | one `Npc` model per NPC entity; the `Spawner` models; a registry by kind; per-variant shared state; the nav check | `Bind(ent, variantName, config) -> npc` (then calls the variant's `Cull`), `Unbind(ent)`, `All(kind) -> list`, `Spawn(class, config, pos, ang) -> ent`, `BindSpawner(ent, config) -> spawner`, `Shared(variantName) -> table` (cross-instance state for a variant, e.g. the eyeball level), `SetBossHealth(fraction)` | boss health bar (reads Global2 `wetsand_boss_health`); registers `halloween, scary_ghost, eyeboss, cinefx` pcfs |
| `combat` | `Projectile` models per projectile entity | `BindProjectile(ent, variantName, config) -> projectile`, `Explode(explosionConfig)` (runs an `Explosion` against the world), `TeamOf(ent)`, `InRespawnRoom(ent)` | none |
| `holiday` | the `Holiday` model; the Halloween mode's gift schedule; fortune teller models (P2) | `BindHoliday(ent, kv)`, `HolidayActive(h)`, `UsingSpells()`, `SetUsingSpells(b)`, `DropSpellPickup(pos, tier)`, `AddGiftLocation(pos)`, `BindFortuneTeller(ent, kv)` | none |
| `spells` | one `SpellBook` per player; the caster port | `BookOf(ply) -> book`, `Grant(ply)`, `Revoke(ply)`, `Pickup(ply, tier) -> bool`, `Cast(ply) -> bool`, `BindSpellProjectile(ent, spellIndex, config)` | spell HUD (icon, charges, roll animation, key); registers `halloween, drg_cowmangler, class_fx, rocketjumptrail, cinefx, eyeboss` pcfs |
| `tag` | the `foundation.npc.tag` model (TF2's IT) and its melee/death hooks | `Get()`, `Set(ply)` | none |
| `hazards` | one `Hazard` model per hazard entity | `Bind(ent, variantName, config) -> hazard` | registers the `item_fx` pcf |

The views needed on Halloween maps are the npc view (boss bar and
particles), the spells view (HUD and particles) and the hazards view
(particles). Nothing else is drawn client-side.

### 1.3 Interfaces each system declares

**Action** (`foundation.npc`, a port of `sdk/server/NextBot/NextBotBehavior.h`):

- Overridable methods:
  - `InitialContainedAction(me)`, `OnStart(me, prior)`, `Update(me, interval)`,
    `OnEnd(me, nextAction)`, `OnSuspend(me, interrupting)`,
    `OnResume(me, interrupting)`, `IsOutOfScope(me)`;
  - any event handler `On<Event>(me, ...)`. An absent handler returns
    `TryContinue()`.
- Results: `Continue()`, `ChangeTo(a, why)`, `SuspendFor(a, why)`, `Done(why)`,
  and `TryContinue/TryChangeTo/TrySuspendFor/TryDone/TryToSustain(..., priority)`.
- Constants: `CONTINUE, CHANGE_TO, SUSPEND_FOR, DONE, SUSTAIN`;
  `RESULT_NONE < RESULT_TRY < RESULT_IMPORTANT < RESULT_CRITICAL`;
  `INTERVAL_UNSTARTED = 99999.9`.
- API:
  - `Action:Extend(name)` and `class:New(...)`, which calls `:Init(...)`.
  - `Behavior:New(action, name)`, then `:Update(me, interval)`,
    `:Event(me, name, ...)`, `:Describe()` (e.g. `"ZombieBehavior/Attack"`).
  - `CountdownTimer(clock)` and `IntervalTimer(clock)`, where `clock:Now()`
    gives the time. They follow `sdk/shared/util_shared.h`: an unstarted
    countdown `IsElapsed()`, and an unstarted interval returns
    INTERVAL_UNSTARTED.

**NPC variant** (a part of `foundation.npc`, used by
`Npc.New(variant, config, actor)`, which gives
`npc:Update(interval)`, `npc:Event(name, ...)`, `npc:State()` and
`npc:Describe()`):

- `KIND` (registry kind), `LOCOMOTION` (`{ runSpeed, stepHeight, jumpHeight,
  deathDropHeight, maxYawRate, acceleration, deceleration }`) or `HOVER`, and
  `PATH` (the part name of a path strategy).
- `NewState(config, actor) -> state`
- `InitialAction(state) -> Action`
- `FilterDamage(state, damageEvent, actor) -> bool` (optional; the default is true)
- `Cull(liveStates) -> list of states` (optional): which live NPCs of this
  variant must suicide after a new one binds (the zombie's `tf_max_active_zombie`).

**Boss** (`foundation.npc.halloween_boss`: `CHalloweenBaseBoss` as a template
method, and itself an NPC variant factory `halloween_boss.Variant(bossVariant)`):
the template owns spawn health, the damage filter (own team; round won),
attacker memory and the DPS window, the death and killer bookkeeping, and the
top action `BossBehavior`, which ChangeTos `DyingAction` on death. A boss
variant provides these hooks:

- `BOSS_TYPE`
- `Health(players, level) -> n`
- `ModifyDamage(state, damageEvent) -> amount`
- `EmergeAction(state) -> Action`
- `DyingAction(state) -> Action`
- `OnInjured(state, damageEvent, actor)` (optional)

**Path cost** (`foundation.npc.path`):

- `Cost(step, limits, bot) -> number | IMPASSABLE`, where:
  - `step = { hasFrom, traversable, ladderLength, length, centerDistance,
    heightChange, fromCostSoFar, areaId }`;
  - `limits = LOCOMOTION`;
  - `bot = { entIndex, now }`.
- Constants: `IMPASSABLE = -1`, `JUMP_PENALTY = 5`.

**Spell** (`foundation.spells`), with the spell set it registers by index:

- A strategy provides `INDEX`, `Cast(caster) -> bool`, and, for a projectile
  spell, `PROJECTILE` (the class) and `Impact(caster, impact) -> nil`, which
  the projectile calls.
- A set provides `COUNT`, `Definition(index) -> { charges, kind, castSound,
  speedScale, icon }`, `Roll(tier, random) -> index`,
  `Strategy(index) -> part name`, `TIER_COMMON`, `TIER_RARE`, `ROLL_TIME` and
  `CAST_COOLDOWN`.

**Holiday mode** (`foundation.holiday`): `HOLIDAY`, `ANNOUNCES_IT` (bool),
`GiftSchedule(random) -> schedule | nil`.

**Hazard** (`foundation.hazards`): `NewState(config)`,
`OnDamaged(state, attackerTeam) -> outcome`, `OnInput(state, name, value) -> outcome`,
`OnTouch(state, toucher) -> outcome`, `Tick(state, now) -> outcome`. Outcomes
are `NONE`, `EXPLODE { team, damage, radius, halfFalloff, forceFriendlyFire }`,
`FIZZLE`, and `ZAP { targets }`.

**Projectile** (`foundation.projectile`): `NewState(config)`,
`OnTouch(state, other) -> outcome`, `Tick(state, now) -> outcome`. Outcomes
are `NONE`, `DETONATE`, `BOUNCE` and `EXPIRE`.

### 1.4 Ports (implemented by entities or controllers, faked in tests)

`foundation.npc.actor.METHODS` is implemented by `wetsand_nextbot` and faked
by `tests/fake_actor.lua`. Method names are TF2's wherever TF2 has one:

| group | methods |
|---|---|
| time, chance | `Now()`, `RandomFloat(lo, hi)`, `RandomInt(lo, hi)` |
| self | `IsAlive()`, `GetAbsOrigin()`, `SetAbsOrigin(v)`, `WorldSpaceCenter()`, `EyePosition()`, `GetYaw()`, `SetYaw(deg)`, `GetHealth()`, `SetHealth(n)`, `GetMaxHealth()`, `SetMaxHealth(n)`, `GetOwnerEntity()`, `GetEntIndex()`, `Remove()`, `Shared()` (the npc controller's table for my variant), `Vector(x,y,z)` (a Vec: `+ - *`, `:Length()`, `:Length2D()`, `:GetNormalized()`, `:Dot(v)`, `.x .y .z`) |
| targets (opaque handles) | `IsTargetValid(t)`, `IsTargetAlive(t)`, `TargetOrigin(t)`, `TargetCenter(t)`, `TargetEyes(t)`, `TargetVelocity(t)`, `TargetMaxHealth(t)`, `TargetIndex(t)`, `IsTargetOnGround(t)` |
| relations | `RangeTo(t)`, `IsRangeLessThan(t, r)`, `IsRangeGreaterThan(t, r)` (entity: the hull-to-hull gap of `INextBot::GetRangeTo`, the nearest point on my bounds to its centre, then its bounds to that point, via GMod `NearestPoint`; Vec: distance from my origin), `IsLineOfSightClear(t, ignoreActors)` (`CBaseCombatCharacter::IsLineOfSightClear`: eyes, centre or origin), `IsOnNavMesh(t, tolerance2D)` |
| body | `StartActivity(act)`, `IsActivity(act)`, `IsActivityFinished()`, `PlaySequence(seq)`, `IsSequenceFinished()`, `AddGesture(act)`, `IsPlayingGesture(act)`, `SetPoseParameter(name, v)`, `SetSkin(n)`, `SetModelScale(s)`, `SetBoneScale(bone, s)`, `AttachProp(model, bone)`. Activities are engine names, e.g. `"ACT_MP_RUN_MELEE"` |
| motion | `SetDesiredSpeed(u)`, `FaceTowards(v)`, `Approach(v)`, `IsAttemptingToMove()`, `GetGroundSpeed()`, `NewPath()` -> `{ Compute(goalVec), Update(), GetAge(), IsValid(), Invalidate(), SetMinLookAheadDistance(d), GetCurrentGoalPos() }` |
| effects | `EmitSound(name)`, `DispatchParticleEffect(name, v)`, `ScreenShake(v, amp, freq, dur, radius)`, `ApplyImpulse(t, v)`, `DealDamage(t, amount, dmgType, attacker)`, `FireOutput(name, activator)`, `Spawn(class, config, pos)` (goes to the npc controller) |

- Damage types keep Source's names and bits (`foundation.npc.actor`):
  `DMG_GENERIC=0, DMG_CRUSH=1, DMG_SLASH=4, DMG_BURN=8, DMG_BLAST=64, DMG_CLUB=128`.
- Event payloads are plain values, built once at the entity:
  - `damageEvent = { attacker, inflictor, amount, dmgType, position, crit }`;
  - OnOtherKilled gets `(victim, damageEvent)`;
  - OnContact gets `(other)`.

`foundation.npc.combatant.METHODS` extends the actor for team combat. It is
implemented by `wetsand_combat_nextbot` using `foundation.teams` and
`foundation.players` data, and faked by `tests/fake_combatant.lua`:

- `GetTeamNumber()`, `TeamOf(t)`, `CollectPlayers(team)` (living; nil means
  RED and BLU), `CollectNPCs(kind)`, `InCond(t, cond)`, `IsInvulnerable(t)`,
  `InRespawnRoom(t)`
- `StunPlayer(t, duration, reduction, flags)`, `AddCond(t, cond, duration)`
- `RoundHasBeenWon()`, `DropSpellPickup(v, tier)`, `Explode(config)`,
  `HolidayActive(h)`
- `Tag()` (the `tag` controller), `SetBossHealth(fraction)`,
  `SpawnPoints(name) -> list of Vec` (`info_target`s by name)

`foundation.spells.caster.METHODS` is implemented by the spells controller
and faked by `tests/fake_caster.lua`:

- `Now()`, `RandomFloat()`, `RandomInt()`, `Owner()`, `TeamOf(t)`,
  `ShootPosition()`, `EyeVectors() -> forward, right, up`
- `TraceHull(from, to, size)`, `EntitiesInSphere(v, r) -> list`,
  `IsVisible(from, t)`, `Heal(t, n)`, `AddCond(t, cond, d)`,
  `SetVelocity(t, v)`, `GetVelocity(t)`, `Push(t, v)`
- `Damage(t, n, dmgType)`, `Explode(config)`,
  `LaunchProjectile(class, config) -> handle`, `SpawnNPC(class, config, pos)`,
  `Teleport(t, v)`, `Particle(name, v)`, `EmitSound(name)`

## 2. NPC framework (W1, engine-neutral)

The `foundation.npc` Behavior engine must reproduce these rules exactly, each
citing the C++ function in a comment:

- `InvokeOnStart` builds and starts the child before the parent's `OnStart`.
- `InvokeUpdate` runs `IsOutOfScope`, then `ProcessPendingEvents` (which also
  takes SUSPEND_FOR results left on buried actions), then the child's update,
  and the parent's `Update` last.
- `ApplyResult`:
  - CHANGE_TO calls `OnEnd(old, new)`, then `OnStart(new, old)`. The new
    action inherits the parent and the buried action, and a result from
    `OnStart` is applied at once.
  - SUSPEND_FOR suspends the topmost covering action, and `OnSuspend`
    returning Done ends it.
  - DONE ends the action and resumes the buried one. The resume is skipped
    while the buried action holds a pending change.
- `InvokeOnEnd` ends the children first, then the action itself, then the
  actions covering it.
- Events (`PROCESS_EVENT`):
  - An unstarted action ignores them.
  - An event walks the action and the actions buried under it while each
    returns Continue. The first other result is stored on that action; it
    replaces a stored result when its priority is greater than or equal.
  - The event then recurses into the contained child.
- A Behavior whose last action finished is empty, and updating it does nothing.

`foundation.npc.path.ground` ports the shared body of `CZombiePathCost`
(`sdk/server/tf/halloween/zombie/zombie.h`) and `CHeadlessHatmanPathCost`:

- no from-area costs 0; not traversable is IMPASSABLE;
- dist is the ladder length, else the length when above 0, else the centre
  distance;
- a climb of at least stepHeight is IMPASSABLE when it reaches maxJumpHeight,
  and otherwise adds `JUMP_PENALTY*dist`;
- a drop below −deathDropHeight is IMPASSABLE;
- the cost is `fromCostSoFar + dist*preference`.

`.path.scatter` is ground with
`preference = 1 + 50*(1 + cos(entIndex*areaId*(floor(now/10)+1)))`. This is
the zombie's term, which spreads bots over routes.

`foundation.npc.spawner` ports `CZombieSpawner` as a neutral model:
`Spawner.New{ maxActive, infinite, npcConfig, teamOf }` with `Enable(now)`,
`Disable()` (resets spawned and forgets the active NPCs),
`SetMaxActive(n)`, `Died(handle)`, `Spawned(handle)`, and
`Think(now, random) -> spawnRequest | nil, nextThink`. It thinks every 0.2 s
when idle and 1.5–3 s after a spawn. A finite spawner spawns while
`spawned < max`; an infinite one while `active < max`. `teamOf` is the
variant's team strategy.

**`wetsand_nextbot` entity** (`base_nextbot`, `ENT.Type = "nextbot"`; neutral).
A subclass sets `ENT.Variant = "foundation.npc.<variant>"`. It works as
follows:

- `Initialize`:
  - `self.npc = WETSAND.Feature("npc"):Bind(self, self.Variant, self:Config())`;
  - applies the variant's `LOCOMOTION` to `self.loco`;
  - checks the nav mesh, printing one line per map:
    `wetsand_nextbot: <map> has no usable navigation mesh; run .devtools/bin/nav_convert.py or nav_generate`.
- `BehaveUpdate(interval)` calls `self.npc:Update(interval)`. There is no
  coroutine.
- `BodyUpdate()` ports `CHeadlessHatmanBody::Update`: `move_x`/`move_y` from
  the ground motion, playback rate = speed / sequence ground speed clamped to
  −4..12, then `FrameAdvance()`.
- Engine hooks go to `self.npc:Event(...)`: OnInjured, OnKilled,
  OnOtherKilled, OnContact, OnStuck, OnUnStuck, OnLandOnGround, OnLeaveGround,
  OnNavAreaChanged and OnIgnite.
- `OnKilled` marks the actor dead and runs `hook.Run("OnNPCKilled", ...)`,
  with no ragdoll.
- An `EntityTakeDamage` hook asks the model's `FilterDamage`.
- `Path:Compute` gets a cost function that builds `step` from GMod's
  `(area, fromArea, ladder, elevator, length)`: `loco:IsAreaTraversable`,
  `ladder:GetLength()`, `CNavArea:GetCenter`,
  `:ComputeAdjacentConnectionHeightChange`, `:GetCostSoFar` and `:GetID`.
  It then calls the variant's `PATH` strategy.
- It implements every `foundation.npc.actor.METHODS` entry as
  `function ENT:<Name>(`.
- It knows no teams.

**`wetsand_combat_nextbot`** derives from `wetsand_nextbot` and implements
`foundation.npc.combatant.METHODS` through the `combat`, `holiday` and `npc`
controllers. Its team comes from the `TeamNum`/`teamnum` keyvalue or from
config.

**`wetsand_projectile`** is an `anim` entity, neutral. It sets
`ENT.Variant = "foundation.projectile.<x>"` and on Initialize calls
`WETSAND.Feature("combat"):BindProjectile(self, ...)`. Flight is straight or
ballistic (gravity scale). Touch and Think feed the model, and `DETONATE`
calls `self:Detonate(trace)`, which subclasses override.

## 3. Tools (W2)

`.devtools/bin/nav_convert.py MAP.bsp|MAP.nav... [--out DIR]`:

- reads a loose `.nav`, or the one embedded in the BSP (lump 40, zip entry
  `maps/<map>.nav`, LZMA method 14, which Python's zipfile reads);
- parses it per `CNavMesh::Load` and `CNavArea::Load` (`sdk/server/nav_file.cpp`, v16);
- drops the u32 that `CTFNavArea::Save` appends to each area
  (`tf/nav_mesh/tf_nav_area.cpp`);
- writes sub-version 0 and the BSP's real size;
- writes to `garrysmod/maps/<map>.nav` by default, the path in `gmod_lua.py`.

`.devtools/bin/tf2_content.py model|sound|particle NAME...` and
`tf2_content.py lua FILE...` read the `tf2_misc_dir.vpk` tree, the soundscript
manifest, and the particle names in the `.pcf` files. The same method already
confirms that every model, soundscript, particle and `vgui/spellbook_*` icon
named in this plan exists in TF2's content, except `fatty_explode`
(pl_breadspace's generic bombs, which is in no shipped `.pcf`).

## 4. Combat, holiday, and the seam data (W3)

- **`foundation.players`** (additions only), from `tf_shareddefs.h`:
  `COND.DISGUISED=3, STEALTHED=4, STEALTHED_BLINK=9, INVULNERABLE_USER_BUFF=52,
  STEALTHED_USER_BUFF=64, STEALTHED_USER_BUFF_FADING=66, HALLOWEEN_SPEED_BOOST=72,
  HALLOWEEN_TINY=75, HALLOWEEN_GHOST_MODE=77`; `STUN.BY_TRIGGER=128`.
- **`foundation.combat`**:
  - `CRIT_MULTIPLIER=3`.
  - `Explosion.New{ origin, radius, damage, attackerTeam, attacker, halfFalloff,
    forceFriendlyFire, crit }` then `:DamageTo{ team, isAttacker, distance,
    visible } -> amount | nil`. This is `CTFRadiusDamageInfo`: the damage
    remaps from damage to damage×falloff over the radius, where falloff is 0.5
    with half falloff and damage/radius otherwise. Distance is the lesser of
    the distance to the centre and to the origin. Nothing passes through the
    world. Teammates are skipped, except the attacker, unless
    forceFriendlyFire.
- **`foundation.npc.targeting`** (the TF2 victim rules as data):
  - `IsHiddenFromNPC(conds)`: stealthed and not burning, jarated,
    stealth-blinked or bleeding; or in ghost mode.
  - `EnemyTeamsOf(team)`: RED gives {BLUE}, BLUE gives {RED}, anything else
    gives {RED, BLUE}.
- **`foundation.holiday`**:
  - Constants: `HOLIDAY_NONE=0, BIRTHDAY=1, HALLOWEEN=2, CHRISTMAS=3, FULLMOON=8,
    HALLOWEEN_OR_FULLMOON=9` (EHoliday, `econ_item_constants.h`).
  - `Holiday.New{ mapHoliday, forced, spellsForced }` gives
    `:Active(h)` (TF_IsHolidayActive with no calendar), `:UsingSpells()`,
    `:SetUsingSpells(b) -> changed`, and `:Mode() -> variant | nil` (the mode
    registered for the active holiday).
  - `foundation.holiday.halloween`: `HOLIDAY=HALLOWEEN`, `ANNOUNCES_IT=true`,
    `GiftSchedule(random)`. The first gift comes 7–12 min in, then one every
    7–12 min; `LIFETIME=240` (`CTFGameRules::PeriodicHalloweenUpdate`,
    `tf_halloween_gift_lifetime`). `:Tick(now, players) -> {player, location}`
    gives one gift per player at a random registered location.
- **Controllers**: `combat` and `holiday` (section 1.2), including the server
  convars `tf_forced_holiday` and `tf_spells_enabled` (TF2 names, defaults 0).
  `DropSpellPickup(pos, tier)` returns at once unless UsingSpells. It creates
  `tf_spell_pickup` with `Configure{ tier, dropped = true }` at pos+(0,0,50)
  with velocity 500·normalize(rand ±0.5, rand ±0.5, 1). A dropped pickup uses
  flygravity with bounce, does not respawn, and is removed after 30 s
  (`TF_POWERUP_LIFETIME`).
- **`tf_logic_holiday`** (W3 takes ownership): a binding. Its keyvalues
  (`holiday_type`, `tauntInHell`, `allowHaunting`) go to `holiday:BindHoliday`.
  Input `HalloweenSetUsingSpells(int)` calls `SetUsingSpells(v ~= 0)`, which
  on turning on calls `WETSAND.Feature("spells")`.
  `Halloween2013TeleportToHell` logs once and does nothing.

## 5. P0: skeletons (W4)

### `foundation.npc.zombie` (an NPC variant: CZombie and its actions)

Constants:

- `SKELETON_NORMAL=0, SKELETON_KING=1, SKELETON_MINI=2`
- `KIND="zombie"`, `PATH="foundation.npc.path.scatter"`
- `MAX_ACTIVE_DEFAULT=30` (`tf_max_active_zombie`), `CHASE_MIN_DURATION=3`,
  `STAND_AND_SWING_RANGE=50`, `SWING_RANGE=150`, `REPATH_INTERVAL=0.5`,
  `LOOKAHEAD=100`, `OFF_MESH_TOLERANCE=50`
- `STOMP_DELAY=1`, `STOMP_RANGE=200`, `STOMP_FORCE=500`
- `MINI_LIFETIME=30`, `MINIS_ON_DEATH=3`
- `SKIN_RED=0, SKIN_BLUE=1, SKIN_HALLOWEEN=2`
- `LOCOMOTION = { runSpeed=300, stepHeight=18, jumpHeight=18, deathDropHeight=200, maxYawRate=200, acceleration=500, deceleration=500 }`
- `HULL` = (−13,−13,0)–(13,13,68) × scale, IBody's defaults

`TYPES[type]`: data plus per-type strategy functions, so there is no switch
on type (`CZombie::SetSkeletonType`, `CZombieBehavior`):

| type | model | scale | health | attackRange | attackDamage | laugh s | laugh sound | onDeath | special | dress |
|---|---|---|---|---|---|---|---|---|---|---|
| NORMAL | skeleton_sniper.mdl | 1 | 50 | 50 | 30 | 4–5 | Halloween.skeleton_laugh_medium | throw 3 MINI skull grenades | none | — |
| KING | skeleton_sniper_boss.mdl | 2 | 1000 | 100 | 100 | 6–7 | Halloween.skeleton_laugh_giant | DropSpellPickup(origin, TIER_RARE) | stomp | crown `player/items/demo/crown.mdl` on `bip_head` |
| MINI | skeleton_sniper.mdl | 0.5 | 50 (Spawn's) | 40 | 20 | 2–3 | Halloween.skeleton_laugh_small | none | none | `bip_head` scale 3 |

Rules (`zombie.cpp`, `zombie_behavior/*.cpp`):

- **NewState** (`SpawnAtPos` and `Spawn`), in this order: the team, then
  health 50, a random yaw and `ACT_TRANSITION`. Next, the skin from
  `SKIN_BY_TEAM`: any team but RED or BLU gets SKIN_HALLOWEEN and becomes
  `Teams.HALLOWEEN`. Then the lifetime timer, then the type. `SpawnerTeam`:
  RED and BLUE stay, everything else becomes HALLOWEEN. `Cull`: over
  `tf_max_active_zombie` (config, from the binding's convar), the oldest
  non-kings are forced to suicide.
- **ZombieBehavior**:
  - Update:
    - When dead, remove and return Done.
    - When `ShouldSuicide` holds (lifetime elapsed, owner changed team, or
      forced), `FireOutput("OnDeath", me)` once, then remove and return Done.
    - Laugh: an unstarted timer starts at the type's range; an elapsed one is
      invalidated, and the laugh plays.
  - OnKilled: only when the attacker is a player or NPC. Run the type's
    `onDeath`, remove, and return TryDone.
    - NORMAL: three `Spawn("tf_projectile_spellspawnzombie", { thrower = owner
      or me, team, skeletonType = MINI }, origin)`.
  - Entity side (`Event_Killed`): `Halloween.skeleton_break`, and `OnDeath`
    fires once with activator = inflictor. Any removal breaks the model into
    gibs (`UpdateOnRemove`; GMod `GibBreakClient`) and removes the crown.
- **FilterDamage**:
  - refuse an attacker on my team;
  - otherwise add the gesture `ACT_MP_GESTURE_FLINCH_CHEST` if it is not
    playing;
  - particle at the damage point: `spell_skeleton_goop_green` for HALLOWEEN,
    otherwise `spell_pumpkin_mirv_goop_red`/`_blue`.
- **Spawn action**: `ACT_TRANSITION` (spawn01–07), then ChangeTo Attack when
  the activity finishes.
- **Attack**:
  - OnStart: lookahead 100, `ACT_MP_RUN_MELEE`, special timer 5–10 s.
  - Update:
    - SelectVictim. With no live target, Continue.
    - When the range is over 50 or there is no LOS: recompute the path when
      its age is over 0.5, then Update it.
    - Inside 150: face the target's centre and play the gesture
      `ACT_MP_ATTACK_STAND_MELEE` if it is not playing.
    - Inside attackRange:
      - the type's `special`, when its timer has elapsed: restart the timer
        at 5–10 s and `SuspendFor(StompAttack)`;
      - otherwise, when the attack timer has elapsed: restart it at
        0.8–1.2 s and `DealDamage(target, attackDamage, DMG_SLASH, owner or me)`.
    - Keep `ACT_MP_RUN_MELEE` running.
  - OnStuck: `DealDamage(me, 99999.9, DMG_SLASH)`.
  - OnContact: a skeleton whose team is not HALLOWEEN, touching a living
    player of another team, locks that player as target for 3 s.
- **SelectVictim**:
  - Keep a chaseable target while its 3 s focus lasts.
  - Otherwise pick the nearest (INextBot range) of:
    - living players of `EnemyTeamsOf(team)` who are chaseable and not
      `IsHiddenFromNPC`;
    - `CollectNPCs(KIND)` of another team who are chaseable.
  - Chaseable means alive, `IsOnNavMesh(t, 50)` and not `InRespawnRoom(t)`.
  - A new victim restarts the focus.
- **StompAttack** (`CZombieSpecialAttack`):
  - `ACT_SPECIAL_ATTACK1` (MELEE_swing3).
  - At 1 s, particle `bomibomicon_ring`.
  - Every living player of the target teams (`EnemyTeamsOf`) whose eyes are
    within 200 gets an impulse of 500·(flat direction normalised, z=1) and
    attackDamage `DMG_SLASH`.
  - Done when the activity finishes.

### `foundation.projectile.grenade` and the skull grenade

The model is a timed grenade: `{ fuse, explodeOnTouch=false }`. Tick gives
`DETONATE` when the fuse runs out.

`tf_projectile_spellspawnzombie` (a `wetsand_projectile`; the
`CreateSpellSpawnZombie` and `CTFProjectile_SpellSpawnZombie` pair):

- `Configure{ thrower, team, skeletonType }`.
- Model `props_mvm/mvm_human_skull_collide.mdl`, starting at pos +
  (±32, ±32, 16).
- Velocity: a random unit vector with z replaced by 1–1.6, times 250–300.
  Spin (300,300,100). Fuse 2–2.5 s.
- On detonation: trace from +8 to −32, then
  `Spawn("tf_zombie", { team, lifetime = MINI_LIFETIME, owner = thrower if a
  player, skeletonType }, endpos + normal·2)`. Effects: the team goop
  particle and `Cleaver.ImpactFlesh`.

### Bindings

- **tf_zombie** (`wetsand_combat_nextbot`, `Variant="foundation.npc.zombie"`):
  - Keyvalues: `TeamNum`, `modelscale`. `health`/`max_health` are overwritten
    by NewState, as in TF2.
  - `Configure{ team, lifetime, owner, skeletonType }` before Spawn.
  - Output `OnDeath`. Only the engine's `Kill` input works; others are
    refused, as in TF2 (precipice sends `Enable`).
  - Server convar `tf_max_active_zombie` (default `MAX_ACTIVE_DEFAULT`), created by
    the first binding and passed in config.
- **tf_zombie_spawner** (point):
  - Keyvalues `TeamNum, zombie_lifetime, max_zombies, infinite_zombies,
    zombie_type` go to `npc:BindSpawner`.
  - Inputs `Enable`, `Disable` and `SetMaxActiveZombies(int)` call the
    spawner model.
  - The controller runs its Think and spawns `tf_zombie` at the spawner's
    origin with no owner.

How the maps drive them:

- pl_hasslecastle has 25 spawners (type 0/1, max 1–3, lifetime 0 or 240,
  finite), enabled by `path_track OnPass` and `cap_N_relay OnTrigger` with
  delays of 0–3 s.
- pl_bloodwater: every 103 s `npc_event_case PickRandom` can fire
  `npc_event_skeletons`, which sends `Enable`, then `Disable` 45 s later.
- No map sets a spawner's `TeamNum`, so these skeletons are HALLOWEEN.

## 6. P1: bosses (W5)

**`foundation.npc.halloween_boss`** (the template). Constants:
`BOSS_INVALID=0, BOSS_HHH=1, BOSS_MONOCULUS=2, BOSS_MERASMUS=3`; `DPS_WINDOW=5`.

- It owns the attacker list and the DPS (`RememberAttacker`,
  `UpdateDamagePerSecond`).
- FilterDamage refuses my own team and `RoundHasBeenWon()`, then calls
  `ModifyDamage`.
- `IsSpell = team ~= Teams.HALLOWEEN`.
- At spawn: `SetHealth(Health(players, level))`.
- Entity binding `halloween_base_boss` (a `wetsand_combat_nextbot`):
  - `Configure{ team, owner }` (`SpawnBossAtPos`: the caller spawns at pos+10 z).
  - A map-spawned boss takes its team from `TeamNum`/`teamnum`, else
    UNASSIGNED; the maps' eyeballs set 5.
  - `Break()` makes gibs.

**`foundation.npc.headless_hatman`** (a boss variant; `headless_hatman.cpp`,
`halloween_behavior/headless_hatman_*.cpp`). The constants keep their TF2
names as server convars:

| convar | value |
|---|---|
| `tf_halloween_bot_health_base` | 3000 |
| `tf_halloween_bot_health_per_player` | 200 |
| `tf_halloween_bot_min_player_count` | 10 |
| `tf_halloween_bot_speed` | 400 |
| `tf_halloween_bot_attack_range` | 200 |
| `tf_halloween_bot_chase_duration` | 30 |
| `tf_halloween_bot_terrify_radius` | 500 |
| `tf_halloween_bot_chase_range` | 1500 |
| `tf_halloween_bot_quit_range` | 2000 |

Other constants: `AXE_SWING_DELAY=0.58`, `ATTACK_INTERVAL=1`,
`SCARE_INTERVAL=20`, `HOME_RECALC=3`, `WARN_IT_INTERVAL=7`,
`PATH="foundation.npc.path.ground"`, and locomotion step 18, jump 18, yaw 200.

- **Body:** `models/bots/headless_hatman.mdl` with `AttachProp("weapons/c_models/c_bigaxe/c_bigaxe.mdl")`.
  Each tick the pose parameter `damage` = 1 − health/max.
- **Emerge:**
  - `ACT_TRANSITION`, `halloween_boss_summon`, `Halloween.HeadlessBossSpawnRumble`.
  - Rises 200 over 3 s from origin+10, with a shake every 0.25 s
    (15, 5, 1, 1000). Faces the nearest player.
  - Pushes players within 250 of the emerge point by 200·(flat, z=1).
  - Then Attack.
- **Attack:**
  - Every 3 s, home becomes the first control point of the current round that
    BLU does not own and may capture. The binding feeds this from
    `WETSAND.TeamCanCapPoint`.
  - **Victim and IT:** a chaseable victim is alive, on the mesh, not in a
    respawn room, not invulnerable, and within 2000 of home.
    - With no IT, the nearest chaseable player within 1500 of home becomes IT
      (`Tag():Set`), for 30 s of chase.
    - The nearest visible player is remembered for facing.
  - **Laugh:** every 3–5 s when not swinging; with no IT, a 25% chance each of
    `ACT_MP_GESTURE_VC_FISTPUMP_MELEE` or `..._FINGERPOINT_MELEE`.
  - **Movement:**
    - With no IT: repath home when the path is older than 3 s, or face the
      nearest visible player once home (within 50).
    - With IT: warn them every 7 s, and chase (repath after 1 s) while the
      range is over 100 or there is no LOS.
  - **Target inside 200:**
    - When the 20 s scare timer has elapsed, `SuspendFor(Terrify)`.
    - Otherwise, every 1 s: `ACT_MP_ATTACK_STAND_ITEM1`, swing timer 0.58 s,
      `Halloween.HeadlessBossAttack`.
  - **Swing lands:**
    - It hits when the target is within 200, in LOS, and
      dot(forward, toTarget) > closeness·0.27, where closeness is 0 inside 100
      and rises to 1 at 200.
    - A hit deals the target's max health ×0.8 `DMG_CLUB` and plays
      `Halloween.HeadlessBossAxeHitFlesh`.
    - Every swing: `Halloween.HeadlessBossAxeHitWorld`, a shake, and
      `halloween_boss_axe_hit_world`.
  - **Animation:** moving uses `ACT_MP_RUN_ITEM1` above 50% health, otherwise
    `ACT_MP_RUN_MELEE`, with a footfall shake every 0.25 s. Standing uses
    `ACT_MP_STAND_ITEM1`.
  - **Events:**
    - OnStuck: `SetAbsOrigin(path goal + 10z)`.
    - OnContact: a living combatant becomes the target for 3 s.
- **Terrify:** `ACT_MP_GESTURE_VC_HANDMOUTH_ITEM1`; `Halloween.HeadlessBossBoo`
  at 0.25 s. From 0.75 s, stun each player within 500 and in LOS for 2 s,
  reduction 0, `STUN.LOSER_STATE | STUN.BY_TRIGGER`. Done at 1.25 s.
- **Dying:** `ACT_DIESIMPLE`, `Halloween.HeadlessBossDying`. When the activity
  finishes: Break, `halloween_boss_death`, remove, and `Tag():Set(nil)`.

**`foundation.npc.tag`** (TF2's IT, `CTFGameRules::SetIT`; a model owned by
the `tag` controller, which `headless_hatman` loads):

- `Set(p)` returns notifications. When `announce`, the new IT hears
  `Player.YouAreIT` and `Halloween.PlayerScream`, and the old IT hears
  `Player.TaggedOtherIT`.
- `OnMeleeHit(attacker, victim)`: IT passes to the victim
  (`tf_weaponbase_melee.cpp`).
- `OnDeath(victim, killer)`: IT passes to the killer (`tf_player.cpp`).

`announce` = `HolidayActive(HALLOWEEN)` and the mode's `ANNOUNCES_IT`. The
controller feeds the model from `EntityTakeDamage` (player melee:
`DMG_CLUB|DMG_SLASH`) and `PlayerDeath`, but only while a `headless_hatman`
is bound.

**`foundation.npc.eyeball_boss`** (a boss variant with `HOVER`;
`eyeball_boss.cpp`, `eyeball_behavior/*.cpp`, `teleport_vortex.cpp`).
Constants (TF2 convar names):

| convar | value |
|---|---|
| `tf_eyeball_boss_lifetime` | 120 |
| `_lifetime_spell` | 8 |
| `_speed` | 250 |
| `_hover_height` | 200 |
| `_acceleration` | 500 |
| `_horiz_damping` | 2 |
| `_vert_damping` | 1 |
| `_attack_range` | 750 |
| `_health_base` | 8000 |
| `_health_per_player` | 400 |
| `_health_at_level_2` | 17000 |
| `_health_per_level` | 3000 |

Also `SKIN_NORMAL=0, SKIN_RED=1, SKIN_TEAM_RED=2, SKIN_TEAM_BLUE=3`,
`ROCKET_DAMAGE=50`, `ROCKET_SPEED=1100` and `DEATH_RANGE`.
`foundation.npc.hover` is `CEyeballBossLocomotion::MaintainAltitude` and
`Update` as a model: `Hover.New(cfg)`, then
`:Step(dt, groundZ, ceilingZ, approachGoal) -> velocity, desiredMove`. The
binding resolves the move with hull traces and reflects off surfaces.

- **Spawn:** `halloween_demoeye.mdl`, bounds ±50. The spawn spots are
  `SpawnPoints("spawn_boss_alt")`.
- **Mood:**
  - Enraged when a spell, when health is under 1/3, or while the rage timer
    runs. The timer runs 5 s after a crit or when DPS > 300, and 20 s after a
    stun.
  - Grumpy when health is under 2/3.
  - Skin and the `anger` pose parameter follow the mood: 1 enraged, 0.4
    grumpy, 0 otherwise.
- **Emerge:**
  - Map-spawned: `arrives`, `halloween_boss_summon`; rises 150 over 3 s from
    origin+100. Pushes players within 250 of the ground by 200·(flat, z=1).
    For the first 2 s, players within 100 (200 above level 1) take 2× their
    max health `DMG_BLAST`.
  - Spell: `teleport_in`.
- **Idle:**
  - Talk every 3–5 s (`Halloween.EyeballBossIdle`), or every 1–2 s with
    `...Rage` when enraged.
  - Move timer 10–15 s: when near the ground, SuspendFor Teleport, or Escape
    once the lifetime is over. A spell eyeball escapes at 8 s.
  - Escape warnings at 60, 30 and 10 s via `WETSAND.Announce`.
  - Looks around with `lookaround1/2/3`. After anyone dies, laughs with
    `laugh` and `Halloween.EyeballBossLaugh`.
  - A visible victim triggers SuspendFor Notice.
- **Notice:** 0.25 s with `Halloween.EyeballBossBecomeAlert`, then Approach.
- **Approach:**
  - Gives up after 5 s, and leaves when a better victim appears after 0.5 s.
  - Lingers 1 s without LOS.
  - Within 750 (×2 when enraged), ChangeTo LaunchRockets. Otherwise approaches
    the victim's centre at 250.
- **LaunchRockets:**
  - Calm: 1 rocket after 0.5 s (`firing1`). Grumpy or enraged: 3 rockets
    after 0.25 s (`firing2`/`firing3`).
  - Rockets are 0.3 s apart, at speed 1100 when enraged and 330 otherwise.
  - When enraged and further than 150, it leads the target.
  - Each rocket is `Spawn("tf_projectile_rocket", { damage 50, crit = not
    spell, model eyeball_projectile.mdl })` with `Weapon_RPG.SingleCrit`.
  - Strafes ±100, by the victim index's parity.
- **Teleport:** `teleport_out`, then a hidden vortex (`spawn_purgatory`),
  `eyeboss_tp_normal` and `Halloween.EyeballBossTeleport`. Moves to a random
  `spawn_boss_alt` + 75 z, plays `teleport_in`, then Done.
- **Escape:** `escape`, `Halloween.EyeballBossLaugh`, `eyeboss_tp_escape`;
  remove, then reset `Shared().level` to 1.
- **Dead:**
  - `death` and `Halloween.EyeballBossStunned`, then falls at −300 z
    acceleration until under 100 above the ground or 10 s.
  - Then `eyeboss_death`, `Cart.Explode`, `Halloween.EyeballBossDie`, and a
    shake (25, 5, 5, 1000).
  - Players within 750 and in LOS get 10 s of `COND.URINE`.
  - Spawns a death vortex (`spawn_loot`) and, unless it is a spell, adds 1 to
    `Shared().level` (TF2's static `m_level`).
- **Victims:** the nearest visible living player of any team (a spell eyeball:
  the enemy team) who is not `IsHiddenFromNPC`, plus visible `zombie` NPCs of
  other teams, and `boss` NPCs when it is a spell.
- **ModifyDamage:** a spell eyeball takes 0. `SetBossHealth(health/max)`
  (the controller networks Global2 `wetsand_boss_health`; 0 hides the bar).
- **teleport_vortex** (a model in the eyeball part, bound by an entity):
  - A ±50 trigger living 5 s.
  - It pulls airborne players who are looking at it and in LOS within 500
    (impulse 30·dir).
  - Touch teleports the player to a random `info_target` named `spawn_loot`
    (death vortex, book model, `Halloween.TeleportVortex.BookSpawn`) or
    `spawn_purgatory`. It avoids spots within 25 of an enemy, and telefrags
    the enemy when every spot is taken (`SendPlayerToTheUnderworld`).
- **`foundation.projectile.rocket`** and **tf_projectile_rocket**
  (`CTFBaseRocket`): straight flight; touch → DETONATE; `Explosion` radius
  `ROCKET_RADIUS=146`, damage ×`CRIT_MULTIPLIER` when crit.

**`foundation.npc.merasmus`** (a boss variant; `merasmus.cpp`,
`merasmus_behavior/*.cpp`, `merasmus_trick_or_treat_prop.cpp`). His convars
keep TF2's names and defaults (`tf_merasmus_*`, `CONVARS`; health 33750 +
2500 per player past 10, lifetime 120, speed 600, attack range 200, stun 2,
bomb heads 15 s and 1 per team, props 150 health).

- **Collision:** players pass through him and he through them
  (`CMerasmusLocomotion::ShouldCollideWith`); the variant's
  `PLAYERS_PASS_THROUGH` puts the NextBot in `COLLISION_GROUP_PASSABLE_DOOR`,
  which bullets, melee traces and projectiles still hit.
- **Arrival:** `Halloween.MerasmusAppears` to everyone, `merasmus_summoned`,
  the map's `boss_enter_relay` (he moves to it), `merasmus_spawn`; then the
  reveal (`ACT_SHIELD_UP`): bar shown, players within 400 pushed by 500,
  nearby bombs removed, faces the nearest player.
- **Attack:** the nearest chaseable player within 2000 of home (the first
  point BLU may take), kept 7 s. Staff every 1 s inside 200 (70 `DMG_CLUB`,
  push 500, cone as the Horsemann's, reach 180); a bomb every 2-3 s
  (`tf_projectile_pipe`: 50 damage, radius 300, 2 s fuse, `bomb_temp.mdl`);
  a fire spell every 3-4 s (up to 6 + level-1 players within 600 + 50 per
  level: burning 5 s, flung up 1000, 50 to 20 `DMG_BURN` by distance, plus 5
  per level).
- **Bomb heads:** at 10 s, then every 16 s, each team's longest-spared
  living player in a `func_nav_prefer` area: loser-state stun and speed for
  15 s, then a 100-damage blast at their head (theirs too) that throws
  players within 150. Reaching him within 100 frees and buffs them (pumpkin
  crits, speed, invulnerability 10 s), blows the bomb on him and stuns him
  2 s; the third stun sends him home + 75 to rain rings or spokes of bombs
  from the air over the first point (`AOEAttack`), otherwise to a free
  preferred area.
- **Hiding:** after losing 45% since his reveal he hides among up to 10
  props on preferred areas 500 apart; 70-100% of them must be smashed, and
  the last one brings him out where it stood and buffs its finder. Past the
  first level he heals 0.1% of his max per second per level while hidden.
- **Leaving:** `merasmus_escape_warning` at 60, 30 and 10 s; at 120 s (not
  while stunned or aloft) `ACT_FLY`, `merasmus_escaped`, `boss_exit_relay`,
  and the level resets to 1.
- **Death:** `Halloween.MerasmusBanish`, the death music to everyone, then
  gibs, `merasmus_killed`, `boss_dead_relay`, a loot vortex that sends each
  team to `spawn_loot_red`/`spawn_loot_blue`, and the next one is a level up.
- **Boss timer** (`foundation.npc.boss_timer`, the `boss_timer` feature;
  `CTFGameRules::SpawnHalloweenBoss`): his death or departure starts it at
  `tf_merasmus_spawn_interval` ± `tf_merasmus_spawn_interval_variation`
  (180 ± 30; a minute past level 3); any Halloween boss alive restarts it;
  a new round forgets it and the next update starts it afresh. When it runs
  out, during Halloween, outside setup and waiting for players, with
  `tf_halloween_bot_min_player_count` (10) living humans, Merasmus spawns at
  a `spawn_boss`, else on the point BLU must take next (it reverts to
  neutral and KOTH clocks pause), else on a random nav area 100 a side
  outside the spawn rooms. `tf_halloween_force_boss_spawn` and
  `cc_spawn_merasmus_at_level N` (cheats) skip the wait. TF2 runs it only on
  koth_lakeside_event; Sandcastle names no maps, so it runs on any map once
  a Merasmus has appeared there.
- **Weapon multipliers** (`MerasmusModifyDamage`, `WEAPON_SCALES`): a
  player's hit is scaled by the TF2 weapon its damage type stands for:
  `DMG_SNIPER` (sniper rifle), `DMG_BULLET|DMG_NEVERGIB` (HL2's crossbow
  bolt: the Huntsman) and `DMG_SLASH` (knife) x3, `DMG_BUCKSHOT`
  (scattergun) x2. Plain bullets, clubs, blasts (rockets, grenades, pumpkin
  bombs, bomb heads) and fire (spells) are as dealt, as TF2's spellbook and
  bombs are; the zapper deals no damage; NPCs' hits are as dealt. No damage
  type stands for the minigun or sentry (x0.5) or the revolver, Soda
  Popper, Shortstop and Baby Face's Blaster. The NPC's `FilterDamage` now
  returns the amount taken, which the npc controller applies.
- **His killers:** `merasmus_killed` keeps TF2's one field, `level`; each
  player who hit him in his last 5 s gets `merasmus_killer { player, level }`
  (Sandcastle's own, for TF2's SayText2), which clients show as "NAME has
  defeated MERASMUS! (LEVEL n)", unless sv_cheats was on when he spawned.
  The econ hat levels, Valve achievements and gamestats, soul packs and
  `halloween_boss_killed` (which feeds only those) have no counterpart, and
  TF2's scoreboard gives no points for him.
- **Wheel of Fate** (`wheel_of_doom`, TF2's class for it; `foundation.holiday.wheel`,
  the `wheel` feature, `merasmus_dancer`): keyvalues `effect_duration`,
  `has_spiral`; inputs `Spin`, `ClearAllEffects`; outputs `OnEffectApplied`,
  `OnEffectExpired`. A spin plays `Halloween.WheelofFate`, flicks the
  faces of every wheel for 5.75 s (0.1 s apart, slowing to 0.55), Merasmus
  calls it at 1.6 s, and a second after the stop the effect lands on every
  player, with its face, Merasmus's line and the HUD's icon (blinking in
  its last 3 s). Uber (10 s at most), pumpkin crits, double speed, triple
  jump with no fall damage, big or small heads (the head bone; GMod voice
  chat cannot be pitched), quarter gravity, the Dance (everyone alive to
  `dance_teleport_<red|blue><n>`, frozen, dancing every 3.5 s for 8 s, a
  dancing Merasmus at either end of the floor by turns) and the Burn whammy
  (10 s at most). A whammy comes one roll in buffs + 1. Respawning players
  get the effects that reapply. The boss timer waits while the first wheel
  spins or names its effect. **Not done:** the Jarate rain (needs
  `tf_projectile_jar` and Jarate's effects) and the Ghosts (needs TF2's
  haunting ghosts), so Burn takes every whammy roll; and the players'
  magic voice responses (GMod players have no class voices). No payload
  event map places a wheel.
- **Left out:** the critical flag on hits while stunned or aloft (only
  TF2's hit numbers show it).
- **Bomb-rain scene:** as TF2, one of `scenes/bot/merasmus/low/
  bomb_attack_001..009.vcd` through `PlayScene` (a NextBot is a CBaseFlex):
  `Halloween.BombSuperMove<n>`, `Halloween.BombinomiconBombs` at 4.2 s and
  `Halloween.MerasmusBombTaunt` at 6 s (`.devtools/bin/tf2_scene.py` reads
  them from TF2's `scenes.image`, the only place TF2 ships them). The server
  must load TF2's `scenes.image` (tf2_misc.vpk ahead of GMod's HL2 packs in
  gameinfo.txt); a scene it lacks is reported once in the console. Prop separation and the area round the point
  are measured straight, where TF2 walks the mesh.

How the maps drive them:

- pl_bloodwater's `eyeball_cap_N_template`s are `point_template`s sent
  `ForceSpawn` by relays.
- millstone, fifthcurve, rumble and terror use the templates `horseman_spawn`
  and `eyeball_spawn`, plus `Kill` on `OnMapSpawn`/`OnMultiNewRound`.
- fifthcurve and rumble spawn Merasmus from the template `merasmus_triggered`
  (`relay_merasmus` sends `ForceSpawn`) and `Kill` him on `OnMultiNewRound`.
- The maps supply the `spawn_boss_alt`, `spawn_loot` and `spawn_purgatory`
  info_targets.

## 7. P1: hazards and gifts (W6)

- **`foundation.hazards.pumpkin_bomb`** (`sdk/shared/tf/tf_pumpkin_bomb.cpp`).
  The C++ reads no keyvalues: TF2 ignores the FGD's damage and radius, and
  hacksaw sets only fade and AutoMaterialize.
  - Defaults: team HALLOWEEN, damage 150, radius 300, scale 1.
  - A HALLOWEEN pumpkin takes any damage as `EXPLODE{ team = attackerTeam,
    halfFalloff = true }`, using `pumpkin_explode.mdl` with vphysics,
    `pumpkin_explode` and `Halloween.PumpkinExplode`, then gibs.
  - A team pumpkin (a spell) uses `pumpkin_explode_teamcolor.mdl` with skin
    BLU 2 and RED 1. Damage from its own team is EXPLODE; any other team, its
    lifetime, or `trigger_hurt` is FIZZLE (team goop).
  - Binding: `Configure{ scale, damage, radius, team, lifetime, isSpell }`.
- **`foundation.hazards.generic_bomb`** (`tf_generic_bomb.cpp`):
  - Keyvalues: `damage, radius, health, explode_particle, sound, friendlyfire,
    passActivator`, plus the model, skin and scale.
  - Input `Detonate`, output `OnDetonate`.
  - Death or Detonate gives `EXPLODE{ halfFalloff=true, forceFriendlyFire =
    friendlyfire == 1 }`, with the particle at the `alt-origin` attachment
    and the sound.
  - `OnDetonate` fires with the attacker as activator when passActivator,
    otherwise with itself.
  - Hacksaw has 8, with OnDetonate going to `Add` and
    `SpeakResponseConcept`; breadspace has 15, going to `ForceSpawn`.
- **`foundation.hazards.zapper`** (`CTFHellZap`, `tf_weapon_spellbook.cpp`):
  - `ZAP_ON_TOUCH=0, ZAP_ON_TEST=1`.
  - The zap is only a beam: `ZAP { targets }` becomes
    `util.ParticleTracerEx(ParticleEffect)` from the zapper to each target.
  - ON_TOUCH zaps the players inside every 0.25 s. `ZapTouching` zaps now.
    `Enable` and `Disable` are also inputs.
  - Keyvalues: `touch_trigger` (a `dispenser_touch_trigger` found by name),
    `ParticleEffect`, `ZapperType`.
- **Gifts** (the holiday controller and the Halloween mode's `GiftSchedule`):
  - `tf_halloween_gift_spawn_location` passes its origin to
    `holiday:AddGiftLocation` and removes itself, but only while
    `HolidayActive(HALLOWEEN)`.
  - `tf_halloween_gift_pickup` binds to the holiday controller:
    - model `props_halloween/gargoyle_ghost.mdl`;
    - only its target player is sent the entity (`SetPreventTransmit`) and
      can touch it;
    - touch plays `duck_collect_green`, `Halloween.PumpkinPickup` and
      `sf15.Merasmus.Gargoyle.Got` for that player;
    - it gives no reward (TF2's are soul packs and econ credit) and despawns
      after 240 s.

## 8. P1: spellbook (W7)

**`foundation.spells`**, the system (neutral flow):
`SpellBook.New(set)` with `EMPTY=-1, UNKNOWN=-2`. It ports the state of
`CTFSpellBook`.

| method | rule |
|---|---|
| `:Pickup(tier, now, random) -> bool` | `RollNewSpell`'s guard: refused for `TIER_COMMON` while charges remain; otherwise selected = UNKNOWN until `now + ROLL_TIME`, and the next spell = `set.Roll(tier, random)` |
| `:Tick(now) -> "rolled" \| nil` | `RollNewSpellFinish`: charges = `Definition(next).charges` |
| `:CanCast(now)` | `CanCastSpell`: charges > 0, a valid index, and the cooldown has passed |
| `:Cast(caster, now) -> bool` | `CastSpell` + `PaySpellCost` (the charge is spent before the strategy runs), then `Strategy(index):Cast(caster)`; the next cast comes no sooner than `now + CAST_COOLDOWN` |
| `:HasASpellWithCharges()` | charges > 0, or rolling |
| `:State() -> { selected, charges, rollingUntil }` | |

Parts are loaded lazily per index (`require` of `set.Strategy(index)`).

**`foundation.spells.halloween`**, the TF2 set (`g_NormalSpellList`, `g_RareSpellList`,
`g_generalSpellIndexList`):

- Indices: `SPELL_FIREBALL=0, SPELL_BATS=1, SPELL_OVERHEAL=2, SPELL_MIRV=3,
  SPELL_BLASTJUMP=4, SPELL_STEALTH=5, SPELL_TELEPORT=6, SPELL_LIGHTNING=7,
  SPELL_ATHLETIC=8, SPELL_METEOR=9, SPELL_SPAWN_BOSS=10, SPELL_SKELETON_HORDE=11`.
- `KIND_ROCKET=0, KIND_JAR=1, KIND_SELF=2`; `TIER_COMMON=0, TIER_RARE=1`;
  `ROLL_TIME=2`, `CAST_COOLDOWN=0.5`; `PROJECTILE_SPEED=1000`, `UP_SPEED=200`.
- Charges: 2 for fireball, bats, blast jump and teleport; 1 for the rest.
- `COMMON_ROLL`: indices 0–5 four times each, then 7, 8 and 9 once each (27
  entries). Teleport, boss and horde are never common.
- A rare roll is uniform over 7–11.
- Icons are `vgui/spellbook_<name>`. Cast sounds are `Halloween.spell_*`,
  plus `Halloween.Merasmus_Spell` for spawn boss.

**Strategies** (`foundation.spells.<spell>`). Numbers come from the classes
in `sdk/shared/tf/halloween/tf_weapon_spellbook.cpp`, and everything acts
through the caster port:

- **Projectile spells**, cast via `TossJarThink`:
  - The spawn point is the shoot position + up·−9 + right·7 + forward·3,
    checked with an 8³ hull.
  - Velocity = forward·1000 + up·(200±10) + right·(±10), × speedScale.
  - A rocket flies straight along the eye angles at that speed.
  - `LaunchProjectile(PROJECTILE, …)`, and the projectile's impact calls
    `Impact`.
- **fireball** (rocket): radius 200. Each enemy burns for 5 s and takes 100
  `DMG_BURN`, then an `Explode` of 10 `DMG_BLAST` over radius 200.
  `bombinomicon_burningdebris`, `Halloween.spell_fireball_impact`.
- **bats** (jar): radius 250. Each enemy is stunned 0.5 s at 0.5, pushed
  200·dir + 800 z, bleeds for 3 s, and takes 40 `DMG_BURN`; then an explosion
  of 10.
- **mirv** (jar): 6 `tf_projectile_spellpumpkin` launched at (±75, ±110, 400)
  and (±135, 0, 400), each with fuse 2 + 0.05·i s. Each detonates into a
  `tf_pumpkin_bomb` with `{ scale 0.6, damage 80, radius 200, team, lifetime 40–41, isSpell }`.
- **teleport** (jar): keeps the projectile's last 5 positions, every 0.05 s.
  On impact the caster teleports to the newest one whose hull is clear, and
  gains 30 health. Screen fade, `Building_Teleporter.Ready`.
- **lightning** (rocket ×0.4): not solid, 5 s life, bounces off the world.
  Zaps 2 enemies every 0.25–0.35 s and 16 at the end, for 20 `DMG_BURN` each
  within 200. Pulls enemies in every 0.2 s.
- **meteor** (jar): on impact, a spawner that for 4 s, every 0.2 s, drops 1–2
  meteor fireballs (damage 50). They fall from 400–500 up (45–60 under a
  ceiling), within 200, at velocity (±75, ±75, −700).
- **spawn_boss** (jar): `SpawnNPC("eyeball_boss", { team = caster's team, owner = caster })`,
  which makes a spell eyeball that lives 8 s. It tries 5 hull positions up to
  the hover height. When none fits, the caster keeps the spell.
- **skeleton_horde** (jar): 3 × `SpawnNPC("tf_projectile_spellspawnzombie",
  { thrower = caster, team, skeletonType = SKELETON_NORMAL })`.
- **overheal** (self): teammates within 250 and in LOS gain 50 health, 1 s of
  `INVULNERABLE_USER_BUFF` and 3 s of `HALLOWEEN_QUICK_HEAL`. Enemies are
  pushed 300.
- **blastjump** (self): clamp z velocity ≥ 0, add 800 z, gain 25 health. Push
  enemies within 100 by 800, then an explosion of 20 over radius 100.
- **athletic** (self): gain 100 health; 20 s each of `HALLOWEEN_TINY` and
  `HALLOWEEN_SPEED_BOOST`.
- **stealth** (self): gain 40 health; 8 s of `STEALTHED_USER_BUFF`.

**Controller `spells`:**

- Owns one `SpellBook` per player. Grants `tf_weapon_spellbook` in
  `PlayerLoadout` while UsingSpells, and to living players when spells turn
  on. Books reset on respawn, since TF2 regenerates items.
- Runs `+use_action_slot_item` (server concommand) as `Cast(ply)`. A failed
  cast plays `Player.DenyWeaponSelection`, at most every 0.5 s.
- Plays the `spell_cast_wheel_red`/`_blue` particle at +100 z, except for
  stealth.
- Implements the caster port.
- Applies the condition effects via hooks, never by editing
  `sv_teams_conditions.lua`:
  - `STEALTHED_USER_BUFF`: not drawn;
  - `HALLOWEEN_TINY`: model scale 0.5;
  - `HALLOWEEN_SPEED_BOOST`: the speed bonus from `CTFPlayer::TeamFortress_CalculateMaxSpeed`,
    cited in code;
  - `INVULNERABLE_USER_BUFF`: no damage.
- Networks each book's `State()` as NW2 on the weapon: `spells.selected`,
  `spells.charges`, `spells.rollingUntil`.

**Bindings:**

- `weapons/tf_weapon_spellbook.lua` is a thin SWEP in slot 5. PrimaryAttack
  calls `spells:Cast(owner)`.
- `tf_spell_pickup` (rewritten on `wetsand_pickup_base`):
  - keyvalue `tier`, with skin = tier; model `hwn_spellbook_upright.mdl`, or
    `_major` for tier 1;
  - ValidTouch calls `spells:Pickup(ply, tier)`;
  - touch plays `Halloween.spell_pickup` or `_rare` to the player and fires
    `OnPlayerTouch`;
  - `Configure{ tier, dropped }`.
- The ten spell projectile classes (`tf_projectile_spellfireball`, `…spellbats`,
  `…spellmirv`, `…spellpumpkin`, `…spelltransposeteleport`, `…lightningorb`,
  `…spellmeteorshower`, `tf_spell_meteorshowerspawner`, `…spellspawnboss`,
  `…spellspawnhorde`) derive from `wetsand_projectile` and bind through
  `spells:BindSpellProjectile`.

**View** (`CHudSpellMenu`): shows the icon, `xN` charges, and the key from
`input.LookupBinding("+use_action_slot_item")`. While rolling, it cycles
random icons with a gap that starts at 0.01 s and grows by 0.015 each tick,
alternating `Halloween.spelltick_a`/`_b`. When the spell is set, it plays
`Halloween.spelltick_set`.

## 9. P2 (W8)

| entity | binding / model | why not more |
|---|---|---|
| tf_halloween_minigame, tf_logic_minigames | stub: every FGD keyvalue and input accepted, nothing fired | karts and minigame arenas (rumble only) |
| halloween_fortune_teller | model `foundation.holiday.fortune`, bound to the holiday controller (CTFHalloweenFortuneTeller, `tf_logic_halloween_2014.cpp`); see below | the curses (econ, dances, ghosts) are left out |
| tf_point_weapon_mimic | bound to combat. WeaponType 0 is a `tf_projectile_rocket`; 1 is a timed `foundation.projectile.grenade`. Honours SpeedMin/Max, SpreadAngle, Damage, SplashRadius, Crits, ModelScale/Override, FireSound, ParticleEffect; inputs FireOnce, FireMultiple(int). Arrows and stickies log once | terror uses types 0 and 1 |
| func_croc | `foundation.hazards.croc`: on start-touch a croc prop plays `attack`; after 0.1 s a player still touching takes 1000 `DMG_CRUSH`, and `OnEat` and `OnEatRed`/`OnEatBlue` fire. Keyvalues TeamNum, StartDisabled, filtername, croc_model; inputs Enable, Disable, Toggle | |
| filter_tf_damaged_by_weapon_in_slot | `PassesDamageFilter`: weaponSlot 2 (melee) passes player damage with `DMG_CLUB`/`DMG_SLASH`; other slots deny and log once | GMod has no TF slots; the maps use only 2 |
| trigger_add_or_remove_tf_player_attributes | "dmg taken from fire reduced" scales `DMG_BURN` by its value while inside (duration −1) or for the duration; other attributes log once | there is no attribute system, and crits never reach it |

The fortune teller's timeline: every 120 s it fires `OnFortuneWarning`, then
2 s later `OnFortuneTold` with `Halloween.WheelofFateQuiet`. After 6.1 s it
teleports each team to its `red_teleport`/`blue_teleport` and fires
`OnFortuneCurse`, and 30 s later `OnFortuneEnd`. Its inputs are
Enable/Disable/Start/EndFortuneTelling.

## 10. I/O the event maps use

**KV** keyvalues, **In** inputs, **Out** outputs. *Italics* mark I/O in the
FGD or C++ that no event map sets or fires.

| entity | KV used | In used | Out used |
|---|---|---|---|
| tf_zombie_spawner | zombie_type 0/1, zombie_lifetime, max_zombies 1–6, infinite_zombies 0, *TeamNum* (`zombie_scale` on 5 maps is in neither FGD nor C++: ignored) | Enable, Disable, Kill, *SetMaxActiveZombies* | — |
| tf_zombie | TeamNum 3, modelscale 2.25, health (overridden) | Kill (Enable refused) | *OnDeath* |
| tf_spell_pickup | tier, StartDisabled, AutoMaterialize, TeamNum 0/3 | Enable, Disable, Kill, *Toggle* | OnPlayerTouch |
| eyeball_boss | teamnum 5 | Kill (templates) | — |
| headless_hatman, merasmus | — | Kill | — |
| tf_pumpkin_bomb | fade, AutoMaterialize (FGD damage etc. unread by C++) | — | — |
| tf_generic_bomb | all seven, plus model, skin, scale | *Detonate* | OnDetonate |
| tf_halloween_gift_spawn_location | — | — | — |
| halloween_zapper | touch_trigger, ParticleEffect, ZapperType 1 | ZapTouching, AddOutput, Kill, *Enable, Disable* | — |
| tf_logic_holiday | holiday_type 2/3, tauntInHell, allowHaunting | HalloweenSetUsingSpells 1, Halloween2013TeleportToHell | — |
| halloween_fortune_teller | red_teleport, blue_teleport | DisableFortuneTelling | OnFortuneWarning, OnFortuneCurse, OnFortuneEnd, *OnFortuneTold* |
| tf_point_weapon_mimic | WeaponType 0/1, SpeedMin/Max, SpreadAngle, SplashRadius, Damage, Crits, ModelScale | FireOnce | — |
| func_croc | TeamNum, StartDisabled | — | *OnEat\** |
| tf_halloween_minigame | MinigameType 3, Red/BlueSpawn, MaxScore, ScoreType, SuddenDeathTime, InRandomPool, hud_res_file | ScoreTeamRed/Blue, Kart*Animation* | OnRed/BlueHitMaxScore, OnAllRed/BlueDead |
| tf_logic_minigames | — | SetAdvantageTeam, TeleportToMinigame | — |
| filter_tf_damaged_by_weapon_in_slot | weaponSlot 2, Negated | — | — |
| trigger_add_or_remove_tf_player_attributes | attribute_name, value, duration −1, add_or_remove 0 | — | — |

Bosses and the precipice skeletons appear through the engine's
`point_template ForceSpawn`.

## 11. Work packages

Every package works in its own worktree and edits only the files it owns;
it asks for other changes in its report. The Feature package, which builds
`WETSAND.Feature` and is outside this plan, must land before any controller
is exercised in game. Until then, controllers are plain modules that the
models' tests never need.

| pkg | owns | depends on |
|---|---|---|
| **W1 npc framework** | foundation/npc.lua, foundation/npc/{actor,path,hover,spawner}.lua, foundation/npc/path/{ground,scatter}.lua, foundation/projectile.lua, foundation/projectile/grenade.lua; entities/{wetsand_nextbot,wetsand_projectile}.lua; features/npc (controller registry, spawner ticking, nav check; no view yet); tests/{npc,npc_path,npc_spawner,npc_hover,projectile}_test.lua, tests/fake_actor.lua | lands first |
| **W2 tools** | .devtools/bin/{nav_convert,tf2_content}.py and their test_*.py | any time |
| **W3 combat and holiday** | foundation/{combat,holiday}.lua, foundation/holiday/halloween.lua, foundation/npc/{combatant,targeting}.lua, additions to foundation/players.lua; entities/{wetsand_combat_nextbot,tf_logic_holiday}.lua; features/{combat,holiday}; tests/{combat,holiday,targeting}_test.lua, tests/fake_combatant.lua; deletes foundation/halloween.lua, wetsand/sv_halloween.lua, tests/halloween_entities_test.lua | W1 |
| **W4 skeletons (P0)** | foundation/npc/zombie.lua; entities/{tf_zombie,tf_zombie_spawner,tf_projectile_spellspawnzombie}.lua; tests/zombie_test.lua | W1, W3 |
| **W5 bosses** | foundation/npc/{halloween_boss,headless_hatman,eyeball_boss,tag}.lua, foundation/projectile/rocket.lua; entities/{halloween_base_boss,headless_hatman,eyeball_boss,teleport_vortex,tf_projectile_rocket}.lua; features/tag; the npc feature's view (boss bar); tests/{halloween_boss,headless_hatman,eyeball_boss,tag}_test.lua | W1, W3 |
| **W6 hazards and gifts** | foundation/hazards.lua, foundation/hazards/{pumpkin_bomb,generic_bomb,zapper}.lua; entities/{tf_pumpkin_bomb,tf_generic_bomb,halloween_zapper,tf_halloween_gift_spawn_location,tf_halloween_gift_pickup}.lua; features/hazards; tests/hazards_test.lua | W3 |
| **W7 spellbook** | foundation/spells.lua, foundation/spells/{caster,tf2}.lua and the 12 strategy parts; weapons/tf_weapon_spellbook.lua; entities/tf_spell_pickup.lua and the ten spell projectile entities; features/spells (controller and view); tests/{spells,spells_tf2,spells_cast}_test.lua, tests/fake_caster.lua | W1, W3; merges after W4 (horde), W5 (spawn boss), W6 (MIRV pumpkins) |
| **W8 P2** | foundation/holiday/fortune.lua, foundation/hazards/croc.lua; entities/{merasmus,tf_halloween_minigame,tf_logic_minigames,halloween_fortune_teller,tf_point_weapon_mimic,func_croc,filter_tf_damaged_by_weapon_in_slot,trigger_add_or_remove_tf_player_attributes}.lua; tests/{fortune,croc}_test.lua | W3; merges after W5 (rocket), W6 (hazards) |

The packages merge in this order: W1, W3, W4, then W5 and W6, then W7, then
W8. W2 can merge at any point. Once W1 and W3 land, W4 to W8 can be built in
parallel, because they meet only through the interfaces above: entity
`Configure{...}` tables, controller methods, and port methods.

### Acceptance criteria

Every package must satisfy:

- `.devtools/bin/run_lua_tests.sh` passes.
- `luajit -b` passes on every changed file.
- `luajit -bl <foundation file> | grep GGET` shows only the captured globals.
- No bare meaningful integers anywhere, tests included.
- No entity file requires anything at top level.
- Each test was written first and seen failing.

The tests are mostly **model scenarios** run against the fakes, with a fake
clock and a scripted random source.

**W1 npc framework**

- `npc_test`: one test per rule in section 2, each asserting the call order
  through an action log. The rules: start order; update order; ChangeTo,
  including a chain from OnStart; SuspendFor and resume; OnSuspend→Done;
  end propagation; the event walk and priorities; events to an unstarted
  action; a pending SUSPEND_FOR buried; the empty Behavior; resume skipped;
  and the timers.
- `npc_path_test`: the ground and scatter rules.
- `npc_spawner_test`, as a scenario:
  - enable, then 3 spawns at 1.5–3 s intervals up to the cap;
  - Died does not refill a finite spawner but does refill an infinite one;
  - Disable resets it;
  - the 0.2 s idle think.
- `npc_hover_test`: altitude clamped to ±acceleration, and damping.
- `projectile_test`: fuse and touch rules.
- A contract test finds every name in `foundation.npc.actor.METHODS` in
  `tests/fake_actor.lua`, and `function ENT:<Name>(` in `wetsand_nextbot.lua`
  (read as text).
- Neutrality: this must print nothing:
  `grep -nE 'Teams|TEAM_|[Hh]alloween|tf_|TF2|skeleton|spell|WETSAND\.(Team|Halloween|Rules|FireOutput|KeyValues|State)'`
  over `foundation/npc.lua`, `foundation/npc/{actor,path,hover,spawner}.lua`,
  `foundation/npc/path/*.lua`, `foundation/projectile*.lua`, and
  `entities/entities/wetsand_{nextbot,projectile}.lua`.

**W2 tools**

- `test_nav_convert.py`: `ctf_2fort.nav` re-parses as v16 sub-version 0, with
  the same area count and ids, consumes the file exactly, and the output size
  is the input minus 4 × the area count. `pl_hasslecastle.bsp`'s embedded
  mesh converts, and its header carries the BSP's real size.
- `tf2_content.py` exits 0 for a known model and 1 for a made-up one.

**W3 combat and holiday**

- `holiday_test`: Halloween by map and by the forced convar; Christmas;
  spells on then off; the gift schedule's first delay, interval, one gift per
  player, and lifetime.
- `combat_test`: Explosion at the centre and the edge, half falloff against
  full; self, teammate, enemy, and forced friendly fire; LOS.
- `targeting_test`: the four stealth exceptions, ghost mode, and EnemyTeamsOf
  for all teams.
- A contract test: `fake_combatant` implements
  `foundation.npc.combatant.METHODS`, and `wetsand_combat_nextbot.lua` defines
  each one.

**W4 skeletons: `zombie_test` scenarios on `fake_combatant`**

1. HALLOWEEN NORMAL:
   - it rises, finishes the spawn activity and chases the nearest of a RED and
     a BLU player;
   - it hits for 30 only inside 50, and at most once per 0.8–1.2 s;
   - between 50 and 150 it faces and gestures;
   - it repaths only after 0.5 s;
   - killed by a player, it spawns 3 MINI skull grenades with its team and
     `OnDeath` fires once.
2. A RED skeleton never targets RED. It skips a victim in a respawn room, off
   the mesh, dead, or stealthed, but targets a stealthed player who is
   burning. It fights a BLU skeleton that is closer than any player. It keeps
   its target for 3 s, and a contact lock holds for 3 s.
3. KING: when the special timer has elapsed inside 100, it SuspendFors the
   stomp. At 1 s the stomp pushes and hits only target-team players within 200
   of its eyes; then Attack resumes. On death it requests a rare spell drop.
4. MINI from a grenade: lives 30 s and suicides (`OnDeath` once). Owned by a
   player who changes team, it suicides.
5. Laugh cadence per type; OnStuck kills itself; a Halloween skeleton ignores
   contact; there is no damage from its own team; a death with no combatant
   attacker spawns nothing.
6. `Cull` picks the oldest non-kings above the cap and never a king.

**W5 bosses**

- `headless_hatman_test`, scenario:
  - emerge (rise and push);
  - pick IT within 1500 of home, chase, and drop IT beyond 2000;
  - the swing lands at 0.58 s and hits only inside the cone;
  - terrify at 20 s, with stun flags and LOS;
  - animation by health;
  - dying ends with `Tag():Set(nil)`.
- `tag_test`: melee transfer, death transfer, and announce only in Halloween
  mode.
- `eyeball_boss_test`, scenario:
  - emerge and the 2 s kill radius by level;
  - idle to notice to approach to rockets (count, delay, speed, crit by mood);
  - approach gives up after 5 s and lingers 1 s;
  - teleport on the move timer to a `spawn_boss_alt`;
  - escape at the lifetime and level reset;
  - death falls, jarates within 750, spawns a `spawn_loot` vortex and raises
    `Shared().level`;
  - a spell eyeball is immune, enraged, and gone at 8 s.
- `halloween_boss_test`: health scaling, the DPS window, the round-won
  filter, and a variant's hooks called in template order.

**W6 hazards and gifts: `hazards_test`**

- Pumpkin: a HALLOWEEN pumpkin shot by RED explodes as RED. A team pumpkin
  explodes for its own team and fizzles for others, on its lifetime, and on
  `trigger_hurt`.
- Generic bomb: friendlyfire and passActivator; Detonate.
- Zapper: ON_TOUCH every 0.25 s, and ZapTouching.

**W7 spellbook**

- `spells_test`, scenario:
  - a common pickup rolls, the book is UNKNOWN for 2 s, then takes that
    spell's charges;
  - a second common pickup is refused while charges remain, but a rare one is
    accepted;
  - casting spends a charge and respects the 0.5 s cooldown;
  - a failed spawn_boss keeps the spell.
- `spells_halloween_test`: COUNT; charges and kinds; `COMMON_ROLL` has 27 entries
  with the right counts; a rare roll gives only 7–11.
- `spells_cast_test`: each self spell's effects on `fake_caster`, and each
  projectile spell's launch parameters and Impact effects, with their numbers.

**W8 P2**

- `fortune_test`: the timeline over two intervals, and pause and resume on
  Disable/Enable.
- `croc_test`: eat only while still touching after 0.1 s, with the team
  outputs.

### In-game checks (integrator)

Loading:

- On pl_badwater, no Halloween feature loads (check `package.loaded`).
- On pl_hasslecastle, only `npc`, `combat`, `holiday` and `spells` load.

Nav:

- After `nav_convert.py`, `navmesh.IsLoaded()` is true and the area count is
  above 0 on pl_hasslecastle and pl_bloodwater.
- Without the converted mesh, exactly one log line appears.

Templates:

- `point_template ForceSpawn` creates the Lua bosses (`relay_horseman` on
  pl_millstone_event).

P0, skeletons (on pl_hasslecastle, capturing point 1 wakes `skele_point1`):

- It rises, runs, flinches, laughs, swings, and hits for 30. It ignores
  players in spawn rooms.
- Killing one throws 3 skulls that become big-headed minis living 30 s. A
  king stomps.
- Gibs appear on death and on lifetime expiry.
- A NextBot keeps ticking after `OnKilled` until it is removed.
- Collision: GMod has no per-locomotion `ShouldCollideWith`, so watch for
  doorway jams.

P1:

- pl_bloodwater's eyeball event: rise, rockets, teleports, the boss bar, and
  the death vortex to `spawn_loot`.
- HHH on millstone: IT by melee and by death, terrify, the axe.
- plr_hacksaw_event: pumpkins and the OnDetonate chains.
- Particles appear on clients.
- Spells: the book on the maps that turn spells on, H casts, the HUD rolls,
  all 12 spells work, and a king drops a rare book.

## 12. Reuse for other gamemodes

A CS:S mode, or any later NPC, can reuse these unchanged:

- `foundation.npc` (Behavior, actor port, path strategies, spawner, hover)
  with `wetsand_nextbot` and the `npc` controller. A CS:S hostage is a new
  NPC variant, `foundation.npc.hostage`, whose Behavior follows its rescuer,
  bound by a `hostage_entity` entity.
- `wetsand_combat_nextbot` and `foundation.combat`, given CS:S team data in
  `foundation.teams`.
- `foundation.projectile` and `wetsand_projectile`, for grenades: HE, flash
  and smoke would be variants.
- `foundation.spells` with a different set, for any charged one-button item.
- `nav_convert.py`: CS:S meshes are sub-version 1 with no data added to each
  area, so it passes them through. Verify this on a CS:S nav first.

These are TF2 content and stay TF2's:

- the variants `zombie`, `halloween_boss`, `headless_hatman`, `eyeball_boss`
  and `tag`;
- `foundation.spells.halloween` and its strategies;
- `foundation.holiday.halloween` and `.fortune`;
- the hazard variants;
- every `tf_*` and `halloween_*` binding.

## 13. Judgment calls to revisit

- Holiday and spells come from the map entity, with TF2's convars as
  overrides once an entity loads the holiday controller. There is no calendar.
- The spellbook is a real SWEP in slot 5, and casts with TF2's bind command.
- Gifts give nothing.
- The eyeball's escape warnings are `WETSAND.Announce` text, where TF2 uses
  game events.
- Skeleton collision is GMod's default; TF2's zombies collide with nothing.
- `IsOnNavMesh` uses `navmesh.GetNavArea(pos, 100)` and `GetClosestPointOnArea`.
- The eyeball's purgatory Z and TF2's per-weapon damage multipliers are
  dropped.
- Controller file paths wait on the Feature package; `features/<name>/{sv,cl}.lua`
  is only a proposal.
- The IT hooks run only while a `headless_hatman` is bound, so a map without
  one loads nothing for IT.
