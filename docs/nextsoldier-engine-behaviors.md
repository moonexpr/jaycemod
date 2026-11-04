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
engine vtable is written, so the only writes to engine memory are that one link.

An action's fields live in the engine's object, and its Lua table only holds what
the behaviour itself keeps. Hooks answer `{ type, action, reason, priority }`,
decoded once at the boundary.

## What was proved

On a live server (instance 3) with bare `base_nextbot` bots.
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

1. **Bot players.** Only `Action<CLuaNextBot>` and `Behavior<CLuaNextBot>` exist in
   the binary. `NextBotPlayer<CGMOD_Player>` has no statechart to join, so a bot
   player needs our chart or its own answer.
2. **Update order.** The engine updates a child before its container, so actions
   run *before* `CLuaBehaviour::Update` calls `BehaveUpdate`, the reverse of
   `base_nextsoldier` today, which runs its chart from inside it.
3. **Events.** `OnInjured`, `OnSight`, `OnLostSight`, `OnContact`, `OnNavAreaChanged`
   and `OnOtherKilled` are the engine's. `OnHeard` and `OnContactLost` are ours, and
   need a route through it (`OnSound`, `OnCommandString`). Only `OnInjured` and
   `OnStuck` are wired so far, and the `CTakeDamageInfo` is not yet passed to Lua.
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
8. **Testing.** The LuaJIT tests cannot reach the engine. The Lua twin stays as what
   they run, and each difference from the engine is a live check.
9. **Not measured.** The cost per update against our chart, real soldiers, and many
   bots at once.

## Beyond the intention

The same RTTI shows the rest of the kit in the binary: `CLuaNextBotBody` (`IBody`),
`CLuaNextBotVision` (`IVision`, with `CKnownEntity`), `CLuaLocomotion`
(`NextBotGroundLocomotion`), `PathFollower`, `ChasePath`. None has been touched yet.
