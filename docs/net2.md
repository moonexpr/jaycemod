# net2: events between server and clients

**Status (2026-11-10): built in the Sandcastle base gamemode,** under
`gamemodes/sandcastle/gamemode/includes/modules/`: `net2.lua` and
`game_events.lua`, tested by `tests/net2_test.lua` and
`tests/game_events_test.lua`. It supersedes the game events v2 design
(`docs/game-events-v2.md`, `-plan.md`, `-research.md`, `-handoff.md`). Those
documents stay as the record of what was weighed. Wetsands still runs v1
(`WS.Events`) until it moves onto net2.

## Why it changed from v2

- **The stale-code check is gone.** v2's research found that a client can't
  read the server-sent file it ran (`file.Read` returns `nil`, and Facepunch
  won't change that). It also found that with `sv_allowcslua 0` the client
  runs what the server sent, so the threat only arises in development, and
  `dev.reload` already handles that. One version number in the handshake
  (`net2.SetVersion`) replaces the check.
- **No one-literal-site rule, generated events file, pre-commit hook or
  freeze test.** The current code already broke the one-site rule (two
  `Fire` sites each for `game_aiwar_slots`, `game_round_gore_cleared` and
  `game_teamplay_broadcast_audio`), and the reviewer showed that tail calls
  defeat it too. A rule nothing can enforce is not worth enforcing.
- **No event kinds (system, game, recovery) and no per-feature stops.** The
  base gamemode has no features and no foundation, so net2 stands alone as a
  GMod library. Names beginning `net2_` are the library's own.
- **State replaces history on resync.** v2 had each feature re-fire its
  state when a client resynced. net2 has replicated tables instead, which a
  joining client receives whole.

## Two layers

**net2** (`includes/modules/net2.lua`) is the transport: GMod's `net`
library taken further. It knows nothing of events. **game_events**
(`includes/modules/game_events.lua`) is built on it: local dispatch, with
listeners in order. Game events 2 is that layer, and other systems may use
net2 directly.

### net2

| Mechanism | How |
|---|---|
| Send and Receive | `Send(name, payload[, options])` carries a table to the other realm's `Receive(name, fn)`. It returns true, or false and why (`nobody`, `not_ready`, `not_accepted`, `predicted`). One receiver per name. |
| Ad hoc names | A name is any string, made up where it is used. Nothing registers it: no `util.AddNetworkString`, no precache at load, on either realm, at any time. Everything rides one net message. A name goes over once per connection, then as a number. |
| Encoding | Tagged values, so a message decodes without any schema. Whole numbers up to 2^52 go as zig-zag varints, other numbers as exact doubles. Strings carry a length, so a NUL is kept. Vectors and angles go as three float32s, exact for Source's values. Entities go by index. Lists and records may nest up to 32 deep. |
| Shape cache | A record's keys are sent once per connection as a shape. After that, the shape is a small number. A frame defines only what the peer doesn't yet hold. |
| Batching | Each tick's reliable messages go to a peer in one frame, in the order they were sent. |
| Budget | A peer is sent 30% of the `rate` its client asked for, held between 10 and 60 KB/s, and always at least one message a tick. |
| Large payloads | A frame over 4 KB is compressed when that makes it smaller. A payload over one net message (60 KB) is sent in parts with what the budget has left, and smaller messages sent after it arrive before it. Up to four may arrive in parts at once. |
| Unreliable | `unreliable = true` sends a frame of at most 1000 bytes that defines everything it uses, with a sequence number per name. An older one arriving after a newer is dropped. |
| Prediction | With `predicted = true`, a client sends nothing, and the server sends to everyone except the player predicting. |
| Ready gate | A client says hello once its Lua is up. Until the server answers, it is sent nothing. A client on another wire or game version is kicked with a message. `OnReady(id, fn)` runs in both realms as a connection becomes ready, and at once for one that already is. |
| Client admission | The server takes only the names it `Accept`s, at a token-bucket rate per player and name, and tells the client once per 10 s when it drops one (`net2_refused`). Decoding from a client is bounded: 16 levels deep, 4096 names, 1024 shapes, keys of at most 256 bytes, 256 KB a payload (decompressed size included). A message outside these limits is dropped whole, and what it defined is discarded. |
| Request and reply | `Serve(name, fn, rate)` on the server, and `Call(name, payload[, callback])` on a client. In a coroutine, `Call` polls with `coroutine.yield` until the answer. A handler may yield and is resumed each tick. An answer is a value, a refusal (`nil, reason`), or `failed` when the handler raises (reported on the server). Calls time out after 10 s. |
| Replicated tables | `Table(name)` gives a proxy the server writes and clients read. Changes go out key by key each tick, ahead of that tick's messages, and a joining client gets the whole table. `OnChange(name, id, fn(key, value, old))` runs in both realms. Nested values are replaced whole, not diffed. |
| Introspection | `Stats()` and the console command `net2_print` show, per name: sends, sent, bytes, received and refused. |

### game_events

`Fire(name, fields[, options])` hands the event to net2 first, so fields
the wire can't carry stop it before any listener runs. It then runs this
realm's listeners at once, in the order they were added. A listener that
raises is reported, and the rest still run. `Listen(name, id, fn)` under
the same id replaces that listener in place. A predicted event runs on a
client the first time its code is predicted. `Accept` is net2's.

### What other libraries taught

Read for this: vNet, gBetterNet and ducknetkit.

- **Taken:** the budget from the client's `rate` and `OnReady` (ducknetkit);
  small messages passing a large transfer, which all three lack.
- **Not taken yet:** cancelling a transfer from either side (vNet); a
  declared schema per name as a fast path for hot messages (gBetterNet's
  positional writers); back-references for repeated values in one payload
  (vNet).
- **Avoided:** trusting a client's declared sizes, unbounded partial
  buffers, no inbound rate limit, JSON payloads that turn numbers into
  strings, and a queue where one large send blocks everything after it.

## The first user

`round_manager` fires `teamplay_round_win { team }` through game_events
when a round ends. Sandcastle's client listener calls the gamemode's
`RoundWinAnnounce(winner)`, which shows the result in the center of the
screen where the server's `PrintMessage` used to. A derived gamemode can
override `GM:RoundWinAnnounce` to present it its own way.

## For testing

### net2's debug layer

Each realm has its own, set by `net2.SetDebug` or these convars (the
server's console for what the server sends, a client's for what that client
sends):

| Convar | What |
|---|---|
| `net2_debug_trace 1` | Prints each message the realm sends and takes: its name, size and player. |
| `net2_debug_delay <ms>` | Holds everything the realm sends that long, in order. |
| `net2_debug_loss <0..1>` | Drops that share of unreliable messages. Reliable ones are never dropped, as on the engine's channel. |

### The hit auditor

`includes/modules/hit_audit.lua` measures how often a client's bullets hit
what the server's did. It changes no shot: the server's trace still
decides.

- With the server's `hit_audit 1`, each client records what its predicted
  bullets hit (`PostEntityFireBullets`) and claims them over net2, one
  message per player command.
- The server records its own bullets for the same command number and
  compares pellet by pellet: agree, client only (the client hit what the
  server missed), server only, or different entities. It also keeps the
  worst distance between the two hit positions where they agreed.
- `hit_audit_print` on the server prints the counts by weapon, and
  `hit_audit_reset` starts them over.
- With `hit_audit_show 1` and `developer 1` on a client, each disagreement
  of that client's own shots is drawn for four seconds: its hit in yellow,
  the server's in red.
- Claims are held to 66 a second per player, 32 pellets a command and 64
  shots waiting; a shot one realm never reports is counted unmatched after
  two seconds.

Run it with `net2_debug_delay` on a client to see how the counts move with
latency.

## What is not settled

- **Nothing has been run in game.** The numbers that hold up in tests may
  not hold up there:
  - `UNRELIABLE_BYTES`, the budget's share of `rate` and the cost of
    compression are unmeasured;
  - so are `IsFirstTimePredicted` outside prediction and how
    `EntityIndex` treats the world and `NULL`.

  Check them on the dev server (`dev.reload` can't reload a shared module,
  so use `dev.run` or a map change).
- **The auditor's hooks are unchecked in game:** whether
  `GetCurrentCommand` answers inside `PostEntityFireBullets` on both realms,
  and whether that hook's trace is the lag-compensated one.
- **Entities a client hasn't received yet** decode as `NULL`, as GMod's
  `net.ReadEntity` does. Sending an entity before it is in the client's PVS
  loses it.
- **A client's Lua refresh drops the events in flight.** The client says
  hello again and both sides start their dictionaries over. Tables are
  resent; one-off events are not.
- **Tables go to every ready client.** There is no per-team table yet.
- **A large payload can wait indefinitely** while smaller messages use a
  peer's whole budget every tick.
- **Wetsands' `WS.Events`** (32 `Fire` sites, `Transact`/`Serve` on
  foundation's transactions) is still v1. Moving it is the next step. Its
  `system_`/`game_` naming rule has no counterpart in net2.
