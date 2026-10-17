# Game events v2: the plan

**Architect, 2026-10-08, main at 38eb752.** This plan turns
`docs/game-events-v2.md` (the spec), `docs/game-events-v2-research.md` (the
research) and the scholar's verdicts at the end of it into five phases, each
with acceptance criteria an agent can check by running something. **The
operator approves it before phase A starts** (handoff §4 step 3). The
operator approved it on 2026-10-08 and answered §4's five decisions; the
answers are under "Operator decisions (2026-10-08)", and every phase below is
written to them.

**Where this plan and the spec differ, this plan wins** until the writer
applies the spec edits in §1. Programmers read §1 before they read the spec.

**Revised 2026-10-08 (main at 544da69) for the operator's design change:
event classes.** The operator asked for the network architecture as classes,
with three kinds of event (system, game, recovery) so that failure states
can be recovered. **The operator approved this revision on 2026-10-08,**
with his answers to its six questions folded in (see "Operator answers to
the design change (2026-10-08)"). Phase A resumes on §0's steps. The five
sections that follow the baseline are new: the design change and the
architect's four decisions, the class layout, the failure states and their
recovery, what happens to phase A's existing commits, and the operator's
answers. Every phase carries a "What changed" note, and its
criteria are revised. The spec (`docs/game-events-v2.md`) is edited for the
design change itself; §1's scholar edits are still the writer's.

**Baseline at 38eb752** (re-measured for this plan):

| Measure | Value | Command |
|---|---|---|
| LuaJIT tests | 1357 passed, 0 failed | `.devtools/bin/check_lua.sh` |
| Lua files compiled | 365 | same |
| Python harness tests | 134 passed | `cd .devtools/bin && python3 -m pytest -q` |
| `tests/events_test.lua` | 27 tests | `luajit tests/events_test.lua` |
| Files the server sends clients | 191 | research §2 |
| `E.Define` calls | 30 lines in 10 files (29 events plus `client_ready`) | `grep -rn 'Define("' addon --include='*.lua'` |
| `WS.BroadcastSound(ToOthers)` calls | 19, plus 2 definitions and 2 uses through the Wheel's port (the handoff's 23) | §D |
| Boss forwarder `me:FireGameEvent(` calls | **13 in 3 files** (merasmus 7, eyeball_boss 4, headless_hatman 2) | `grep -rc 'me:FireGameEvent(' addons/sandcastle/gamemodes/sandcastle/gamemode/foundation` |

The scholar counted 16 forwarder calls in 6 files. The other three hits it
counted (`npc/halloween_boss.lua:28`, `payload/race.lua:21`,
`rounds/payload.lua:16`) are comments that cite TF2's
`FireGameEvent`. `halloween_boss.lua:52` is the port's `METHODS` entry.

---

## Operator design change (2026-10-08): event classes

### What the operator said

1. "scaffold the network architecture into classes as much as possible. I
   want classes of system events, game events, and recovery events so
   failure states can be recovered."
2. A correction, which replaces any earlier reading of "system": "system
   events should almost never be updated, only for major releases: things
   like the announcer voice".

### What it means in this plan

- **The library is made of classes.** Each class has one job, and the models
  stay pure. Their I/O (net, files, the clock, the player list, logs) goes
  through ports that one composition root wires. See "Event classes: the
  class layout".
- **There are three kinds of event,** and each kind is a class with its own
  rules:
  - **System events** are the gamemode's stable vocabulary. They change only
    in a major release. The announcer voice is the operator's example.
  - **Game events** are the gameplay and mode events. They change freely
    from build to build, and they are most of what features fire.
  - **Recovery events** are the library's own protocol. Each failure state
    the library can detect is a named class, and recovery events carry its
    recovery. See "Failure states and recovery".
- **Recovery comes on top of reporting.** Operator decision 3 stands:
  nothing is blocked or dropped because a failure state is open. A recovery
  re-sends or replays; it never stops an event. `critical` stays built and
  unused.
- **There is one deliberate exception** (the operator's answer P3). The
  server disconnects a client on another system major, with a message
  telling it to update. No other failure state stops an event or
  disconnects anyone, and stale files stay report-only.

### Decision (a): system events use the self-describing encoding

System events get the same self-describing encoding as game events, not a
fixed schema. A major version and a freeze test keep them fixed.

- **One wire for all three kinds.** The kind is not on the wire: the id is
  the event, and each realm knows an event's kind from its own sites.
- **Why not a fixed schema:**
  - Self-description is what keeps a mismatched client safe. A client on
    another major still decodes every message, and a field the other side
    dropped arrives as `nil`, never as another field's bytes. A fixed layout
    would misread at exactly the moment the majors differ, which is the
    failure the major exists to catch.
  - A schema would be a second place that specifies the event. Goal 2 (one
    source of truth) forbids that, and phase C removes `Define` for good.
  - There is one codec, one size model and one set of tests, and they are
    already built on the A branch.
- **What keeps system events fixed:**
  - `MAJOR = 1`, in `foundation/events/event/system.lua`. The client sends
    its major in `client_ready`, and the server compares it with its own. A
    different major is the failure state `major_mismatch`, and the server
    disconnects that client with a message telling it to update (P3). The
    `handshake` still carries the server's major, for the client's print
    command.
  - A freeze test, built in C. `tests/events_system_frozen.lua` lists each
    system event and its field keys, under the major they were frozen at.
    `tests/events_system_test.lua` fails when the scanned system sites differ
    from that list at the same major.
  - So changing a system event means bumping `MAJOR` and refreezing in the
    same commit. That commit is a major release. The fixture is a test guard,
    like the events file: the game never reads it, so it can't make the wire
    stale.
- **When majors can differ.** With `sv_allowcslua 0` a client runs the text
  the server sent, so the two majors can differ only through drift.
  `system.lua` is compiled once, so if it is edited on disk mid-session,
  later joiners get the new major while the server keeps its own. The check
  is still worth its 8 bits: it is direct and costs nothing, and it names
  the most serious drift in plain words.
  - Because of that, a disconnected client that reconnects at once gets the
    same served text and is disconnected again, until the server's own code
    agrees (at its next map change at the latest). The disconnect message
    says so, which the operator confirmed is enough.
- **The limit.** The freeze covers event names and field keys, not value
  types, because the codec infers a value's type per message. A field that
  changes type within a major isn't caught; the site's trailing comments
  describe each field's type.
- **When major 1 freezes.** It is frozen when E passes (the alpha playtest
  build). Until then, C writes the fixture, and D may add system events to
  it without a bump, because no release has shipped yet. After E, any change
  bumps the major. The operator confirmed this release point (P5).

### Decision (b): the stale-file check is the same for every kind

The check is the same for every kind; what differs is what a hit means.

- **Detection is about files, not kinds.** The sent and run references, the
  scanner and `code_stale` are the same for all three (A.4).
- **A stale file touching game events** is reported, as before. The stop
  rule, which nothing calls (decision 3), could stop them. `code_current`
  recovers it.
- **A stale file touching system events** is reported too, and they are
  listed apart in the report line. **They can never be stopped, even in the
  model.** A system event's contract rests on the major, which the handshake
  checks directly. So `Touch:Blocks` is false for every system event, as it
  already is for client-only events.
- **Recovery events are never touched.** They are the library's own, fired
  only from `foundation/events/protocol.lua`. A stale library file is a
  stale always-loaded file: it is reported, and its events can't be stopped.
- **The report line names both kinds:**

  `network error: gamemode/features/capture/cl.lua differs from the server's; events it touches (not stopped): game: teamplay_capture_blocked; system (major 1): teamplay_point_captured`

### Decision (c): the library's own traffic is recovery traffic

The library's lifecycle traffic belongs to the recovery kind. There is no
fourth kind.

- **Every library message detects a failure state or answers one:**
  - the handshake answers `joining`;
  - `code_stale`, `code_touched` and `code_current` report and answer
    `stale_code`;
  - `event_refused` answers a refusal;
  - the `resync_*` events answer the rest.

  So the recovery kind is the library's protocol, and nothing is left over
  for a fourth kind.
- **Only the library fires recovery events.** Each has its one literal site
  in `foundation/events/protocol.lua`, a class with one method per event.
  Features never fire one. On the server they may listen to `resync`, to
  supply their state to a client being brought up to date.
- **The library accepts its own client events.** The recovery events a
  client sends are accepted at fixed rates, without `Accept`, and they never
  appear in the accepted list.
- **Where today's library traffic goes:**

| Traffic | On the A branch today | Now |
|---|---|---|
| A client's readiness | `client_ready`, a library event fired by the adapter | `client_ready { major }`, a recovery event fired from `protocol.lua` |
| The accepted list on ready | `events_accepted { names }`, to that player | `handshake { major, accepted }` to that player, then the ready resync |
| The accepted list later | `events_accepted { names }` | Unchanged, as a recovery event |
| Drift reports | `code_stale { files }` and `code_touched { events }` | Unchanged, as recovery events, plus `code_current { files }` when the files match again |
| A refused client event (not accepted, rate limited, malformed) | dropped, and logged once per player | Still dropped and logged. Also answered with `event_refused { id, reason }`, at most once per player and event per 10 s |
| A message the client can't decode | raised as our bug | Logged as our bug once, and answered by a resync of its feature |
| A burst over budget | `ready_burst`, logged | Logged, and paced over the following ticks |
| An unknown id on a client | ignored | Unchanged. Local dispatch to no one is not a failure |
| An oversized event | `too_large`, raised at `Fire` | Unchanged. It is our bug at the call, not a failure state |

### Decision (d): which of today's events are system events

**The operator's rule** (P4, in his words): "System events include major
game sync events like round resets, system announcements, or any other
wide-broadcasted events that fundamentally affect the game or reset state.
Gameplay events concern decorative audio cues, halloween-specific
programming, or anything else that's not fundamental to Sandcastle itself."
And: "Ideally, we should avoid updating system events as much as possible so
these events should occupy a very limited set."

So **game is the default kind,** and an event is system only if it passes
the rule. I applied the rule strictly to the six events I had proposed, and
the operator named four more.

| Kind | Event | Why |
|---|---|---|
| **System** (5 today) | `teamplay_broadcast_audio`, **split** | The gamemode's announcer: the overtime nag, the map's `PlayVO*` inputs, the capture model's "others" line, the admin's transition line and the cart warning. These are wide-broadcast system announcements. It also carried Halloween lines (the fortune teller's broadcast, the Wheel of Fate, Merasmus), which the rule makes game, so D moves them to the new game event `holiday_broadcast_audio`. |
| | `teamplay_timer_time_added` | It announces a change to the round's timer to everyone: a system announcement of round state. The clock itself rides on a networked variable, which makes this the closest call of the five. It stays system because it is the only announcement of the change, and its fields are TF2's own. |
| | `teamplay_point_captured` | A change of control-point owner, broadcast to everyone, which fundamentally affects the game. |
| | `teamplay_capture_blocked` | The operator's pick (P4): a broadcast capture-state notice. |
| | `feature_load` | It tells clients which features to load. That defines and resets their state, and goes to everyone when a feature loads. |
| **System** (4 more in D) | `teamplay_round_win` | The round's end: a state reset, broadcast to everyone. |
| | `teamplay_suddendeath_begin` | A change of round state, broadcast to everyone. |
| | `teamplay_alert`, `teamplay_teambalanced_player` | The operator's picks (P4): team balance announcements. |
| **Game**, the default (24 today) | The 12 boss events and `npc_ragdoll_create` (the operator's answer); the 8 debug overlays; `gameplay_transition_cancelled`; `announcement` and `gameplay_chat` until D retires them. In D: `holiday_broadcast_audio`, the tag events (TF2's IT, which only the Horsemann loads: Halloween-specific, the operator's answer), `gameplay_transition_started`, `gameplay_requested`, `gameplay_sandbox_entered`, and the team-full notice, which goes to one player | Decorative, Halloween-only, debug, or Sandcastle's own mode flow, which still changes |
| **Recovery** | `client_ready`, plus the library's new events | Decision (c) |

That accounts for all 29 of today's events (5 system and 24 game), plus
`client_ready`.

Promoting or demoting an event before the freeze is a small change: its
site and listeners move between `Events.Game` and `Events.System`, and the
frozen fixture gains or loses it.

### At the call site

```lua
local Events = WS.Events

-- features/capture/sv.lua
-- CTeamControlPoint::InternalSetOwner: a team took the point (not a reset
-- to nobody, nor the owner a round starts with).
Events.System.Fire("teamplay_point_captured", {
	cp = index, -- the point's place in the master's order
	cpname = name, -- its name, as the map gives it
	team = team, -- the team that took it
})

-- features/capture/cl.lua
Events.System.Listen("teamplay_point_captured", "ws_capture_view", function(fields)
	...
end)

-- features/nbdebug/sv.lua
Events.Game.Fire("nb_debug_state", {
	...
}, { to = ply })

-- ws/sh_core.lua, server: bring a client's loaded features up to date
Events.Recovery.Listen("resync", "ws_feature_load", function(fields, ply)
	...
end)
```

- `Events.Game` and `Events.System` each have `Fire`, `Listen`, `Ignore`
  and, on the server, `Accept`. `Events.Recovery` has only `Listen`.
- **A name has one kind.** A `Listen` or `Accept` of another kind than the
  event's `Fire` site raises `bad_kind`, and the scanner reports it.
- **Until C,** `Events.Fire`, `Events.Listen`, `Events.Ignore` and
  `Events.Accept` remain as `Events.Game`'s. So A changes no feature, and A
  stays "behind today's API". B moves each site to its kind, and C removes
  the aliases.

---

## Event classes: the class layout

**What a class is here** (the `lua` skill, applied):

- Each class is one `module(...)` file. The module holds the constructor
  (`New`, or a named factory such as `FileKey.FromSource`) and the class's
  constants.
- An instance is `setmetatable(state, Class)`, with `Class.__index = Class`,
  as `rates.lua` and `sent.lua` already do on the A branch.
- **Variants are parts** (the skill's Strategy). The base file declares the
  methods a variant fills in, and each variant is
  `foundation/events/<base>/<variant>.lua`, with
  `setmetatable(Variant, { __index = Base })`. The event kinds and the
  failure states are built this way.
- **Values exist only if they are valid.** A factory either builds a valid
  instance or raises our named error (or returns `nil` and a refusal, for
  the client's input). Nothing past it re-checks what the type guarantees.
- **Pure** means the purity grep under "Code style" prints nothing. The
  models never `require` the adapter and never read a GMod global.

**Who depends on whom:**

```
ws/sh_events.lua         the composition root: builds the ports and the Library once per
  |                           Lua state, exposes WS.Events, registers net and the hooks
  +-- ws/sh_events_ports.lua   GMod's side of each port
  +-- foundation/events.lua   Library: one realm's coordinator
        +-- Catalog ---------- Event <| GameEvent, SystemEvent, RecoveryEvent
        +-- Listeners
        +-- Codec
        +-- Rates
        +-- Protocol           the recovery vocabulary; fires through the Library
        +-- Recovery --------- Failure <| the 8 failure states
        +-- Touch
        +-- client: Handshake
        +-- server: Peers, Pacer, Sent, Drift, Scanner
        shared values: FileKey (paths.lua), Error (errors.lua)
```

**The model classes** (all pure, all under
`addons/sandcastle/gamemodes/sandcastle/gamemode/foundation/`):

| Class | File | Its one job | On the A branch |
|---|---|---|---|
| `Library` | `events.lua` | One realm's coordinator. It routes `Fire`, `Listen`, `Accept`, receives and ticks through the classes below, and holds no rule of its own. | Exists (04bc088); slimmed |
| `Event`, with the parts `GameEvent`, `SystemEvent`, `RecoveryEvent` | `events/event.lua`, `events/event/{game,system,recovery}.lua` | An event's identity (name, id) and its kind's policy: which options it takes, whether it can ever be stopped, whether it is frozen, where it may be fired from, and whether clients may send it without `Accept`. `SystemEvent.MAJOR` lives here. | New |
| `Catalog` | `events/catalog.lua` | The realm's events by name and by id, each one's site (key and feature), and the refusals `id_collision` and `bad_kind`. | New; taken out of `Library` |
| `Listeners` | `events/listeners.lua` | Listeners per event, in order. Each dispatch runs over a snapshot, with each listener isolated, and records each listener's file key. | New; taken out of `Library` |
| `Codec` | `events/codec.lua` | Validation, the exact size model, encoding, and bounded decoding (A.3). | Exists as module functions (241c9be); becomes a class |
| `Rates` | `events/rates.lua` | The accepted names and each player's token bucket per event. | Exists (a360c08); kept |
| `FileKey` | `events/paths.lua` | A source path parsed into our file key (its path, feature and loader kind), or `nil` when the file isn't ours. | Exists as functions (84a91e7); becomes a value class |
| `Error`, with `OurFault` and `ClientFault` | `events/errors.lua` | The named errors, split into our bugs and the client's faults. | Exists as functions (241c9be); becomes a class |
| `Sent` | `events/sent.lua` | The keys of the files sent to clients, fixed at start-up, and `late_send`. | Exists (3a7927d); kept |
| `Drift`, `Scanner` | `events/drift.lua` | `Drift` holds the sent and run references, what each player loaded, and the stale and current queries. `Scanner` holds the round-robin probe schedule. | Not written; waits for T1 and T2 |
| `Touch` | `events/stops.lua` | The events a stale set touches, split into game and system, and the stop rule that nothing calls. | Exists as functions (0c42776); becomes a class |
| `Protocol` | `events/protocol.lua` | The recovery vocabulary: one method per recovery event, each holding that event's one literal site. | New; replaces the adapter's library events |
| `Failure`, with 8 parts | `events/failure.lua`, `events/failure/<state>.lua` | One failure state: its key, its report lines, the recovery it starts, which recovery event answers it, and its retry policy. | New |
| `Recovery` | `events/recovery.lua` | The open failure states of a realm. It opens a state (reporting once and starting its recovery), closes it on an answer (reporting the recovery), retries what is due, and reports a give-up once. | New |
| `Handshake` | `events/handshake.lua` | The client's side of joining: the joining, ready-sent and ready states; `client_ready` (with the client's major) and its retries; the events held while joining. | New; takes over the client's accepted list |
| `Peers` | `events/peers.lua` | The server's record of each connected player: ready or not, its handshake epoch, and its touched events. Bots are never peers. | New; replaces `ply.wsReady` |
| `Pacer` | `events/pacer.lua` | Each player's byte budget per tick. Sends over the budget wait, in order. | New; replaces `CountSent`'s logging |

**The ports.** Each is an interface the `Library` is handed. The GMod
classes in `ws/sh_events_ports.lua` implement them, and
`tests/fake_ports.lua` fakes them.

| Port | Methods | GMod class | Realm |
|---|---|---|---|
| `values` | the codec's value interface (A.2) | the adapter's `VALUES` table (exists) | both |
| `hash` | `hash(text) -> string` | `util.CRC` | server |
| `Transport` | `Send(players, outgoing)`, `SendToServer(outgoing)` | `NetTransport`: `net.Start`, `outgoing:WriteTo(net)`, `net.Send` / `net.SendToServer` | both |
| `Roster` | `Resolve(to) -> { player... }`, `Name(player)`, `Disconnect(player, reason)` | `GModRoster`: players, teams, `RecipientFilter` for a `Vector`, and `ply:Kick(reason)` | server |
| `Files` | `Read(key) -> text \| nil`, `Time(key) -> number \| nil` | `GModFiles`: `file.Read` and `file.Time` through `LUA` | server |
| `Clock` | `Now() -> seconds` | `GModClock`: `CurTime()` | both |
| `Log` | `Ours(line, traceback)`, `ClientFault(player, line)`, `Report(line)` | `GModLog`: `ErrorNoHalt`, `MsgN`, and on a client also chat | both |

`SendWatcher` (in the ports file) is the `AddCSLuaFile` wrapper (A.4). It
feeds `Sent` and `Drift` through the `Library`.

**The composition root** is `ws/sh_events.lua`, and nothing else
constructs these classes.

- It builds the ports, then the one `Library` per Lua state. The `Library`
  is kept across a gamemode refresh in `WS.EventLibrary`, as v1 kept its
  registry, and a refresh only re-binds its ports and hooks.
- It exposes `WS.Events`: the `Game`, `System` and `Recovery` facades,
  plus the aliases until C.
- It registers the two net messages and the hooks: `PlayerInitialSpawn`,
  `PlayerDisconnected`, `InitPostEntity` (start-up on the server, `Loaded` on
  a client), `Think` (`Tick`), and `OnReloaded`, deduplicated.
- It installs `SendWatcher`.
- It fires no event itself. Every recovery site is in `protocol.lua`.

**The one view** is `ws/cl_network_notice.lua` (client). It listens to
`network_notice` and presents it: the chat line and TF2's cue (P1). The
models never print to chat or play a sound.

---

## Failure states and recovery

**A failure state** is a condition of a connection that the library can
detect at run time with correct code, or that drift creates. Our own bugs
at a call are not failure states: `bad_fields`, `too_large`, `bad_options`,
`bad_accept`, `id_collision` and `bad_kind` raise at the line that made
them, `late_send` is logged, and the fix is the code.

**How recovery works.** Each failure state is a part of `Failure`
(`foundation/events/failure/<state>.lua`). `Recovery` tracks the open ones,
per realm and per peer.

- **Opening** a state reports it once (`network error: ...`) and starts its
  recovery. Detecting it again while it is open reports nothing new.
- **An answer** closes it: a recovery event, or the realm seeing the cause
  gone. Closing reports once (`network recovered: ...`).
- **Retries** follow the state's policy. After the last one, it reports once
  that it gave up and stays open, so a later answer still closes it.
- **Nothing is blocked** while a state is open (decision 3).
- **The one exception** is `major_mismatch`: the server disconnects that
  client (P3).
- **Where reports go** (P1, the operator's answer):
  - Every report goes to the console, and the server logs every open and
    every close.
  - `stale_code` and any give-up also go to chat, with an audio cue: TF2's
    `ui/system_message_alert.wav` for a failure, and TF2's
    `ui/message_update.wav` for a recovery. Both are in the mounted TF2's
    `tf2_sound_misc_dir.vpk`, read-only. TF2 has no sound named for a
    "system update". `system_message_alert` is the one TF2 plays for a
    system message, so it is the nearest.
  - A `stale_code` that only a reconnect can cure adds the chat hint
    `reconnect to update` (P2). The library never forces a reconnect.
  - **Clients present.** `Recovery` fires the client-local recovery event
    `network_notice`. Its listener in `ws/cl_network_notice.lua` prints
    the chat line and plays the cue, from the named constants
    `NOTICE_SOUND_FAILURE` and `NOTICE_SOUND_RECOVERED`.
  - A disconnected client (`major_mismatch`) has no Lua left to run, so it
    gets GMod's disconnect dialog with the message, and no cue.

**Recovery replays state, not history.** A resync fires each feature's
current state: today that is `feature_load`, and persistent gameplay state
rides on networked variables, which the engine re-sends by itself. A
one-shot fact a client missed, such as a capture announcement, is not
replayed (P1, the operator's answer).

**The recovery vocabulary,** each event with its one site in
`protocol.lua`:

| Event | Direction | Fields | Rate from a client | Its part in recovery |
|---|---|---|---|---|
| `client_ready` | client to server | `major` | 2 per 10 s | Opens the handshake |
| `handshake` | server to one client | `major`, `accepted` | | Answers `joining` and `handshake_timeout`. The major is for the client's print command; the server has already compared it. |
| `events_accepted` | server to the ready clients, or to one | `names` | | A later `Accept`; the answer to a `not_accepted` refusal |
| `resync_request` | client to server | `features`, `reason` | 4 per 10 s | Asked by `decode_failed`, `listener_failed` and `refused` |
| `resync_begin` | server to one client | `epoch`, `features` | | Opens a resync |
| `resync` | server, local only | `epoch`, `features`, and `ply` | | Runs the providers: the always-loaded ones and those of the features named |
| `resync_end` | server to one client | `epoch` | | Closes what waited on that epoch |
| `code_stale` | server to one client | `files` | | Opens `stale_code` on the client |
| `code_touched` | client to server | `events` | 4 per 10 s | The server's record of that player's touched events |
| `code_current` | server to one client | `files` | | Closes `stale_code` |
| `event_refused` | server to one client | `id`, `reason` | | Opens `refused` on the client |
| `network_notice` | client, local only | `state`, `line`, `recovered`, `chat` | | Its listener in `ws/cl_network_notice.lua` presents a report: chat and the cue (P1) |

**The failure states.** Each test is in `tests/events_recovery_test.lua`
unless the row names another file. Those tests run over
`tests/fake_link.lua`: a server `Library` and its clients wired through
`tests/fake_net.lua` buffers, with a shared fake clock and taps that drop,
corrupt or delay the next message. So each test drives the failure, then
watches for the recovery events and the report lines.

| Failure state | How it is detected | Recovery event(s) | What "recovered" means | The test that drives it and watches it recover |
|---|---|---|---|---|
| `joining` | Server: `Peers` has the player connected (`PlayerInitialSpawn`) but not ready, so nothing fired meanwhile is sent to it (net messages sent before a client loads are lost). Client: `Handshake` is not ready, and the events it fires are held, at most `HELD_MAX`. | `client_ready { major }`, then `handshake { major, accepted }`, then `resync_begin`, the `resync` providers (always-loaded first, `feature_load` among them), and `resync_end` | Server: `Peers:IsReady(ply)` holds, and the ready resync's `resync_end` was sent. Client: `Handshake:State()` is ready after that `resync_end`. The held events the server accepts were sent once, in order; the rest stayed local. | `a joining client is brought up to date by the ready resync, and the events it fired while joining leave once accepted` |
| `handshake_timeout` | Client: `Handshake:Tick(now)` finds no `handshake` and `resync_end` `HANDSHAKE_SECONDS` after `client_ready`. The cause is a server mid-refresh, or a failed ready path. | `client_ready` again, up to `HANDSHAKE_TRIES` times, within its rate. The server answers each with a fresh handshake and resync under a new epoch; older epochs are void. | A `handshake` and the latest epoch's `resync_end` arrive. After the last try it reports the give-up once and keeps waiting, so a later handshake still recovers it. | `a lost handshake is retried until the server answers, and reported once after the last try` |
| `major_mismatch` | Server: `client_ready.major` differs from `SystemEvent.MAJOR`, on any `client_ready`. | None on the wire. **The deliberate exception to report-only (P3):** the server logs the mismatch and disconnects the client through `Roster:Disconnect(ply, MAJOR_MISMATCH_MESSAGE)`, before any handshake. Nothing else is stopped or disconnected. | The player's next connection has a client on the server's major, and its handshake completes normally. In GMod that happens once the server's own code agrees again, at its next map change at the latest (decision (a)). | `a client on another major is logged and disconnected with a message to update, before any handshake` |
| `stale_code` | Server: `Drift:StaleFor(ply)` lists a file whose text, as served when the player loaded it, differs from what the server runs (A.4). It is asked at the player's ready, at `feature_load` to it, after a deduplicated gamemode refresh, and after each full scanner cycle. | `code_stale { files }`, then the client's report and its `code_touched { events }`. Then `code_current { files }` once they match again. | `Drift:StaleFor(ply)` no longer lists the files, the client heard `code_current` and reported it, and the server cleared that player's touched set. This happens when a refresh reruns an included file or an entity on both realms. A compiled file (`foundation/` and features) never reruns, so a player who loaded a changed one recovers only by reconnecting after the file is restored (P2). | `a stale included file recovers when a gamemode refresh reruns it on both realms, and the client hears code_current`; `a stale compiled file stays stale for its player until that player reconnects; a player who joins after it is restored is not stale` |
| `refused` | Server: `Library:Receive` refuses a client's event as `not_accepted`, `rate_limited` or `malformed` (by `Rates` and the codec's bounded read). Client: `event_refused` arrives. | `event_refused { id, reason }`, at most once per player and event per `REFUSAL_NOTICE_SECONDS`. For `not_accepted` the server first re-sends `events_accepted` to that player. The client then asks `resync_request { features = { the event's feature }, reason = "refused" }`. | It is judged on the client: the `resync_end` for its request arrived, so its view of that feature is the server's. After a `not_accepted`, its accepted names equal the server's. The server's part is the notice, which a client that keeps misbehaving keeps getting at the notice rate. | `a refused client event is answered with event_refused, and the client's resync brings its feature back to the server's state`; `a client whose accepted list is out of date gets it again on not_accepted` |
| `decode_failed` | Client: `Codec:ReadFields` refuses a message from the server. That is our bug: a codec bug, or a stale `codec.lua`. It is logged as our bug, once per id. | `resync_request { features = { the id's feature, or every loaded feature when the id is unknown }, reason = "decode_failed" }`. The server logs it as our bug with the player's name, then runs `resync_begin` to `resync_end`. | The resync's `resync_end` arrived, and every message in it decoded. It retries up to `RESYNC_TRIES` times, `RESYNC_RETRY_SECONDS` apart, then reports the give-up once. | `a message the client cannot decode is logged as our bug once, and its feature's resync clears it` |
| `listener_failed` | Either realm: `Listeners:Dispatch` runs each listener under `xpcall` with a traceback. One that raises is logged as our bug, once per listener and event, and the other listeners and the send still run. A feature whose client part fails to load shows up here, as a failure of `feature_load`'s listener. | Client: `resync_request { features = { the listener's feature }, reason = "listener_failed" }`. Server, for a listener of a client's event: it resyncs that feature to that player unasked. | That listener next runs without raising, on the resync or on its event's next dispatch, and that is reported. Retries are as for `decode_failed`. | `a listener that raises is logged with its traceback, the other listeners and the send still happen, and its next clean run reports it recovered` |
| `ready_burst` | Server: `Pacer:Push` finds more than `PACE_BYTES_PER_TICK` for one player this tick, or a backlog over `READY_BURST_MAX_BYTES`. | None on the wire. The `Pacer` sends the rest over the next ticks, in order, and every later message to that player queues behind it, so `resync_end` arrives last. The backlog is logged once per player and resync, as our bug: thin the resync. | `Pacer:Pending(ply)` is 0. | `a burst over the per-tick budget goes out over later ticks in order, logged once, and its resync ends after its last event` |
| `stopped`, in the model only | `Touch:Blocks(name)` for a non-empty stale set. No runtime code calls it (decision 3). | `code_current`: the file leaves the stale set the touch was built from. | `Touch.Of` over the new stale set blocks none of that file's events. | `tests/events_stops_test.lua`: `a stop lifts when its file matches again` |

One more test guards decision 3 and its one exception across every row:
`apart from major_mismatch's disconnect, nothing a failure state does stops an event or disconnects a client`.
It opens each state, then checks that every event is still dispatched and
sent, and that `Roster:Disconnect` was called once, for the mismatched
client only.

**The named constants** (in the class that owns each):

| Constant | Value | Class |
|---|---|---|
| `HANDSHAKE_SECONDS` | 6 | `Handshake` |
| `HANDSHAKE_TRIES` | 3 (two retries fit `client_ready`'s 2 per 10 s) | `Handshake` |
| `HELD_MAX` | 32 events | `Handshake` |
| `RESYNC_TRIES` | 3 | `Failure` |
| `RESYNC_RETRY_SECONDS` | 5 | `Failure` |
| `REFUSAL_NOTICE_SECONDS` | 10 | `Recovery` |
| `PACE_BYTES_PER_TICK` | 16384, provisional until T6 | `Pacer` |
| `READY_BURST_MAX_BYTES` | 131072 (the existing constant), now the backlog that is logged | `Pacer` |
| `MAJOR` | 1 | `SystemEvent` |
| `MAJOR_MISMATCH_MESSAGE` | `"Sandcastle was updated: this server runs system events major %d, your client has major %d. Update and reconnect; if this repeats, wait for the server's next map change."` | `failure/major_mismatch.lua` |
| `NOTICE_SOUND_FAILURE` | `"ui/system_message_alert.wav"` (TF2's) | the view, `ws/cl_network_notice.lua` |
| `NOTICE_SOUND_RECOVERED` | `"ui/message_update.wav"` (TF2's) | the view, `ws/cl_network_notice.lua` |

---

## Phase A's existing commits

I inspected both branches read-only: `gev2-phase-a` at fcc7511, and
`gev2-phase-a-tools` at d163a33. Both build on b752d5b, which is on main at
544da69.

- Every commit is signed (`%G?` is `G`).
- After b752d5b the two branches change disjoint files, so they merge
  without conflicts.
- The A programmer kept committing while I read: 36a9678, 04bc088 (the
  switch), 3eca116, 5fcb196, bddcfb0 and fcc7511. Its worktree is clean at
  fcc7511. More may come, and the last row gives the rule for them.

**Nothing is dropped.** The tools and the client facts are unchanged by the
design, and the library's pieces are reshaped into classes, not thrown
away.

| Commit | Piece | Verdict | How |
|---|---|---|---|
| 086875b | `check_totals.sh` | **Keep** | |
| eca72f0 | `gmod_client.py` | **Keep**, with ee4048b's fix | The client tools settle how a client loads files, which the event classes don't change |
| fe7262b | `gev2_marker.py` | **Keep**, with a896b66's tag | |
| 4ff0d02 | `srcds.py --no-lua-refresh` | **Keep** | |
| 1b62fe4 | `gev2_probe.py run --client` | **Keep** | |
| b752d5b | the T1, T2 and T4 probes | **Keep** | They settle facts the design doesn't touch |
| ee4048b, a896b66, b8e989c, d163a33 (tools branch) | the client's identification, the marker tag, `check_no_markers.py`, `gev2_client_session.sh` | **Keep** | They answer the gate's FAIL. That FAIL's re-evaluation and the T1, T2 and T4 session still make sense and still gate detection. T7 (E) reuses the session's staging. |
| 241c9be | the codec, errors and `fake_net.lua` | **Keep** the wire, the size model, the bounded reader, `fake_net.lua` and the 26 tests. **Reshape** two interfaces. | The codec becomes the `Codec` class (`Codec.New(values)`) over the same functions; the module's `Id`, `Crc32` and constants stay for the scanner and the probes. `errors.lua` becomes the `Error` class with `OurFault` and `ClientFault`; the kinds and how errors print don't change. |
| a360c08 | `rates.lua` | **Keep** as built | It is already a class. The `Library` seeds it with the recovery events' fixed rates. |
| 84a91e7 | `paths.lua` | **Reshape** | It becomes the `FileKey` value class (`FileKey.FromSource`, `FileKey.Resolve`, and the fields `path`, `feature` and `kind`), with the functions as its internals. The 8 tests are kept and re-pointed. |
| 0c42776 | `stops.lua` | **Reshape** | It becomes the `Touch` class, with decision (b)'s system and recovery exemptions and the test `a stop lifts when its file matches again`. The 6 tests are kept. |
| 3a7927d | `sent.lua` | **Keep** as built | |
| 9d603ba, 36a9678 | the site scanner | **Keep**, and extend | The scanner learns `Events.Game.` and `Events.System.` sites with their kind, `Events.Recovery.Listen`, `RecoveryFire(` only in `protocol.lua`, a `Listen` or `Accept` of another kind, and the field capture C's freeze test needs. |
| 04bc088 | the switch: the facade, the adapter, `events_test.lua`, the adapter test, the sites test, the ratchet, the converted options, and `init.lua`'s order | **Keep** the switch's outcomes. **Reshape** its two big files. | Kept: v1 is gone, `Request` is gone, the options are converted, `init.lua`'s order, the ratchet, and the sites test. In `foundation/events.lua`, `Library` gives registration and sites to `Catalog` and listeners to `Listeners`; its library events go to `Protocol`; `CountSent` becomes `Pacer`; the client's accepted list moves to `Handshake`. `ply.wsReady` becomes `Peers`. The adapter splits into the composition root and `sh_events_ports.lua`, and gains the facades. Two committed tests are reworded for recovery (A.5), so the count stays. |
| 3eca116 | `expected_sent_files.sh` | **Keep** | Its count grows with A's new `foundation/` files. A.6 item 9 diffs against the tree, so nothing needs changing. |
| 5fcb196 | the probe modules line, and the `events_size` and `events_sent` probes | **Keep** | `events_size.lua` is re-pointed at `Codec.New(values)`. |
| bddcfb0 | the codec asks the host for the kind of any engine value (found live; `events_size` now reads `mismatches 0` over 24 events) | **Keep** | A real fix, independent of the classes. |
| fcc7511 | the T3 probe, `client_t3.lua` | **Keep** | Re-pointed at `Codec.New(values)`. A.6 item 15 adds one line to its output: the client's handshake state and major. |
| any later commit | | | Library internals are reshaped by the class layout. Tools and probes are kept. |

### How the two branches combine

1. **Pause the A programmer** at its next clean commit; the coordinator has
   paused A. Once the operator approves this revision, hand it this section
   and A's revised criteria.
2. **The architect re-evaluates `gev2-phase-a-tools`** against the stage-one
   gate: A.6 item 13 plus the two defects of the FAIL. The criteria haven't
   changed.
3. **On a pass, the director merges `gev2-phase-a-tools` into main**
   (`--no-ff`, then both checks on main). It changes only `.devtools/bin/`,
   so the addon on main doesn't change. The client session then runs from
   main's own scripts, against the main the server loads.
4. **The researcher runs T1, T2 and T4** (`gev2_client_session.sh`), as
   planned. That can overlap with the A programmer's reshaping: two agents.
5. **The A programmer merges main into `gev2-phase-a`** at a clean point,
   with a signed `--no-ff` merge, before stage 3. No file is in both, so the
   merge is clean.
6. **The A programmer finishes A** on the branch: the reshaping, the new
   classes and recovery, then detection once T1 and T2 are recorded. The
   director merges A to main once, `--no-ff`. Then come T3 and the
   architect's evaluation (A.6).

The other order also works: merge the tools into `gev2-phase-a` and land
everything with A. It keeps one merge per phase, but the client session
would then run from a worktree's scripts against a main that lacks them.

---

## Operator answers to the design change (2026-10-08)

The operator answered the six product questions and approved the revision.
Each answer below is already worked into the sections it names.

| # | Question | Answer | Where it lands |
|---|---|---|---|
| P1 | What a player sees during recovery | Console for every report. Chat for `stale_code` and any give-up, **plus an audio cue**: TF2's `ui/system_message_alert.wav` for a failure and `ui/message_update.wav` for a recovery, played by a client recovery listener (the view `ws/cl_network_notice.lua`). Missed one-shot lines are still not replayed. | "Failure states and recovery", A.1, A.2, A.5, A.6 item 23, E.3 item 7 |
| P2 | May the library tell a client to reconnect? | **No.** A chat hint, `reconnect to update`, where only a reconnect cures a stale file. | "Failure states and recovery", A.5 |
| P3 | A client on another major | **Disconnect it,** with a message telling it to update. This is a deliberate exception to report-only. Decision 3 still holds for stale code, and nothing else stops an event or disconnects anyone. | Decision (a), the `major_mismatch` row and its test, the guard test, A.6 item 21, E.1's recovery check |
| P4 | Which events are system | `teamplay_capture_blocked`, `teamplay_alert` and `teamplay_teambalanced_player` are system. The 12 boss events, `npc_ragdoll_create` and the tag events (Halloween-specific under the rule) are game. The operator's rule decides the rest; game is the default, and the system set stays minimal. | Decision (d), B, C, D, the spec's §1 |
| P5 | When major 1 freezes | At the alpha playtest build, when E passes. | Decision (a), E |
| P6 | May the client exception cover T6 and T7? | **Yes.** It is still the GMod client only, unattended, in "Team Fortress 2", and the server still runs only in "Steam". T6 and T7 are required E criteria. | "Live runs", §3, E.3 item 7, §5 |

**The operator's follow-up answers (2026-10-08):**

- **The tag events are game:** they are Halloween-specific under the rule.
  D adds 4 system events, not 5.
- **The major-mismatch disconnect message is enough as written.** A client
  that reconnects before the server's code agrees is disconnected again,
  and the message tells it to wait for the next map change. That behaviour
  stays.
- **E adds no real end-to-end kick.** The live check's recording stand-in
  and the unit test are enough.

---

## 0. Before phase A (the director)

1. **Commit the research inputs to main.** `docs/game-events-v2-research.md`,
   `.devtools/bin/gev2/`, `.devtools/bin/gev2_probe.py` and
   `.devtools/bin/gmod_lua_cache.py` are untracked at 38eb752. A worktree
   made from main won't have them, and phase A's live probes reuse
   `gev2_probe.py`. Commit them in one signed commit, together with this plan
   once it's approved.
2. **The operator's answers to §4:** done on 2026-10-08, and recorded in
   the next section.
3. **Before A resumes** (the design change): the operator approves this
   revision: done on 2026-10-08, with P1 to P6 answered. What remains: the
   architect re-evaluates the tools gate, and the director merges
   `gev2-phase-a-tools` ("How the two branches combine").

---

## Operator decisions (2026-10-08)

The operator answered the five decisions §4 asked. Three differ from the
plan's defaults. Nothing in this plan waits on the operator any more.

| # | Decision | Answer | The default? | Where it lands |
|---|---|---|---|---|
| 1 | Servers with `sv_allowcslua 1` | **Ignore it.** No report and no refusal: the library treats such a server like any other, and never reads the convar. | No (the default was to report once) | §1 row 2, A.4, A.6 item 12 |
| 2 | A client for T1 to T5 (extended to T6 and T7 by P6, 2026-10-08) | **Yes, unattended.** The GMod client runs in the CrossOver bottle **"Team Fortress 2"**, because that bottle has the right Wine settings. The dedicated server still runs only in "Steam", through `srcds.py`. The exception covers only that GMod client, for T1 to T5; no server and no other process ever runs in that bottle (handoff §5 still holds for everything else). T1 to T5 are required phase-E criteria, and they confirm detection. | No (the default was no client) | "Live runs", §3, A.1, A.5, A.6 items 11, 13 to 15, E, §5 |
| 3 | Stop events on a stale file, or report it? | **Report only,** in the client's console and chat (and the server's log). `critical` is built but unused. | Yes | §1, A.2, A.4, A.6 item 7, C.1, C.3 item 10, E.1 |
| 4 | The events file | **Build** the generator, the pre-commit hook and the staleness test, in C. | Yes | C, as written |
| 5 | Phase D's scope | **Also move** `WS.Announce`'s server-built text (the `announcement` event) and `gameplay_chat` to client listeners. | No (the default was to leave them) | D.1, D.2, D.3 items 7 to 9 |

**The architect's calls that follow from these** (technical; they are
listed again under "Judgment calls" at the end):

- **The convar `ws_events_check` is dropped.** With report only, its
  values 0 (off) and 2 (stop) have no use. The check is cheap (at most 1 ms
  a tick, plus one read of the sent files per map), and stopping isn't
  wanted. So the check always runs and only reports, and A adds no convar.
  - `code_stale` loses its `stop` field.
  - The client's answer is renamed from `code_stopped` to `code_touched`,
    because nothing stops.
  - The stop rules (`foundation/events/stops.lua`) and the `critical` option
    are still built and unit-tested, but no runtime code calls
    `Touch:Blocks`.
  - Turning stopping on later would be a new decision and a small adapter
    change, not a setting.
- **T1, T2 and T4 run early in A, as the gate for detection** (A.6 items 11
  and 14). They run unattended while the programmer builds A.1 to A.3.
  - T1 decides whether detection's premise holds, and T2 decides
    `SERVED_TEXT`, both before `drift.lua` is written. In E they would come
    after B to D had been built on a detection that might be wrong.
  - T4's client path form becomes a `FileKey.FromSource` test in A, not a late fix.
  - None of the three needs the v2 library, only the client tools and
    probes.
  - **T3** runs once A is merged (A.6 item 15), because it tests A's codec
    over real `net`.
  - **In E, all five run again on the finished main** (E.3 item 4). That
    run confirms detection end to end, with a real client and a real stale
    file, and T5 sets `UNRELIABLE_MAX_BYTES`.
- **The two bottles share one GMod install.** The "Steam" bottle's
  `GarrysMod` folder is a symlink into the "Team Fortress 2" bottle's, so the
  client and the server read the same `garrysmod/`: `addons/sandcastle` (the
  symlink to this repo), `data/`, `cache/lua/` and `console.log`. That
  changes how T1 is staged (§3), and it means the client must never use
  `-condebug`, whose `console.log` the server writes.
- **D's counts were re-measured at main 29a6070** (D.3). `BroadcastSound`
  is unchanged (19 calls, of which 10 stay), and so are the text sites (23,
  of which 17 stay). `WS.Announce` has 2 callers, not the 3 that §4
  said.

---

## 1. Spec changes adopted

The scholar's 14 required changes are adopted or adopted with a
modification. None is rejected. The writer applies the edits in the last
column to `docs/game-events-v2.md` when it starts work (after C lands). Until
then, this table is the spec.

| # | Scholar's change | Verdict | Reason, and the spec edit |
|---|---|---|---|
| 1 | §4 "What is compared": the server keeps references and compares them with what it now serves | **Adopted, modified** | The server keeps two references per sent file: the text **sent** (hashed by the `AddCSLuaFile` wrapper at send) and, for files it runs, the text **run** (read with `file.Read` just before `CompileFile` in `WS.require` and `FeatureFiles:Run`). It does not switch to `CompileString`, which would change every chunk name and error path. What "now serves" means is the constant `SERVED_TEXT`, which T2 settles (§3); the default is `SERVED_DISK`. Edit: replace §4's first bullet with the scholar's wording plus these two sentences. |
| 2 | §4 threat sentence: shadowing happens on the server; name `sv_allowcslua 1` | **Adopted** | The operator chose to ignore `sv_allowcslua 1` (decision 1): no report and no refusal. Edit: rewrite the paragraph under "## 4". Shadowing happens on the server. With `sv_allowcslua 1` a client may run a local copy the check can't see, and the library treats such a server like any other. |
| 3 | §4 "When": the triggers are client ready, `feature_load` on a client, and a deduplicated gamemode refresh | **Adopted, modified** | A background scanner keeps the current hashes fresh within a per-tick budget, and the three triggers only *read* its results. That way no trigger reads files. An entity's refresh also takes a fresh reference for that entity, because its file reruns. Edit: replace the "When" bullet, and say `CompileFile`d files never rerun on refresh. |
| 4 | §4 file set: 191 files from the wrapper, fixed at start-up, no late sends | **Adopted, modified** | The adapter installs the wrapper once, before `init.lua`'s first `AddCSLuaFile`. To make that possible, `init.lua` includes `shared.lua` before its two `AddCSLuaFile` lines. A late call for a path not already sent is our error, `late_send`, which is logged. A repeat call for a path already sent (a refresh) is allowed. Edit: name the set and the rule. |
| 5 | §4 stop rules as a pure function of the stale set | **Adopted** | `foundation/events/stops.lua`. Edit: restate the rules as a function, independent of detection. |
| 6 | §4 cost: never stall a tick; no full reread at join | **Adopted** | The scanner probes at most `FILES_PER_TICK` files per tick. It screens by `file.Time` if phase A's measurement shows that is cheap and changes on save; otherwise it reads in turn. Start-up still reads every sent file once (126–163 ms, once per map). Edit: add the rule. |
| 7 | §4 attribution: match the path suffix; reject tail calls; say which feature an `entities/` site has | **Adopted** | The key is the path after `<folder>/gamemode/` or `<folder>/entities/`, giving `gamemode/...` or `entities/...`. `features/<name>/` keys belong to that feature, and every other key of ours is always loaded, entities included. Phase B moves every boss site out of `entities/` anyway. Edit: add the three rules. |
| 8 | §1 no wrapper forwards a name to `Fire`; migrate the boss forwarder | **Adopted, extended** | The count is corrected to 13 calls in 3 files (see the baseline). The rule extends to `Listen`: its name is a literal, and its listener is a function literal, so the field check can read it. The npc view's loop over `BossEvents.NAMES` goes. Edit: add both rules to §1's site rules and to the scan's list. |
| 9 | §2 values rewritten | **Adopted** | A record's keys are strings of at most 255 bytes. Tables with a metatable (`Color`) are `bad_fields`; send `r, g, b`. Edit: replace §2's "Values" bullet. |
| 10 | §3 tag table revised | **Adopted, modified** | Strings get a length prefix plus `WriteData`: 16 bits of length for values and 8 for keys. The int width is folded into the tag (`int8`, `int16`, `int32` are three tags), so there is no separate width tag. The full table is §A.3. Edit: replace §3's table with §A.3's. |
| 11 | §3 `too_large`: exact size, the 65,533-byte cap, an unreliable cap, and the ready burst | **Adopted, modified** | `UNRELIABLE_MAX_BYTES = 1200` is provisional, a named constant set by measurement (T5). The ready burst is several `Fire`s, so it isn't raised. Instead, the adapter counts the bytes sent to one player in one tick and logs our error `ready_burst` past `READY_BURST_MAX_BYTES = 131072`, half the 256 KB reliable buffer. Edit: add both. |
| 12 | §1/§3 order: validate and size before local dispatch, always | **Adopted** | A client-only event is validated but not sized, because it is never encoded. Edit: rewrite §1's "`Fire` runs the listeners…" paragraph. |
| 13 | §2 decoding a client's message: accept and rate by id first, then bounded decoding | **Adopted** | The refusal is `malformed`. It is the client's fault: dropped, and logged once per player per reason. Edit: add it under "Clients to the server". |
| 14 | §6 step 3 tests extended | **Adopted, extended** | The list is §A's tests. It adds `""` written without a zero-length `WriteData`, 255 against 256 keys, the depth cap, and 65,535 against 65,536 list items. The rewrite of `tests/events_test.lua` moves from step 3 to phase A (see the edits below). Edit: point §6 at this plan. |

**Further spec edits this plan makes** (technical calls; the writer applies
them too):

- **§2 `Fire`'s third argument is `options`** (`to`, `unreliable`,
  `critical`). Phase A rewrites every call that passes recipients today.
- **The client never hears the rates.** The accepted list goes to clients
  as names only, in the library event `events_accepted`. The rates are the
  server's business.
- **§4's protocol becomes three library events,** each with its one literal
  site in the adapter:
  - `code_stale { files }`: server to one client;
  - `code_touched { events }`: client to server, accepted. These are the
    events the stale files touch on that client; nothing stops;
  - `events_accepted { names }`: server to clients.

  The spec's `code_mismatch` is dropped, because the client no longer
  compares anything.
- **The check only reports** (operator decision 3), and no convar sets it:
  it always runs, and it never stops an event.
  - §4's "On a mismatch, only those events stop" and "Critical events stop
    their feature" become the definition of the stop rules: a pure model,
    built and tested, which no runtime code calls.
  - The error line reads as in A.4.
- **§5's generator is written in Lua,** as `.devtools/bin/gen_events_res.lua`,
  run by `luajit`. It shares one scanner, `.devtools/bin/events_scan.lua`,
  with the tests, which is what "the same scan" requires. The spec named a
  `.py` file.
- **§6's order changes:**
  - step 1 (A) replaces the v1 registry and rewrites `tests/events_test.lua`
    in the same commit, so that the test total never drops;
  - step 3 (C) removes only the `Define` and type-constructor shims, and
    builds the events file, the hook and the staleness test;
  - `Request` goes in A, since its only caller is the library's own
    `client_ready`.
- **The design change (2026-10-08) is applied to the spec directly:** goal
  4, §1's kinds and call sites, §2's facades, §3's note, §4's rule for
  system and recovery events, the new §4b on failure states and recovery,
  §5's kind lines, and §6. "Failure states and recovery" supersedes the
  bullets above that call these "library events": `events_accepted` on
  ready becomes `handshake`, and `code_current` and the `resync_*` and
  `event_refused` events are added.

---

## Rules for every phase

**Per-commit checks.** All of these must pass before each commit. The
evaluator reruns them on the branch.

```sh
.devtools/bin/check_lua.sh                      # exit 0; "TOTAL N passed, 0 failed"
python3 .devtools/bin/check_names.py            # exit 0
(cd .devtools/bin && python3 -m pytest -q)      # when any .devtools/bin/*.py changed; >= 134 passed
.devtools/bin/check_totals.sh main              # (from A's first commit) exit 0: no commit's TOTAL below its parent's
git log --format='%G?' main..HEAD | sort -u     # prints only G
git log --format=%B main..HEAD | grep -ciE 'co-authored-by|claude'   # prints 0
git status --short                              # empty when reporting
```

Commit with `git -c gpg.program=gpg-loopback commit -m "..."`. Keep commits
small, with no attribution and no push.

**The test total never drops, commit by commit.** A commit that deletes
tests along with the code they test must add at least as many in the same
commit. Phase A's switch commit is the one place this bites.
`check_totals.sh` enforces it.

**Code style** (load the `lua` skill):

- **Models in `foundation/` are pure `module(...)` files.** Each phase's new
  model gets its LuaJIT tests written first and seen failing. "Pure" is
  checked by `grep -nE '\b(net|util|file|hook|timer|player|ents|game|concommand|GetConVar|CurTime|SysTime|IsValid|Entity)\b[.(]' <file>`,
  which prints nothing. The models' I/O goes through a `host` table or
  injected functions.
- **Controllers coordinate, entities are thin bindings, clients present.**
  The adapter (`ws/sh_events.lua`) only wires `net`, players and hooks
  to the models.
- **Constants are named.** Multi-field tables have one field per line.
- **No `TF2` or `tf2` in our identifiers** (`check_names.py`).
- **No ENT function shares a name with an engine metatable method.** Check
  the wiki's Entity, NextBot and Player method lists.
- **Lazy loading stays:** no always-loaded file holds one mode's content.
  The event library itself is generic, so it is always loaded.

**Names:**

- New console names go through `.devtools/bin/check_engine_names.sh NAME...`,
  which must print `free`. It only reads files.
- New convars are listed in `addons/sandcastle/cfg/sandcastle_defaults.cfg` at their
  default; `tests/cfg_defaults_test.lua` checks this.
- Meta and debug names use `ws_`.
- New event names reuse TF2's event and field names where TF2 has the event.
  Read them from the mounted TF2's `tf/resource/modevents.res`, read-only.
- Recovery events, the library's own (sited in `protocol.lua`), have plain
  names, like `client_ready` and `resync_request`. `feature_load` is
  `sh_core.lua`'s system event and keeps its name.

**Live runs.**

- Run servers only through `.devtools/bin/srcds.py` and
  `.devtools/bin/ingame_tests.py`, in the bottle "Steam".
- **The bottle "Team Fortress 2" has one exception** (operator decision 2,
  extended by P6): the GMod client for T1 to T7, unattended. Only
  `.devtools/bin/gmod_client.py` launches
  or closes it, with §3's safeguards. No server and no other process ever
  runs there, and nothing else launches or signals anything in that
  bottle.
- The server loads main through the `sandcastle` symlink. A phase's live
  criteria therefore run on main after the director merges it. Phase A's
  probes are the exception: they may run earlier by copying the modules they
  test into `garrysmod/data/ws_tests/`, as `gev2_probe.py` does.
- Stop the server when done (`python3 .devtools/bin/srcds.py stop`).

---

## Phase A: the library, as classes, behind today's API

**Goal.** Build the whole v2 library: the codec with its exact size model,
validation before dispatch, a client's `Fire`, `Accept` and the rate limit,
attribution by path suffix, the `AddCSLuaFile` wrapper, the server-side drift
check, and the stop rules. Every feature keeps working unchanged.

- `Define` and the type constructors become inert shims that only phase B's
  migration still calls.
- The site scanner and its tree test land, with a list of unmigrated files
  that B empties.
- The client tools for T1 to T5 land first (§3): `gmod_client.py`,
  `gev2_marker.py`, and `gev2_probe.py`'s client mode.

**What changed (event classes, 2026-10-08).**

- A builds the library as the classes of "Event classes: the class layout",
  with the three kinds and the recovery protocol. It is still behind today's
  API: `Events.Fire`, `Listen`, `Ignore` and `Accept` are `Events.Game`'s
  until C, so no feature changes kind in A.
- **New:** the event kinds, `Catalog`, `Listeners` (isolated dispatch),
  `Protocol`, `Failure` and its 8 states, `Recovery`, `Handshake`, `Peers`,
  `Pacer`, the ports with `sh_events_ports.lua`, and `tests/fake_ports.lua`
  and `tests/fake_link.lua` with `tests/events_recovery_test.lua`.
- **Reshaped:** `codec`, `errors`, `paths` and `stops` become classes, and
  the facade and the adapter split, as "Phase A's existing commits" says.
- **Detection** gains what each player loaded and `code_current`. It still
  waits for T1 and T2.
- **The library events** become the recovery vocabulary. On ready,
  `events_accepted` is replaced by `handshake`.
- **Criteria:** items 3 and 7 change, item 10 adds a log check, item 15 (T3)
  also checks the handshake, and items 16 to 22 are new.

**One programmer, plus the researcher for the early client session** (§3),
which is the second agent.

1. **Stage 1, done:** `check_totals.sh`, the client tools and their tests,
   and `srcds.py --no-lua-refresh` (086875b to b752d5b, fixed on
   `gev2-phase-a-tools`).
2. **The client session.** Once the tools gate passes and the tools are on
   main ("How the two branches combine"), the director starts the
   researcher on T1, T2 and T4, run from main's scripts against main.
3. **Stage 2, meanwhile:** the programmer merges main into the A branch,
   reshapes the committed modules into classes, and builds the new classes,
   recovery included (A.1 to A.3, A.5).
4. **Stage 3, after T1 and T2 are recorded** (A.6 item 11): detection.
   That is `drift.lua`, the scanner, the triggers, what each player loaded,
   and `stale_code`'s recovery with `code_current`.

### A.1 Files

| File | Change |
|---|---|
| `addons/sandcastle/gamemodes/sandcastle/gamemode/foundation/events.lua` | **Replaced:** the v2 core facade (pure), composed of the modules below. The v1 `Registry`, types and schemas go. `Crc32` moves to `codec.lua`. |
| `foundation/events/codec.lua` | New. Validation, the key table, the exact bit-size model, encode, and bounded decode. |
| `foundation/events/rates.lua` | New. The accepted names and the per-player, per-event token bucket (moved from v1's `Admit`). |
| `foundation/events/paths.lua` | New. Source path to key, key to feature and kind, and `AddCSLuaFile` argument resolution. |
| `foundation/events/drift.lua` | New. The sent and run references, observed hashes, the scanner's state, and the stale query. |
| `foundation/events/stops.lua` | New. The stop rules. |
| `gamemode/ws/sh_events.lua` | **Rewritten.** The adapter: `net`, recipients (`to`), readiness, the wrapper's install, the scanner's `Think`, reports, and the library events. It has no convar (decision 3). It keeps inert `Define` and type constructors until C. `Request` goes. |
| `gamemode/ws/sh_core.lua` | On the server, `WS.require` and `FeatureFiles:Run` read the text and record the run hash for sent files. Files compiled before the adapter exists are queued, and recorded when it starts. |
| `gamemode/init.lua` | `include("shared.lua")` moves above the two `AddCSLuaFile` lines, so the wrapper sees every send. |
| Every `Fire` call with a third argument (`sh_core.lua:82`, `features/nbdebug/sv.lua` ×6 and any others the scan finds) | The argument becomes `{ to = ... }`. Behaviour is unchanged. |
| The three sites whose event had a `Default` (`features/capture/sv.lua` `cappers`, `ws/sv_world.lua` `others` and `team`) | Each sends the value the default supplied, or the listener treats `nil` the same way. Behaviour is unchanged. |
| `.devtools/bin/gmod_client.py`, `test_gmod_client.py` | New, A's second commit. It launches and closes the GMod client in the bottle "Team Fortress 2" for T1 to T5. §3's safeguards are its tested behaviour (A.5). |
| `.devtools/bin/gev2_marker.py`, `test_gev2_marker.py` | New. It sets and restores the uncommitted marker lines that T1, T2 and E's client check put in an addon file (§3). |
| `.devtools/bin/gev2_probe.py` | Gains `run --client NAME...`: the probe runs on every connected client (§3). Its output lands in `.devtools/artifacts/gev2-research/client/`. |
| `.devtools/bin/srcds.py`, `test_srcds.py` | `start` gains `--no-lua-refresh`, which adds `-disableluarefresh` (T1). Nothing else changes, and it still refuses every bottle but "Steam". |
| `.devtools/bin/gev2/client_t1.lua`, `client_t2.lua`, `client_t4.lua` | New client probes, written by the researcher for the early session. `client_t3.lua` is the programmer's, for A.6 item 15. |
| `.devtools/bin/events_scan.lua` | New. The Lua site scanner (tokenizer-aware: strings and comments are never calls), used by the tests now and the generator in C. |
| `tests/events_unmigrated.lua` | New. The ratchet: `return { b1 = { ...paths }, b2 = { ...paths } }`, the files exempt from the site rules until B migrates them. The two blocks sit at least 5 lines apart, so B1's and B2's edits merge cleanly. |
| `.devtools/bin/check_totals.sh BASE` | New, and A's first commit. For each commit in `BASE..HEAD`, it exports the tree (`git archive`) to a temp dir, runs its `check_lua.sh`, and prints `sha TOTAL subject`. It exits 1 if any commit's total is below its parent's. |
| `.devtools/bin/expected_sent_files.sh` | New. Prints the sorted keys the server should send, from the tree: `gamemode/shared.lua`, `gamemode/cl_init.lua`, every `gamemode/foundation/**/*.lua`, `gamemode/features/*/{sh,cl}.lua`, `gamemode/ws/{sh_,cl_}*.lua`, and every `entities/{entities,weapons}/*.lua` with a line starting `AddCSLuaFile()`. |
| `.devtools/bin/gev2/events_size.lua`, `events_sent.lua`, `events_scan_cost.lua` | New probes, run by `gev2_probe.py` (A.6). |

**The design change adds or reshapes these files.** It wins where a row
above differs. Paths are under `addons/sandcastle/gamemodes/sandcastle/gamemode/`
unless they start with `tests/` or `.devtools/`.

| File | Change |
|---|---|
| `foundation/events.lua` | **Reshaped:** the `Library` class, one realm's coordinator over the classes below. `Events.New(ports)`. It keeps no registry, sites or listeners of its own. |
| `foundation/events/event.lua`, `event/game.lua`, `event/system.lua`, `event/recovery.lua` | New. The `Event` base and its three kinds. `system.lua` holds `MAJOR = 1`. |
| `foundation/events/catalog.lua` | New. `Catalog`. |
| `foundation/events/listeners.lua` | New. `Listeners`, with isolated dispatch. |
| `foundation/events/protocol.lua` | New. `Protocol`, holding the recovery events' only sites. |
| `foundation/events/failure.lua` and `failure/{joining,handshake_timeout,major_mismatch,stale_code,refused,decode_failed,listener_failed,ready_burst}.lua` | New. `Failure` and its 8 parts. |
| `foundation/events/recovery.lua` | New. `Recovery`. |
| `foundation/events/handshake.lua`, `peers.lua`, `pacer.lua` | New. `Handshake` (client), `Peers` and `Pacer` (server). |
| `foundation/events/codec.lua`, `errors.lua`, `paths.lua`, `stops.lua` | **Reshaped** into `Codec`, `Error`, `FileKey` and `Touch`. |
| `foundation/events/drift.lua` | As above, plus `Loaded`, `Refreshed`, `StaleFor` and `Forget` (A.2). Stage 3. |
| `ws/sh_events.lua` | **Reshaped:** the composition root. It builds the ports and the one `Library`, exposes the `Game`, `System` and `Recovery` facades plus the aliases until C, and registers net and the hooks. It has no `Fire` site. |
| `ws/sh_events_ports.lua` | New. `NetTransport`, `GModRoster` (with `Disconnect`, by `ply:Kick`), `GModFiles`, `GModClock`, `GModLog` and `SendWatcher`. `sh_events.lua` includes it first. |
| `ws/cl_network_notice.lua` | New. The view: `Events.Recovery.Listen("network_notice", ...)` prints the chat line and plays TF2's cue (P1). `init.lua`'s walk sends it as a `cl_` file. |
| `gamemode/shared.lua` | `LOADED_FIRST` gains `sh_events_ports.lua`, so the `sh_` walk doesn't include it a second time. |
| `ws/sh_core.lua` | Unchanged in A, apart from A.1's run hashes. Its `client_ready` listener keeps working through the alias, and B makes it a `resync` provider. |
| `tests/fake_ports.lua`, `tests/fake_link.lua` | New. The fake ports, and a server and its clients wired through `fake_net.lua` buffers, with a shared clock and taps to drop, corrupt or delay the next message. |
| `tests/events_kinds_test.lua`, `events_listeners_test.lua`, `events_handshake_test.lua`, `events_pacer_test.lua`, `events_failures_test.lua`, `events_recovery_test.lua` | New (A.5). |

### A.2 Interfaces

**Public API** (`WS.Events`, both realms unless marked):

```lua
Events.Game.Fire(name, fields, options)  -- options: nil or { to = nil|team|Player|{Player...}|Vector, unreliable = bool, critical = bool }
Events.Game.Listen(name, id, fn)         -- fn(fields) ; on the server, for a client's event, fn(fields, ply)
Events.Game.Ignore(name, id)
Events.Game.Accept(name, rate)           -- server only; rate = { count = whole >= 1, seconds = number > 0 }
Events.System.Fire(name, fields, options) -- the same four, for system events; options: nil or { to, unreliable }
Events.System.Listen / Ignore / Accept
Events.Recovery.Listen(name, id, fn)     -- the library's events; on the server, features listen to "resync"
WS.IsReady(ply)                     -- server: that player's handshake is done
WS.LocalReady()                     -- client: this client's handshake is done
-- until phase C only: Events.Fire, Listen, Ignore and Accept are Events.Game's,
-- and Events.Define and the type constructors exist and do nothing
```

**`foundation.events`: the `Library` (pure).**

```lua
Events.New(ports) -> Library
-- ports = {
--   realm = REALM_SERVER | REALM_CLIENT,
--   folder = "sandcastle",                 -- GM.FolderName
--   values = <the codec's value port, below>,
--   hash = function(text) -> string,       -- util.CRC in game, any stable function in tests
--   transport = <Transport>, clock = <Clock>, log = <Log>,
--   roster = <Roster>, files = <Files>,    -- server only
-- }
GAME, SYSTEM, RECOVERY                      -- the kinds: GameEvent.KIND, SystemEvent.KIND, RecoveryEvent.KIND
Library:Fire(kind, name, fields, options, source)
-- source: debug.getinfo(2, "S").source, taken by the facade.
-- In order: the kind's options, the codec's plan and size, the site (Catalog), the
-- local dispatch (Listeners, isolated), then the send. The server sends through the
-- Pacer to the ready players that `to` names. A client sends to the server only
-- if the event is accepted, and holds it while joining (Handshake).
-- Raises bad_fields, too_large, bad_options, bad_kind or id_collision before any listener runs.
Library:Listen(kind, name, id, fn, source)  -- raises bad_kind
Library:Ignore(kind, name, id)
Library:Accept(kind, name, rate)            -- server; raises bad_accept or bad_kind
Library:Receive(reader, sender)
-- Server, from a client: id, then accepted?, then rate, then bounded decode, then
-- dispatch(fields, sender). A refusal is logged once per player and reason, and
-- opens refused (event_refused).
-- Client, from the server: an id with no listener is ignored; a decoding failure
-- is logged as our bug and opens decode_failed.
Library:Connected(player), Library:Disconnected(player)   -- server; bots are never peers
Library:StartedUp()                         -- server, at InitPostEntity: the sent set is fixed
Library:Loaded()                            -- client, at InitPostEntity: the handshake starts
Library:Refreshed()                         -- server: a gamemode refresh, already deduplicated to one per tick
Library:Tick()                              -- Recovery's retries; the Pacer and the scanner (server); the handshake clock (client)
Library:IsReady(player), Library:LocalReady()
Library:Sites() -> { [name] = { key, feature, kind, critical } }
Library:ListenKeys() -> { [name] = { [path] = true } }
Library:Failures() -> { failure... }        -- the open failure states, for tests and C's print commands
```

**The ports.** `sh_events_ports.lua` implements them, and
`tests/fake_ports.lua` fakes them.

```lua
Transport:Send(players, outgoing)    -- server; the GMod class does net.Start(FIRE_NET, outgoing.unreliable), outgoing:WriteTo(net), net.Send(players)
Transport:SendToServer(outgoing)     -- client
Roster:Resolve(to) -> { player... }  -- nil = every player, a team, a player, a list, or a Vector (its PVS)
Roster:Name(player) -> string
Roster:Disconnect(player, reason)    -- ply:Kick(reason); only major_mismatch calls it (P3)
Files:Read(key) -> text | nil        -- file.Read(key:LuaPath(folder), "LUA")
Files:Time(key) -> number | nil
Clock:Now() -> seconds               -- CurTime()
Log:Ours(line, traceback)            -- our bug: ErrorNoHalt, with the traceback when there is one
Log:ClientFault(player, line)        -- the client's fault: MsgN (the Library already dedupes)
Log:Report(line)                     -- console on a client (chat and the cue are the view's, through network_notice); the log on a server
```

**The event kinds** (`foundation.events.event`, and its parts
`foundation.events.event.game`, `.system` and `.recovery`):

```lua
GameEvent.New(name), SystemEvent.New(name), RecoveryEvent.New(name, clientRate)
event.name, event.id, event.KIND     -- the id is Codec.Id(name)
event:CheckOptions(options)          -- raises bad_options. Game takes to, unreliable and
                                     -- critical; system takes to and unreliable; recovery takes to
event:Stoppable() -> boolean         -- game true; system and recovery false (decision b)
event:Frozen() -> boolean            -- system true
event:FiredFrom(key) -> boolean      -- recovery: only gamemode/foundation/events/protocol.lua
event:ClientRate() -> rate | nil     -- a recovery event a client sends: accepted at this rate, without Accept
SystemEvent.MAJOR = 1
```

**`foundation.events.catalog`.**

```lua
Catalog.New() -> Catalog
catalog:Use(event) -> event          -- the realm's one Event per name. Raises id_collision for
                                     -- another name on the same id, and bad_kind for another kind
catalog:Fired(name, key)             -- records the site's key the first time; bad_kind if the kind may not fire from key
catalog:ByName(name), catalog:ById(id) -> Event | nil
catalog:SiteOf(name) -> FileKey | nil
catalog:Sites() -> { [name] = { key, feature, kind, critical } }
```

**`foundation.events.listeners`.**

```lua
Listeners.New() -> Listeners
listeners:Listen(name, id, fn, key)  -- again under the same id: replaced in its place
listeners:Ignore(name, id)
listeners:Dispatch(name, fields, sender, only) -> { failure... }
-- Runs a snapshot, in the order added, each fn under xpcall with debug.traceback.
-- A listener that raises is returned as { name, id, key, message, traceback },
-- and the rest still run. only(key) -> boolean is optional; resync uses it to
-- run the always-loaded listeners and those of the features it names.
listeners:Keys() -> { [name] = { [path] = true } }
```

**`foundation.events.codec`.** The wire, the size model and the bounded
reader are unchanged (A.3, 241c9be and bddcfb0). They are wrapped in a
class:

```lua
Codec.New(values) -> Codec
codec:Plan(fields) -> plan           -- raises bad_fields; plan.bits = the payload's exact bit count, header excluded
codec:Bytes(plan) -> integer         -- HEADER_BYTES + ceil((ID_BITS + plan.bits) / 8): what net.BytesWritten() will read
codec:CheckSize(plan, unreliable)    -- raises too_large: Bytes > MESSAGE_MAX_BYTES, or > UNRELIABLE_MAX_BYTES when unreliable
codec:Write(id, plan, writer)
codec:ReadId(reader) -> integer
codec:ReadFields(reader) -> fields | nil, refusal   -- bounded; never raises
Codec.Id(name), Codec.Crc32(s), and A.3's constants  -- module functions, for the scanner and the probes
-- values (the codec's value port):
-- { kind(v) -> "entity"|"vector"|"angle"|nil, index(e) -> integer|nil (nil for NULL),
--   entity(i), null(), xyz(v) -> x, y, z, vector(x, y, z), angle(p, y, r) }
-- reader/writer: net's Write/ReadUInt, Bool... plus WriteData/ReadData, WriteFloat/ReadFloat,
--   WriteDouble/ReadDouble, and BytesLeft()
```

**`foundation.events.rates`** (as built, a360c08):

```lua
Rates.New() -> Rates
Rates:Accept(name, rate)             -- raises bad_accept
Rates:NameOf(id) -> name | nil
Rates:Admit(sender, id, now) -> boolean
Rates:Names() -> { name... }         -- sorted, for handshake and events_accepted
```

**`foundation.events.paths`: `FileKey`** (a value class):

```lua
FileKey.FromSource(source, folder) -> FileKey | nil     -- nil: not ours
FileKey.Resolve(callerSource, arg, folder) -> FileKey | nil   -- AddCSLuaFile(arg) as called from callerSource
key.path                             -- "gamemode/features/capture/cl.lua", "entities/entities/merasmus.lua"
key.feature                          -- "capture", or nil: always loaded
key.kind                             -- KIND_INCLUDED | KIND_COMPILED | KIND_ENTITY
key:LuaPath(folder)                  -- "sandcastle/gamemode/...", for file.Read(..., "LUA")
```

**`foundation.events.sent`** (as built, 3a7927d): `Sent.New()`,
`sent:Add(key, startedUp)` (raises `late_send`), `sent:Has(key)`,
`sent:Keys()`.

**`foundation.events.drift`** (stage 3):

```lua
Drift.New(served) -> Drift           -- served: SERVED_DISK (default) | SERVED_SENT, settled by T2
drift:Sent(key, hash, time)          -- the wrapper's reference, by A.4's kind rule
drift:Ran(key, hash)                 -- the run reference
drift:Observe(key, hash, time)       -- the scanner's reading of what is served now
drift:NeedsRead(key, time) -> boolean   -- the file.Time screen
drift:Loaded(player, keys)           -- the player loads these keys now: what is served is what it runs
drift:Refreshed(keys)                -- a refresh reran these on both realms: new references, and
                                     -- each ready player's loaded hash becomes the new text
drift:StaleFor(player) -> { { key = ..., reason = ... } ... }
drift:Forget(player)
Scanner.New(keys, perTick) -> Scanner
scanner:Step() -> { key... }         -- at most perTick keys per call, round robin
scanner:Cycled() -> boolean          -- a full cycle has finished since the last call
```

**`foundation.events.stops`: `Touch`.**

```lua
Touch.Of(staleKeys, sites, listenKeys) -> Touch
-- On the client: the events with a listener in a stale key, plus the events
-- whose client Fire site is in one.
touch.game, touch.system             -- { [name] = true } each; recovery events are never touched
touch:IsEmpty() -> boolean
touch:Blocks(name, sites) -> boolean
-- The stop rule: name is touched; or a touched event is critical and shares
-- name's feature; or a touched critical event's stale key is always loaded.
-- Always false for system and recovery events (decision b). Built and
-- unit-tested, but no runtime code calls it (operator decision 3).
```

**`foundation.events.protocol`.**

```lua
Protocol.New(fire) -> Protocol       -- fire(name, fields, options): the Library's recovery Fire
protocol:ClientReady(major)                    -- client
protocol:Handshake(player, major, accepted)    -- server
protocol:EventsAccepted(names, to)             -- server
protocol:ResyncRequest(features, reason)       -- client
protocol:ResyncBegin(player, epoch, features)  -- server
protocol:Resync(player, epoch, features)       -- server, local only: runs the providers
protocol:ResyncEnd(player, epoch)              -- server
protocol:CodeStale(player, files)              -- server
protocol:CodeTouched(events)                   -- client
protocol:CodeCurrent(player, files)            -- server
protocol:EventRefused(player, id, reason)      -- server
protocol:Notice(state, line, recovered, chat)  -- client, local only: network_notice, for the view
Protocol.CLIENT_RATES                -- { client_ready = 2 per 10 s, code_touched = 4 per 10 s, resync_request = 4 per 10 s }
-- Each method holds its event's one literal site, as a statement, never a tail call:
--   RecoveryFire(self, "code_stale", {
--   	files = files, -- the keys that differ from the server's
--   }, { to = player })
```

**`foundation.events.failure` and its parts**
(`foundation.events.failure.<state>`):

```lua
<State>.New(...) -> Failure          -- each part's factory, with what it needs (player, feature, file, id)
failure.STATE                        -- "joining", "handshake_timeout", ...
failure:Key() -> string              -- at most one open failure per key (state, peer, and feature or file)
failure:ReportLine(), failure:RecoveredLine(), failure:GaveUpLine()
failure:Start(protocol, now)         -- its recovery's first step
failure:AnsweredBy(name, fields) -> boolean   -- whether this recovery event clears it
failure:Due(now) -> boolean
failure:Retry(protocol, now) -> boolean       -- false: no tries left
```

**`foundation.events.recovery`.**

```lua
Recovery.New(protocol, log) -> Recovery
recovery:Open(failure, now)          -- reports once and starts it; a failure already open under its key is kept
recovery:Answer(name, fields, now)   -- closes every open failure this recovery event answers, reporting each
recovery:Cleared(key, now)           -- closes one whose cause the realm saw go (a clean listener run, an empty queue)
recovery:Tick(now)                   -- retries what is due; reports a give-up once
recovery:Open() -> { failure... }
```

**`foundation.events.handshake`** (client):

```lua
Handshake.New(major) -> Handshake
hs:Start(now)                        -- READY_SENT; the Library fires client_ready
hs:Tick(now) -> nil | RETRY | GIVE_UP
hs:Answer(fields) -> { accepted = { name... }, major = n }   -- the server already compared the majors
hs:Hold(outgoing) -> boolean         -- false once HELD_MAX are held
hs:Ended(epoch) -> { outgoing... }   -- the latest epoch's resync_end: READY, and the held events to send if accepted
hs:State() -> JOINING | READY_SENT | READY
```

**`foundation.events.peers`** (server):

```lua
Peers.New() -> Peers
peers:Connect(player), peers:Gone(player)
peers:Handshaken(player) -> epoch    -- a new epoch; older ones are void
peers:Ended(player, epoch)           -- READY
peers:IsReady(player) -> boolean, peers:Ready() -> { player... }
peers:Touched(player, events), peers:TouchedBy(player) -> { [name] = true }
```

**`foundation.events.pacer`** (server):

```lua
Pacer.New(bytesPerTick, backlogMax) -> Pacer
pacer:Push(player, outgoing, bytes) -> boolean   -- true: send now; false: queued behind the backlog
pacer:Drain() -> { { player, outgoing }... }     -- this tick's share, in order
pacer:Pending(player) -> bytes
pacer:Over(player) -> boolean        -- the backlog passed backlogMax (logged once per resync)
pacer:Forget(player)
```

**Named errors** (the `Error` class). Each is an instance that prints as
`kind: message`; `err:IsOurs()` tells the two families apart.

- Our bugs, raised at the call: `bad_fields`, `too_large`, `bad_options`,
  `bad_accept`, `id_collision`, `bad_kind`. Logged: `late_send`.
- The client's fault, refused: `not_accepted`, `rate_limited`, `malformed`.
  Each also opens `refused`.
- Failure states, which are detected, reported and recovered, and never
  raised: `joining`, `handshake_timeout`, `major_mismatch`, `stale_code`,
  `refused`, `decode_failed`, `listener_failed`, `ready_burst`.

### A.3 The wire (replaces spec §3's table)

A message is the net header (3 bytes), then:

1. the id, 24 bits;
2. the key count, 8 bits, then for each key an 8-bit length and its bytes;
3. the top-level fields as an untagged record body: an 8-bit count, then for
   each field an 8-bit key index and a tagged value.

A tag is 4 bits.

| Tag | Payload | Bits after the tag |
|---|---|---|
| `false`, `true` | none | 0 |
| `int8`, `int16`, `int32` | zig-zag, unsigned; the narrowest that fits; whole numbers in [-2^31, 2^31-1] | 8 / 16 / 32 |
| `double` | `WriteDouble`, for every other number (`inf`, `NaN`, ±2^31 and beyond, fractions) | 64 |
| `string` | 16-bit length, then `WriteData` (skipped when the length is 0) | 16 + 8·len |
| `entity` | its index (the world is 0) | 13 |
| `entity_null` | none: `NULL`, kept apart from the world | 0 |
| `vector`, `angle` | three `WriteFloat`s, exact | 96 |
| `list` | 16-bit count, then each item tagged; `{}` is an empty list | 16 + Σ |
| `record` | 8-bit count, then key index (8) and tagged value per field | 8 + Σ (8 + v) |

Named constants:

| Constant | Value |
|---|---|
| `TAG_BITS` | 4 |
| `ID_BITS` | 24 |
| `KEY_COUNT_BITS`, `KEY_INDEX_BITS`, `KEY_LENGTH_BITS`, `RECORD_COUNT_BITS` | 8 each |
| `LIST_COUNT_BITS`, `STRING_LENGTH_BITS` | 16 each |
| `ENTITY_BITS` | 13 |
| `MAX_DEPTH` | 16 |
| `HEADER_BYTES` | 3 |
| `MESSAGE_MAX_BYTES` | 65536 (`net.BytesWritten()`, header included) |
| `UNRELIABLE_MAX_BYTES` | 1200 (provisional; T5) |
| `READY_BURST_MAX_BYTES` | 131072 |

These are `bad_fields`:

- a function, a cycle, or other userdata;
- a table with a metatable;
- non-string keys, mixed list and record keys, or a list whose keys aren't
  exactly 1..n;
- a key over 255 bytes, or more than 255 distinct keys;
- a list over 65,535 items, or nesting over `MAX_DEPTH`.

A string over 65,535 bytes is `too_large`.

**Decoding a client's message, in this order:**

1. read the id;
2. `Rates:NameOf(id)`, else `not_accepted`;
3. `Rates:Admit`, else `rate_limited`;
4. decode, refusing with `malformed` on any of:
   - a count or length that can't fit in the `BytesLeft()` that remain (each
     item costs at least `TAG_BITS`);
   - depth over `MAX_DEPTH`;
   - an unknown tag;
   - a key index at or past the key count.

### A.4 Detection and the stop protocol

- **The wrapper.** The adapter's server block replaces the global
  `AddCSLuaFile` once (kept in `WS.SentFiles` across refreshes), always
  calling the previous function. Each call:
  1. resolves its argument with `FileKey.Resolve` against
     `debug.getinfo(2, "S").source`, skipping files that aren't ours;
  2. reads the text through `LUA`;
  3. records `Drift:Sent` with the kind's rule:
     - `KIND_COMPILED` keeps its first reference, because nothing reruns it;
     - `KIND_INCLUDED` and `KIND_ENTITY` take the new one, because their
        file reran.

  "Started up" is `InitPostEntity` on the server. After it, a new key raises
  `late_send`; the adapter catches it and logs it as our error.
- **The scanner.** A server `Think` hook probes `FILES_PER_TICK` keys per
  tick (start at 2; tune from A.6's measurement), and `Drift:Observe`s each.
  If A.6 shows `file.Time` is cheap and changes on save, set
  `SCREEN_BY_TIME = true`. Otherwise every probe reads and hashes the file.
- **Triggers.** Each one asks `Drift:StaleFor` about the player for its keys:
  - a player's `client_ready`: the entry files, `ws/`, `foundation/` and
    the entities;
  - `feature_load` to a player: that feature's client parts;
  - a gamemode refresh: `OnReloaded`, deduplicated to one handling per tick.
    It only re-takes references through the wrapper's reruns; connected
    clients reran the same included files.

  A non-empty result is fired to that player as `code_stale { files }`,
  and the server logs it.
- **What each player loaded, and recovery** (the design change). Each
  trigger first calls `Drift:Loaded(ply, keys)` for the keys that player
  loads then, and asks `Drift:StaleFor(ply)`.
  - A gamemode refresh calls `Drift:Refreshed` with the included keys, and
    an entity's refresh with that entity's key. Both realms reran those
    files, so their references and each ready player's loaded hash become
    the new text.
  - After every full scanner cycle (`Scanner:Cycled()`), the server asks
    `Drift:StaleFor` again for each ready player. Files that left a player's
    stale set go to it as `code_current { files }`, and `stale_code` closes
    for them ("Failure states and recovery").
- **The client** works out `Touch.Of`. It reports once to its console and
  its chat, in this form, with the game and system events listed apart
  (decision b):

  `network error: gamemode/features/capture/cl.lua differs from the server's; events it touches (not stopped): game: teamplay_capture_blocked; system (major 1): teamplay_point_captured`

  It stops nothing (operator decision 3), and it fires
  `code_touched { events }`.
- **The server** records each player's touched set and logs one line, in
  the same form with the player's name in front. It drops nothing. No
  runtime code calls `Touch:Blocks`, which stays a tested model in case
  stopping is ever wanted.
- **Client-only events** (client `Fire` and client `Listen`, never on the
  wire) are never stopped: both ends are the client's own code.
- **`sv_allowcslua` is ignored** (operator decision 1). The library never
  reads it, logs nothing about it, and refuses nothing. The check runs the
  same whatever its value.
- **The library's events are the recovery vocabulary** (decision (c); its
  table is in "Failure states and recovery"). Each has its one literal site
  in `foundation/events/protocol.lua`, and none is in the adapter.
  - `client_ready { major }` leaves the client before any accepted list,
    because recovery events from clients are accepted at their own rates.
  - On ready, the server answers with `handshake { major, accepted }`, then
    runs the ready resync. `events_accepted { names }` goes to all ready
    players only when `Accept` runs after start-up, and to one player after
    a `not_accepted` refusal.
  - Bots never handshake. `Peers` skips them, as the A branch's `Ready`
    already does.

### A.5 Tests to write first

Write each file's tests first and watch them fail.

- Each listed name is an exact `T.test` name the evaluator greps for.
- More tests are welcome.
- The fake buffer in the tests counts bits per write as GMod does (research
  §4's table), exposes `BytesWritten()` and `BytesLeft()`, and errors on a
  read of the wrong kind or width.

`tests/events_codec_test.lua`:
- `an empty string and a string holding NUL round-trip exactly`
- `2^31-1 and -2^31 go as ints; 2^31 and -2^31-1 go as doubles`
- `inf, -inf and NaN go as doubles; -0 arrives as 0`
- `an int takes the narrowest of 8, 16 and 32 bits`
- `vectors and angles round-trip exactly, beyond 16384 too`
- `NULL and the world arrive apart`
- `{} arrives as {}`
- `the key table names each key once, however many records use it`
- `a list with a hole, non-string keys, mixed keys, a cycle, a function or a table with a metatable is bad_fields`
- `255 distinct keys fit; 256 is bad_fields`
- `65535 list items fit; 65536 is bad_fields`
- `nesting deeper than MAX_DEPTH is bad_fields`
- `the size model counts every bit the writer writes` (over a corpus of at least 20 events covering every tag; the plan's bits equal the fake buffer's)
- `an event at the reliable cap fits; one byte over is too_large`
- `an unreliable event over UNRELIABLE_MAX_BYTES is too_large`
- `a count larger than the bytes left is malformed`
- `a string length past the bytes left is malformed`
- `an unknown tag is malformed`
- `a key index past the key table is malformed`
- `nesting past MAX_DEPTH on the wire is malformed`

`tests/events_test.lua` (rewritten in the same commit that replaces the v1
core, with at least 27 tests):
- `CRC32 is the standard one (zlib's, GMod's util.CRC)` (kept)
- `an event's id is its name's CRC32 cut to 24 bits, the same in any realm and order`
- `two names with one id in a realm raise id_collision, naming both` (v1's `event_188781` / `event_326020` pair)
- `listeners run in the order added with the fields and what the adapter adds` (kept)
- `listening again under an id replaces that listener in its place; Ignore removes it` (kept)
- `a listener added during a dispatch counts from the next one`
- `Fire validates and sizes before any local listener runs`
- `Fire raises bad_fields with no listener and no recipient`
- `unknown options, to on a client, and a non-boolean critical are bad_options`
- `a client's Fire stays local unless the server accepted the event`
- `client_ready leaves a client before any accepted list arrives`
- `the server dispatches a client's accepted event with its sender`
- `a client's event the server did not accept is refused before its fields are read`
- `each player's sends are rate limited per event; the allowance refills with time` (v1's schedule, kept)
- `a malformed client message is refused as the client's fault and logged once per player`
- `an id with no listener is ignored on the client`
- `Fire records its site's key, feature and critical flag the first time it runs`
- `a rate is refused unless count is whole and at least 1 and seconds is above 0`
- `only the event adapter registers, starts or receives net messages` (kept; the adapter's two messages)

`tests/events_paths_test.lua`:
- `a source in the legacy addon folder, under gamemodes/, or LUA-relative gives the same key`
- `entities and weapons keep their entities/ key`
- `Sandbox's and GMod's own files are not ours`
- `a key under features/<name>/ belongs to that feature; every other key of ours is always loaded`
- `AddCSLuaFile resolves against the caller's folder, and no argument means the caller's own file`
- `ws/ and the entry files are included, foundation/ and features/ compiled, entities/ entities`
- `a source longer than short_src keeps resolves whole`

`tests/events_drift_test.lua`:
- `a file sent and run with the same text is not stale`
- `a compiled file whose text changes is stale, and stays stale after a gamemode refresh`
- `an included file sent again by a gamemode refresh takes the new text as its reference`
- `an entity sent again by its refresh takes the new text as its reference`
- `a module compiled after start-up from other text than was sent is stale`
- `under SERVED_SENT a change on disk alone is not stale`
- `the scanner probes at most its per-tick count and visits every file in turn`
- `with time screening a file whose time is unchanged is not read`
- `a new path sent after start-up is late_send; a path sent again is not`

`tests/events_stops_test.lua`:
- `a stale file stops the events it listens to and the events it fires, and nothing else`
- `a critical event touched by a stale file stops every event of its feature`
- `a critical event touched by a stale always-loaded file stops every event`
- `a critical site that first runs after the report still widens the stop`
- `an empty stale set stops nothing`
- `client-only events are never stopped`
- `a stale file's touch lists game and system events apart, and never stops a system or recovery event`
- `a stop lifts when its file matches again`

`tests/events_scan_test.lua` (fixture strings, not the tree):
- `strings and comments that look like calls are not calls`
- `a Fire with a non-literal name is reported`
- `fields that are not a table literal are reported`
- `a second Fire site for one name is reported`
- `a listener reading a field its site does not send is reported`
- `return Events.Fire( and return Events.Listen( are reported`
- `a Listen with a non-literal name or a listener that is not a function literal is reported`
- `options other than a table literal of to, unreliable and critical are reported`
- `an alias of WS.Events other than local Events is reported`
- `a Fire site with no comment directly above it, or a field line with no trailing comment, is reported`
- `an Accept with no Fire site is reported`
- `two names with one id are reported`
- `Events.Game.Fire and Events.System.Fire sites record their kind`
- `a Listen or Accept of another kind than its event's site is reported`
- `a RecoveryFire outside protocol.lua is reported`
- `Events.Recovery.Listen is a listen of a recovery event; Events.Recovery.Fire is reported`

`tests/events_sites_test.lua` (the whole of `addons/sandcastle/`, minus the ratchet's
files):
- `every event has exactly one literal Fire site`
- `every listener reads only fields its event's site sends`
- `no Fire or Listen is tail-called`
- `no two event names share an id` (over Fire, Listen, Accept and the
  remaining `Define` names)
- `every Fire's options are a table literal of to, unreliable and critical`
  (ratchet ignored: A converts every call)
- `no file is exempt from the site rules except those the migration lists`
  (each ratchet entry exists and still breaks a rule)

**Added by the design change.** Write these first and watch them fail, like
the rest.

`tests/events_kinds_test.lua`:
- `a game event takes to, unreliable and critical; a system event refuses critical; a recovery event takes only to`
- `one name used as two kinds raises bad_kind, naming both`
- `a recovery event fired from any file but protocol.lua raises bad_kind`
- `a client's recovery events are accepted without Accept, at their own rates, and never listed`
- `system and recovery events are never stoppable, and SystemEvent.MAJOR is the major`

`tests/events_listeners_test.lua`:
- `listeners run in order, each isolated: one that raises does not stop the next`
- `a resync runs the always-loaded listeners and those of the features it names, in the order added`

`tests/events_handshake_test.lua`:
- `client_ready leaves at Loaded with the client's major, and the client is ready only after the latest epoch's resync_end`
- `events fired while joining are held up to HELD_MAX, and the overflow is logged once and stays local`

`tests/events_pacer_test.lua`:
- `under the per-tick budget everything goes now`
- `over it the rest goes in later ticks, in order, and later messages queue behind`
- `a backlog over READY_BURST_MAX_BYTES is reported once per resync`

`tests/events_failures_test.lua`:
- `every failure state has a part, a report line, a recovered line and the recovery event that answers it` (over all 8 parts)
- `a failure is reported once while open, however often it is detected`
- `retries stop after the part's tries with one give-up line, and a later answer still closes it`

`tests/events_recovery_test.lua` (over `tests/fake_link.lua`; one test or
two per row of "Failure states and recovery"):
- `a joining client is brought up to date by the ready resync, and the events it fired while joining leave once accepted`
- `a lost handshake is retried until the server answers, and reported once after the last try`
- `a client on another major is logged and disconnected with a message to update, before any handshake`
- `a stale included file recovers when a gamemode refresh reruns it on both realms, and the client hears code_current` (stage 3)
- `a stale compiled file stays stale for its player until that player reconnects; a player who joins after it is restored is not stale` (stage 3)
- `a refused client event is answered with event_refused, and the client's resync brings its feature back to the server's state`
- `a client whose accepted list is out of date gets it again on not_accepted`
- `a message the client cannot decode is logged as our bug once, and its feature's resync clears it`
- `a listener that raises is logged with its traceback, the other listeners and the send still happen, and its next clean run reports it recovered`
- `a burst over the per-tick budget goes out over later ticks in order, logged once, and its resync ends after its last event`
- `apart from major_mismatch's disconnect, nothing a failure state does stops an event or disconnects a client`

`tests/network_notice_test.lua` (the view, with GMod's chat and sound
calls faked as `tests/events_adapter_test.lua` fakes `net`):
- `a chat failure plays ui/system_message_alert.wav and its recovery ui/message_update.wav; a console-only one plays nothing`
- `a stale file only a reconnect cures adds the hint reconnect to update`

`tests/events_adapter_test.lua` adds:
- `WS.Events has Game and System facades with Fire, Listen, Ignore and Accept, and Recovery with Listen only`
- `until phase C, Events.Fire, Listen, Ignore and Accept are Events.Game's`
- `the adapter fires no event itself: every recovery event comes from protocol.lua`
- `a gamemode refresh keeps the Library and re-binds its ports`

**Two committed tests are reworded** in `tests/events_test.lua` (04bc088),
so the count stays:
- `a malformed message from the server is raised as our bug` becomes
  `a malformed message from the server is logged as our bug once and opens decode_failed`;
- `a player sent over READY_BURST_MAX_BYTES in one tick is logged once as ready_burst`
  becomes `a burst over the budget is paced and logged once as ready_burst`.

`tests/events_paths_test.lua` keeps its names, re-pointed at `FileKey`.

`.devtools/bin/test_gmod_client.py` (pytest). The process table, the `lsof`
output, the launcher, the clock and the signal call are injected, so no test
starts or signals a real process:
- `test_refuses_while_tf2_runs` (any `tf_win64.exe`, `tf.exe` or `hl2.exe`,
  in any bottle)
- `test_refuses_while_a_gmod_client_runs` (`gmod.exe` or `gmod_win64.exe`)
- `test_refuses_without_steam_running_in_the_tf2_bottle`
- `test_refuses_while_its_own_client_still_runs`
- `test_has_no_way_to_choose_another_bottle`
- `test_launches_only_the_gmod_client`: exactly one launch, of
  `gmod_win64.exe` through the bottle's wine with
  `--bottle "Team Fortress 2"`, `+connect 127.0.0.1:<port>` and
  `+con_logfile` under `data/ws_tests/client/`, and never `-condebug`
- `test_records_the_one_new_client_pid`
- `test_stop_signals_only_the_launched_client`: with a wineserver, wine's
  services, `steam.exe`, `steamwebhelper.exe`, a `tf_win64.exe`, the wine
  launcher and a second `gmod_win64.exe` in the table, only the recorded PID
  is signalled
- `test_stop_leaves_a_reused_pid_alone`
- `test_stop_escalates_to_sigkill_on_the_same_pid_only`
- `test_the_watchdog_closes_the_client_when_the_operators_game_starts`
- `test_the_watchdog_closes_the_client_at_its_time_limit`
- `test_stop_reports_changed_cfg_files`

`.devtools/bin/test_gev2_marker.py`:
- `test_refuses_a_file_with_uncommitted_changes`
- `test_refuses_a_file_outside_addon`
- `test_refuses_a_second_set_before_restore`
- `test_restore_puts_back_the_exact_bytes`
- `test_restore_after_a_failed_run_leaves_the_file_clean`

`.devtools/bin/test_srcds.py` adds:
- `test_no_lua_refresh_adds_disableluarefresh`

### A.6 Acceptance criteria

1. The per-commit checks pass on every commit (`check_totals.sh main` exit
   0), and the final TOTAL is at least 1357 + the tests A adds.
2. Every test named in A.5 exists and passes:
   `grep -hoE 'T\.test\("[^"]+"' tests/events_*_test.lua` contains each one.
3. Purity: the grep under "Code style" prints nothing for
   `foundation/events.lua`, `foundation/events/*.lua` and
   `foundation/events/*/*.lua`. Each starts with `module(...)` after its
   locals, and each is a class:
   `grep -L '__index = ' addons/sandcastle/gamemodes/sandcastle/gamemode/foundation/events.lua addons/sandcastle/gamemodes/sandcastle/gamemode/foundation/events/*.lua addons/sandcastle/gamemodes/sandcastle/gamemode/foundation/events/*/*.lua`
   prints nothing.
4. `grep -rnE '\.Request\(' addon --include='*.lua'` prints nothing.
5. `grep -c 'local Registry' addons/sandcastle/gamemodes/sandcastle/gamemode/foundation/events.lua`
   prints 0: the v1 core is gone.
6. `grep -n 'include("shared.lua")' addons/sandcastle/gamemodes/sandcastle/gamemode/init.lua`
   is line 1 or the first non-comment line, and comes above both
   `AddCSLuaFile` lines.
7. No convar, and nothing stops (operator decision 3):
   - `grep -rn 'ws_events_check' addon tests .devtools/bin` prints
     nothing (0 at 29a6070);
   - `git diff --quiet main -- addons/sandcastle/cfg/sandcastle_defaults.cfg` exits 0,
     and `luajit tests/cfg_defaults_test.lua` passes, because A adds no
     convar;
   - `grep -rn ':Blocks(' addon --include='*.lua' | grep -v 'foundation/events/stops.lua'`
     prints nothing;
   - `grep -rn 'code_stopped' addon tests` prints nothing.
8. The ratchet: `luajit -e 'local u = dofile("tests/events_unmigrated.lua"); print(#u.b1, #u.b2)'`
   prints the B1 and B2 file counts of §B. Every file in it breaks a rule
   (that is the last sites test).
9. **Live probes** (srcds on koth_viaduct, then
   `python3 .devtools/bin/gev2_probe.py run events_size events_sent events_scan_cost`;
   outputs land in `.devtools/artifacts/gev2-research/live/`):
   - `events_size.txt`: for at least 20 events (every tag, one event at the
     cap and one a byte over), `Codec.Bytes(plan)` equals
     `net.BytesWritten()` after `Codec.Write`. The file ends
     `mismatches 0`, and the over-cap case reports `too_large` before any
     write.
   - `events_sent.txt`: the wrapper's keys. Then
     `diff <(.devtools/bin/expected_sent_files.sh) <(sed -n '/^keys$/,$p' .devtools/artifacts/gev2-research/live/events_sent.txt | tail -n +2)`
     prints nothing. That's 191 at 38eb752, plus A's new `foundation/`
     files.
   - `events_scan_cost.txt`:
     - the cost of `file.Time` over every sent key (total and per file);
     - whether `file.Time` changed after `touch` on a data-folder copy;
     - the scanner's worst tick over 600 ticks, which must be at most
       1.0 ms;
     - the `SCREEN_BY_TIME` and `FILES_PER_TICK` chosen.
10. **Post-merge smoke:**
    `python3 .devtools/bin/ingame_tests.py --maps koth_viaduct` exits 0, and
    the report shows 0 Lua errors. The server's log has no `network error:`
    line, because no client joins.
11. The drift work starts only after T1 and T2 are recorded (item 14).
    That is A.4's detection: `drift.lua`, the wrapper, the scanner and the
    triggers.
    - If T1 fails, the architect re-plans A.4 with the operator before any
      of it is written (§3).
    - Only the detection waits. The stop rules, codec, rates and paths
      don't.
12. `sv_allowcslua` is ignored (operator decision 1):
    `grep -rn 'allowcslua' addon --include='*.lua'` prints nothing (0 at
    29a6070). No test asserts a report, because none is made.
13. The client tools pass their tests:
    `cd .devtools/bin && python3 -m pytest -q test_gmod_client.py test_gev2_marker.py test_srcds.py`
    passes. `grep -hoE 'def test_[a-z0-9_]+' test_gmod_client.py test_gev2_marker.py test_srcds.py`
    contains every name A.5 gives for them.
14. **The early client session** (§3: T1, T2 and T4), unattended:
    - the research file gains `## Client session` with each test's result,
      and the outputs are under `.devtools/artifacts/gev2-research/client/`;
    - `.devtools/artifacts/gev2-research/client/gmod_client.log` shows, for
      each launch, the preflight's findings, the one PID launched, and that
      PID (and only it) being closed;
    - after the session, no `gmod_win64.exe` runs
      (`ps -axo command= | grep -c '[g]mod_win64.exe'` prints 0), and
      `git status --short` on main is what it was before (the markers are
      restored);
    - `Drift.New`'s default `served` is the value T2 chose, with a comment
      citing the research section;
    - `tests/events_paths_test.lua` has T4's client form as a case, if it
      differs from the three forms.
15. **T3, after the merge:**
    1. start the server with `srcds.py start --map koth_viaduct`, and the
       client with `gmod_client.py start`;
    2. `python3 .devtools/bin/gev2_probe.py run --client client_t3` writes
       `client/client_t3.txt`, which ends `mismatches 0` for both
       directions;
    3. the client's log has 0 Lua errors (the command in E.3 item 4);
       `client_t3.txt` also has the line `handshake ready major 1` (the
       probe reads `WS.EventLibrary`);
    4. `gmod_client.py stop`, then `srcds.py stop`.
16. **The kinds and the failure states are classes and parts:**
    - `ls addons/sandcastle/gamemodes/sandcastle/gamemode/foundation/events/event/`
      prints `game.lua`, `recovery.lua` and `system.lua`;
    - `ls addons/sandcastle/gamemodes/sandcastle/gamemode/foundation/events/failure/`
      prints exactly the 8 states' files;
    - `grep -n '^MAJOR = 1' addons/sandcastle/gamemodes/sandcastle/gamemode/foundation/events/event/system.lua`
      prints one line.
17. **Only the protocol fires recovery events:**
    - `grep -rlE 'RecoveryFire\(' addon --include='*.lua'` prints only
      `foundation/events/protocol.lua`;
    - `grep -cE 'Events\.(Game\.|System\.)?Fire\(' addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sh_events.lua addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sh_events_ports.lua`
      prints `0` for both.
18. **One composition root:**
    `grep -rn 'Events\.New(' addon --include='*.lua'` prints one line, in
    `ws/sh_events.lua`.
19. **`Peers` replaced the player field:**
    `grep -rn 'wsReady' addon --include='*.lua'` prints nothing.
20. **Recovery works in the fakes:** `luajit tests/events_recovery_test.lua`
    passes, and its `T.test` names include every name A.5 lists for it. The
    two stage-3 names land with detection.
21. **Nothing stops, with one exception** (decision 3, and P3): the
    recovery test
    `apart from major_mismatch's disconnect, nothing a failure state does stops an event or disconnects a client`
    passes, and so does item 7. `grep -rn ':Kick(' addon --include='*.lua'`
    prints one line, in `GModRoster:Disconnect`, and
    `grep -rln 'Disconnect(' addons/sandcastle/gamemodes/sandcastle/gamemode/foundation`
    prints only `foundation/events/failure/major_mismatch.lua`.
22. **The scanner knows the kinds:** `luajit tests/events_scan_test.lua`
    passes with the four names this revision adds to it.
23. **The notice view** (P1): `luajit tests/network_notice_test.lua` passes
    with its two names, and
    `grep -c 'NOTICE_SOUND_' addons/sandcastle/gamemodes/sandcastle/gamemode/ws/cl_network_notice.lua`
    is at least 2.

---

## Phase B: migrating each feature

**Goal.**

- Every event has its one literal `Fire` site, with its comment block and
  trailing field comments.
- No `E.Define` remains.
- The boss forwarder is gone.
- Every `Listen` is literal.
- The ratchet is empty.

**Two programmers may run at once, on disjoint files** (the two-agent limit;
the writer does not start in B). Each B programmer works in its own
worktree off main after A merges. The director merges B1 and B2 one after
the other, and the architect evaluates B once both are in.

**What changed (event classes, 2026-10-08).**

- **Each site moves to its kind's facade** by decision (d). B1 holds all five
  of today's system events: `teamplay_broadcast_audio`, `feature_load`,
  `teamplay_point_captured`, `teamplay_capture_blocked` and
  `teamplay_timer_time_added`. Everything else becomes `Events.Game`,
  including the 12 boss events and `npc_ragdoll_create` (P4). Listeners and
  accepts move with their event.
- **`sh_core.lua`'s `client_ready` listener becomes the first `resync`
  provider** (`Events.Recovery.Listen("resync", "ws_feature_load", ...)`).
  It fires `feature_load` to the player being brought up to date. Its
  `Fire` site, `FeatureFiles:TellClients`, is a system site.
- **Criteria:** items 9 to 11 are new; items 1 to 8 are unchanged.

### B.1 Scope

**B1: always-loaded, rounds, capture and gamemode** (9 events).

| Files | Events | What changes |
|---|---|---|
| `ws/sh_core.lua` | `feature_load` | Its two sites (`:55`, `:82`) become one function holding the site, `FeatureFiles:TellClients(names, to)` |
| `ws/sh_announcer.lua`, `ws/sv_world.lua` | `teamplay_broadcast_audio`, `announcement` | `BroadcastSound` and `BroadcastSoundToOthers` call one local function holding the single site; the two `Define`s go |
| `ws/sh_gameplay.lua`, `features/gamemode/sv.lua` | `gameplay_chat`, `gameplay_transition_cancelled` | `Define`s go; sites documented |
| `features/capture/{sh,sv,cl}.lua` | `teamplay_point_captured`, `teamplay_capture_blocked` | same |
| `features/rounds/{sh,sv,cl}.lua` | `teamplay_timer_time_added` | same |
| `ws/{sh,sv,cl}_npc_ragdolls.lua` | `npc_ragdoll_create` | same |

**B2: the npc feature and the debug overlays** (20 events).

| Files | Events | What changes |
|---|---|---|
| `foundation/npc/halloween_boss.lua` (`METHODS`), `foundation/npc/{merasmus,eyeball_boss,headless_hatman}.lua`, `entities/entities/halloween_base_boss.lua`, `features/npc/{sh,sv,cl}.lua`, `foundation/npc/boss_events.lua` | the 12 boss events | See "The boss port" below. |
| `features/nbdebug/{sh,sv,cl}.lua`, `features/aiwar/sv.lua` (the `aiwar_debug` site only) | 6 `nb_debug_*`, `aiwar_debug` | `Define`s go; sites documented; `Optional` fields simply left out when absent |
| `ws/sh_nodegraph.lua`, `features/nodegraph/sv.lua` | `nodegraph_debug` | same |
| `tests/{merasmus,eyeball_boss,headless_hatman,halloween_boss,boss_events,nbdebug_contract}_test.lua` and the fakes they use | | Updated to the new port, with per-file counts kept (B.3) |

**The boss port (a technical call; see the end of this plan).**

- **The port.** `METHODS` loses `"FireGameEvent"` and gains one method per
  event:
  - `PumpkinLordSummoned()`, `PumpkinLordKilled()`;
  - `EyeballBossSummoned(level)`, `EyeballBossKilled(level)`,
    `EyeballBossEscapeImminent(level, seconds)`,
    `EyeballBossEscaped(level)`;
  - `MerasmusSummoned(level)`, `MerasmusKilled(level)`,
    `MerasmusEscapeWarning(level, seconds)`, `MerasmusEscaped(level)`,
    `MerasmusKiller(player, level)`;
  - `HalloweenBombHead(player, duration)`, which is called from both bomb
    head sites and so keeps one `Fire` site.
- **The binding.** `halloween_base_boss.lua` implements each method by
  calling the npc controller (`WS.Feature("npc"):<Method>(...)`).
- **The sites.** `features/npc/sv.lua` holds each literal `Fire` site, so
  the events belong to the `npc` feature, beside the view that hears them.
- **The view.** `features/npc/cl.lua` drops the loop over `BossEvents.NAMES`
  for 11 literal `Listen`s (plus the bomb head's). Each passes its literal
  name to `View:PlayBossCue`.
- **The names list.** `BossEvents.NAMES` goes if nothing else uses it;
  `Cue` keeps its name-keyed table.

### B.2 Tests to write first

- **B2, the bosses.** Change the boss model tests to expect the new port
  calls (for example, Merasmus's summon calls `MerasmusSummoned(level)`
  once), and watch them fail before changing the models.
- **B2, the contract test.**
  `tests/nbdebug_contract_test.lua`'s test
  `every game event they fire is defined in the feature's shared part, for both realms`
  becomes `every game event they fire has its one literal site in the controllers`.
  The count stays at 4.
- **B2, the port test.** `tests/halloween_boss_test.lua`'s port test is
  updated for the new `METHODS`, and checks that no port method shares a
  name with an engine method on the wiki's lists.
- **Both programmers.** For each file taken off the ratchet, run
  `luajit tests/events_sites_test.lua` first and see it fail on that file.
- **B1, the resync provider.** `tests/events_adapter_test.lua` adds
  `the ready resync fires feature_load with every client feature, first`,
  written first and seen failing.

### B.3 Acceptance criteria

1. The per-commit checks pass on every commit of B1 and of B2.
2. `grep -rnE '\.Define\(' addon --include='*.lua' | grep -v 'ws/sh_events.lua'`
   prints nothing.
3. `grep -rnE '[^:]:FireGameEvent\(|[.:]FireGameEvent *=|function [A-Za-z_.:]*FireGameEvent|"FireGameEvent"' addon tests`
   prints nothing. Only comments citing TF2's `::FireGameEvent` remain.
4. `luajit -e 'local u = dofile("tests/events_unmigrated.lua"); print(#u.b1 + #u.b2)'`
   prints `0`.
5. `luajit tests/events_sites_test.lua` passes, now over every file.
6. Per-file test counts are at least the baseline:
   - merasmus 45, eyeball_boss 44, headless_hatman 25, halloween_boss 17,
     boss_events 12, nbdebug_contract 4;
   - capture_points 43, rounds_game 28, gameplay 3, gamemode 20,
     npc_ragdoll 7, nodegraph 8.

   Command:
   `for t in merasmus eyeball_boss headless_hatman halloween_boss boss_events nbdebug_contract capture_points rounds_game gameplay gamemode npc_ragdoll nodegraph; do printf "$t "; luajit tests/${t}_test.lua | tail -1; done`.
7. `grep -rn 'BossEvents.NAMES' addon --include='*.lua'` prints nothing.
8. Post-merge smoke:
   - B1: `python3 .devtools/bin/ingame_tests.py --maps koth_viaduct,cp_dustbowl`
     exits 0, with 0 Lua errors.
   - B2: the same over the Halloween maps whose `bosses` step covers all
     three boss classes. To list them:
     `cd .devtools/bin && python3 -c "import ingame_tests as t; [print(r.map, [s.args for s in r.steps if s.check == 'bosses']) for r in t.full_plan()]"`
     (it reads the BSPs, read-only). The run exits 0 with 0 Lua errors.
9. Every site names its kind:
   `grep -rnE 'Events\.(Fire|Listen|Ignore|Accept)\(' addon --include='*.lua' | grep -v 'ws/sh_events.lua'`
   prints nothing.
10. The system sites are decision (d)'s:
    `grep -rhoE 'Events\.System\.Fire\("[a-z_]+"' addon --include='*.lua' | sort`
    prints exactly the five, for `feature_load`, `teamplay_broadcast_audio`,
    `teamplay_capture_blocked`, `teamplay_point_captured` and
    `teamplay_timer_time_added`.
11. `client_ready` belongs to the library:
    `grep -rn '"client_ready"' addon --include='*.lua'` prints only lines
    of `foundation/events/protocol.lua` and `foundation/events/handshake.lua`.

---

## Phase C: removing `Define`, and the events file

**Goal.** Remove what the migration needed, and build what the spec's §5
describes.

- **Removed:** the `Define` and type-constructor shims, and the ratchet.
- **Built:**
  - the generated `resource/sandcastle_events.res`;
  - its generator `.devtools/bin/gen_events_res.lua`;
  - the pre-commit hook `.devtools/bin/hooks/pre-commit`;
  - the staleness test;
  - the `ws_events_print` / `ws_events_print_cl` commands.

This reads the handoff's "(C) removing `Define`, the generator and
pre-commit hook" with the spec: none of the three exists at 38eb752, and
the spec builds them. The operator confirmed it: build all three
(decision 4).

**One programmer.** The writer may start drafting once C lands.

**What changed (event classes, 2026-10-08).**

- **Also removed:** the aliases `Events.Fire`, `Listen`, `Ignore` and
  `Accept`. Once they are gone, the scanner reports a bare call of any of
  them.
- **The events file names each event's kind.** It is grouped as system,
  then game, then recovery, sorted by name within each group, and its
  header gives the system major.
- **The freeze:** `tests/events_system_frozen.lua` (major 1, with each system
  event and its field keys) and `tests/events_system_test.lua` (decision
  (a)).
- **The print commands also list the open failure states** (per player on
  the server) and how many times each state has opened and closed.
- **Criteria:** items 11 to 15 are new, and C.2's report test is reworded.

### C.1 Scope

- **`ws/sh_events.lua`:** remove `API.Define`, the constructor names,
  and any v1 leftovers.
- **`tests/events_unmigrated.lua`:** deleted. `tests/events_sites_test.lua`
  loses its exemption parameter. The ratchet test becomes
  `no file is exempt from the site rules`, so the count stays.
- **`.devtools/bin/events_scan.lua`** is extended to capture, for each
  event:
  - its site's comment block, `file:line` and id;
  - each field with its trailing comment;
  - its `Listen` sites.
- **`.devtools/bin/gen_events_res.lua [--check]`:** writes
  `addons/sandcastle/gamemodes/sandcastle/resource/sandcastle_events.res` in §5's format,
  with events sorted by name. `--check` exits 1 if the file differs.
- **`.devtools/bin/hooks/pre-commit`:** when a staged `.lua` file contains
  `Events.Fire(`, `Events.Listen(` or `Events.Accept(`, it runs the
  generator and stages the file. It must not commit or sign, so the gpg
  rules are unaffected.
  - Enabling it is the operator's one-time step:
    `git config core.hooksPath .devtools/bin/hooks`. The programmer doesn't
    change git config.
  - If `.git/hooks` holds an active hook, the report says so, because
    `core.hooksPath` would bypass it.
- **`tests/events_res_test.lua`:** fails when the committed file differs
  from the generator's output (it shares the scanner, without running a
  subprocess).
- **The print commands (pure part).** A formatter in
  `foundation/events.lua`, `Library:Report()`, lists each event:
  - its listeners (id and key);
  - whether it is accepted, and its rate;
  - its fire count;
  - the tags observed per field on the wire;
  - the stale keys.
- **The print commands (adapter part).** The adapter registers
  `ws_events_print` (server; admins only, or the console) and
  `ws_events_print_cl` (client). Both print, and never write the
  repository.
- **`critical` stays, unused** (decision 3). The option is still
  validated and recorded in `Sites()`, and `Touch:Blocks` keeps its
  critical branches and their tests, but no `Fire` site passes it. Nothing
  is removed for report only: A built no stopping into the adapter.
- **The aliases go** (the design change). `ws/sh_events.lua` loses
  `Events.Fire`, `Listen`, `Ignore` and `Accept`, and
  `.devtools/bin/events_scan.lua` reports a bare call of any of them.
- **The kinds in the events file.** Each entry gains a `"kind"` line, and
  the header comment gives `system events: major 1`.
- **The freeze.** `tests/events_system_frozen.lua` returns
  `{ major = 1, events = { [name] = { field keys, sorted } } }` for B's five
  system events. `tests/events_system_test.lua` scans
  the tree and fails when the system sites' names or field keys differ from
  the fixture while `SystemEvent.MAJOR` equals the fixture's major. It also
  fails when the major is higher than the fixture's, until the fixture is
  refrozen.
- **Failures in the report.** `Library:Report()` also lists the open failure
  states (per player on the server) and the counts of each state opened and
  closed.

### C.2 Tests to write first

- `tests/events_res_test.lua`:
  - `the committed events file is what the Fire sites generate`
  - `an edited comment above a Fire site changes the generated file`
    (on a fixture)
- `tests/events_scan_test.lua` adds:
  - `a site's comment block and its fields' trailing comments are captured`
  - `the generated entry lists fired file:line, the id in hex, and each heard file`
- `tests/events_test.lua` adds:
  - `the report lists listeners, accepts, fire counts, observed tags, stale files and open failure states`
- `tests/events_system_test.lua`:
  - `every system event's fields are the ones frozen at this major`
  - `the frozen set names only events with a System site`
- `tests/events_scan_test.lua` also adds:
  - `a change to a system event's fields without a new major fails the freeze` (on a fixture)
  - `a bare Events.Fire, Listen, Ignore or Accept is reported`
- `tests/events_res_test.lua` also adds:
  - `each entry names its kind, and the header gives the system major`

### C.3 Acceptance criteria

1. The per-commit checks pass on every commit.
2. `grep -rnE '\bDefine\b|\bUInt\b|\bOptional\b|\bRecord\b' addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sh_events.lua`
   prints nothing, and `grep -rn '\.Define(' addon --include='*.lua'`
   prints nothing.
3. `test ! -e tests/events_unmigrated.lua && ! grep -rn 'unmigrated' tests .devtools/bin`
   succeeds.
4. `luajit .devtools/bin/gen_events_res.lua --check` exits 0, and the file
   starts with
   `// GENERATED by .devtools/bin/gen_events_res.lua from each Events.Fire; do not edit.`
5. The number of events in the file equals the number of distinct `Fire`
   names the scan reports (both printed by `gen_events_res.lua --count`).
6. The staleness test bites. In a scratch export (`git archive HEAD | tar -x -C <scratch>`):
   1. append a line to the `.res`;
   2. `luajit tests/events_res_test.lua` exits nonzero;
   3. restore the file, and it exits 0.
7. The hook works. In a scratch clone with `core.hooksPath` set:
   1. edit the comment above one `Fire` site;
   2. `git add` the file;
   3. commit with `git -c gpg.program=gpg-loopback commit -m test`;
   4. `git show --stat HEAD` lists the `.res`.
8. `.devtools/bin/check_engine_names.sh ws_events_print ws_events_print_cl`
   prints `free` for both.
9. Post-merge smoke: `ingame_tests.py --maps koth_viaduct` exits 0. Then
   `srcds.py start --map koth_viaduct` and
   `srcds.py rcon ws_events_print` prints `client_ready`,
   `events_accepted`, `feature_load` and `teamplay_point_captured` with
   their sites.
10. `critical` is built but unused (decision 3):
    `grep -rnE 'critical *= *true' addon --include='*.lua'` prints nothing
    (0 at 29a6070), and `luajit tests/events_stops_test.lua` still passes
    its critical tests.
11. The aliases are gone:
    `grep -rnE 'Events\.(Fire|Listen|Ignore|Accept)\(' addon --include='*.lua'`
    prints nothing, and
    `grep -nE 'Events\.(Fire|Listen|Ignore|Accept) *=' addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sh_events.lua`
    prints nothing.
12. `luajit tests/events_system_test.lua` passes, and
    `tests/events_system_frozen.lua` lists major 1 with B's five system
    events.
13. The freeze bites. In a scratch export
    (`git archive HEAD | tar -x -C <scratch>`):
    1. add a field to `teamplay_broadcast_audio`'s site;
    2. `luajit tests/events_system_test.lua` exits nonzero, naming the event
       and the field;
    3. bump `MAJOR` to 2: it still exits nonzero, until the fixture is
       refrozen at 2;
    4. restore both files, and it exits 0.
14. The kinds are in the events file:
    `grep -c '"kind"' addons/sandcastle/gamemodes/sandcastle/resource/sandcastle_events.res`
    equals the event count that `gen_events_res.lua --count` prints, and
    the file has the line `// system events: major 1`.
15. After the post-merge smoke (item 9), `srcds.py rcon ws_events_print`
    also prints `failures open 0`; no player has joined.

---

## Phase D: presentation moved to client listeners

**Goal.** Where the server picks an announcer line or builds gameplay text
from state that a fact event can carry, fire the fact on its TF2-named event
and let the client listener pick and play.

- **Lines that stay on `teamplay_broadcast_audio`:** those named by map
  data, or chosen by a model's own pick. TF2 broadcasts those from the
  server too.
- **Text that stays:** admin-command replies.

**One programmer, plus the writer drafting** (that's two agents).

**What changed (event classes, 2026-10-08).**

- `teamplay_round_win` and `teamplay_suddendeath_begin` are new **system**
  events (decision (d)). Their client listeners, which pick the announcer
  lines, are `Events.System.Listen`, as are those of
  `teamplay_timer_time_added` and `teamplay_point_captured`.
- `teamplay_alert` and `teamplay_teambalanced_player` are system events too
  (the operator's answer P4).
- D's other new events are game events: `gameplay_transition_started`,
  `gameplay_requested`, `gameplay_sandbox_entered`, and the tag events,
  which are Halloween-specific (the operator's answer). So is the team-full
  notice (`ws/sv_teams.lua:108`), which goes to one player, not to
  everyone.
- **`teamplay_broadcast_audio` is split** (P4's rule, decision (d)). Its
  Halloween lines (the fortune teller's broadcast, the Wheel of Fate's
  lines, and Merasmus's) move to a new game event,
  `holiday_broadcast_audio { team, sound, others }`, with the same client
  hearing rule. It has one site, `WS.BroadcastHolidaySound(team, sound)`
  in `ws/sv_world.lua`, and its listener sits beside the announcer's in
  `ws/sh_announcer.lua`. `teamplay_broadcast_audio` keeps only the
  gamemode's announcer: the overtime nag, the map's `PlayVO*` inputs, the
  capture model's "others" line, the admin's transition line and the cart
  warning.
- D adds its new system events to `tests/events_system_frozen.lua` within
  major 1. No release has shipped, so there is no bump (decision (a)).
- **Criteria:** item 2 changes for the split, and items 10 to 12 are new.

### D.1 Scope: the 19 `BroadcastSound` calls

| Site | Line or rule | Decision | Event the client listens to |
|---|---|---|---|
| `features/rounds/sv.lua:193,196,197` (`PlayWinSong`) | stalemate; each side's win or loss | **Move** | `teamplay_round_win` (TF2's: `team`, `winreason`, `full_round`, ...) |
| `features/rounds/sv.lua:762` (`RoundWinLines`) | the mode's win lines | **Move** | `teamplay_round_win`, plus the fields `RoundWinLines` reads (for example `multiple_trains`) |
| `features/rounds/sv.lua:203,204,206` (`AnnounceTimeAdded`) | the credited team's lines | **Move** | `teamplay_timer_time_added` (exists) |
| `features/rounds/sv.lua:767` | sudden death | **Move** | `teamplay_suddendeath_begin` |
| `features/rounds/sv.lua:665` (`CapSounds`) | `PlaySpecialCapSounds` | **Move** | `teamplay_point_captured`, plus the fields the mode's `CapSounds` reads |
| `features/rounds/sv.lua:330` | the overtime nag | Stay | (TF2 broadcasts it) |
| `features/rounds/sv.lua:927` (`VoiceTo`) | the map's `PlayVO*` inputs | Stay | (the map names the sound) |
| `features/capture/sv.lua:330` | the capture model's "others" line | Stay | (already a client-side hearing rule) |
| `features/holiday/sv.lua:169` | the fortune's broadcast | **To `holiday_broadcast_audio`** (game) | (the model's pick; Halloween) |
| `features/gamemode/sv.lua:57` | the admin's transition line | Stay | (an admin command; its cancel needs the server's record) |
| `features/wheel/sv.lua:106,114` | the Wheel's lines | **To `holiday_broadcast_audio`** (game) | (the model's pick; Halloween) |
| `entities/entities/merasmus.lua:140,147` | Merasmus's lines | **To `holiday_broadcast_audio`** (game) | (the model's pick; Halloween) |
| `entities/entities/team_train_watcher.lua:342` | the cart warning | Stay | (TF2 broadcasts it; no TF2 event) |

**Gameplay text (6 of 23 `ChatPrint`/`PrintMessage` sites).**

| Site | Decision | Event |
|---|---|---|
| `ws/sv_teams.lua:137` | Move | `teamplay_alert` (TF2's `alert_type`) |
| `ws/sv_teams.lua:155` | Move | `teamplay_teambalanced_player` (TF2's `player`, `team`) |
| `ws/sv_teams.lua:108` | Move | TF2's event if `modevents.res` has one, else Sandcastle's own, `to = ply` |
| `features/tag/sv.lua:29,30,31` | Move | TF2's tag events where `modevents.res` has them, else Sandcastle's own. The notice text is built on the client from shared `foundation` constants. |

The other 17 text sites stay: admin replies, console reports, the editor
tool, and `npc/cl.lua:84`, which is already client-side.

**Announcements and gameplay chat (operator decision 5).** Today the
server builds this text and fires it as text:

- `announcement { text, team }`, through `WS.Announce`
  (`ws/sv_world.lua:117`);
- `gameplay_chat { title, lines }`, from one site
  (`features/gamemode/sv.lua:72`).

Both events are retired. The server fires facts on Sandcastle's own events
(TF2 has none for these), and client listeners build the same text. The
lines are at 29a6070.

| Site | Text today | After |
|---|---|---|
| `features/gamemode/sv.lua:109` (`OpenTransition`) | `gameplay_chat`: `Gameplay.Describe(MapInfo())`, plus "Gameplay mode begins in N seconds; then choose a team." | `gameplay_transition_started { map, trains, race, points, rounds, flags, seconds }`. The listener in `ws/sh_gameplay.lua`'s client block calls `Gameplay.Describe` and adds the line. |
| `features/gamemode/sv.lua:133` (`NOTICE_REQUEST_CHAT`) and `:134` (`NOTICE_REQUEST_ANNOUNCEMENT`) | the AI war's `Story()` (`features/aiwar/sv.lua:2001`): a chat title and lines, or an announcement | `story` becomes facts (`{ size }`; the factions follow from the teams), and one site fires `gameplay_requested { source, notice, story }`. A pure function in `foundation/` (for example a new `foundation/aiwar/story.lua`) builds the text. It is called by the chat listener (`ws/sh_gameplay.lua`) and by the announcement listener (`features/rounds/cl.lua`, beside `View:Announce`). |
| `features/gamemode/sv.lua:136` (`NOTICE_CALLED_OFF`) | `gameplay_chat`: "Game called off. Carry on." | The existing `gameplay_transition_cancelled` listener adds the line. |
| `features/gamemode/sv.lua:141` (`NOTICE_SANDBOX`) | `WS.Announce("Gameplay mode has ended. Sandbox mode until a new game begins.")` | `gameplay_sandbox_entered {}`, announced by its listener in `features/rounds/cl.lua` |
| `ws/sv_world.lua:117` (`WS.Announce`), and `announcement` in `ws/sh_announcer.lua` and `features/rounds/cl.lua` | | Removed. The client's `View:Announce` stays, and `features/capture/cl.lua:266` keeps calling it. |

- The admin replies (`Tell`, `NOTICE_REFUSED` and `NOTICE_DENIED`) stay
  server-side text, like every other admin reply.
- The sounds beside these notices (`PlayToAll`) are the admin's transition
  lines, which stay (the `features/gamemode/sv.lua:57` row above).
- B1 documents the `gameplay_chat` and `announcement` sites first, and D
  then retires them.

**How a move is done:**

- The rule that picks the line moves into (or already is) a pure
  `foundation/` function, which both the old server path and the new
  client listener can be tested against.
- The listener lives in the feature's `cl.lua` (`features/rounds/cl.lua`,
  `features/capture/cl.lua`), in `ws/cl_teams.lua` for team text, or
  in `ws/sh_gameplay.lua`'s client block for gameplay chat.
- New events get their one literal site with comments, and pass the site
  rules.
- After a move, the server sends no `teamplay_broadcast_audio` for that
  line.

### D.2 Tests to write first

- **The equivalence table.** For each moved rule, a test that the client's
  pick for every (local team, event fields) equals what the server's
  `BroadcastSound(team, line)` plus `foundation.teams.HearsBroadcast` would
  have delivered. Examples:
  - `each side hears its own result, and a stalemate everyone's`
  - `the credited team and its enemy hear their time-added lines`
  - `sudden death is everyone's line`
  - `special cap sounds follow the mode, whether the cap would win, and the score per round`
  - `a round's win lines follow the mode, the round and the number of trains`
- **The notices.** Tests for the tag notices' client text, and for the
  team-full and balance text: `each tag notice reads as the server printed it`.
- **The gameplay notices** (decision 5), in a new
  `tests/gameplay_notices_test.lua`, with at least these four tests:
  - `the transition chat reads as the server built it`, over a corpus of
    map infos: payload, race, koth, cp with stages, ctf, arena and none;
  - `the AI war's chat and announcement read as its story built them`,
    for several team sizes, against the old `Story()` strings;
  - `the called-off line reads as the server built it`;
  - `the sandbox announcement reads as the server built it`.

### D.3 Acceptance criteria

1. The per-commit checks pass on every commit.
2. `grep -rnE 'WS\.BroadcastSound(ToOthers)?\(' addon --include='*.lua' | grep -v 'function WS' | wc -l`
   prints 5, and these are exactly the Stay rows above. The 5 Halloween
   rows call `WS.BroadcastHolidaySound(` instead:
   `grep -rnE 'WS\.BroadcastHolidaySound\(' addon --include='*.lua' | grep -v 'function WS' | wc -l`
   prints 5. And
   `grep -nE 'WS\.BroadcastSound' addons/sandcastle/gamemodes/sandcastle/gamemode/features/rounds/sv.lua`
   shows only the nag and `VoiceTo` lines.
3. `grep -nE 'PrintMessage\(|ChatPrint\(' addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sv_teams.lua addons/sandcastle/gamemodes/sandcastle/gamemode/features/tag/sv.lua`
   prints nothing. The repo-wide count of `:ChatPrint(` plus `PrintMessage(`
   is 17.
4. `luajit tests/events_sites_test.lua` passes. The new events appear in the
   regenerated `.res`, and `gen_events_res.lua --check` exits 0.
5. Post-merge:
   `python3 .devtools/bin/ingame_tests.py --maps koth_viaduct,cp_dustbowl,pl_millstone_event`
   exits 0 with 0 Lua errors.
   - The `koth` and `cp_capture` checks gain a server-side listener record
     showing `teamplay_round_win` fired with a `team` field when the round
     ended.
   - `test_ingame_tests.py` is updated if the plan's steps change, and
     pytest passes.
6. The harness's `HUMAN_ONLY` list still names the announcer lines. Hearing
   them is a playtest item for the operator, not an agent criterion.
7. `WS.Announce`, `announcement` and `gameplay_chat` are gone:
   - `grep -rnE 'WS\.Announce\b' addon --include='*.lua'` prints
     nothing. At 29a6070 it prints 3 lines: the definition and its 2
     callers.
   - `grep -rnE '"(announcement|gameplay_chat)"' addon --include='*.lua'`
     prints nothing. It prints 6 lines at 29a6070, and B1 leaves 4.
8. No server file builds the moved text:
   `grep -rlE 'AI war declared|Game called off|Gameplay mode has ended|Gameplay mode begins in|Gameplay\.Describe\(' addon --include='*.lua' | grep -E '/sv(_[^/]*)?\.lua$'`
   prints nothing. At 29a6070 it prints `features/gamemode/sv.lua` and
   `features/aiwar/sv.lua`.
9. `luajit tests/gameplay_notices_test.lua` passes, and contains the four
   test names in D.2.
10. `luajit tests/events_system_test.lua` passes, and the fixture lists
    exactly `teamplay_round_win`, `teamplay_suddendeath_begin`,
    `teamplay_alert` and `teamplay_teambalanced_player` among D's events,
    at major 1. The tag events are not in it.
11. `grep -rnE 'Events\.System\.Fire\("teamplay_(round_win|suddendeath_begin|alert|teambalanced_player)"' addon --include='*.lua'`
    prints 4 lines, and the tag events' sites are `Events.Game.Fire`.
12. `grep -rnE 'Events\.Game\.Fire\("holiday_broadcast_audio"' addon --include='*.lua'`
    prints 1 line, in `ws/sv_world.lua`. The scanner finds no
    `holiday_broadcast_audio` in the frozen fixture.

---

## Phase E: in game

**Goal.** Run the whole system live:

- the harness on the 14 maps with zero Lua errors;
- a staged stale-file check on one map, without a client and with one;
- T1 to T7 with the GMod client in "Team Fortress 2" (operator decision 2,
  extended by P6), unattended, through `gmod_client.py` (§3).

**One programmer** (it runs the harness and the client session), plus the
writer finishing the docs.

**What changed (event classes, 2026-10-08).**

- **A new server-side check, `events_recovery`,** stages failure states on
  the live library and watches each recover (E.1).
- **The client session adds three things:**
  - **T6:** a paced resync of 300 KB to the real client;
  - **T7:** a file made stale for the client, then recovered by a refresh;
  - **the real handshake**, read from the client's log.

  T6 and T7 use the GMod client in "Team Fortress 2". The operator extended
  decision 2's exception to them (P6), so they are required.
- **Major 1 freezes when E passes** (decision (a); P5).
- **Criteria:** E.3 items 5 to 7 are new, and item 4 gains T6, T7 and the
  handshake.

### E.1 Scope

- **A new in-game check,**
  `.devtools/bin/ingame/checks/events_stale.lua`, added to koth_viaduct's
  `MapRun` in `ingame_tests.py`, with `test_ingame_tests.py` updated. It
  stages staleness **without editing any addon file**:
  1. It replaces the drift record's sent and run references for
     `gamemode/features/capture/cl.lua` with a different hash.
  2. It waits one full scan cycle.
  3. It asserts the scanner reports the key as stale.
  4. It calls the server's `client_ready` trigger path for a fake sender
     key, and asserts a `code_stale` is produced naming that key.
  5. It feeds a fake `code_touched { events = { "teamplay_point_captured", "teamplay_capture_blocked" } }`
     from that sender.
  6. It asserts two things. `Touch:Blocks`, called directly with the live
     library's `Sites()`, holds for those two events and not for
     `teamplay_timer_time_added`: attribution feeds the model correctly.
     And the adapter would still send that sender all three: nothing stops
     (decision 3).
  7. It asserts the server log has one `network error:` line naming the
     key.
  8. It restores the references.
- **The client's staged stale file** (with the client, and §3's markers):
  1. Start the server on koth_viaduct and wait for start-up.
  2. Set a comment marker in `features/capture/cl.lua` and
     `lua_refresh_file` it. It is a `CompileFile`d file, so the server
     keeps running the old text while later joiners get the new one (T2).
  3. Wait one scan cycle, then launch the client.
  4. The client's log has the `network error:` line for
     `gamemode/features/capture/cl.lua`, naming `teamplay_point_captured`
     and `teamplay_capture_blocked` as touched and not stopped. The
     server's log has its one line for that player.
  5. Close the client, restore the marker, and stop the server.

  If T2 chose `SERVED_SENT`, a refreshed feature file is never stale. The
  architect then replaces steps 2 and 3 with a lazily compiled server
  module's case before E starts.
- **A recovery check** (the design change):
  `.devtools/bin/ingame/checks/events_recovery.lua`, added to
  koth_viaduct's `MapRun` after `events_stale`. It uses a fake peer (a
  sender key with no client), touches no addon file, and asserts each line
  in the server log:
  1. **stale_code:** it swaps the drift record's references for
     `gamemode/ws/sh_gameplay.lua` and has the fake peer load it, so
     `code_stale` is produced. Then it calls `Library:Refreshed` with that
     key, as a gamemode refresh would, and asserts `code_current` for the
     peer and one `network recovered:` line.
  2. **refused:** from the fake peer it feeds an id that is not accepted,
     then `client_ready` three times in one second. It asserts
     `event_refused` with `not_accepted` (with `events_accepted` before it),
     then with `rate_limited`, and one log line per reason.
  3. **major_mismatch:** it feeds a `client_ready` with `major = MAJOR + 1`
     and asserts one `network error:` line naming both majors, and no
     handshake. The fake peer can't be kicked, so for this step the check
     re-binds the `Library`'s roster port to a wrapper that records
     `Disconnect` for its fake peer and passes every other call to
     `GModRoster`. It asserts one recorded `Disconnect` with
     `MAJOR_MISMATCH_MESSAGE`, then re-binds `GModRoster`.
  4. **listener_failed:** it adds a check-owned listener that raises once,
     then fires its check-owned game event twice. It asserts one log line
     with a traceback, that the other listener ran both times, and one
     `network recovered:` line after the second, clean run.
  5. It restores everything, and removes its listener and the fake peer.
- **`SERVED_TEXT`** was set in A from T2. If E's run of T2 disagrees, the
  programmer reports it, and the architect decides before E passes.
- **The client session** (§3): T1 to T7 on the finished main, with the
  staged stale file above, in one session. The programmer appends the
  results to the research file under `## Client session (E)`.

### E.2 Tests to write first

- `test_ingame_tests.py`: koth_viaduct's plan includes `events_stale`.
- The `events_stale.lua` check fails on main before the drift record is
  reachable, which shows it reads the live library.
- `test_ingame_tests.py`: koth_viaduct's plan includes `events_recovery`
  after `events_stale`.
- The `events_recovery.lua` check fails on main before A's recovery is
  merged, which shows it reads the live library.

### E.3 Acceptance criteria

1. The harness:
   `python3 .devtools/bin/ingame_tests.py --maps pl_fifthcurve_event,pl_rumble_event,pl_millstone_event,pl_bloodwater,pl_terror_event,pl_hasslecastle,pl_sludgepit_event,plr_hacksaw_event,plr_hightower_event,pl_precipice_event_final,pl_coal_event,koth_viaduct,cp_granary,cp_dustbowl`
   exits 0.
   - Every row of the report's summary is PASS, with Lua errors 0.
   - The report's path is given in the programmer's report.
2. The `events_stale` step on koth_viaduct is PASS in that same run.
3. The per-commit checks pass, and `cd .devtools/bin && python3 -m pytest -q`
   passes.
4. **The client session** (operator decision 2; §3), unattended, on main
   after D merges. All of these are required:
   - T1 to T7 are recorded in the research file under
     `## Client session (E)`, each with its output under
     `.devtools/artifacts/gev2-research/client/`.
   - T1 passes, or A.4 was re-planned when it failed in A.
   - T3's `client_t3.txt` ends `mismatches 0` for both directions.
   - `UNRELIABLE_MAX_BYTES` is set from T5: at most half the largest size
     that arrived 100 out of 100 under load, and below 4000.
   - `tests/events_paths_test.lua` has T4's client form as a case, if it
     differs from the three.
   - The client's staged stale file (E.1) passes: the client's log has the
     `network error:` line for `gamemode/features/capture/cl.lua`, and the
     server's log has one line for that player.
   - Every client log has 0 Lua errors. For each
     `.devtools/artifacts/gev2-research/client/client_console-*.log`,
     `cd .devtools/bin && python3 -c "import ingame_tests as t, pathlib, sys; print(len(t.lua_errors(pathlib.Path(sys.argv[1]).read_text())))" <log>`
     prints 0.
   - The safeguards held. `gmod_client.log` shows every launch's
     preflight, one PID launched per launch, and that PID (and only it)
     closed. Afterwards `ps -axo command= | grep -c '[g]mod_win64.exe'`
     prints 0, and `git status --short` is what it was before the
     session.
5. The `events_recovery` step on koth_viaduct is PASS in item 1's run.
6. **The real handshake.** In the client session, each
   `client_console-*.log` from a normal join has no `network error:` line,
   and `client/client_t3.txt` has the line `handshake ready major 1`.
7. **T6 and T7** (§3), in the same session (decision 2, extended to them by
   P6):
   - `client/client_t6.txt` ends `received 300 of 300 in order`. The client
     stayed connected, and the server's log has exactly one `ready_burst`
     line for it. `PACE_BYTES_PER_TICK` is set from the run, with a comment
     citing the research section.
   - For T7, the client's log has the `network error:` line for the staged
     file, then a `network recovered:` line for it after the refresh. The
     server's log has both lines for that player. The client's
     `client_t7.txt` (its probe hooks `surface.PlaySound`) records
     `ui/system_message_alert.wav`, then `ui/message_update.wav`.

---

## 3. The client tests (T1 to T7)

**Operator decision 2: allowed, unattended.** The GMod client runs in the
CrossOver bottle **"Team Fortress 2"**, which has the right Wine settings.
It joins the dedicated server that `srcds.py` runs in "Steam". On
2026-10-08 the operator extended the exception from T1 to T5 to T6 and T7
(P6); it still covers only the GMod client, and the server still runs only
in "Steam".

- It is the only thing that ever runs in "Team Fortress 2" for this work,
  and only `gmod_client.py` launches or closes it.
- The operator plays TF2 in that bottle, and a server there once ended his
  game. So the tool's safeguards are its tested behaviour (A.5).

**The shared install.** The "Steam" bottle's
`C:\Steam\steamapps\common\GarrysMod` is a symlink into the "Team Fortress
2" bottle's, so the client and the server read one `garrysmod/` folder:

- **`addons/sandcastle`,** the symlink to this repo, is both the server's
  copy and the client's local copy. The two can only differ in time, which
  is how T1 is staged.
- **`data/`:** the client reads its probes from `data/ws_tests/` and
  writes its results there, as the server does.
- **`cache/lua/`:** the dedicated server writes nothing there (research
  §1), so every entry is the client's.
- **`console.log`** is the server's `-condebug` log. The client never uses
  `-condebug`. It logs with
  `+con_logfile data/ws_tests/client/console.log` instead.

**`gmod_client.py`** (A.1; its tests are in A.5):

```sh
gmod_client.py check                                  # the preflight alone: exit 0 if a launch is allowed, 3 if not, saying why
gmod_client.py start [--port 27025] [--minutes 20]    # preflight, launch, wait until the server's status lists the player
gmod_client.py stop                                   # close the client this tool launched, and keep its log
```

- **The preflight, before every launch.** It refuses, and launches
  nothing, when any of these holds:
  - any `tf_win64.exe`, `tf.exe` or `hl2.exe` runs, in any bottle (the
    operator's TF2). Refusing on the name alone is stricter than working
    out which bottle a process is in.
  - any `gmod.exe` or `gmod_win64.exe` runs: the operator's GMod, or a
    client a previous run left.
  - no `steam.exe` runs in "Team Fortress 2". A process is in that bottle
    when its working directory, from `lsof`, is under the bottle's folder.
    Launching GMod without Steam would start Steam, a second program in
    the operator's bottle, so the tool leaves that to him and refuses.
  - its own PID file names a client that still runs.
- **The launch is one command:** the bottle's `wine` with
  `--bottle "Team Fortress 2"`, running
  `gmod_win64.exe -novid -nojoy +con_logfile data/ws_tests/client/console.log +connect 127.0.0.1:<port>`.
  - The bottle is a constant, and the tool has no option for another one.
    `srcds.py` still refuses this bottle.
  - The tool records the client's PID and its start time in
    `.devtools/artifacts/gmod_client.pid`. The client is the one
    `gmod_win64.exe` process that wasn't running before the launch, found
    the way `srcds.py`'s `new_server` finds its server.
  - It appends what it found and did to
    `.devtools/artifacts/gev2-research/client/gmod_client.log`.
- **The watchdog** is a detached supervisor, like `srcds.py`'s, that checks
  every 2 s. It closes the client when the operator's game starts (any of
  the names above, other than our PID), or when `--minutes` pass. So a
  crashed agent never leaves the client running.
- **Closing.** `stop` and the watchdog signal only the recorded PID:
  - `SIGTERM`, then `SIGKILL` 15 s later if it still runs;
  - only while that PID still runs `gmod_win64.exe` with the recorded start
    time, so a reused PID is left alone;
  - never the wine launcher, a wineserver, wine's services (`srcds.py`'s
    `NEVER_STOP`), `steam.exe`, `steamwebhelper.exe`, or anything found by
    name or pattern.

  Then `stop` copies the client's log to
  `.devtools/artifacts/gev2-research/client/client_console-<UTC time>.log`.
  `gmod_client.log` lists any `garrysmod/cfg/*.cfg` whose content changed
  during the run, so the operator can see whether GMod saved settings.

**Markers.** T1, T2 and E's client check need an uncommitted change to an
addon file that the server reads through main.

- `gev2_marker.py set <file> <line>` appends the line. It refuses a file
  with uncommitted changes, because the operator may be working on main.
- `gev2_marker.py restore` puts back the exact bytes it saved. Every run
  calls it in a `finally`.
- Markers are never committed, and `git status --short` must be unchanged
  afterwards.

**Running a probe on the client.** `gev2_probe.py run --client NAME`:

1. copies `.devtools/bin/gev2/NAME.lua` to `data/ws_tests/gev2/`;
2. over RCON, has the server `SendLua` each connected player a one-line
   loader, which `RunString`s the probe from the client's `data/` (the
   shared folder). This works with `sv_allowcslua 0`, which every test
   keeps;
3. waits for the client to write `data/ws_tests/gev2/client_out/NAME.txt`,
   and copies it to `.devtools/artifacts/gev2-research/client/`.

| Test | When | What it settles | What each result changes |
|---|---|---|---|
| **T1** | early A; again in E | With `sv_allowcslua 0`, does the client run the copy the server sent rather than its local copy, for `include` and for `CompileFile` (`WS.require`, the feature loader)? And after joining, do the client's `cache/lua` names match the server's `util.SHA256(text .. "\0"):sub(1, 40)` list for every sent file? **Staging** (the install is shared, so the copies can differ only in time): (1) set the marker `WS_T1_INCLUDE = "sent-<nonce>"` in `ws/cl_spectate.lua` (`include`d) and `WS_T1_COMPILE = "sent-<nonce>"` in `features/capture/cl.lua` (`CompileFile`d); (2) start the server with `--no-lua-refresh` on koth_viaduct, which loads `capture`; (3) rewrite both markers to `"disk-<nonce>"`; (4) launch the client; (5) the probe reports both globals, and the cache check runs. | **Pass:** both read `sent-`, and the cache holds the `sent-` texts. The engine guarantee holds, and the server-side check is complete. **`disk-`, with the cache holding the `disk-` text:** the server serves disk text even without a refresh. The guarantee still holds, and T2 should choose `SERVED_DISK`. **`disk-` with no matching cache entry, or a mix:** the premise of §4 is false. The architect re-plans A.4 with the operator before detection is built (A.6 item 11). The codec, rates and stop rules are unaffected. |
| **T2** | early A; again in E | After `lua_refresh_file` of `features/capture/cl.lua`, and after a plain save (in case autorefresh fires under CrossOver), each with a new marker: does the connected client gain the new cache entry, and does a client that joins next (a second launch) run the new text? | **New text for later joiners after a refresh, and after a plain save:** `SERVED_DISK` is exact. **After a refresh only:** keep `SERVED_DISK`, and the report says "differs on disk; stale for clients that load it after a refresh". **Never before a map change:** set `SERVED_SENT`, and drift can then come only from lazily compiled server modules. |
| **T3** | after A merges; again in E | The wire through real `net`, in both directions, with A's codec: every tag of A.3, `""`, a NUL string, the caps, `WriteUInt` at 32 bits with values ≥ 2^31, and `ReadData` with NUL bytes | The fake buffer is the only other evidence for the read side. Any mismatch is a codec defect, fixed in A (or, in E, before E passes). |
| **T4** | early A; again in E | `debug.getinfo(fn, "S").source` on the client, for a server-sent file, a feature view and an entity | If it is a fourth form, `FileKey.FromSource` gains it as a test case in A. Attribution on the client depends on it. |
| **T5** | E | The largest unreliable message that reliably arrives: 200, 500, 1000, 1200, 2000 and 4000 bytes, 100 of each, idle and under load | Sets `UNRELIABLE_MAX_BYTES`. No event is unreliable yet, so nothing waits on it. |
| **T6** | E | The paced resync with a real client. A probe-only `resync` provider fires 300 game events of 1 KB each to the client in one resync. The client probe counts what arrives, and in what order. | Sets `PACE_BYTES_PER_TICK`. If the client drops, or anything arrives out of order, lower the budget, or the `Pacer` is wrong and is fixed before E passes. |
| **T7** | E | A stale included file recovers. Start with `--no-lua-refresh`, put a marker in `ws/sh_gameplay.lua` (an included file the server runs), and launch the client, which gets the new text while the server ran the old one. Then `lua_refresh_file` it, so both realms rerun it. | The client reports the file stale, then recovered (`code_current`). If T2 shows that `lua_refresh_file` doesn't reach a client under `-disableluarefresh`, the architect replaces the step before E. |

**Who runs what, and when.**

- **Early A,** by the researcher (the second agent): T1, T2 and T4.
  - They start as soon as the programmer's client tools are committed on
    the A branch, using that worktree's scripts against main.
  - The results go in the research file under `## Client session`.
  - Detection waits for T1 and T2 (A.6 items 11 and 14).
- **After A merges,** by the A programmer, before the architect's A
  evaluation: T3 (A.6 item 15).
- **E,** by the E programmer: all seven again on the finished main, plus the
  client's staged stale file (E.1) and the real handshake, in one session
  (E.3 items 4, 6 and 7). T1 to T5 run again, and T6 and T7 run for the
  first time.
- **Every session runs in this order:**
  1. `srcds.py start`;
  2. `gmod_client.py start`;
  3. the probes;
  4. `gmod_client.py stop`;
  5. `srcds.py stop`.

  The markers are restored in a `finally`.

---

## 4. Operator decisions

All five were answered on 2026-10-08, and none is open. The questions, the
answers and what they changed are under "Operator decisions (2026-10-08)"
near the top. The researcher's two product questions were decisions 1 and
2.

---

## 5. Order of work, the two-agent limit, and risks

### Order

| Step | Agents running (at most 2) | Gate to the next step |
|---|---|---|
| 0. Commit the research inputs and this plan (approved, with §4 answered) | director | the commit is on main |
| 0b. Re-evaluate the tools gate, then merge `gev2-phase-a-tools` to main ("How the two branches combine") | architect, then director | the gate passes, and the merge is on main |
| A. The library as classes, with the three kinds and recovery (A.1–A.6) | programmer (stage 2, then stage 3); plus the researcher for the early client session (T1, T2, T4) | stage 3 (detection) waits for T1 and T2's results; T3 runs after the merge; architect's A evaluation passes |
| B. Migration | programmer B1 and programmer B2, in parallel on disjoint files | both merged; architect's B evaluation passes |
| C. Removal and the events file | programmer | architect's C evaluation passes |
| D. Presentation | programmer D; the writer starts drafting | architect's D evaluation passes |
| E. In game | programmer E (the harness and the client session, T1 to T7); the writer continues | architect's E evaluation passes |
| Docs finish, close | writer, then director | |

- **The two-agent limit applies:**
  - in A, the programmer plus the researcher, who runs only the early
    client session;
  - in B, the two programmers. The writer doesn't start in B, and the
    researcher doesn't run then;
  - in D and E, the programmer plus the writer.
- **Merging and evaluation.** After each phase the director merges with
  `--no-ff` and runs both checks on main. The architect then runs that
  phase's criteria, including the post-merge smoke. A failed criterion goes
  back to the programmer before the next phase.

### Risks

1. **Only a client exercises the real wire.**
   - The dedicated server has no client, so `net` decode is proven live
     only by T3. Until T3 runs, the codec rests on a fake buffer that mimics
     GMod's bit costs (measured in research §4).
   - Mitigations: A's live size probe proves the write side exactly, and T3
     runs as soon as A is merged (A.6 item 15), then again in E.
   - Known suspects T3 checks: `WriteUInt`/`ReadUInt` at 32 bits for values
     ≥ 2^31, and `ReadData` with NULs.
2. **`file.Time` under Wine through a symlink is unmeasured.** If it is
   costly or doesn't change on save, the scanner reads in turn. That costs
   about 0.7 ms per file, so `FILES_PER_TICK` drops to 1 and a full cycle
   takes about 3 s at 66 ticks. The 1 ms per-tick budget is checked in A.6.
3. **Start-up reads every sent file once** (126–163 ms under Wine), for the
   sent references. This happens once per map, never per join.
4. **Wrapping a global.** Another addon may wrap `AddCSLuaFile` too. Ours
   chains to the previous function, and is installed once per Lua state. A
   gamemode refresh reruns `init.lua`, and the kind rules (A.4) decide which
   references refresh.
5. **Detection can over-report** if T2 shows that a plain save (with no
   refresh) doesn't change what later loaders run. The report's wording
   follows T2's result. Detection only reports (decision 3), so an
   over-report costs a console and chat line, never a lost event.
6. **Merges in B.** The shared file is `tests/events_unmigrated.lua`. Its
   two blocks are far apart, so the edits merge cleanly. If they don't, the
   conflict is two lists that both end empty. No other file is in both
   sets.
7. **The boss port change touches three large models and five tests.** The
   per-file test counts (B.3 item 6) guard against lost coverage.
8. **Client sound choice needs client-side state.** The mode, trains and
   score per round must travel as event fields, or already be known to the
   view. A wrong field shows up as a wrong line, which only a human hears.
   The equivalence tests (D.2) are the guard.
9. **The spec lags the plan** until the writer applies §1. Programmers must
   read §1 first. The evaluator judges against this plan.
10. **E's harness run is long** (14 maps, with boss steps of 150 s each). Run
    it once, with nothing else on the server.
11. **The client runs in the operator's bottle.** The preflight, the
    watchdog and PID-only closing (§3) are the guards, and they are tested
    (A.5).
    - What remains: the operator starting TF2 during a run, which the
      watchdog answers within 2 s by closing only our client.
    - GMod may save its own settings when it closes. `gmod_client.log`
      lists any `cfg/*.cfg` that changed.
12. **The shared install.** The client and the server share `garrysmod/`.
    - So the client logs with `con_logfile`, never `-condebug`.
    - Its probes and results stay under `data/ws_tests/`.
    - T1 is staged in time, not with a second copy of the addon (§3).
13. **Recovery code runs only when things go wrong.**
    - `tests/fake_link.lua` drives every failure state in the fakes, and E's
      `events_recovery` check and T6 and T7 drive them live.
    - A recovery that is never exercised would rot, so each row of the table
      keeps its test.
14. **Isolated listeners change v1's semantics.** A listener that raises no
    longer stops the listeners after it, or the send.
    - The error is logged as our bug with its traceback, so nothing is
      quiet.
    - A feature that relied on an error aborting the rest would behave
      differently. None is known; B's smoke runs would show one.
15. **Pacing is unmeasured** until T6. `PACE_BYTES_PER_TICK = 16384` is
    provisional. Today's largest resync is `feature_load`'s list of names,
    far under the budget.
16. **In GMod, majors differ only through drift**, so `major_mismatch` will
    rarely fire. Its tests and E's staged check keep it honest. When it
    does fire, the disconnected client gets the same served text if it
    reconnects at once, and is disconnected again until the server's code
    agrees (its next map change at the latest). The message says so.

### Judgment calls the operator may want to revisit

- **Hashing compiled text.** The run reference comes from `file.Read` just
  before `CompileFile`, not from `CompileString`. This keeps chunk names and
  error paths; the cost is a microsecond window in which the file could
  change between the read and the compile.
- **The boss port.** It gets one method per event, and the `Fire` sites
  live in `features/npc/sv.lua`, not in the entity. That way the events
  belong to the `npc` feature beside the view that hears them. The
  alternative is literal sites in `halloween_base_boss.lua`, which would
  make the events always loaded.
- **`Listen` is literal too, with a function-literal listener.** Without
  that, the spec's field check can't be built.
- **`tests/events_test.lua` is rewritten in A, and `Request` is removed in
  A.** The v1 registry's tests are replaced in the commit that replaces the
  registry, so the test total never drops.
- **Stopping is modelled, not enforced** (decision 3). `Touch` defines
  which events a stale file would stop, feature-wide and all-event stops
  included, and its tests pin that down. No runtime code stops an event.
  Client-only events are never stopped, even in the model.
- **No `ws_events_check` convar.** Report only leaves its off and stop
  values without a use, so the check always runs. `code_stale` has no
  `stop` field, and the client's answer is `code_touched`.
- **The client sessions.** T1, T2 and T4 run early in A, as the gate for
  detection. T3 runs after A merges, and all five run again in E.
- **The client's preflight** refuses by process name, machine-wide. It also
  refuses when Steam isn't already running in "Team Fortress 2", rather
  than start it there.
- **T1 is staged in time** (markers rewritten after the server starts with
  `-disableluarefresh`), because the shared install makes the client's
  local copy the server's own.
- **D's new events are Sandcastle's own** (TF2 has none):
  `gameplay_transition_started`, `gameplay_requested` and
  `gameplay_sandbox_entered`. `gameplay_requested` carries the source's
  facts as a `story` record, so the gamemode stays generic.
- **The site comments are enforced by the scanner** (a comment block above
  each `Fire`, and a trailing comment on each field line). The spec calls
  them the documentation, so a missing one is a failing test.
- **The constants:**
  - `UNRELIABLE_MAX_BYTES = 1200`, provisional until T5 in E;
  - `READY_BURST_MAX_BYTES = 131072`, logged rather than raised;
  - `FILES_PER_TICK = 2` to start;
  - `MAX_DEPTH = 16`;
  - the wire widths in A.3.
- **The phase-D split.** Lines named by map data or by a model's own pick
  stay on `teamplay_broadcast_audio`, as TF2 itself does. The overtime nag
  and the cart warning stay because TF2 has no event for them.
- **The generator is in Lua,** sharing one scanner with the tests, not
  Python as the spec named it.
- **The kinds are chosen at the call site,** by the facade the site calls
  (`Events.Game`, `Events.System`), and not by an option or a list of
  names. The site is the spec, so the kind belongs to it. `Events.Recovery`
  has no `Fire`.
- **System events keep the self-describing encoding.** A major in the
  handshake and a freeze test on names and field keys keep them fixed
  (decision (a)). A fixed schema would bring back a second specification.
- **The stale check is the same for every kind.** System and recovery
  events are never stoppable, even in the model (decision (b)).
- **Lifecycle traffic is recovery traffic,** with no fourth kind (decision
  (c)). `handshake` replaces `events_accepted` on ready, and every recovery
  site is in `protocol.lua`: one class, one method per event, as the boss
  port has one method per event.
- **Decision (d)'s split,** by the operator's rule (P4): five of today's
  events are system, D adds four more, and everything else is game, the
  default (the tag events included). `teamplay_broadcast_audio`
  keeps only the gamemode's announcer, and its Halloween lines move to the
  game event `holiday_broadcast_audio`.
- **The cue sounds** (P1): TF2's `ui/system_message_alert.wav` and
  `ui/message_update.wav`. TF2 has no sound named for a "system update".
- **The live major_mismatch step** re-binds the roster port to a recording
  wrapper for its fake peer, since a fake peer can't be kicked. The kick
  itself is covered by the fakes and by `GModRoster:Disconnect`'s one line.
  The operator confirmed this is enough: E adds no real end-to-end kick.
- **The disconnect message** stays as written; the operator confirmed it
  covers a client disconnected again before the server's code agrees.
- **Every dispatch isolates each listener,** local or received, so a view's
  error neither aborts the other listeners nor stops the send. The error is
  logged with its traceback.
- **A client that can't decode a message logs it and resyncs,** instead of
  raising. The message is still our bug, and it is still logged as one.
- **Recovery replays state, not history.** A resync re-fires each feature's
  current state; missed one-shot facts stay missed (P1).
- **Refusals are answered,** at most once per player and event per 10 s, so
  a flooding client can't make the server amplify.
- **Pacing.** The ready burst is paced, not only logged, because an
  overflowing reliable buffer is the one failure that would cost a player
  the connection.
- **Major 1 freezes when E passes,** as the operator confirmed (P5).
- **The committed modules are reshaped into classes over the same
  functions** (codec, errors, paths, stops), rather than rewritten. Their
  tests keep their names.
