# NextSoldier on the engine's own behaviours

A soldier's behaviours can run as the engine's own `Action<CLuaNextBot>`s, inside
its real `IIntention` and `Behavior`, instead of on our statechart. This records
what was found in GMod's win64 `server.dll` (build 2026.04.29, sha1 `0f0f70162486…`),
what `native/nextsoldier` proved on a live server, and what stands between that
and soldiers running on it.

## What GMod actually runs

Every `CLuaNextBot` already has the whole system, with one action on it:

```
CLuaNextBot                     INextBot at +0x2240
  CLuaNextBotIntention          IIntention; its Behavior at +0x28
    Behavior<CLuaNextBot>       0x70 bytes; its root action at +0x10
      CLuaBehaviour             Action<CLuaNextBot>, 0x68 bytes, no fields of its own
```

`CLuaBehaviour` overrides `OnStart` (calls `BehaveStart`), `Update` (calls
`BehaveUpdate`, always answers `Continue`), and turns twelve events into Lua
hooks. So what GMod calls Lua's behaviour is a placeholder action in the engine's
real statechart. The engine's template code (`InvokeUpdate`, `ApplyResult`,
suspending, the event walk, dead actions) is compiled in and running; our
`generator.state_chart` is a port of that same `NextBotBehavior.h` on top of it.

The vtables match the SDK's `NextBotBehavior.h` with Dota's `#ifdef` block out: 42
slots for `INextBotEventResponder`, 91 for `Action<T>`, 9 for `IContextualQuery`.
`.devtools/bin/pe_rtti.py` lists any class's vtables and slots from its RTTI.

## The mechanism: nothing is patched

No detour is needed. `native/nextsoldier` builds objects laid out as
`Action<CLuaNextBot>`, with a copy of that class's vtable in which the hooks are
ours, and links one under the bot's `CLuaBehaviour` (`parent` and `child`). The
engine does the rest, through virtual calls it already makes. No engine code or
shared vtable is written: what changes is that one link on a NextBot, and one
intention's vtable pointer on a player bot.

An action's fields live in the engine's object, and its Lua table only holds what
the behaviour itself keeps. Hooks answer `{ type, action, reason, priority }`,
decoded once at the boundary.

## Where a soldier plugs in

- **An entity:** `base_nextsoldier`. A class's `ENT:NSInitialAction()` returns its first
  action, inserted in `BehaveStart`, which is the first moment a link holds: the root's
  `InvokeOnStart` sets its child from `InitialContainedAction` just before calling it.
- **A player bot:** `player.CreateNextSoldier(botName)`, then `nextsoldier.engine.Insert`.
  A `NextBotPlayer<CGMOD_Player>` has a plain `IIntention` and no statechart, so it gets
  one: the engine's `Behavior`, updated by `CLuaNextBotIntention::Update` on a shadow of
  its intention, whose vtable pointer is swapped for a copy answering
  `FirstContainedResponder` and `Update`. That code reaches its actor only at +0x2240, so
  it is handed the player's `INextBot` less that. Its actions are the root: no
  `CLuaBehaviour`, no `BehaveUpdate`.
- **Ending a player's actions:** from `EntityRemoved`, while the player is whole. Inside
  `~INextBot`, `GetEntity` is pure, and `InvokeOnEnd` reaches it logging (a
  `CLuaNextBot` ends its actions earlier, from its own destructor). A destructor that
  gets there first clears the `Behavior`'s actor, which skips `InvokeOnEnd`.

## A carrier on it: npc_ctfbot

MvM's bomb carrier, as TF2's tree, with no round or wave around it:

```
CLuaBehaviour                 GMod's, calling BehaveUpdate
  TacticalMonitor             Rust (native/nextsoldier: tactical.rs, engine.rs)
    DeliverFlag               Lua (nextsoldier.behavior.ctfbot), with the flag
    ScenarioMonitor (buried)  Rust (scenario_monitor.rs), over a registry in Rust (scenarios.rs)
      FetchFlag (buried)      Lua
```

`npc_ctfbot`, on `base_nextsoldier`, is the running entity. Each monitor is one native
action: `engine.TacticalMonitor{ scenario, never_retreats, retreat, commands }` is its
config, as `engine.ScenarioMonitor{ scenarios, context, behaviors, interrupts }` is the
other's, and only what they run and suspend for is Lua. Its `Update` asks the engine's
query walk `ShouldRetreat`, and its `OnCommandString` suspends for what `commands` names,
over everything it runs (`engine.Command(bot, "taunt")`, or the engine's `nb_command`).
The rest of TF2's monitor waits on what it needs from the game.

`.devtools/bin/ctfbot_check.lua` on `mvm_decoy` watches one go: given the bomb at 0.1 s,
`ScenarioMonitor` suspends for `DeliverFlag`; told to taunt at 6 s, the monitor suspends
over all of it and it resumes at 7.6 s; at about 33 s, 5,621 units on, the zone fires
`OnCapture` and `ScenarioMonitor` resumes.

What the run found: `FollowPath` must leave a leap alone, since an engine action is
updated whatever the body is doing; and with no war to open them, a NextBot takes a
forcefield for a wall and the nav mesh the areas under it for blocked, until it next
looks. Until then a path is the straight line the engine falls back on.

## A player on it: a round of ctf_2fort

`WS.AddNextSoldier(team, name)` (`gamemode/sv_next_soldiers.lua`) is a bot player on the
same tree, `TacticalMonitor > ScenarioMonitor > FetchFlag`, with `DeliverFlag` over them
while it has the flag. GMod has no `PlayerLocomotion`, so its body is keys from
`nextsoldier.body.player_body` through `StartCommand`, and its routes are planned on a
`ws_bot_navigator`.

`.devtools/bin/next_soldier_round_check.lua` is the assessment: `mp_winlimit 1`, one
player, on BLU. It writes to `data/ns_round_check.txt` as it goes. On instance 2, at
commit 2f80dcbe, it captured three times in 408 s and won by `FLAG_CAPTURE_LIMIT`, then
the rotation moved the map on. A map can load with its rounds off when nobody is
connected: toggling `sv_gameplay_enabled` to 0 and back to 1 starts the game.

What the runs found, each fixed in Lua on the shared terms:

- **Blocked door areas.** The engine's search refuses an `IsBlocked` area before asking
  the cost function, and the flag outlasts the door opening. `RefreshBlockers` clears it
  on door areas, or a closed spawn door cuts the whole spawn off the mesh.
- **Route price.** A bot player prices routes as TF2's bots do, with
  `wetsands.path.tfbot` over `wetsands.navsearch`'s `Told` and `Calculator`, told whether
  its body fits each step. No new foundation structure was needed.
- **The engine's points are for a narrower body.** The search's width is the navigator's,
  and a TF2 hull is 48 wide. `Locomotion.StepOff` walks past a drop's ledge,
  `Locomotion.StandPoints` moves a point the body cannot stand on (ctf_2fort's pillars by
  the battlements), and `Locomotion.Avoid` veers off a jamb. Its shape and constants are
  from memory of TF2's `PathFollower`, since the vendored SDK does not include it.
- **A seam deadlock.** `ws_bot_navigator`'s `Settled` waited forever when the nearest area
  and the last known one lay either side of a seam at the same distance.

Each lap still stalls about 0.9 s in four places, at STUCK_TIME, until `player_body`'s
jump clears it. The first order after setup also stood 9.9 s at the spawn, not yet
explained. A war's bot player steers on the same traces (`features/npc/bot_steering.lua`).

**Hazards.** `wartactics.hazards` closes an area after two deaths on it, saved across maps. It
used to count recoveries too, so a bot's failure to get on read as bad ground: with war bots
stranded by their steering, 23 areas of ctf_2fort's courtyard closed in an afternoon and every
route went through the sewers, 18,000 units where 10,000 would do, which looked like a slow bot.
Recoveries are now only counted, for whoever inspects an area (`ns_hazards_print`), and saved
closures they alone made open again as they load.

**Replanning, as TF2's.** A route is planned again every 1 to 2 seconds whether or not its goal
moved, and `Path:Compute`'s answer tells a straight path it found (both ends in one area) from
one it did not. `.devtools/bin/war_round_check.lua` plays a war to one capture, BLU against nobody.

## The rest on it

**npc_pathfollower** is `nextsoldier.behavior.pathfollower`: `Idle`, `Travel` and `Errand`.

**The Halloween bots** (`tf_zombie`, `ghost`, `eyeball_boss`, `headless_hatman`, `merasmus`)
run unchanged. `Action.EngineBehavior` answers what `generator.state_chart`'s root does, and
`Controller:Bind` gives it to an NPC variant wherever the binary is bound, so what is written
for the chart runs on the engine. The chart stays where it is not bound, and in the tests.

**The AI war's bot players** are NextSoldiers (`Controller:AddBot`), their orders and monitors
unchanged. An action entering the engine gets `QueryBelow`, `GetActionBuriedUnderMe` and
`IsSuspended` on its instance, reading the engine's links, since chart code reads its own. Its
orders are made anew each life: `engine.End` ends a life's tree, and `Insert` puts the next in
its place. On ctf_2fort, 8 a side: 66.7 ticks a second held, 12 deaths and their respawns with no
errors, the engine's live actions steady. Each tree now updates about 9 times a second, at the
engine's own pace, where the war's `THINK_INTERVAL` gave 4; the cost of that is not measured.
The war's NPC soldiers (`npc_nextsoldier`) stay on the chart.

**Events and queries from Lua.** `engine.Event(bot, name, ...)` goes through the engine's own
`OnCommandString` under a private mark, its arguments left on the Lua stack, so its priorities
and pending results are the engine's and no `CTakeDamageInfo` needs bridging.
`engine.Query(bot, name, ...)` walks from the innermost action out. `engine.End(bot)` runs each
`OnEnd` while the bot is whole, since the engine's own would come from its destructor.

**The debug layer.** `Action.DebugNpc` shows the engine's stack for bot players and any class
the engine runs, logging each change as the layer looks.

## LOOK_AT: a head in Rust

`look.rs` is `IBody::AimHeadTowards` as `PlayerBody` decides it: a request of a higher priority
takes over, a lower one waits for the current to run out, an equal one for the head to settle.
Lua gives its config once, in `engine.Look(soldier, { settle, steady_rate, turn_rate, interval,
sources })`, and is asked nothing after. Each tick `INextBot::Upkeep` reaches slot 44 of the
soldier's intention, which runs the model and sets the eyes, with no Lua in between. Its feet go
their way under its eyes: `Drive` turns where it walks into forward and side moves.

`reach.rs` reads what it needs from `server.dll`, whose Lua methods are entries in static tables
(`.devtools/bin/lua_glue.py` disassembles them): `EyePos`, `EyeAngles` and `Alive` give virtual
slots, `Team` a field, `SetEyeAngles` a function no vtable holds. A binary where these differ is
refused at bind. The priorities' names and order are from memory of the SDK: GMod's binary holds
only the `nb_head_aim_*` convars and the `LOOK_AT` debug category.

`ws_nb_debug LOOK_AT` shows the requests, in the words of the engine's own debug line. Only bot
players on NextSoldier have a head so far; a threat's source waits for combat, and an NPC's head
for where it turns (the clients', `nextsoldier.body.gaze`).

## GroupIdentityBehavior: the tree beside the main one

A bot player runs two trees, as L4D2's survivors run `SurvivorBehavior` and `SurvivorLegs`:

```
TacticalMonitor > ... > FetchFlag        what it is doing
GroupIdentityBehavior > LegsWait         who it is with, and where that puts its feet
```

`engine.InsertGroup(soldier, action[, me])` gives it the second: another `Behavior` and shadow on
the same soldier. `soldier_update` runs both; `NextContainedResponder` (slot 2 of its intention)
hands events on from the first to the second, so it hears what the main tree hears. Its root is
native (`group.rs`, `engine.GroupIdentityBehavior{ initial }`), and `nextsoldier.behavior.group_identity`
gives it to NextSoldiers and war bots for the player's whole life, not each spawn. `engine.GroupStack`
shows it, and the debug layer lists it after the main tree. Only players have one: a `CLuaNextBot`'s
intention is the engine's own.

A bot player's waits, for now. `npc_pathfollower` driven by its legs (the Path Follower stool's Local mode, `docs/ns-debugging.md`)
runs it alone, starting at `LegsAtEase`: told an order (`group_identity.Muster(point)`,
`FallBack(point, from)`), it changes to `LegsMuster` or `LegsFallBack`, and dissolved, back to ease.
On an order, the order's action contains its squad's mode's (`MODE`, one whole number on the order),
as L4D2's legs contain theirs: `LegsStationary` (rests at a seat near its place), `LegsPatrol`,
`LegsWander`, `LegsEvacuate` (runs out of the room), `LegsStayClose` (keeps near its leader), and
`LegsRegroup`, suspending the first three for a member strayed from the squad's point. A full squad's
leader calls the fall back on heavy casualties (`Order:Rout`). The actions are
`nextsoldier.behavior.gib_behaviors`; the orders they run on, `group_identity`.
An order's `Places(members, spacing)` gives each member a place. `engine.Separation(me, others, tie)`
and `engine.GroupSpacing()` give Lua the push that `GroupPush` holds. To come under it, replacing `SquadMonitor`: boids on a chase path for a squad's
cohesion, filling a room when a squad assaults or ambushes one, and the set-up's stances.

## What was proved

On a live server (instance 3), on `srcds.py start --gamemode base` for the bare NextBots
and player bots and the full gamemode for `base_nextsoldier`.
`.devtools/bin/nextsoldier_engine_check.lua` repeats all but the map change.

- A child starts before its container; `SuspendFor` buries and `Done` resumes, with
  the right prior and next actions; `ChangeTo` replaces; dead actions are deleted.
- The engine's own query walk answers from the innermost action out.
- A real damage event reaches an action, including one fired inside a hook. Its
  change is stored and made at the next update.
- A hook that errors is reported and the tree goes on.
- `BehaveUpdate` keeps running beside the actions.
- Removing a bot ends its actions (`OnEnd` runs) and deletes them.
- A `changelevel` with live actions does not crash: `gmod13_close` deletes every
  action through the engine's destructor before its code unloads.

`engine::bind` checks the running binary before binding: the classes by RTTI, the
slot counts, the `INextBot` offset, the bytes of the function returning the Behavior.
Anything off refuses with the reason and leaves the engine untouched. `Action`'s
own field offsets are not checked at run time, only against this build.

## What stands between this and soldiers

1. **NextSoldier on its own.** `base_nextsoldier` needs foundation and the gamemode's
   loader, so it does not load on `base` or `sandbox`. A development kit has to load
   itself.
2. **Update order.** The engine updates a child before its container, so actions
   run *before* `CLuaBehaviour::Update` calls `BehaveUpdate`, the reverse of
   `base_nextsoldier` today, which runs its chart from inside it.
3. **Events.** `OnInjured`, `OnSight`, `OnLostSight`, `OnContact`, `OnNavAreaChanged`
   and `OnOtherKilled` are the engine's. `OnHeard` and `OnContactLost` are ours, and
   need a route through it (`OnSound`, `OnCommandString`). Only `OnInjured` and
   `OnStuck` are wired from the engine so far, and the `CTakeDamageInfo` is not passed to Lua;
   what Lua hears itself goes through `engine.Event`.
4. **Queries.** `ShouldAttack`, `ShouldHurry`, `ShouldRetreat`, `ShouldPickUp` and
   `SelectMoreDangerousThreat` are all `IContextualQuery`'s. Only `ShouldHurry` is
   wired. The two taking a `CKnownEntity` need that bridged.
5. **Differences from our twin.** A `ChangeTo` to nothing is refused by our chart;
   the engine carries on with the action it had. A failing hook no longer raises to
   its caller.
6. **Reasons.** The engine keeps reasons by pointer, so they are interned for good.
   A reason built with a changing value would grow without limit.
7. **Platforms and updates.** This is the win64 binary only: a Linux server needs its
   own binding, and a GMod update can move what is checked and refuse. Where it
   refuses or does not exist, a soldier needs a fallback, and the Lua chart is it.
   A player's actions also keep running through a respawn, and nothing resets them;
   while it is dead they are not updated at all.
8. **Testing.** The LuaJIT tests cannot reach the engine. The Lua twin stays as what
   they run, and each difference from the engine is a live check.
9. **Not measured.** The cost per update against our chart, real soldiers, and many
   bots at once.

## Beyond the intention

The same RTTI shows the rest of the kit in the binary: `CLuaNextBotBody` (`IBody`),
`CLuaNextBotVision` (`IVision`, with `CKnownEntity`), `CLuaLocomotion`
(`NextBotGroundLocomotion`), `PathFollower`, `ChasePath`. None has been touched yet.
