# Vendored libraries

`gamemode/vendor/` holds other people's GMod Lua, copied in as it was
written. The gamemode reaches it only through `ws/sh_vendor.lua`, which
includes it the first time something asks (`WS.MapFile`, `WS.MapQuery`,
`WS.UseVendored`). Clients are sent every file (`Features.CLIENT_DIRS`).

## Credits

- **Foohy and the Jazztronauts team**: the libraries in
  `vendor/jazztronauts/`, from [Jazztronauts](https://github.com/Foohy/jazztronauts)
  (`gamemodes/jazztronauts/gamemode/lib/`, commit
  `1a813ade43b6b2aabac6bd9e5b8985066eaf9379`). The coding is theirs.
- **ZakBlystone**: `vendor/loaders/bsp3.lua` and `phy3.lua`, from
  [loaders](https://github.com/ZakBlystone/loaders) (MIT, the notice kept in
  each file), as Jazztronauts carries them (`lib/ext/`; its `bsp3` adds
  brush support the Jazztronauts BSP query needs).

## What each is

| File | What |
|---|---|
| `loaders/bsp3.lua` | Source map (.bsp) reader: any lumps, LZMA lumps, the pakfile (`GetPakFiles`, `ReadPakFile`) |
| `loaders/phy3.lua` | Collision model (.phy) reader |
| `jazztronauts/sh_bsp2.lua` | The current map, loaded whole: brushes with windings, leafs, brush models, entities |
| `jazztronauts/sh_bspquery.lua` | Ray traces through the map's BSP tree, brush models and displacements (`map:Trace`); `jazz_debug_bspquery` draws them |
| `jazztronauts/sh_brush.lua`, `sh_poly.lua` | Convex brushes and polygon windings: split, clip, render |
| `jazztronauts/sh_bmodelmap.lua` | Brush model index ↔ the entities that use it |
| `jazztronauts/sh_mdl.lua` | Model (.mdl, .vvd, .vtx) reader and meshes from it |
| `jazztronauts/sh_task.lua` | Coroutine tasks run a slice each Think (`task.YieldPer`) |
| `jazztronauts/sh_mathutils.lua`, `sh_geomutils.lua` | Ray, box, plane and triangle intersections (globals) |
| `jazztronauts/sh_mesh.lua`, `sh_gc.lua` | Pooled meshes freed by the garbage collector |
| `jazztronauts/sh_irt.lua`, `sh_rect.lua`, `sh_scene.lua`, `sh_camera.lua`, `sh_gfx.lua` | Render targets, rectangles, scenes, cameras and debug drawing the above use |

## Left out

Jazztronauts' game itself (snatch, hacking, drugs, unlocks, workshop,
whiteboard, event feed), and what `foundation/core` already has (queue,
tree, graph, matrix, state machine, GMA).

## Changes

Only `sh_bspquery.lua`: its one `/* */` comment is `--[[ ]]`, so
`.devtools/bin/check_lua.sh` can compile it with LuaJIT. Every file starts
with a three-line header naming where it came from.
