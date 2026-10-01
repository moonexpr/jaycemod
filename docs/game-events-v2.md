# Game events, version 2: local dispatch

**Status: target design, workshopped with the operator (2026-09-30); not
built.** `docs/game-events.md` describes the code as it is today (`E.Define`
schemas). This replaces it once built: game events are the last system
before the fine-tune to the alpha playtest.

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

## 1. The model

```lua
local Events = WETSAND.Events

-- features/capture/sv.lua
-- CTeamControlPoint::InternalSetOwner: a team took the point (not a reset
-- to nobody, nor the owner a round starts with).
Events.Fire("teamplay_point_captured", {
	cp = index, -- the point's place in the master's order
	cpname = name, -- its name, as the map gives it
	team = team, -- the team that took it
})

-- features/capture/cl.lua
Events.Listen("teamplay_point_captured", "wetsand_capture_view", function(fields)
	WETSAND.Feature("rounds"):Announce(WETSAND.TeamName[fields.team] .. " captured " .. fields.cpname, fields.team)
end)
```

`Fire` runs the listeners of the realm it is called in, at once, in the
order they were added (as `hook.Run` does). The library then carries the
event to the other realm and dispatches it there the same way. Nothing is
declared first.

Gone: `E.Define` and its schemas, the type constructors (`UInt`, `List`,
`Record`...), `clientSendable`, and `Request` (a client calls `Fire`).

### The Fire site is the spec

- **One site per event.** Each event name appears in exactly one `Fire`
  call. Code elsewhere that needs to fire it calls a function holding that
  site. Two sites would be two specs.
- **Literal name, literal fields.** The name is a string literal. The fields
  are a table literal written at the call: its keys are the event's fields.
  Values may be any expression.
- **Comments are the documentation.** The comment block directly above the
  `Fire` call describes the event, with TF2's source where it mirrors one.
  The trailing comment on each field's line describes that field. TF2's
  event and field names are reused where TF2 has the event.

`tests/events_sites_test.lua` (run by `check_lua.sh`) scans the addon's Lua
and fails on:

- an event with no `Fire` site, or with more than one;
- a non-literal name, or fields that are not a table literal;
- a listener that reads a field (`fields.x`) its event's site does not send;
- two names with the same id (§3).

## 2. API

```lua
Events.Fire(name, fields, options)  -- both realms
Events.Listen(name, id, fn)         -- both realms
Events.Ignore(name, id)
Events.Accept(name, rate)           -- server only: clients may fire this
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
for high-rate snapshots small enough for one datagram. A client is ready
once its `client_ready` event arrives. Anything a joining client needs is
fired to it then.

### Clients to the server

The server says which events clients may send:

```lua
Events.Accept("team_menu_choice", {
	count = 4,
	seconds = 1,
})
```

The accepted names and rates go to each client when it is ready, and again
when a feature that accepts more loads. A client's `Fire` dispatches to its
own listeners, then carries the event to the server only if the server
accepts it. Every other client event stays on the client, so client-only
events cost nothing on the wire. The server quietly drops anything it does
not accept, or that comes over its rate (a token bucket per player per
event). It runs the listeners of what it admits with `(fields, ply)`; what
the fields say is the client's word.

## 3. Encoding (the library's business)

Two net messages for the whole gamemode, registered only by the adapter:
`wetsand_game_event_fire` (server to clients) and
`wetsand_game_event_request` (client to server). Each message is one event:

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
- **On a mismatch:** both sides report a network error naming the files:
  `network error: features/capture/cl.lua differs from the server's; the
  capture feature's events are stopped for this client until it reconnects
  or the file matches`. It goes to the client's console and chat once, and
  to the server's log. The server then fires none of that feature's events
  to that client, and drops that feature's events from it. Other features
  carry on. A mismatch in an always-loaded file stops every event for that
  client.
- **Which feature an event belongs to** is the feature whose file holds its
  `Fire` site (§1), recorded when the site first runs.

| Error | Meaning |
|---|---|
| `bad_fields` | a value the library cannot carry, a cycle, or a mixed table (raised at `Fire`) |
| `too_large` | the encoded event exceeds a net message |
| `stale_code` | a client's copy of a file differs from the server's (reported, never raised) |

## 5. The events file

`addon/gamemodes/sandcastle/resource/sandcastle_events.res`, in the spirit
of TF2's `modevents.res`. It is derived documentation: the game never reads
it, so even out of date it cannot affect the netcode.
`.devtools/bin/gen_events_res.py` writes it from the `Fire` sites (§1),
using the same scan as `tests/events_sites_test.lua`.

```
// GENERATED by .devtools/bin/gen_events_res.py from each Events.Fire; do not edit.
"sandcastle_events"
{
	// CTeamControlPoint::InternalSetOwner: a team took the point (not a reset
	// to nobody, nor the owner a round starts with).
	// fired: features/capture/sv.lua:412, id 0x3fa21c
	// heard: features/capture/cl.lua:88, features/aiwar/sv.lua:640
	"teamplay_point_captured"
	{
		"cp"      ""   // the point's place in the master's order
		"cpname"  ""   // its name, as the map gives it
		"team"    ""   // the team that took it
	}
}
```

Fields carry no types, because the library infers them per message.

### Keeping it current

- **A pre-commit hook** (`.devtools/bin/hooks/pre-commit`, enabled once with
  `git config core.hooksPath .devtools/bin/hooks`) regenerates the file and
  stages it when a staged Lua file calls `Fire`, `Listen` or `Accept`.
- **`tests/events_sites_test.lua` also fails when the committed file differs
  from what the sites generate.** So a commit made without the hook cannot
  leave the documentation stale either.
- **In game,** `wetsand_events_print` (server) and `wetsand_events_print_cl`
  (client) list the events that realm has seen: listeners, accepts, fire
  counts, the field types observed on the wire, and any files found stale.
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
4. Then move the remaining server-side presentation (announcer lines
   through `WETSAND.BroadcastSound`, gameplay chat text) into client
   listeners on TF2-named events.
