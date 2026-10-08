# Game events v2: research

**Researcher, 2026-10-08, main at 38eb752.** This file answers the six open
questions in `docs/game-events-v2-handoff.md` §4 step 1, for the design in
`docs/game-events-v2.md`. It gives facts and options only and chooses no
architecture. The scholar's verdicts follow at the end.

**How the tests were run.** The live tests used the dedicated server
(`.devtools/bin/srcds.py`, bottle "Steam"), GMod `VERSION` 260917, on
koth_viaduct, with `sv_allowcslua 0` and **no client connected**. The probes
are in `.devtools/bin/gev2/*.lua`, run by `.devtools/bin/gev2_probe.py`. Raw
outputs are in `.devtools/artifacts/gev2-research/live/`. Wiki pages cached by
the previous researcher are in `.devtools/artifacts/gev2-research/wiki/`. The
client's Lua cache format was checked offline, read-only, with
`.devtools/bin/gmod_lua_cache.py`.

Each section is marked **[live]** (tested on the server), **[offline]**
(checked against files on disk), or **[docs]** (taken from the wiki, source
or issues).

## Summary

1. **A client cannot use `file.Read(path, "LUA")` to hash the copy it ran.**
   For a file that came from the server, `file.Read` returns `nil`. This is
   an open GMod issue that Facepunch confirmed. If the client also has a
   local copy (Workshop, or its own `addons/`), `file.Read` returns that
   local copy instead. With `sv_allowcslua 0`, the client runs the server's
   copy, not its local one. So `file.Read` reads either nothing or the wrong
   file. The client's Lua cache (`cache/lua/<first 40 hex of
   SHA-256(text..NUL)>.lua`) does hold the server's bytes, but the format is
   reverse-engineered and undocumented. On the server, legacy `addons/`
   folders come before everything else in the search path.
2. **No API lists the files the server sends, but wrapping the global
   `AddCSLuaFile` works.** It sees every call this gamemode makes, including
   the entities' no-argument `AddCSLuaFile()`; the caller's source gives the
   file. The sent set is fixed at load and does not depend on lazy loading:
   `init.lua` sends every feature's client parts up front. Today that is
   **191 files (967 KB)**, not about 360. 49 of the 98 entity files send
   themselves; GMod sends no entity files automatically.
3. **A server refresh is not one thing.**
   - Refreshing a gamemode file reached through `include` (`shared.lua`,
     `wetsand/*`) reruns the whole gamemode, including `init.lua`, Sandbox and
     every `AddCSLuaFile`. `OnReloaded` fires twice.
   - Refreshing a file loaded with `CompileFile` (all of `foundation/` and
     every feature part) is an "Unhandled Lua Refresh": nothing reruns and
     no hook fires.
   - Refreshing an entity reruns that file alone.
   - GMod's author describes the client side as "server reloads, then
     messages clients". I could not observe it without a client.
4. **Net limits.**
   - A message holds 65,533 bytes of payload (65,536 with the 3-byte header).
     Writes past that are dropped silently: no error, and the message still
     sends.
   - `WriteDouble` costs 64 bits. Other measured costs: `WriteFloat` 32,
     `WriteEntity` 13, `WriteVector` 42 to 54 (lossy), `WriteAngle` 54, and
     `WriteString` 8 per byte plus 8.
   - Unreliable sends have no documented hard size limit.
5. **`debug.getinfo(fn, "S").source` is the real mount path:**
   `@addons/sandcastle/gamemodes/sandcastle/gamemode/...` for every way this
   gamemode loads code, and `@gamemodes/sandbox/...` or `@lua/...` for GMod's
   own files. `short_src` is cut at 127 characters, so use `source`. The
   path form a client sees for server-sent files was not observed.
6. **Hashing is cheap. Reading is what costs.** For the 191 sent files on the
   server:

   | Step | Time |
   |---|---|
   | `util.CRC` | 2.6 ms |
   | `util.MD5` / `util.SHA1` | about 2.6 ms |
   | `util.SHA256` | 8.5 ms |
   | `file.Read` of the 269 files | 114 to 164 ms |
   | Decompressing and hashing the files' compressed text (the cache route) | 27 ms |
   | 191 `file.Exists` misses in the `GAME` path | 463 ms |

   All times are under Wine.

## 1. Can client Lua hash the copy of a file it actually ran?

**Answer.**

- **`file.Read(path, "LUA")` on a client does not return the server-sent
  copy.** For a file the server sent, with no local copy on the client,
  `file.Read` and `file.Open` return `nil`. `file.Exists` and `file.IsDir`
  return true for the same path. If the client also has a local copy of the
  file (a Workshop subscription, or a folder in its own `addons/`),
  `file.Read` returns that local copy. With `sv_allowcslua 0` that copy is
  not the one the client ran.
- **Which copy a client runs.** With `sv_allowcslua 0` (the default, and this
  server's setting), `include` and `CompileFile` run the copy the server
  sent, even if a local copy exists. Only with `sv_allowcslua 1` does
  `include` "try to load local client file" first. So a Workshop copy on a
  client shadows the server's copy only when the server allows client Lua.
- **Shadowing order within one machine.** The `LUA` search path for the
  server state (`lsv`), as `path` prints it here, is:
  1. legacy `addons/<name>/lua/` and `addons/<name>/gamemodes/`;
  2. `garrysmod/workshop/lua/` and `garrysmod/workshop/gamemodes/`;
  3. `garrysmod/lua/`;
  4. `garrysmod/gamemodes/`.

  Content first in the list wins. A developer copy in a legacy addon folder
  (as `addons/sandcastle` is here) therefore shadows a Workshop or
  base-folder copy on the server, and the server sends whichever copy won.
  Where a mounted Workshop `.gma` sits was not observed, because this server
  runs `-noworkshop`. Community guides put legacy folders above local `.gma`
  files, and those above Workshop `.gma` files.
- **The client's Lua cache holds the server's bytes.** Each server-sent file
  the client compiles is stored as `garrysmod/cache/lua/<name>.lua`:
  - `<name>` is the first 20 bytes, in hex, of SHA-256(text + NUL);
  - the file is a 32-byte header (the full SHA-256 of text + NUL), then
    `util.Compress`'s LZMA stream of text + NUL.

  The server can compute the same name: `util.SHA256(text .. "\0"):sub(1,
  40)` gave the same value as Python for `shared.lua`.

  Options this opens:
  - a client checks `file.Exists("cache/lua/" .. name .. ".lua", ...)` for
    the names the server sends;
  - or it reads an entry (path `GAME` or `MOD`), decompresses it and hashes
    it.

  Both rest on a format that is undocumented and reverse-engineered by third
  parties. The cache also keeps entries across sessions (here, 5290 of the
  5374 date from 2026-09-19). A hit therefore shows that the client has
  compiled that text at some time, not that it ran it in this session.

**Evidence.**

- [docs] Facepunch/garrysmod-issues
  [#1798](https://github.com/Facepunch/garrysmod-issues/issues/1798)
  ("file.Read() fails to read Lua files clientside when they do not truly
  exist clientside"):
  - opened 2015-02-22 and still open;
  - sohpeach: "The decompressed contents of the Lua files don't actually
    exist anywhere on the file system… Use CompileFile";
  - robotboy655 (Rubat), 2024-09-27, asked what the reasons for it were and
    has not acted on it since;
  - the latest comment, 2026-04-03, still hits the bug ("clients couldn't
    read files that `file.Exists` returns true on").
- [docs] [#5719](https://github.com/Facepunch/garrysmod-issues/issues/5719):
  - closed 2024-04-30 as a duplicate of #1798;
  - the reporter says "The issue has been confirmed to exist by Rubat";
  - its client test, on VERSION 240129 (dev branch), gives: `file.Exists
    LUA` true, `file.IsDir LUA` true, `file.Read LUA` **false**, `file.Open
    LUA` **false**.
- [docs] #1798's opening post: reading works "when the addon is mounted via
  SVN or Workshop". That is, `file.Read` reads the local mounted copy.
- [docs] Wiki `include`
  (`.devtools/artifacts/gev2-research/wiki/Global.include.txt`): "This
  function will try to load local client file if `sv_allowcslua` is
  **1**."
- [docs] Wiki File_Search_Paths: `"LUA"` "automatically selects `lcl`, `lsv`
  or `LuaMenu`", and "Content from paths that appear first will override
  content from paths that appear last."
- [live] `path` on the server: `.devtools/artifacts/gev2-research/live/path.txt`,
  lines 8 to 21 (the `--- LUA ---` block, in the order above).
- [live] `sources.txt`: on the server, `file.Read` of
  `sandcastle/gamemode/shared.lua` through `LUA`, through `lsv`, and through
  `GAME` (`gamemodes/…` and `addons/sandcastle/gamemodes/…`) all return
  1535 bytes, `sha256 a4c6b4607fe7e1b9…`, which matches `shasum` of the file
  in the repo. Through `lcl`, `file.Read` returns `nil` on a dedicated
  server.
- [offline] `python3 -I .devtools/bin/gmod_lua_cache.py verify` over the
  operator's client cache: "entries 5374; name == sha256(text+NUL)[:20]:
  5374; header == sha256(text+NUL): 5374; unreadable: 0".
- [docs] The layout claim comes from djsime1/gluapack:
  - `src/pack.rs` lines 425 to 442: SHA-256 of the chunk plus `[0u8]`,
    first 20 bytes;
  - `src/gluapack.lua` lines 160 to 181: "Skip 32 bytes (SHA256 header)",
    then `util.Decompress`, and "Lua files do not show up in here until they
    are compiled".
- [live] Server: `util.SHA256(file.Read("sandcastle/gamemode/shared.lua",
  "LUA") .. "\0"):sub(1, 40)` printed `44122893fca9a7f534dce6b1d6938dec464ee74e`,
  the same as Python's `sha256(text+b"\0")[:20]`
  (`live/rcon_replies.txt` and this session's output).
- [live] A dedicated server writes nothing into `cache/lua`: 0 entries were
  newer than its start. The cache is the client's alone.

**Confidence.**

| Claim | Confidence |
|---|---|
| `file.Read` returns `nil` for server-only files on the client | High: two issues, Rubat's confirmation, a 2026 report. Not run here. |
| `file.Read` returns the local copy when one exists | Medium-high: implied by #1798 and by how `lcl` mounts. Not run here. |
| With `sv_allowcslua 0` the client runs the server's copy | Medium: one wiki sentence. Not run here. |
| Server-side search order | High: live. |
| Cache naming and layout | High for the files on this machine: offline, 5374 of 5374. Low as a stable contract. |

**Unknowns, and the client test that would settle each.**

- These cannot be observed on a dedicated server alone. A client must join
  it: the operator's GMod in the "Steam" bottle, with the operator's consent,
  never the "Team Fortress 2" bottle.
- Test: put a marker file in the gamemode, then on the client compare
  `file.Read("sandcastle/gamemode/<file>", "LUA")` with and without a local
  copy of the addon in the client's `addons/`. Repeat under both
  `sv_allowcslua` values, and record which copy the marker shows ran.
- Whether a client compiles every server-sent file into `cache/lua` when it
  runs, including when a local copy exists: check that each sent file's
  name is present after joining.
- Whether `CompileFile` on a client (used by `WETSAND.require` and the
  feature loader) follows the same server-copy rule as `include`.
- Where a mounted Workshop `.gma` sits in the `LUA` path. Run `path` on a
  client or server that mounts the addon from the Workshop.

## 2. How can the server list the files it sends clients?

**Answer.**

- **GMod has no Lua API for the sent list.** The engine keeps it in the
  `client_lua_files` string table, which only a binary module
  (`gm_stringtable`) can read.
- **This gamemode's sent set has three sources, all calling the global
  `AddCSLuaFile`:**
  1. `init.lua`'s walks: `foundation/` recursively, each feature's `sh.lua`
     and `cl.lua`, and `wetsand/`'s `sh_` and `cl_` files;
  2. `shared.lua` and `cl_init.lua` by name;
  3. 49 entity and weapon files that call `AddCSLuaFile()` with no argument.
     The other 49 entity files never call it, and GMod does not send them:
     the folders sent automatically are only `lua/autorun/` (and its
     `client/`), `vgui/`, `postprocess/`, `matproxy/` and `skins/`. This
     addon has no `lua/` folder, and no `effects/`.
- **Total: 191 files, 966,822 bytes.** That is 2 entry files, 108 in
  `foundation/`, 16 feature parts, 16 `wetsand/` modules and 49 entities.
  The handoff's "about 360" does not match the tree at 38eb752.
- **A wrapper sees every call.** Installed before the calls (on the server,
  in the live test), a wrapper around the global logged each of them with its
  caller:
  - 188 calls per gamemode refresh: 46 are Sandbox's, and 142 are ours.
    The 142 matches the offline count of `init.lua`'s walks exactly;
  - the entity's no-argument form, as `AddCSLuaFile | nil |
    caller=@addons/sandcastle/gamemodes/sandcastle/entities/entities/merasmus.lua:9`.

  What a wrapper must do itself:
  - resolve paths: relative to the caller's folder (`init.lua` passes
    `foundation/x.lua`, Sandbox passes `cl_init.lua`), and `nil` means the
    caller's own file;
  - turn the caller's mount path (`addons/sandcastle/gamemodes/…`) into a
    `LUA`-relative name;
  - ignore files that are not ours (Sandbox's 46);
  - not wrap twice: a gamemode refresh reruns `init.lua`, which repeats
    every call (both refreshes logged the same 188).
- **Reusing `init.lua`'s walk instead** is exact for the gamemode's 142 files
  (2 + 108 + 16 + 16), because the walk *is* the send. It misses the 49
  entities, which send themselves. To cover them it would need a second rule,
  such as "every file under `entities/` that calls `AddCSLuaFile`", which is
  a text scan, not what ran.
- **Lazy loading does not change the sent set.** `init.lua` sends every
  feature's client parts at start-up, whichever features the map loads
  (`init.lua:16-30`). On koth_viaduct the server loaded only `rounds`,
  `capture`, `koth` and `gamemode`, but all 16 parts were sent. What lazy
  loading changes is which sent files a client *runs*: a feature's parts run
  on the client only after `feature_load`.
- **A late `AddCSLuaFile` raises no error.** Called after start-up on an
  existing file, it returned silently. On a missing file it errored
  "Couldn't find". Whether a late call reaches clients is unknown. A Steam
  Workshop discussion (its date not checked) says Lua "cannot be added after
  everything has been initialized anymore because of the new datapack
  feature".

**Evidence.**

- [offline] Repo:
  - `addon/gamemodes/sandcastle/gamemode/init.lua`: lines 1-2 (entry
    files), 8-14 (the foundation walk), 19-30 (feature client parts), 32-33
    (`wetsand/` `sh_` and `cl_`);
  - `grep -L AddCSLuaFile` over `entities/`: 49 of 98 files lack it;
  - no entity uses a folder layout.
- [live] `.devtools/artifacts/gev2-research/live/reload_report.txt`: 188
  `AddCSLuaFile` lines with callers in each of the two gamemode refreshes
  (lines 1-221 and 222-442); line 443 is the entity's no-argument call. Wrapper: `.devtools/bin/gev2/reload_arm.lua`.
- [live] `sources.txt`: "loaded features | rounds,capture,koth,gamemode".
- [live] `live/rcon_replies.txt`: the late `AddCSLuaFile` replies.
- [docs] Wiki `AddCSLuaFile` (cached `Global.AddCSLuaFile.txt`): the list of
  folders sent automatically, and "You can add up to **8192** files. Each
  file can be up to **64KB** compressed (LZMA)."
- [docs] glua/gm_stringtable `example/GetLuaFileContents.lua`: reads
  `stringtable.Get "client_lua_files"`, which needs a binary module.
- [docs] Steam Workshop discussion on the datapack
  (https://steamcommunity.com/workshop/filedetails/discussion/287012681/3099012755245201379):
  a search-result summary, not read in full.

**Confidence.**

| Claim | Confidence |
|---|---|
| The wrapper sees every call in this gamemode, with callers | High: live. |
| The 191 count | High: offline count against `init.lua`'s rules. |
| GMod sends no entity files automatically | Medium-high: from the wiki's list; not observed from a client. |
| What a late call does for clients | Low. |

**Unknowns.**

- Whether the engine really sends exactly the files `AddCSLuaFile` accepted.
  A client test would settle it: compare the client's
  `cache/lua` names after joining with the server's list of
  `util.SHA256(text .. "\0"):sub(1, 40)`.
- Whether a late `AddCSLuaFile` (for example, from a feature loaded mid-map)
  reaches clients that are already connected, or only later joiners.
- Whether another addon on a real server wraps `AddCSLuaFile` too. The
  wrappers would chain, and the order of addon loading would decide which
  one sees what.

## 3. Lua autorefresh: when the server reloads a file, in what order does the client receive it, and does `OnReloaded` fire on both realms?

**Answer.**

**Server, tested live with `lua_refresh_file`.**

| Kind of file | What a refresh does | Hooks |
|---|---|---|
| A gamemode file reached by `include` (`shared.lua`, `wetsand/sh_events.lua`) | Reruns the whole gamemode from its root: `init.lua` (every `AddCSLuaFile` again), `DeriveGamemode` (all of Sandbox's `init.lua`), `shared.lua`, every `wetsand/` file, then `sv_` files | `GM:OnReloaded` fires **twice**: when Sandbox re-registers (the base-class branch of `gamemode.Register`), then when sandcastle does |
| A file loaded with `CompileFile`: everything in `foundation/` (`WETSAND.require`) and every feature part (`FeatureFiles:Run`) | `Unhandled Lua Refresh: [NAME:addons/sandcastle/gamemodes/sandcastle/gamemode/foundation/teams.lua] [TYPE:!UNKNOWN]`. Nothing reruns, and the wrapped `CompileFile` logged no calls. A full gamemode refresh does not rerun these either: `WETSAND.require` keeps `package.loaded`, and `WETSAND.FeatureLoader` is kept on purpose (`sh_core.lua:58-60`) | None |
| An entity file | Reruns that file alone | None in the `OnReloaded` hook. GMod's `scripted_ents.Register` calls `ENT:OnReloaded` on that class's live entities |

`lua_refresh_file` paths: gamemode files need the `gamemodes/…` form. The
`LUA`-relative form `sandcastle/gamemode/…` gets `lua/` put in front and
fails.

**Client, from docs only.** Garry Newman's 2012 post on the design says the
server:

1. loads the changed file and runs its type-specific reload;
2. updates the datapack, "so that clients joining the server after this
   point will get the updated files";
3. "send[s] a usermessage to all clients with the changes", which each
   client applies with its own `HandleLuaFileChange`.

So the documented order is **the server first, then the clients**, with a
window in which the two run different code. On the client, the
`OnReloaded` hook fires from the client's own `gamemode.Register`, so it is
realm-local: each realm fires its own, once its own copy has rerun. Nothing
says the client's fires at the same time as the server's.

**Whether autorefresh runs here at all.** The wiki's Auto_Refresh page says
"It doesn't work on OSX". The operator's server runs the Windows build
under CrossOver on macOS, and reaches the addon through a symlink. I did not
test whether saving a file triggers refresh here, because that would mean
editing addon code. Only `lua_refresh_file` was tested.

**Evidence.**

- [live] `.devtools/artifacts/gev2-research/live/reload_report.txt`:
  - lines 1-221 come from refreshing `sh_events.lua`, with `OnReloaded` at
    lines 61 and 221;
  - lines 222-442 come from refreshing `shared.lua`, with `OnReloaded` at
    lines 282 and 442;
  - line 443 comes from refreshing `merasmus.lua`.
- [live] `live/rcon_replies.txt`: the "Unhandled Lua Refresh" lines for
  `foundation/teams.lua` and `features/capture/sv.lua`.
- [docs] Facepunch/garrysmod `garrysmod/lua/includes/modules/gamemode.lua`,
  `Register` (lines 20-35 at the fetched revision): it calls
  `Call("OnReloaded")` once when the current gamemode re-registers, and once
  when its BaseClass does.
- [docs] `garrysmod/lua/includes/modules/scripted_ents.lua`, about lines
  86-117: `entity:OnReloaded()` for each live entity of the class and of
  classes based on it.
- [docs] Wiki `GM:OnReloaded` (cached): "It seems that this event can be
  triggered more than once for a single refresh event." garrysmod-issues
  [#1205](https://github.com/Facepunch/garrysmod-issues/issues/1205) (2014)
  reports double calls on both realms.
- [docs] https://garry.net/posts/auto-refresh (2012-08-10): the
  server-then-usermessage order, and "whenever a file is included() we store
  its parents file". That explains why `include`d files reload from their
  root and `CompileFile`d ones do not.
- [docs] Wiki Auto_Refresh (cached `Auto_Refresh.txt`): "doesn't work on
  OSX", and "doesn't work with dynamically included / AddCSLuaFile'd
  content".

**Confidence.**

| Claim | Confidence |
|---|---|
| Server behaviour by kind of file | High: live. |
| Order on the client | Medium-low: one 2012 design post. |
| `OnReloaded` is realm-local and fires per realm | Medium: from the source. |
| Autorefresh on save under CrossOver | Unknown. |

**Unknowns, and the client test that would settle them.**

- Test: connect a client and add an `OnReloaded` logger with `SysTime()` and
  `RealTime()` on both realms. Then:
  1. `lua_refresh_file` a gamemode `sh_` file and a `cl_` file, and record
     which realm logs first and how far apart;
  2. refresh a feature's `cl.lua`, and see whether the client reports
     "Unhandled" and whether its cache gains the new text while the old code
     keeps running;
  3. save a file with no other change, to see whether autorefresh fires
     under CrossOver at all.
- Whether a server refresh of a `CompileFile`d client file still updates the
  datapack and messages clients, even though neither side reruns it.

## 4. Net limits

**Answer.**

**Message size [live].**

- A message carries at most **65,533 bytes** of payload. `net.BytesWritten`
  counts the 3-byte header, so it reads 65,536 at the limit.
- A write that would cross the limit is **dropped silently**, with no Lua
  error. `net.Broadcast` still succeeds, and later smaller writes can still
  fit. Writing 70 × 1 KiB, for example, stopped at 64,515 bytes.
- The library therefore cannot count on GMod to raise anything. To raise
  `too_large` it has to compare `net.BytesWritten()` with 65,536 itself, or
  work out the size before writing.

**What each write costs [live], from `net.BytesWritten` before and after.**

| Write | Bits |
|---|---|
| empty message (header) | 24 |
| `WriteDouble` (any value) | **64** |
| `WriteFloat` | 32 |
| `WriteUInt(v, n)` / `WriteInt(v, n)` | n |
| `WriteBool` | 1 |
| `WriteString(s)` | 8·#s + 8 (`''` = 8, `'cpname'` = 56) |
| `WriteEntity` | 13 (`MAX_EDICT_BITS`; `WritePlayer` uses 6) |
| `WriteVector` | 42 to 54, depending on value; lossy |
| `WriteAngle(Angle(10,20,30))` | 54 |
| `WriteNormal` | 3 for (0,0,1) |
| `WriteData(16 bytes)` | 128 |

**Other limits [docs].**

- `WriteVector` keeps one decimal digit (5 bits of fraction), and components
  beyond ±16384 are "irrecoverably altered".
- `WriteString` stops at the first NUL byte ("The input will be terminated
  at the first null byte"). A Lua string containing `"\0"` arrives cut
  short.

**Unreliable sends [docs].** There is no documented hard size limit for an
unreliable send beyond the 64 KB message limit.

- Unreliable data goes into the same packet after the reliable data. When a
  packet is too large, "the unreliable data is discarded first", whole: "no
  truncation of data halfway".
- The reliable buffer holds about 256 KB, and overflowing it kicks the
  client.
- Each transmit carries at most 7 fragments of 256 bytes, and the engine
  uses 4 by default (`net_maxfragments`).
- Around 12 kb/s of unreliable data the buffer is reported to overload.
- Nothing I read gives a datagram size above which a single unreliable
  message is always dropped. **Insufficient evidence for a number.**

**Evidence.**

- [live] `.devtools/artifacts/gev2-research/live/netcost.txt` (probe
  `.devtools/bin/gev2/netcost.lua`) and `live/rcon_replies.txt` (the
  70 × 1 KiB and the 65,530-byte cases).
- [docs] Wiki `net.Start`: "Each net message has a length limit of 65,533
  bytes (approximately 64 KiB) and your net message will error and fail to
  send if it is larger than this." The live test found no error on the
  server; with no client connected, a failure on the receiving side could not
  be seen.
- [docs] Wiki Networking_Usage (cached), lines 292-346: "64kb (65535 bytes -
  3 bytes used internally)", the 256 KB buffer, fragments, and unreliable
  behaviour.
- [docs] Wiki Net_Library_Usage, lines 332-343: unreliable discarded first,
  all-or-nothing.
- [docs] Wiki `net.WriteVector`, `net.WriteString`, `net.BytesWritten` ("This
  will include 3 extra bytes").
- [docs] Facepunch/garrysmod `garrysmod/lua/includes/extensions/net.lua`,
  lines 52-60: `WriteEntity` writes `MAX_EDICT_BITS`.

**Confidence.**

| Claim | Confidence |
|---|---|
| Bit costs and the silent drop on the server | High: live. |
| Unreliable behaviour | Medium: wiki only. |
| An unreliable size number | None. |

**Unknowns, and the client test that would settle them.**

- What a client does on receiving a message that hit the limit, since the
  dropped writes leave a message that ends early. With a client connected,
  send a filled message and decode it; with `developer 1`, watch for
  overflow warnings.
- The largest unreliable message that reliably arrives. With a client and
  `net_graph`, send unreliable messages of 200, 500, 1000, 1200, 2000 and
  4000 bytes, 100 of each, and count arrivals at idle and under load.

## 5. `debug.getinfo` source paths in GMod

**Answer [live, server].**

- `debug.getinfo(fn, "S").source` is `@` plus the path relative to
  `garrysmod/`, as the file is really mounted. That is **the same for every
  way this gamemode loads code**:
  - `include`: `init.lua`, `shared.lua`, `wetsand/sh_core.lua`,
    `sh_events.lua`;
  - `CompileFile`: `foundation/*` through `WETSAND.require`, features
    through `FeatureFiles:Run`, or a direct call;
  - GMod's entity and weapon loader.
- The forms seen:

  | Code | `source` |
  |---|---|
  | This gamemode (legacy addon folder) | `@addons/sandcastle/gamemodes/sandcastle/gamemode/<rel>` and `@addons/sandcastle/gamemodes/sandcastle/entities/{entities,weapons}/<file>` |
  | Base gamemode | `@gamemodes/sandbox/gamemode/init.lua` |
  | GMod's Lua | `@lua/includes/modules/hook.lua` |
  | `CompileString(code, name)` and `RunString(code, name)` | `@` + name (`@x/y.lua`, `@wetsand_tests/gev2/sources`) |

- One way to find a call site's feature is to match a suffix after
  `/gamemode/`: `features/<name>/…`, `foundation/…`, `wetsand/…`, or
  `/entities/`. That works whatever the prefix is (`addons/<folder>/gamemodes/`,
  `gamemodes/`, or a `.gma` mount, whose form was not observed).
- `short_src` is cut at **127 characters**, with a `...` prefix that keeps
  the tail. A path of 166 characters showed as 127. The longest real path,
  92 characters, came through whole. `source` is never cut.
- `debug.getinfo(level, "S")` inside a wrapper reaches the caller's file as
  well (question 2).

**Evidence.**

- [live] `.devtools/artifacts/gev2-research/live/sources.txt` (probe
  `.devtools/bin/gev2/sources.lua`): every line quoted above.
- [live] The truncation check came back through RCON in this session:
  `93 @addons/…/scenario/control_points.lua`, `92 addons/…`, and `166 127
  .../d/d/…`.
- [docs] Wiki Structures/DebugInfo (cached): `source` is "The path to the
  file where the passed function is defined prepended by an @", and
  `short_src` "May be truncated if the source path is long."

**Confidence.** High for the server: live. **The client is not observed.**

**Unknowns, and the client test that would settle them.**

- What `source` a client reports for a file it got from the server, which
  would have no `addons/` folder of its own. It may be
  `@gamemodes/sandcastle/gamemode/…`, or the server's mount path, or
  something else.
- What a client reports when the addon is mounted from a Workshop `.gma`.
- Test: with a client connected, run
  `debug.getinfo(WETSAND.Events.Fire, "S").source` and the same for a
  feature view and an entity. Do it once with no local copy and once with
  one.

## 6. The cost of hashing the sent files at client join, `util.CRC` versus `util.SHA256`

**Answer [live, server, under Wine].** The numbers are the best of 5 rounds;
they agreed across two server runs.

| Work | 191 sent files, 967 KB | 269 files, 1.42 MB |
|---|---|---|
| `util.CRC` | 2.6 ms | 3.9 ms |
| `util.MD5` | 2.5–2.6 ms | 3.8 ms |
| `util.SHA1` | 2.6 ms | 3.9 ms |
| `util.SHA256` | 8.4–8.6 ms | 12.5–12.9 ms |
| `file.Read` of all 269 | n/a | 114–164 ms |
| `file.Read` + `util.SHA256` of the sent files, one pass | 126–163 ms | n/a |

At about 360 files of the same average size, `util.SHA256` would take about
16 ms and `util.CRC` about 5 ms.

- **Reading the files costs 10 to 60 times more than any hash.** On a client
  the reads matter less than they seem, because `file.Read` cannot read
  server-sent files at all (question 1).
- **Format.** `util.CRC` returns a decimal string (CRC32, for example
  `3154434689`). `util.SHA256` returns 64 hex characters, `MD5` 32 and
  `SHA1` 40. CRC32 is not collision-resistant, so it can collide by chance
  across hundreds of files. It is unsafe only against someone crafting
  collisions on purpose.
- **The cache route on a client.** These are server measurements over the
  same 191 texts:

  | Step | Time |
  |---|---|
  | Computing the 191 cache names | 8.6 ms |
  | 191 `file.Exists("cache/lua/<name>.lua", "GAME")` misses | **463 ms**: the `GAME` path searches every mount and VPK, under Wine |
  | `util.Decompress` of the 191 compressed texts (346 KB) | 17.9 ms |
  | `util.Decompress` + `util.SHA256` | 26.6 ms |

  A narrower path id (`MOD`, as luaviewer uses) was not timed.

**Evidence.**

- [live] `.devtools/artifacts/gev2-research/live/hashing.txt` (the second
  run; the first is in this session's output) and `live/cachecost.txt`.
- Probes: `.devtools/bin/gev2/hashing.lua` and
  `.devtools/bin/gev2/cachecost.lua`.

**Confidence.** High for relative costs. Medium for absolute ones: the server
runs under Wine on macOS, and a native Windows client would differ.

**Unknowns.**

- Costs on a real client, and with `MOD` instead of `GAME` for cache
  lookups.
- Whether a client's file lookups during join (the spawn-in frame) add to a
  visible hitch.

## Risks for the spec

These are places where the findings bear on `docs/game-events-v2.md`. They
are stated as risks, for the scholar's verdicts; none of them is decided
here.

**§4, "the client hashes the copy it actually loaded" with `file.Read(path,
"LUA")`.**

1. **As written, this cannot be built.** On a client, `file.Read` returns
   `nil` for server-only files, so the check would compare nothing. Where a
   local copy exists (the very Workshop-shadowing case §4 names), it returns
   the local copy, which with `sv_allowcslua 0` is not the copy that ran.
   The check would then report a stale file that is not stale.
2. **The threat model shifts.** With `sv_allowcslua 0` the engine itself
   makes clients run the server's bytes, so a Workshop copy cannot shadow on
   the client. Shadowing happens on the **server**, where a legacy folder
   wins over other copies, and clients then get whatever the server
   resolved. The client-side cases that remain:
   - `sv_allowcslua 1` with a local copy;
   - a refresh that reached one side only (the order is server first, then
     a message to clients);
   - files loaded with `CompileFile`, which never rerun on refresh (next
     risk).
3. **"Again for any file the server reloads (`OnReloaded`)" does not hold
   for most files.**
   - All of `foundation/` and every feature part load through `CompileFile`,
     and their refresh is "Unhandled": nothing reruns and no `OnReloaded`
     fires.
   - A full gamemode refresh does not rerun them either (`package.loaded`
     and the kept `FeatureLoader`).
   - So after an edit on disk, the server's `file.Read` hash describes the
     file on disk, not the code the server or its clients are running.
   - `OnReloaded` also fires twice per gamemode refresh, so a hash exchange
     tied to it would run twice.
4. **Options that exist (not chosen):**
   - the client's Lua cache, named and headed by SHA-256(text + NUL) and
     undocumented: an existence check, or a read, decompress and hash;
   - relying on the engine's guarantee when `sv_allowcslua` is 0, with the
     server knowing its own convar;
   - hashing each file's text at the moment it is run, on the server, from
     what `CompileFile` or `include` was given. GMod exposes no text there,
     so this would mean a wrapper that reads the file just before compiling
     it. That still reads disk, which can differ from what was compiled if
     the file changes in between.
5. **The size of the job.** The always-loaded set is 142 gamemode files plus
   49 entities that send themselves, not about 360. Entities are not in
   §4's always-loaded list (`wetsand/`, `foundation/`), so §4 has no rule
   for them.

**§3, encoding, against the net limits.**

6. **`too_large` needs the library's own check.** GMod drops writes past
   65,533 bytes silently and still sends the message. "Raises `too_large`
   at `Fire`" works only if the library checks `net.BytesWritten()` (which
   counts the 3-byte header, so the cap is 65,536) or works out the size
   first.
7. **`WriteString` cuts at NUL.** The spec's string tag would silently cut
   any field string containing `"\0"`. The round-trip tests in §6 step 3
   would catch it only if they include such a string. `WriteData` with a
   length is the option without that limit.
8. **`WriteVector` and `WriteAngle` lose precision.** One decimal digit;
   components beyond ±16384 are corrupted. "Round trips of every value kind"
   cannot expect exact equality for these. Positions on large maps could
   pass 16384 units.
9. **Entities.** The spec gives an entity 16 bits; GMod's own `WriteEntity`
   uses 13 (`MAX_EDICT_BITS`). Either works. 16 wastes 3 bits per entity.
10. **The cost of self-description.** Every message carries 24 bits of
    header, 24 bits of id, a key table (8 bits per character plus 8 per
    key), and a type tag per value (width not given in §3), against
    `WriteDouble`'s 64 bits for any non-integer.
    - Example: `teamplay_point_captured` (`cp`, `cpname`, `team`) would carry
      keys of 3 + 7 + 5 = 15 bytes before any value.
    - That is fine for reliable events. For `unreliable` snapshots, the
      measure that matters is the wiki's guidance that unreliable data is
      dropped whole when a packet is too full, and no safe size is
      documented. The spec's "small enough for one datagram" has no number
      behind it yet.
11. **Tracing a site to its feature through `debug.getinfo`.** This works on
    the server with a suffix match after `/gamemode/` or `/entities/`. The
    client's path form is unobserved. Keying on the `addons/sandcastle/…`
    prefix would break on any other install (`gamemodes/`, Workshop).

## Product questions

- **Should `sv_allowcslua 1` servers be supported for the code check?** With
  it off, the engine already makes clients run the server's code. With it
  on, clients may run their own local copies. Whether the operator cares
  about mixed copies on servers that allow client Lua decides how much of
  §4 is needed.
- **May a client be connected for testing?** Several answers here are
  client-side and stay unverified without one: the operator's GMod in the
  "Steam" bottle joining the dedicated server. That needs the operator's
  consent and a time when it won't disturb his play.

## Verdicts (scholar)

**Scholar, 2026-10-08, main at 38eb752.** I judged the spec's riskiest claims
against the research above. Where a verdict hinges on a primary source, I
read that source myself:

- garrysmod-issues #1798 and #5719, read through the GitHub API;
- Facepunch/garrysmod `includes/extensions/net.lua`;
- garry.net's auto-refresh post;
- the wiki's `string.dump` and `jit.version` pages;
- the Source engine's `engine/net.h` and `net_chan.cpp`, from a public
  mirror (nillerusr/source-engine; not GMod's own fork);
- small LuaJIT experiments, run locally on LuaJIT 2.1, outside GMod.

I ran no game server and touched no addon code.

| # | Spec claim | Verdict |
|---|---|---|
| 1 | §4: the client hashes the copy of each file it really loaded | **Unsound.** Client Lua can't read the text it ran. Move the check to the server, as drift between what the server loaded and what it now serves, and rest the rest on the engine's own guarantee. |
| 1a | Alternative: read the client's `cache/lua/` | **Unsound as a mechanism.** It's undocumented, it keeps entries across sessions, and it costs 463 ms on `GAME`. Use it only as a test instrument. |
| 1b | Alternative: hash the compiled function (`string.dump`) | **Unsound.** The bytecode format differs between GMod's 32-bit and 64-bit builds, and it isn't guaranteed to be deterministic. |
| 1c | Alternative: a server-sent manifest of hashes | **Unsound on its own.** The client has nothing to compare it against, except the cache (1a). |
| 1d | Alternative: the engine's guarantee plus a server-side drift check | **Sound with changes.** This is the replacement I recommend. Two client tests must confirm its premises (T1, T2 below). |
| 2 | §3: self-describing encoding against the net limits | **Sound with changes.** The shape holds. Strings, vectors, angles, entities, `nil`, lists, keys, size checking, unreliable sends and decoding client input all need rules the spec lacks. |
| 2a | `double` via `WriteDouble`, and zig-zag ints | **Sound.** Keep 64-bit doubles. Fix the int range to [-2^31, 2^31-1]. |
| 2b | `too_large` raised at `Fire` | **Sound with changes.** The library must compute the size itself, and must validate before local dispatch, whoever the recipients are. |
| 2c | `unreliable` "small enough for one datagram" | **Sound with changes.** It needs a named cap below Source's 4000-byte unreliable stream. Nothing uses it today, so the number can wait for a client measurement. |
| 3 | §4's file set ("about 360") and its "when" list | **Sound with changes.** There are 191 files. Entities and the entry files must be in the set, the sent set is fixed at start-up, and the list comes from the `AddCSLuaFile` wrapper. |
| 4 | §4: "again for any file the server reloads (`OnReloaded`)" | **Unsound.** `OnReloaded` never fires for `CompileFile`d files and fires twice for gamemode refreshes. |
| 5 | §4: "an event belongs to the feature whose file holds its `Fire` site, recorded when the site first runs" (via `debug.getinfo`) | **Sound with changes.** A tail call `return Events.Fire(...)` attributes the event to the wrong file (I tested this), and the boss entity's forwarding wrapper already breaks the one-literal-site rule. Match the path suffix, and forbid both in the scan. |
| 6 | Hashing cost at join | **Sound for hashing**: under 10 ms with any hash. **Unsound if the check rereads the files on every join**: 126–163 ms on the server's main thread under Wine. |
| 7 | §1 and §2: `Fire` runs local listeners "at once", then carries the event, with `bad_fields` and `too_large` "at `Fire`" | **Sound with changes.** Encode and validate first, then dispatch. Otherwise a bad event half-happens, and an empty server hides `bad_fields`. |

### 1. §4: hashing the copy the client really loaded

**Verdict: unsound as written. The mechanism can't be built, and the threat
it targets mostly can't happen.**

*What I confirmed myself.*

- **#1798 is open.** The 2015 answer to it, which nobody at Facepunch has
  revised since, is "The decompressed contents of the Lua files don't
  actually exist anywhere on the file system… Use CompileFile".
- **A 2020 commenter sums up the stance:** "devs apparently don't want
  clients reading server's client code". Rubat's only reply (2024-09-27) asks
  why anyone would want this, and a report from 2026-04-03 still hits it.
- **#5719 was closed with `state_reason: not_planned`.** That is a little
  stronger than the research's "duplicate". Its reporter says Rubat
  confirmed the bug on Discord.
- **So this behaviour is intended and won't change.** A design that needs
  `file.Read` of a server-sent file on the client is built on something GMod
  has chosen not to provide.

*Why the threat mostly can't happen.* There are two halves.

- **The client runs what the server sent.** With `sv_allowcslua 0`, the
  client runs the server's datapack text. `include` tries a local file only
  when `sv_allowcslua` is 1.
- **The server sends what it resolved.** On the server, the legacy folder
  wins the search path, so the copy it sends is the copy it runs.

So in steady state the server's code and every client's code come from one
place, and §4's Workshop-shadowing case can't arise on the client. What's
left:

- **A refresh, the developer's loop.** Garry's post gives the order: the
  server updates the datapack, then messages clients. Nothing in it makes the
  datapack update depend on the file's kind. So after an "Unhandled Lua
  Refresh" of a `CompileFile`d feature file, it is likely, though not
  observed, that:
  - the server keeps running the old code;
  - clients already running it keep the old code too;
  - any client that joins, or loads that feature later, compiles the new
    text.

  That is real drift, and nothing hashed on the client would see it. The
  server can see it, by comparing the text it loaded with the text it now
  serves.
- **`sv_allowcslua 1` with a local copy.** No Lua-visible mechanism can see
  which copy the client ran. That's a product question (below).

*The alternatives.*

- **The cache route (1a): reject as a runtime mechanism.**
  - Its format is reverse-engineered.
  - A hit proves the text was compiled at some time, not that it's running
    now: 5290 of 5374 entries predate the session.
  - The lookup costs 463 ms through `GAME` under Wine.
  - It's an excellent test instrument, though. After a client joins, compare
    its `cache/lua` names with `util.SHA256(text .. "\0"):sub(1, 40)` for
    the server's list. That proves what the engine sent (T1, T2).
- **Bytecode via `string.dump` (1b): reject.** I checked:
  - `string.dump` exists in GMod.
  - Stripped bytecode doesn't depend on the chunk name (equal for
    `@addons/…` and `@gamemodes/…`).
  - But the wiki's `jit.version` page gives LuaJIT 2.0.4 for 32-bit GMod
    and 2.1.0-beta3 for the x86-64 branch, and the two dump different
    formats.
  - On modern LuaJIT 2.1, dumping one chunk with a record-table constructor
    gave three different byte strings in three runs. Template-table order
    follows the string hash, which newer builds seed.
  - A server and a playtest client on different branches would always
    mismatch.
- **A server-sent manifest (1c).** It's only a way to carry hashes. The
  client still can't produce its own hash to compare against.
- **Hashing at include time (1d): sound on the server only.**
  - The server can hash exactly what it compiles: its loaders read the text
    and compile it with `CompileString(text, name)`, keeping the chunk name,
    which `debug.getinfo` showed is preserved as `@` + name.
  - For client-only files, the `AddCSLuaFile` wrapper can hash the text
    when it sends it.
  - Comparing those references with what the server now serves catches the
    developer's-loop drift.
  - Whether "now serves" equals "the current disk text" depends on T2.

*What the stop rules need.* §4's rules for which events a stale file stops
(listener files, `Fire` files, critical events stopping their feature) don't
care how staleness was found. They are a pure function from a set of stale
files to the events they stop, so they can be built and unit-tested in phase A
with the stale set injected. Only detection waits on T1 and T2.

**Must be tested with a client. I recommend doing it before the plan; it is
one short session.**

- **T1.** With `sv_allowcslua 0` and a local copy of the addon in the
  client's `addons/`, with a marker in one file:
  - which copy the client runs, for both `include` and `CompileFile`
    (`WETSAND.require`, the feature loader);
  - that the client's `cache/lua` names match the server's list after
    joining.

  If T1 fails, the engine guarantee is false and §4 needs a different
  premise.
- **T2.** `lua_refresh_file` a feature's `cl.lua`, and also save it if
  autorefresh fires under CrossOver. Then check:
  - whether the connected client gains the new cache entry;
  - whether a client that joins next, or loads that feature next, runs the
    new text.

  This decides whether "the disk text differs from what the server loaded"
  means "stale for later loaders", or is a false alarm.

If the operator can't connect a client before the plan, the architect can
still plan §4. In that case:

- build the stop rules as a model, in phase A;
- have detection report but not stop until T1 and T2 pass;
- make T1 and T2 phase-E acceptance criteria.

### 2. §3: the encoding against the net limits

**Verdict: sound with changes.** Type tags with a key table are the right
shape: there's no layout to disagree on, and a dropped field reads as `nil`.
The changes:

- **Numbers (2a): sound.**
  - Keep `WriteDouble` for non-integers. It's exact, and v1's 32-bit `Float`
    loses precision on growing values like `CurTime()`.
  - The int rule must say [-2^31, 2^31-1]: zig-zag(2^31) needs 33 bits, and
    "within ±2^31" admits it.
  - In LuaJIT, `math.floor(math.huge) == math.huge` is true, so the range
    test, not the floor test, must keep `inf` out of `int`.
  - `-0` becomes `0`. That's harmless, but a test should name it.
- **Strings: change.** `WriteString` stops at the first NUL. The spec must
  pick one of these:
  - a length prefix plus `WriteData`: exact for any Lua string, costing 8
    more bits than `WriteString`. This is my preference, because it keeps
    local dispatch's promise;
  - `bad_fields` on a string containing `"\0"`.

  Silent truncation is not acceptable. A round-trip test must cover `""`
  and a string containing `"\0"`.
- **Vectors and angles: change.**
  - `WriteVector` keeps 5 fraction bits and corrupts components beyond
    ±16384, and `WriteAngle` is lossy too.
  - A Source `Vector` and `Angle` hold 32-bit floats, so three `WriteFloat`s
    carry each one exactly: 96 bits, against 42–54.
  - The spec should say vectors and angles arrive exactly, at 96 bits, or
    else state the precision and range and test within tolerance. I'd
    choose exact: positions are the only place the format would otherwise
    change values silently.
- **Entities: change.**
  - GMod's own `net.WriteEntity` writes `0` for an invalid entity, and
    `ReadEntity` returns `Entity(0)`, the world. So NULL and the world
    become one value (I read this in `net.lua`).
  - TF2-style events (`attacker` = world on fall damage, against no
    attacker) need them apart. Encode NULL distinctly, either as its own tag
    or as index + 1.
  - 13 bits (`MAX_EDICT_BITS`) is enough; 16 is harmless.
  - The spec should also say what a listener gets for an entity its client
    doesn't have yet (outside its PVS): `NULL`. Listeners must expect it.
- **`nil`, lists and keys: change.** I checked these in LuaJIT:
  - `{x = nil}` has no key `x`, so a record can never carry a `nil` tag.
  - `#{1, nil, 3}` is 1, so a list with a hole loses its tail.

  The spec must say:
  - an absent key is how a field is `nil`;
  - a list is a table whose keys are exactly 1..n, and anything else that
    isn't a string-keyed record is `bad_fields`;
  - drop the `nil` tag.

  It must also cover:
  - **non-string keys**, such as `{[2] = …, [3] = …}` keyed by team. Today
    no event needs them (v1 has no map type), so making them `bad_fields`
    costs nothing now;
  - **tables with a metatable**, such as `Color`: these would arrive as
    plain tables. Make them `bad_fields`, or add a tag;
  - **the empty table**: say it decodes as `{}`.
- **Widths: change.** §3 gives no width for the type tag, the key index, or
  list and record counts. 13 tags fit in 4 bits. The spec must name each
  width and the error raised when one overflows, such as "more than 255
  keys".
- **Size (2b): change.**
  - GMod drops writes past the limit silently (research §4).
  - The encoder knows every write's width, so the pure model can compute
    the exact bit count. `too_large` then becomes a unit-testable rule:
    payload over 65,533 bytes, which is `net.BytesWritten()` over 65,536.
  - The adapter can assert that `BytesWritten` matches the prediction, to
    catch the model and adapter drifting apart.
  - The 256 KB reliable buffer is a second limit. The wiki says overflowing
    it disconnects the client, and it matches Source's `NET_MAX_PAYLOAD` of
    288,000. The ready-time fan-out ("anything a joining client needs is
    fired to it then") must stay well under it.
- **Unreliable sends (2c): change.**
  - In the Source engine mirror, `CNetChan` sizes the unreliable stream at
    `NET_MAX_DATAGRAM_PAYLOAD` = 4000 bytes, commented "maximum unreliable
    payload size" (`net_chan.cpp:518`, `net.h:59`). So no unreliable message
    over about 4000 bytes can ever arrive. That's medium confidence for
    GMod's fork.
  - The spec must give unreliable events a named cap, enforced as
    `too_large`, well below that.
  - No event uses `unreliable` today (grep: the option exists only in
    `foundation/events.lua`), so the number can be measured with a client
    in phase E, or when the first unreliable event arrives.
- **Decoding what a client sends: a missing rule.**
  - A self-describing message from a client is untrusted structure. A
    forged count of 2^32 makes the server loop on a message that ends
    almost at once, and deep nesting overflows the stack.
  - The spec must say the server:
    1. reads the id;
    2. checks `Accept` and the token bucket before decoding anything;
    3. bounds every count by `net.BytesLeft()`;
    4. caps nesting depth;
    5. rejects unknown tags and out-of-range key indices.
  - A malformed message is the client's fault: dropped, and logged once
    per player.

### 3. The file set and the "when" list

**Verdict: sound with changes.**

- **The set.** It's 191 files, not about 360, and §4's "when" list names only
  `wetsand/` and `foundation/`. The set must also include:
  - the two entry files;
  - the feature parts, which are sent at start-up whatever the map loads;
  - the 49 entity files that send themselves.

  One of those entities, `halloween_base_boss.lua`, fires events.
- **The list.** The `AddCSLuaFile` wrapper is the right source: the live test
  shows it sees every call, entities' no-argument form included. It must:
  - resolve paths;
  - keep only this gamemode's files;
  - not wrap twice when a gamemode refresh reruns `init.lua`.
- **No late sends.** The spec should state that the sent set is fixed at
  start-up and that no file is `AddCSLuaFile`d later. A late call's effect is
  unknown, and lazy loading changes what runs, never what's sent.

### 4. Refresh and `OnReloaded`

**Verdict: unsound.** "Again for any file the server reloads (`OnReloaded`)"
is false for every `CompileFile`d file: all of `foundation/` and every
feature part. Those get "Unhandled Lua Refresh", with no hook and no rerun.

- `OnReloaded` fires only for refreshes of `include`d gamemode files, and
  fires twice for each.
- With detection on the server (§1 above), the triggers become:
  - client ready;
  - `feature_load` on a client;
  - a gamemode refresh, deduplicated, after which the server takes fresh
    references because both realms reran.
- The window between the server and clients rerunning is accepted, and the
  spec should say so.

### 5. Working out a site's feature through `debug.getinfo`

**Verdict: sound with changes.**

- **Path form.** Matching the path after the `gamemode/` or `entities/`
  segment works for the server's form. It probably works for the client's
  unobserved form too: it holds whether the client reports `@gamemodes/…`,
  `@addons/…` or a `LUA`-relative path. Make it a phase-A unit test over all
  three forms, plus a phase-E live assertion on a client. It doesn't block
  the plan.
- **Tail calls.** I tested this with LuaJIT 2.1: if the function that holds
  a site calls `return Events.Fire(...)`, `debug.getinfo(2, "S")` inside
  `Fire` reports the *caller's* file (`aiwar/sv.lua`), not the site's
  (`capture/sv.lua`). That breaks attribution exactly where §1 sends code:
  "calls a function holding that site". `tests/events_sites_test.lua` must
  reject `return Events.Fire(` and `return Events.Listen(`.
- **The boss wrapper.** `entities/entities/halloween_base_boss.lua:62`
  defines `ENT:FireGameEvent(name, fields)`, which calls `Events.Fire(name,
  fields)` with a non-literal name. Sixteen calls in six `foundation/` files
  go through it: `npc/merasmus.lua` 7, `npc/eyeball_boss.lua` 4,
  `npc/headless_hatman.lua` 2, and one each in `npc/halloween_boss.lua`,
  `payload/race.lua` and `rounds/payload.lua`.
  - Under §1 that's one illegal site, and under §4 all those events would
    belong to an entity file, which is no feature.
  - Phase B must turn each into a literal site in its own file.
  - §4 must say what feature, if any, a site in `entities/` belongs to. I
    suggest treating it like an always-loaded file.

### 6. The cost of hashing at join

**Verdict: hashing is sound; rereading at every join isn't.**

- **Hashing.** All 191 files take 2.6 ms with `util.CRC` and 8.5 ms with
  `util.SHA256`. Either is fine. CRC32 is enough when a file is compared
  with its own earlier text: the chance of an accidental collision is 2^-32
  per edit. SHA-256 is needed only to match cache names, which happens in
  tests.
- **Reading.** A full reread costs 126–163 ms of server frame under Wine,
  about 10 ticks at 66 tick, on every client's join. The spec must require
  that the check never stalls a tick. The ways to meet that are the
  architect's call: compare `file.Time` first (its cost is unmeasured, which
  makes it a phase-A measurement), or spread the reads over frames.

### 7. Order inside `Fire`

**Verdict: sound with changes.**

- **The problem.** §1 runs the local listeners "at once, … then carries the
  event", and §3 raises `bad_fields` and `too_large` at `Fire`. If encoding
  comes after dispatch, a bad event has already run its local listeners when
  it raises. And if it encodes only when someone will receive it, an empty
  server, like the research's test setup, never raises `bad_fields` at all.
- **The rule.** Every `Fire` validates and sizes its fields first, whoever
  the recipients are, and dispatches only once they pass. The one exception
  is a client-only event, which never needs encoding, but it should still be
  validated the same way so that bugs surface in single-player.

### Required spec changes

These are recommendations for the architect to fold into the plan; the spec
itself is unchanged.

1. **§4, "What is compared": replace it.** Suggested wording: "With
   `sv_allowcslua 0`, GMod runs on each client the text the server sent, so a
   copy can't differ when it is sent. Client Lua can't read server-sent
   files, so the client hashes nothing. The server keeps a reference hash for
   each file it sends: the text it compiled, for files it runs, and the text
   it sent, for client-only files. It compares the references with the text
   it now serves when a client is ready, when a feature loads on a client,
   and after a gamemode refresh. A file that has changed since is stale for
   the clients that will run the new text."
2. **§4, the threat sentence: correct it.** A Workshop copy shadows on the
   **server** (the legacy folder wins), not on the client. Name
   `sv_allowcslua 1` as the case the check can't see, and say what the server
   reports then (product question 1).
3. **§4, "When": replace "(`OnReloaded`)".** The triggers are client ready,
   `feature_load` on a client, and a deduplicated gamemode refresh. State
   that `CompileFile`d files never rerun on refresh.
4. **§4, the file set: name it.** The two entry files, `foundation/`,
   `wetsand/` `sh_` and `cl_` files, every feature's client parts, and the
   self-sending entity files: 191 today, listed by the `AddCSLuaFile`
   wrapper. The set is fixed at start-up, and no late `AddCSLuaFile` is
   allowed.
5. **§4, the stop rules:** keep them, stated as a pure function from a set of
   stale files to the events they stop, independent of detection.
6. **§4, cost:** the check never stalls a server tick, so a full reread of
   the sent files at join is not allowed.
7. **§4, "An event belongs to": add rules.** Attribution matches the path
   after the `gamemode/` or `entities/` segment, never a prefix. The site
   scan rejects tail-called `Fire` and `Listen`. Say which feature an
   `entities/` site belongs to.
8. **§1, the site rules: add a rule.** "No wrapper may forward a name to
   `Fire`". The boss's `FireGameEvent` and its 16 callers are migrated in
   phase B.
9. **§2, values: rewrite them.**
   - A record has string keys; an absent key is a `nil` field.
   - A list has keys exactly 1..n.
   - Non-string keys, holes, and tables with a metatable are `bad_fields`.
   - `{}` decodes as `{}`.
   - An entity field may arrive as `NULL` when the client doesn't know the
     entity.
10. **§3, the tag table: revise it.**
    - Drop the `nil` tag.
    - int covers [-2^31, 2^31-1].
    - Strings get a length prefix plus `WriteData`, or `bad_fields` on NUL.
    - Vector and angle are three `WriteFloat`s each, exact.
    - An entity is 13 bits with NULL kept apart from the world.
    - Name the widths of the tag, the key index and the counts, and the
      error each overflow raises.
11. **§3, `too_large`:** the encoder computes the exact size before writing.
    The cap is 65,533 payload bytes (`net.BytesWritten()` ≤ 65,536), and an
    unreliable event has its own named cap well below 4000 bytes. Add a
    sentence keeping the ready-time burst to one client under the reliable
    buffer.
12. **§1 and §3, order:** `Fire` validates and encodes before it dispatches
    locally, whether or not anyone will receive the event.
13. **§2, "Clients to the server": add the decoding rule.** Check `Accept`
    and the rate by id before decoding. Bound counts by `net.BytesLeft()`,
    cap nesting depth, and reject unknown tags and out-of-range key indices,
    as the client's fault.
14. **§6, step 3, the tests: extend them.** Round trips of `""`, a string
    containing `"\0"`, 2^31-1 and -2^31, ±2^31 going to double, `inf`, `NaN`
    and `-0`, vectors beyond ±16384, NULL against the world, and `{}`. Size
    tests at the cap and one byte over. Malformed client messages.

**Tests and where they belong.**

- **Before the plan, if the operator agrees:** T1 and T2 (§1 above). They
  decide §4's premise and what its detection means.
- **Phase-A acceptance:**
  - attribution over all three path forms;
  - the size model matching `BytesWritten`;
  - the cost of `file.Time` for 191 files;
  - the stop rules with an injected stale set.
- **Phase E:**
  - the client's `debug.getinfo` form;
  - the unreliable cap measured with a client;
  - the staged stale-file check, built on T2's answer.

### Product questions

1. **Servers with `sv_allowcslua 1`: supported or not?** No Lua-visible way
   shows which copy such a client ran. Should the server refuse to run with
   it on, report once that the code check is off, or ignore it?
2. **May the operator's GMod, in the "Steam" bottle, join the dedicated
   server for one test session before the plan (T1, T2)?** If not, §4's
   detection ships report-only until phase E.
3. **How much should §4 do in production?** If T1 holds, divergence occurs
   only in the developer's refresh loop, never on a server that isn't being
   edited. Is stopping events worth it there, or is a reported mismatch
   enough? This decides whether `critical` stays in the spec.
