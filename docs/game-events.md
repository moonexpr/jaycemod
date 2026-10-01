# Game events

Sandcastle's server and clients talk only through game events, modelled on
Source's `IGameEventManager` and TF2's `resource/modevents.res`. The server
fires facts ("the point was captured", "the Horsemann rose"). Each client
decides what to show and play: TF2's `clientmode_tf.cpp` works the same way,
for example playing `Halloween.HeadlessBossSpawn` when `pumpkin_lord_summoned`
arrives.

| Part | File | Job |
|---|---|---|
| Model | `gamemode/foundation/events.lua` (`foundation.events`) | Registry, field types, validation, wire format, listeners, request allowlist and rate limit. Pure; tested in `tests/events_test.lua`. |
| Adapter | `gamemode/wetsand/sh_events.lua` (`WETSAND.Events`) | Carries the registry on GMod's `net` library. `sh_core.lua` includes it before anything else. |

## The two net messages

Only these two network strings exist, and only the adapter registers them.
`tests/events_test.lua` fails if any other file calls
`util.AddNetworkString`, `net.Start` or `net.Receive`.

| Name | Direction |
|---|---|
| `wetsand_game_event_fire` | server to clients |
| `wetsand_game_event_request` | client to server |

## API

```lua
local E = WETSAND.Events

E.Define(name, fields, options)   -- both realms
E.Listen(name, id, fn)            -- both realms; fn(fields) on clients, fn(fields, ply) for a request on the server
E.Ignore(name, id)
E.Fire(name, fields, recipients)  -- server only
E.Request(name, fields)           -- client only; for client-sendable events
```

- `Fire` runs the server's own listeners first. It then sends the event to
  the recipients that are ready:
  - `nil`: every player
  - a team number: that team's players
  - a player
  - a list of players
  - a `Vector`: the players whose PVS holds that point
- A client is ready once its `client_ready` request has arrived
  (`WETSAND.IsReady(ply)`). A net message sent before that point is lost, so
  bots and loading clients are skipped. Anything a joining client needs, the
  server sends when `client_ready` arrives. The feature loader does this with
  `feature_load`.
- On the client, `WETSAND.LocalReady()` becomes true at `InitPostEntity`.
- A listener `id` works like `hook.Add`'s: listening again under the same id
  replaces that listener in its place. Listeners run in the order they were
  added.
- The field types are on `WETSAND.Events` too: `String()`, `Bool()`,
  `UInt(bits)`, `Int(bits)` (one of the bits is the sign), `Float()`,
  `Entity()`, `Vector()`, `Angle()`, `Team()` (a 10-bit uint),
  `List(type, countBits)`, `Record(fields)`, `Optional(type)` and
  `Default(type, value)`.
- Options:
  - `clientSendable = true`, which needs `rate = { count, seconds }`
  - `unreliable = true`, for high-rate snapshots small enough for one
    datagram

## Defining an event

Put the definition where the feature loads, in both realms. That is the
feature's `sh.lua` (`features/<name>/sh.lua`, which loads before `sv.lua` and
`cl.lua`), or, for events every map needs, an always-loaded `wetsand/sh_*.lua`.
Name the event with a literal string. The id-collision test and the
defined-before-use test both scan the source for `Define("name"`. Reuse TF2's
event name and field names wherever TF2 has the event.

```lua
-- features/capture/sh.lua
local E = WETSAND.Events
E.Define("teamplay_point_captured", {
	cp = E.UInt(8),
	cpname = E.String(),
	team = E.Team(),
	cappers = E.Default(E.String(), ""),
})

-- features/capture/sv.lua
WETSAND.Events.Fire("teamplay_point_captured", {
	cp = index,
	cpname = name,
	team = team,
})

-- features/capture/cl.lua
WETSAND.Events.Listen("teamplay_point_captured", "wetsand_capture_view", function(fields)
	WETSAND.Feature("rounds"):Announce(WETSAND.TeamName[fields.team] .. " captured point " .. fields.cp, fields.team)
end)
```

Validation happens when the event is built, on the firing side:

- Every declared field must be present unless it is `Optional` or has a
  `Default`. A `Default` value is filled in, so local listeners and receivers
  see the same fields.
- No undeclared field is allowed.
- Every value must be of its declared type. Integers must be whole and fit
  their width.
- A list must be shorter than 2^countBits. Truncate long lists before firing.

A mistake raises a named error (`kind: message`):

| Kind | Meaning |
|---|---|
| `unknown_event` | No definition has that name, or no definition has the received id. |
| `bad_fields` | A field is missing, undeclared, of the wrong type, or out of range. |
| `bad_schema` | The definition itself is bad: bit width, option, default, or name. |
| `id_collision` | Two names share an id. Rename one. |
| `not_client_sendable` | A client tried to `Request` a server-only event. |

With lazy loading, a client defines a feature's events when `feature_load`
reaches it. That message travels on the same reliable, ordered stream as
every later event of the feature, so definitions arrive first. Do not fire
from a feature file's top level while it loads, because the clients have not
yet been told to load it. An event with `unreliable` can overtake the
reliable stream, so fire it only to players who already have its feature.
No event is unreliable yet.

## Wire format

Each message is one event:

1. The id: the CRC32 of the name (IEEE, as `util.CRC` computes it) cut to its
   low 24 bits, written as `UInt(24)`. Once revisions are built, the name
   hashed is the wire name, letter first ("The events file and revisions"). Every realm derives the same id,
   whatever order lazy loading defines events in. A collision among the
   events defined in one realm raises `id_collision` at declaration.
   `tests/events_test.lua` checks every name in the addon.
2. The fields, sorted by name, each written as its type:

| Type | Written as |
|---|---|
| string, bool, float, entity, vector, angle | `net.Write<Type>` |
| uint(n), int(n) | `WriteUInt` / `WriteInt` with n bits |
| team | `WriteUInt`, 10 bits |
| list | its count as `UInt(countBits)`, then each item |
| record | its fields, sorted by name |
| optional | a presence bit, then the value if present |

A defaulted field is always written, with its default filled in.

## Client-sendable events

Only an event defined with `clientSendable = true` and a `rate` may go from a
client to the server. Building a request for any other event on the client
is our own bug (`not_client_sendable`).

The server's `ReadRequest` refuses three things:

- an unknown id
- an event that is not client-sendable
- a request over its rate: a token bucket per player per event, holding
  `rate.count` and refilling at `rate.count` per `rate.seconds`

A refused request is dropped quietly, because it is the client's mistake.
`developer 1` prints the refusals. An admitted request runs the server's
listeners with `(fields, ply)`. The fields have the declared types, but what
they say is the client's word, so a listener checks what they mean (for
example, whether the player may do that now).

## The events file and revisions

**Status: agreed with the operator (2026-09-30), not built yet.** It replaces
the hand-kept table under "The events" below once built.

### One file, generated

The `E.Define` calls stay the source: each feature defines its events when
it loads, so lazy loading is unchanged. From them a generator writes one
file in the spirit of TF2's `resource/modevents.res`:
`addon/gamemodes/sandcastle/resource/sandcastle_events.res`. It is output
only: never edited by hand, never parsed by the game.

- The generator, `.devtools/bin/gen_events_res.lua`, runs under LuaJIT. It
  loads every file that calls `E.Define` (the scan the id-collision test
  already makes) against the real `foundation.events` registry, so the file
  covers every feature, not just one map's.
- Each event gets its comment from the comment block directly above its
  `E.Define`, and each field gets its comment from a trailing comment on
  its line. It also notes where the event is defined, its revision, its
  wire id and its options.
- Types are written in full, since the file is never read back: `uint8`,
  `int16`, `team`, `entity`, `vector`, `string = ""` (a default),
  `optional<vector>`, `list<vector, 6>`, `list<{ team: team, pos: vector }, 2>`.

```
// GENERATED by .devtools/bin/gen_events_res.lua from each E.Define. Do not edit.
"sandcastle_events"
{
	// CTeamControlPoint::InternalSetOwner: a team took the point (not a reset
	// to nobody, nor the owner a round starts with).
	// features/capture/sh.lua:10; revision A; id 0x3fa21c
	"teamplay_point_captured"
	{
		"cp"       "uint8"
		"cpname"   "string"
		"team"     "team"
		"cappers"  "string = \"\""   // TF2's list of capper indexes, which we do not track
	}
}
```

### Revisions

Every event carries a revision letter, A to Z. The letter changes only for
an event whose encoding changed, and only by one step, Z wrapping back to A.
Every other event keeps its letter.

- **What counts as a change** is anything that changes the bytes on the
  wire: a field added, removed or renamed; a type or bit width; a list's
  count bits; a record's fields; `Optional`. Comments, default values
  (filled in on the firing side) and the `rate` do not.
- **The fingerprint.** The generator reduces each event's encoding to a
  canonical string (fields by name, each type with its widths, nested
  likewise). The `.res` records each event's fingerprint beside its letter.
  The next run compares: an event whose fingerprint differs from the
  committed one moves to its next letter. A new event starts at A.
- **The wire name** is the letter and the name: `teamplay_point_captured`
  at revision B travels as `Bteamplay_point_captured`, and its id is the
  CRC of that (see "Wire format"). Code never writes the letter:
  `Define`, `Fire`, `Listen` and `Request` take the plain name.
- **Shipping the letters.** The runtime needs each event's letter, but a
  letter depends on history, not on the definition alone. So the generator
  also writes `gamemode/foundation/events/revisions.lua` (name to letter),
  which `foundation.events` loads on both realms. An event with no entry
  there is revision A.

### Mismatches

A server and a client built from different revisions of an event cannot
read each other's message. That is reported as a network error, not
dropped:

- A client receiving an id it does not know tries each of its own events
  under every letter. If one matches, it prints
  `network error: the server sent teamplay_point_captured at revision B; this client has revision A`,
  shows it in chat once per event, and requests `event_revision_mismatch`
  (client-sendable, rate-limited) so the server logs it too. An id matching
  nothing is reported as an unknown event.
- The server does the same for a request it cannot read.

### Keeping it current

- **A pre-commit hook** (`.devtools/bin/hooks/pre-commit`, enabled with
  `git config core.hooksPath .devtools/bin/hooks`) runs the generator when a
  staged file calls `E.Define`, and stages the new `.res` and `revisions.lua`.
- **In game**, `wetsand_events_print` on the server and
  `wetsand_events_print_cl` on a client list the events that realm has
  defined now, each with its revision, id and defining file. Under lazy
  loading that is the features this map loaded. These commands print; they
  never write the repository's file.

## The events

Always loaded (`wetsand/`):

| Event | Defined in | Fields | Fired by / heard by |
|---|---|---|---|
| `client_ready` (client-sendable, 2 per 10 s) | `sh_events.lua` | none | a client at `InitPostEntity`; the adapter marks the player ready, and the feature loader answers with `feature_load` |
| `feature_load` | `sh_core.lua` | `names` list(string, 16) | the feature loader; clients load those features |
| `teamplay_broadcast_audio` | `sh_announcer.lua` | `team`, `sound`, `others` (default false) | `WETSAND.BroadcastSound`, `BroadcastSoundToOthers`; the client plays the sound if `foundation.teams.HearsBroadcast` says its player hears it (`UNASSIGNED` means everyone) |
| `announcement` | `sh_announcer.lua` | `text`, `team` (default `UNASSIGNED`) | `WETSAND.Announce`; the rounds view draws it |
| `gameplay_chat` | `sh_gameplay.lua` | `title`, `lines` list(string, 8) | the gamemode controller; chat |
| `gameplay_transition_cancelled` | `sh_gameplay.lua` | `sounds` list(string, 8) | the gamemode controller; clients stop the sounds |
| `nodegraph_debug` | `sh_nodegraph.lua` | `source`, `nodes` {pos, zone}, `links` {a, b, human} | the nodegraph feature; the admin overlay |
| `npc_ragdoll_create` | `sh_npc_ragdolls.lua` | `body`, `model`, `skin`, `bodygroups`, `force`, `pose` (optional) {pos, ang, vel} | `sv_npc_ragdolls.lua` to the body's PVS; `cl_npc_ragdolls.lua` builds the ragdoll |

Per feature (`features/<name>/sh.lua`):

| Event | Feature | Fields | Fired by / heard by |
|---|---|---|---|
| `teamplay_point_captured` | capture | `cp` uint8, `cpname`, `team`, `cappers` | capture controller on a sounding capture; the capture view announces "RED captured point N" |
| `teamplay_capture_blocked` | capture | `cp`, `cpname`, `team` (the defenders) | capture controller; the capture view adds "BLU defended X" as a round notice (for a point with a name) |
| `teamplay_timer_time_added` | rounds | `team`, `seconds_added` int32 | rounds controller; the rounds view flashes +m:ss |
| `pumpkin_lord_summoned`, `pumpkin_lord_killed` | npc | none | the Horsemann as it rises and once gone; the npc view plays `Halloween.HeadlessBossSpawn` / `HeadlessBossDeath` and prints TF2's line |
| `eyeball_boss_summoned`, `eyeball_boss_killed`, `eyeball_boss_escaped` | npc | `level` int16 | a map's MONOCULUS (never a spell's); `Halloween.MonoculusBossSpawn`, `MonoculusBossDeath`, `EyeballBossEscaped` and TF2's lines |
| `eyeball_boss_escape_imminent` | npc | `level`, `time_remaining` uint8 | at 60, 30 and 10 s left; `Halloween.EyeballBossEscapeSoon`, or `EscapeImminent` at 10 s or less, and TF2's line |
| `nb_debug_state`, `nb_debug_path`, `nb_debug_cost`, `nb_debug_behavior`, `nb_debug_nav`, `nb_debug_npc_removed` | nbdebug | see `features/nbdebug/sh.lua` | the nbdebug controller to subscribed admins; the overlay |
| `aiwar_debug` | nbdebug | `fire_teams`, `spheres`, `lanes`, `soldiers` | the aiwar controller to AIWAR-layer admins; the overlay |

`foundation.npc.boss_events` names the boss events and decides each client
cue. The boss models fire them through the boss port's `FireGameEvent`.
