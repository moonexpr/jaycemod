# net2: events between server and clients

**Status (2026-11-10): built in the Sandcastle base gamemode,**
`gamemodes/sandcastle/gamemode/includes/modules/net2.lua`, tested by
`tests/net2_test.lua`. It supersedes the game events v2 design
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

## What it does

The API is at the top of the module. In short:

| Mechanism | How |
|---|---|
| Local dispatch | `Fire` validates and encodes the event, then runs this realm's listeners at once in the order they were added. It then queues the event for the other realm. A listener that raises is reported, and the rest still run. |
| Encoding | Tagged values, so a message decodes without any schema. Whole numbers up to 2^52 go as zig-zag varints, other numbers as exact doubles. Strings carry a length, so a NUL is kept. Vectors and angles go as three float32s, exact for Source's values. Entities go by index. Lists and records may nest up to 32 deep. |
| Shape cache | A record's keys are sent once per connection as a shape, and each event name once. After that, each is a small number. A frame defines only what the peer doesn't yet hold. |
| Batching | Each tick's reliable events go to a peer in one frame, in the order they were fired. |
| Large payloads | A frame over 4 KB is compressed when that makes it smaller. A frame over one net message (60 KB) is sent in parts, in order, about 32 KB per peer per tick. |
| Unreliable | `unreliable = true` sends a frame of at most 1000 bytes that defines everything it uses, with a sequence number per name. An older one arriving after a newer is dropped. |
| Prediction | With `predicted = true`, a client runs the event the first time it is predicted and never sends it. The server sends it to everyone except the player who predicted it. |
| Ready gate | A client says hello once its Lua is up. Until the server answers, it is sent nothing. A client on another wire or game version is kicked with a message. `net2_ready` fires in both realms, with the player on the server. |
| Client admission | The server takes only the names it `Accept`s, at a token-bucket rate per player and name, and tells the client once per 10 s when it drops one (`net2_refused`). Decoding from a client is bounded: 16 levels deep, 4096 names, 1024 shapes, keys of at most 256 bytes, 256 KB a frame (decompressed size included). A message outside these limits is dropped whole, and what it defined is discarded. |
| Request and reply | `Serve(name, fn, rate)` on the server, and `Call(name, fields[, callback])` on a client. In a coroutine, `Call` polls with `coroutine.yield` until the answer, so it works in coroutines resumed by their owner, as GMod's `coroutine.wait` does. A handler may yield and is resumed each tick. An answer is a value, a refusal (`nil, reason`), or `failed` when the handler raises (reported on the server). Calls time out after 10 s. |
| Replicated tables | `Table(name)` gives a proxy the server writes and clients read. Changes go out key by key each tick, before that tick's events, and a joining client gets the whole table. `OnChange(name, id, fn(key, value, old))` runs in both realms. Nested values are replaced whole, not diffed. |
| Introspection | `Stats()` and the console command `net2_print` show, per event: fired, sent, bytes, received and refused. |

## The first user

`round_manager` fires `teamplay_round_win { team }` when a round ends.
Sandcastle's client listener calls the gamemode's `RoundWinAnnounce(winner)`,
which shows the result in the center of the screen where the server's
`PrintMessage` used to. A derived gamemode can override
`GM:RoundWinAnnounce` to present it its own way.

## What is not settled

- **Nothing has been run in game.** The numbers that hold up in tests may
  not hold up there:
  - `UNRELIABLE_BYTES`, `PEER_BYTES_PER_TICK` and the cost of compression
    are unmeasured;
  - so are `IsFirstTimePredicted` outside prediction and how
    `EntityIndex` treats the world and `NULL`.

  Check them on the dev server (`dev.reload` can't reload a shared module,
  so use `dev.run` or a map change).
- **Entities a client hasn't received yet** decode as `NULL`, as GMod's
  `net.ReadEntity` does. Sending an entity before it is in the client's PVS
  loses it.
- **A client's Lua refresh drops the events in flight.** The client says
  hello again and both sides start their dictionaries over. Tables are
  resent; one-off events are not.
- **Tables go to every ready client.** There is no per-team table yet.
- **Wetsands' `WS.Events`** (32 `Fire` sites, `Transact`/`Serve` on
  foundation's transactions) is still v1. Moving it is the next step. Its
  `system_`/`game_` naming rule has no counterpart in net2.
