# Game events, version 2: local dispatch

**Status: target design, workshopped with the operator (2026-09-30); not
built.** `docs/game-events.md` describes the code as it is today (`E.Define`
schemas). This replaces it once built: game events are the last system
before the fine-tune to the alpha playtest.

**Revised 2026-10-08 for the operator's event classes.** There are three
kinds of event (system, game and recovery; §1), and each failure state the
library can detect is recovered (§4b). `docs/game-events-v2-plan.md` holds
the class layout, the failure-state table and the phases, and it wins where
the two differ. Its §1 lists the scholar's edits still to be applied here.

## 0. Goals

1. **No stale netcode is possible.** Nothing the wire depends on is
   generated, committed or kept by hand. Everything it needs is computed at
   runtime from the code actually running on each side, and code that
   differs between the two sides is caught before it exchanges events.
2. **One source of truth.** An event is wholly specified in one place, its
   `Fire` call. Everything else (listeners' checks, the events file) is
   derived from that site and never edited.
3. **Local dispatch.** Code fires and hears events as if everything ran in
   one place. Serialization, encoding, ids and transport belong to the
   library alone.
4. **Failures recover.** Each failure state the library can detect has a
   name, a report and a recovery, carried by recovery events (§4b).
   Recovery adds to reporting; it never stops an event.

## 1. The model

```lua
local Events = WETSAND.Events

-- features/capture/sv.lua
-- CTeamControlPoint::InternalSetOwner: a team took the point (not a reset
-- to nobody, nor the owner a round starts with).
Events.System.Fire("teamplay_point_captured", {
	cp = index, -- the point's place in the master's order
	cpname = name, -- its name, as the map gives it
	team = team, -- the team that took it
})

-- features/capture/cl.lua
Events.System.Listen("teamplay_point_captured", "wetsand_capture_view", function(fields)
	WETSAND.Feature("rounds"):Announce(WETSAND.TeamName[fields.team] .. " captured " .. fields.cpname, fields.team)
end)
```

`Fire` runs the listeners of the realm it is called in, at once, in the
order they were added (as `hook.Run` does). The library then carries the
event to the other realm and dispatches it there the same way. Nothing is
declared first.

Gone: `E.Define` and its schemas, the type constructors (`UInt`, `List`,
`Record`...), `clientSendable`, `Request` (a client calls `Fire`), and a
`Fire` that names no kind.

### Three kinds of event

The operator's rule: "system events should almost never be updated, only
for major releases: things like the announcer voice".

- **System events** are the gamemode's stable vocabulary, and change only in
  a major release. The operator's rule: "System events include major game
  sync events like round resets, system announcements, or any other
  wide-broadcasted events that fundamentally affect the game or reset
  state." They "should occupy a very limited set". Today they are
  `teamplay_broadcast_audio` (the gamemode's announcer only),
  `teamplay_timer_time_added`, `teamplay_point_captured`,
  `teamplay_capture_blocked` and `feature_load`. Phase D adds
  `teamplay_round_win`, `teamplay_suddendeath_begin`, `teamplay_alert` and
  `teamplay_teambalanced_player`.
- **Game events** are everything else, and **game is the default kind.** In
  the operator's words, they "concern decorative audio cues,
  halloween-specific programming, or anything else that's not fundamental
  to Sandcastle itself". They change freely from build to build. The
  Halloween lines that `teamplay_broadcast_audio` used to carry go on the
  game event `holiday_broadcast_audio`, and the tag (IT) events are game
  too.
- **Recovery events** are the library's own protocol (§4b). Only
  `foundation/events/protocol.lua` fires them. On the server, features may
  listen to `resync` to supply their state.

The facade a site calls is part of the site, so the kind is part of the
event's spec: `Events.System.Fire` or `Events.Game.Fire`. A `Listen` or
`Accept` of another kind than its event's `Fire` site raises `bad_kind`.

| | Game | System | Recovery |
|---|---|---|---|
| Options | `to`, `unreliable`, `critical` | `to`, `unreliable` | `to` |
| Can a stale file ever stop it? | in the model (§4) | never | never |
| Fixed? | no | within a major: `SystemEvent.MAJOR`, checked in the handshake, plus a freeze test on names and field keys | changes with the library |
| Fired from | any of our files | any of our files | `protocol.lua` only |
| From clients | if `Accept`ed | if `Accept`ed | always, at the library's own rates |

All three kinds share the encoding (§3), so system events are
self-describing too. Every message decodes whatever the
majors. The server compares the client's major once, in its `client_ready`,
rather than on each message, and disconnects a client on another major
(§4b).

### The Fire site is the spec

- **One site per event.** Each event name appears in exactly one `Fire`
  call. Code elsewhere that needs to fire it calls a function holding that
  site. Two sites would be two specs.
- **Literal name, literal fields, a named kind.** The site calls
  `Events.System.Fire` or `Events.Game.Fire`. The name is a string literal. The fields
  are a table literal written at the call: its keys are the event's fields.
  Values may be any expression. The options (`to`, `unreliable`,
  `critical`) belong to the site too.
- **Comments are the documentation.** The comment block directly above the
  `Fire` call describes the event, with TF2's source where it mirrors one.
  The trailing comment on each field's line describes that field. TF2's
  event and field names are reused where TF2 has the event.

`tests/events_sites_test.lua` (run by `check_lua.sh`) scans the addon's Lua
and fails on:

- an event with no `Fire` site, or with more than one;
- a non-literal name, or fields that are not a table literal;
- a listener that reads a field (`fields.x`) its event's site does not send;
- two names with the same id (§3);
- a `Listen` or `Accept` of another kind than its event's site, or a
  recovery event fired outside `foundation/events/protocol.lua`.

## 2. API

```lua
Events.Game.Fire(name, fields, options)   -- both realms
Events.Game.Listen(name, id, fn)          -- both realms
Events.Game.Ignore(name, id)
Events.Game.Accept(name, rate)            -- server only: clients may fire this
Events.System.Fire / Listen / Ignore / Accept   -- the same, for system events
Events.Recovery.Listen(name, id, fn)      -- the library's events; features listen to "resync"
```

- **Values** a field may hold: `nil`, booleans, numbers, strings, `Entity`,
  `Vector`, `Angle`, and tables of those (a list, `{ a, b, c }`, or a
  record, `{ x = 1 }`), nested without cycles. Anything else (a function, a
  cycle, a table mixing list and record keys, other userdata) raises
  `bad_fields` at `Fire`: our bug.
- **Listeners** get `fn(fields)`. On the server, a listener of an event a
  client fired also gets `ply` (`fn(fields, ply)`). Listening again under
  the same id replaces that listener in its place.

### Server to clients

`options.to` picks who hears it, after the server's own listeners: `nil`
for every ready player, a team number, a player, a list of players, or a
`Vector` (the players whose PVS holds it). `options.unreliable = true` is
for high-rate snapshots small enough for one datagram. `options.critical =
true` marks a game event whose loss on a stale client must stop its whole
feature (§4). A client is ready
once its handshake completes (§4b). Anything a joining client needs is
fired to it in the ready resync.

### Clients to the server

The server says which events clients may send:

```lua
Events.Game.Accept("team_menu_choice", {
	count = 4,
	seconds = 1,
})
```

The accepted names and rates go to each client when it is ready, and again
when a feature that accepts more loads. A client's `Fire` dispatches to its
own listeners, then carries the event to the server only if the server
accepts it. Every other client event stays on the client, so client-only
events cost nothing on the wire. The server drops anything it does not
accept, or that comes over its rate (a token bucket per player per event),
and tells the client once (`event_refused`, §4b). It runs the listeners of what it admits with `(fields, ply)`; what
the fields say is the client's word.

## 3. Encoding (the library's business)

Two net messages for the whole gamemode, registered only by the adapter:
`wetsand_game_event_fire` (server to clients) and
`wetsand_game_event_request` (client to server). All three kinds share them
and this encoding; the kind is not on the wire. Each message is one event:

1. **The id:** the CRC32 of the event's name, cut to 24 bits, computed by
   both sides at runtime. There is no table of ids.
2. **A key table:** the message's distinct field and record keys, each
   written once as a string. Every key below is an index into it, so a list
   of a hundred records names its keys once.
3. **The fields:** each a key, a type tag and a value:

| Tag | Value |
|---|---|
| nil, false, true | none |
| int | zig-zag encoded, in the narrowest of 8, 16 or 32 bits (a width tag), for whole numbers within ±2^31 |
| double | `WriteDouble`, for every other number |
| string | `WriteString` |
| entity | its index, 16 bits |
| vector, angle | `WriteVector`, `WriteAngle` |
| list | a count, then each item tagged |
| record | a count, then each key and tagged value |

Every message is self-describing, so a receiver decodes it without any
schema: there is no layout for the two sides to disagree on. A receiver with
no listener for an id ignores it, as local dispatch to no one would. A
message over the net library's limit raises `too_large` at `Fire`: our bug,
so thin the snapshot.

## 4. Same code on both sides

What remains possible is a client running different code from the server's:
a file hot-reloaded on one side only, or a Workshop copy of the addon
shadowing the server's development copy. Events would then decode but mean
the wrong thing. So the library checks the code itself, at runtime, with
nothing stored:

- **What is compared:** each Lua file the server sends clients
  (`AddCSLuaFile`), by a hash of its contents. The server hashes its copy
  (`file.Read(path, "LUA")`); the client hashes the copy it actually loaded.
- **When:** the always-loaded files (`wetsand/`, `foundation/`) when the
  client is ready; a feature's client files when `feature_load` loads it on
  the client; and again for any file the server reloads (`OnReloaded`).
  The server sends its hashes with those events. The client compares and
  answers with the files that differ (an accepted event, `code_mismatch`).
- **Which events a stale file touches:** those with a client listener in
  that file (the library records each `Listen`'s file), and those whose
  client `Fire` site is in it.
- **On a mismatch, only those events stop.** The client does not dispatch
  them to its listeners in the stale file, and does not send the server the
  events fired from it. The server sends them no events it fires toward
  those listeners. Everything else carries on: a client that missed one
  update to a non-critical event loses only that event. Both sides report
  it once as a network error naming the file and the events:
  `network error: features/capture/cl.lua differs from the server's;
  stopped for this client: teamplay_capture_blocked`. It goes to the
  client's console and chat, and to the server's log.
- **Critical events stop their feature.** A `Fire` site marks its event
  critical with `options.critical = true` (in the one site, so it is part of
  the event's spec). If a stale file touches a critical event, the client
  stops every event of that event's feature until it reconnects or the file
  matches. A stale always-loaded file touching a critical event stops every
  event for that client.
- **System and recovery events are never stopped,** even by these rules.
  A system event's contract is fixed within a major, which the handshake
  checks directly (§1), and recovery events are the library's own. A report
  lists the touched game and system events apart.
- **A stale file is also a failure state** (§4b). It is reported, and it
  recovers with `code_current` once the file matches again.
- **An event belongs to** the feature whose file holds its `Fire` site
  (§1), recorded when the site first runs.

Self-describing encoding is what makes this safe. An event a stale client
still receives always decodes, and a listener reading a field the new site
dropped gets `nil`, never another field's bytes.

| Error | Meaning |
|---|---|
| `bad_fields` | a value the library cannot carry, a cycle, or a mixed table (raised at `Fire`) |
| `too_large` | the encoded event exceeds a net message |
| `stale_code` | a client's copy of a file differs from the server's: a failure state (§4b), reported and recovered, never raised |
| `bad_kind` | one name used as two kinds, or a recovery event fired outside the library (raised at the call) |

## 4b. Failure states and recovery

A failure state is a condition of a connection that the library detects at
run time: a client still joining, a handshake that doesn't come, a client
on another major, stale code, a refused client event, a message the client
can't decode, a listener that raised, or a burst over the send budget. Our
bugs at a call (`bad_fields`, `too_large`, `bad_options`, `bad_kind`, ...)
are not failure states: they raise, and the fix is the code.

- **Each state is a class.** Opening one reports it once
  (`network error: ...`) and starts its recovery. An answer closes it and
  reports once (`network recovered: ...`). Retries are bounded, and a
  give-up is reported once.
- **Nothing is blocked, with one exception.** A recovery re-sends or
  replays, and it never stops an event, and a stale file is still
  report-only (§4). The exception, chosen by the operator: the server
  disconnects a client whose system major differs from its own, with a
  message telling it to update. Nothing else stops an event or disconnects
  a client.
- **What a player sees.** Every report goes to the console. A stale file
  and any give-up also go to chat, with TF2's `ui/system_message_alert.wav`
  for a failure and `ui/message_update.wav` for a recovery. A client view
  plays them, listening to the client-local recovery event
  `network_notice`. Where only a reconnect cures a stale file, the chat adds
  `reconnect to update`; the library never forces a reconnect.
- **Recovery replays state, not history.** A resync re-fires each feature's
  current state. A one-shot fact a client missed stays missed.
- **The recovery vocabulary,** each event with its one site in
  `protocol.lua`:
  - `client_ready { major }`, then `handshake { major, accepted }`, then the
    ready resync. That is how a client joins.
  - `resync_request { features, reason }` from a client. The server answers
    with `resync_begin { epoch, features }`, the local `resync` that runs
    the features' providers, and `resync_end { epoch }`.
  - `code_stale { files }`, `code_touched { events }`, and `code_current
    { files }` when the files match again.
  - `events_accepted { names }`, for a later `Accept`.
  - `event_refused { id, reason }`, the server's answer to a refused client
    event, at most once per player and event per 10 s.
  - `network_notice { state, line, recovered, chat }`, local to a client:
    the report its view presents.

The plan's "Failure states and recovery" gives each state's detection, its
recovery, what "recovered" means, and the test that drives it.

## 5. The events file

`addon/gamemodes/sandcastle/resource/sandcastle_events.res`, in the spirit
of TF2's `modevents.res`. It is derived documentation: the game never reads
it, so even out of date it cannot affect the netcode.
`.devtools/bin/gen_events_res.py` writes it from the `Fire` sites (§1),
using the same scan as `tests/events_sites_test.lua`.

```
// GENERATED by .devtools/bin/gen_events_res.py from each Events.Fire; do not edit.
// system events: major 1
"sandcastle_events"
{
	// CTeamControlPoint::InternalSetOwner: a team took the point (not a reset
	// to nobody, nor the owner a round starts with).
	// fired: features/capture/sv.lua:412, id 0x3fa21c
	// heard: features/capture/cl.lua:88, features/aiwar/sv.lua:640
	"teamplay_point_captured"
	{
		"kind"    "system"
		"cp"      ""   // the point's place in the master's order
		"cpname"  ""   // its name, as the map gives it
		"team"    ""   // the team that took it
	}
}
```

Fields carry no types, because the library infers them per message. Each
entry names its kind, and the system events are grouped first.

### Keeping it current

- **A pre-commit hook** (`.devtools/bin/hooks/pre-commit`, enabled once with
  `git config core.hooksPath .devtools/bin/hooks`) regenerates the file and
  stages it when a staged Lua file calls `Fire`, `Listen` or `Accept`.
- **`tests/events_sites_test.lua` also fails when the committed file differs
  from what the sites generate.** So a commit made without the hook cannot
  leave the documentation stale either.
- **In game,** `wetsand_events_print` (server) and `wetsand_events_print_cl`
  (client) list the events that realm has seen: listeners, accepts, fire
  counts, the field types observed on the wire, any files found stale, and
  the open failure states.
- **A freeze test** (`tests/events_system_test.lua`) fails when a system
  event's name or field keys differ from `tests/events_system_frozen.lua` at
  the same major. Changing one means bumping the major and refreezing.
  They print; they never write the repository's file.

## 6. Migration

1. Build the library behind today's API: the encoder, `Accept`, a client's
   `Fire`, the code check, and `Define` reduced to a no-op that only the
   migration still calls.
2. Move each feature: delete its `E.Define` calls, turn `Request` into
   `Fire` plus a server `Accept`, give each event its one literal `Fire`
   site with its comments, and generate the events file.
3. Remove `Define`, the type constructors and the old schema tests. Rewrite
   `tests/events_test.lua` for the encoder: round trips of every value kind,
   the key table, accept and rate, and the code check.
4. The library is built as classes, with the three kinds and recovery,
   in step 1. Step 2 moves each site to its kind, and step 3 removes the
   kind-less aliases and adds the freeze test. The plan has the details.
5. Then move the remaining server-side presentation (announcer lines
   through `WETSAND.BroadcastSound`, gameplay chat text) into client
   listeners on TF2-named events.
