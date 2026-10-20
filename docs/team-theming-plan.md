# Team theming: RED and BLU NPCs in TF2's illustrative style

**Status:** built through Phase 2, with Phase 3's tooling and the faction
track done; see [Status](#status) for what remains, which needs the game.

The design of a standalone addon, `addons/teamtint/`. It recolors NPCs for
RED or BLU and shades them with the terms of TF2's character model
(Mitchell, Francke, Eng, *Illustrative Rendering in Team Fortress 2*,
NPAR 2007). The look is tuned live with a toolgun mode that works in
Sandbox and in Sandcastle, which derives from Sandbox (`shared.lua:9`), so
STools load in both.

## What is already true (read before the plan)

- **The war's soldiers already wear player models.** `ws_drg_combine`
  (`models/player/combine_soldier.mdl`, `combine_soldier_prisonguard.mdl`),
  `ws_drg_rebel` (`models/player/group03/*`), and the kits in
  `features/aiwar/sv_enlist.lua` (`police.mdl`, `alyx.mdl`, `barney.mdl`)
  all use them. The model swap the request asks for is done for DrGBase
  soldiers. What remains is the vortigaunt medic (`models/vortigaunt.mdl`:
  no player version ships with HL2 or GMod) and Sandbox's HL2 NPCs.
- **HL2 NPCs cannot wear player models.** `npc_combine_s` and `npc_citizen`
  run on NPC activities that player models do not have; swapped, they
  T-pose or stall. That is why the war runs on DrGBase. In Sandbox the addon
  therefore themes HL2 NPCs **on their own models**, so the catalog is keyed
  by **material path**, not model path. Player and NPC variants mostly share
  their sheets (verify in Phase 0), so one entry covers both.
- **The `PlayerColor` proxy only recolors where a texture carries a tint
  mask** (`$blendtintbybasealpha`, mask in the base alpha). As far as I know,
  that is the citizen player models' clothing, and **not** the Combine,
  metrocop, Alyx or Barney models. This is unverified (the dev server was
  down when this was written). Phase 0 settles it with a script. If it
  holds, "recolor by model parameters" covers only the rebels, and every
  other body needs an authored mask.
- **Multiplicative tint cannot make dark grey armour read red.**
  `$color2` multiplies, and a value of 0.25 times red is still near black.
  TF2's team read comes from **albedo painted for it**, at mid value and
  high saturation in the team areas. For the Combine sheets this means
  baked textures (value-lifted and hue-replaced inside a mask), not a
  runtime multiply.
- **No custom shader is needed for TF2's equations.** Equations 1 and 2 of
  the paper (half Lambert, through an artist 1D warp, plus an ambient cube;
  Phong with a Fresnel term, max'ed with broad rim lobes, plus the
  dedicated up-facing ambient rim) are what VertexLitGeneric's phong path
  implements. It is the shader TF2 shipped, and it is why mounted TF2
  characters render correctly in GMod. The parameters are `$phong`,
  `$lightwarptexture`, `$phongexponent`, `$phongexponenttexture`,
  `$phongboost`, `$phongfresnelranges`, `$rimlight`, `$rimlightexponent`,
  `$rimlightboost` and `$rimmask` (the rim mask is the exponent texture's
  alpha).
- **`screenspace_general`, GMod's custom-shader route, can draw an
  animated character, but it brings none of the engine's lighting.** The
  evidence:
  - CS:GO's source (`materialsystem/stdshaders/screenspace_general.cpp`,
    the 2018 cstrike15 tree) declares the vertex stream as
    `VERTEX_POSITION` (`| VERTEX_COLOR`) plus `$tcsize0..7` texcoords. It
    binds no bone indices or weights, so the GPU cannot skin.
  - Meetric's guide (Example 10) gets around this with **`$softwareskin
    1`**, `$model 1` and `$vertexnormal 1` on the VMT. Studiorender then
    skins that material's mesh **on the CPU**, and the vertex shader only
    applies `cModel[0]`: `SkinPositionAndNormal(0, …)`, then `cViewProj`.
    Animation works, and the cost is CPU time per vertex, per frame, per
    body.
  - The dynamic state sets only `$c0`–`$c4` (pixel constants c0–c4; GMod
    documents c0–c3) and the eye position at c10. No light array, no
    ambient cube, no fog, no flashlight. The shader binds four texture slots
    (`$basetexture`, `$texture1..3`).
  - It always writes depth. You need `$depthtest 1` plus a `DEPTH0` output,
    or `render.OverrideDepthEnable`, around the draw.
  - Its SM3 shaders do not translate through ToGL (Linux/macOS native);
    only SM2.0b does. The GMod wiki also disagrees with itself about
    whether `.vcs` files mount from addon paths or only from
    `garrysmod/shaders/fxc`.

  So a custom character shader is possible, but it must rebuild TF2's
  lighting from what Lua can feed it in about 16 floats. VertexLitGeneric
  already has all of it, on the GPU. That makes the custom shader Phase 5's
  alternative to **baking**, not the base of this work.
- Team state reaches clients as `NW2Int "ws_team"` (`ws/sv_world.lua:196`).
  NPC death ragdolls are clientside, built in `ws/cl_npc_ragdolls.lua`.
  `.devtools/bin/vpk.py` / `tf2_content.py` already read VPKs, so an offline
  bake tool can pull HL2 sheets and TF2 lightwarps without new readers.

## The strongest case against doing this as asked

- **The Combine palette is the paper's BLU.** It is cold, industrial and
  orthogonal (§4.2, Fig. 3); the Resistance's browns and denim lean RED.
  *Decided:* each faction has a **home** team (Combine BLU, Resistance
  RED) and can still fight for either. Two consequences:
  - Every tinted sheet is baked for both teams. The home bake is a light
    touch; the away bake (Combine RED, Resistance BLU) is the heavy recolor
    and the real art cost, and is done second.
  - Home teams and swappable sides are a gamemode change, not the
    addon's: see "Faction assignment" below (built). The addon only ever
    reads the team a body fights for.
- **Lightwarp and rim on photo-sourced HL2 albedo will look like "HL2 with
  rim light", not TF2.** The paper is explicit that the style rests on
  low-noise, hand-painted albedo and exaggerated silhouettes (§4.3, §6).
  The shading terms are the cheap 30%. Set expectations for a v1 that reads
  as team-coded and better grounded, not as TF2. The parts that carry the
  most weight are value contrast in the team areas, and rim light that
  separates the silhouette.
- **The toggle is a tuning aid, not a gameplay feature.** Without a rule,
  painting a Combine BLU in Sandcastle while it fights for RED creates
  false information on the battlefield. In Sandcastle, the team a body shows
  must follow `ws_team` unless a debug override is on, and the override
  must be visible as an override.

## Architecture

The addon knows nothing of Sandcastle. Sandcastle knows two hook names and
one function of the addon. The dependency points one way.

```
addons/teamtint/
  addon.json                                   type "tool"
  lua/includes/modules/teamtint_catalog.lua    pure: material path -> class; class + facts -> strategy; baked texture names
  lua/includes/modules/teamtint_resolve.lua    pure: override, given team, gamemode's team -> RED / BLU / ORIGINAL
  lua/includes/modules/teamtint_tuning.lua     pure: the knobs, scopes, JSON, VertexLitGeneric params per view, VMT text
  lua/autorun/teamtint.lua                     loader; the hooks a gamemode answers
  lua/teamtint/sh.lua                          the modules, the networked override
  lua/teamtint/sv.lua                          the override (tool, teamtint_paint), dupes, the A/B pair
  lua/teamtint/cl_convars.lua                  teamtint_* convars, the tuning (data/teamtint/tuning.json)
  lua/teamtint/cl_materials.lua                CreateMaterial per (team, source material), rewritten live
  lua/teamtint/cl_apply.lua                    SetSubMaterial per body; the sweep; ragdolls
  lua/teamtint/cl_debug.lua                    views, overlay, census, export
  lua/teamtint/cl_panel.lua                    the tool's menu and Utilities > Team Tint
  lua/weapons/gmod_tool/stools/teamtint.lua    the tool
  materials/teamtint/{lightwarp,white,black}.vtf   made by teamtint_bake.py builtins
  materials/teamtint/<team>/<base>.vtf         baked team textures (none yet: they need masks)
addons/sandcastle/.../ws/sh_teamtint.lua       Sandcastle's answers: ws_team, the override gate
tests/teamtint_{catalog,resolve,tuning}_test.lua   the pure modules
tests/teamtint_{client,server}_test.lua        the runtime under stubbed GMod globals (wiring, not drawing)
.devtools/bin/teamtint_bake.py (+ test_teamtint_bake.py)
```

**Representation resolution, per entity, each time it changes**

1. A debug override (`NW2Int "teamtint"`: RED, BLU, ORIGINAL), set by the
   tool, wins. It is shown in the overlay as an override.
2. Otherwise a team given in code (a ragdoll takes its body's).
3. Otherwise `hook.Run("TeamTintTeamOf", ent)` decides. Sandcastle answers
   it from `ws_team` (`ws/sh_teamtint.lua`). Sandbox has no answer, so the
   entity stays ORIGINAL, as its model was made.
4. A material that matches nothing in the catalog is left alone; the
   overlay names it in red.

**Why `SetSubMaterial` with runtime `!` materials, client-side**

- One `CreateMaterial` per (team, source material) means that moving a
  slider rewrites that material, and every body using it updates at once.
  That is the fine-tuning loop the request is after.
- Client-side only: a server-set `!name` may arrive before the client
  has created the material, and would show the error checkerboard.
- Costs and hazards, named:
  - `SetModel` (the kits swap models) clears sub-materials, so
    `cl_apply` re-applies when the model path changes. That needs a
    cheap per-entity check: `EntityNetworkedVarChanged` for the override
    and a 0.5 s sweep (which also notices a full update that cleared the
    sub-materials), not a Think per NPC.
  - Ragdolls: Sandcastle's `cl_npc_ragdolls.lua` calls
    `TeamTint.CopyTo(body, ragdoll)` when the addon is present. Sandbox's
    engine ragdolls use `CreateClientsideRagdoll(owner, ragdoll)`.
  - `RenderOverride` with `render.MaterialOverrideByIndex` was
    considered and rejected. It fights DrGBase's own `Draw`, and does
    not follow the body to its ragdoll.

**Tint strategies (per catalog material, decided in the game from the material's facts)**

| Strategy | When | How |
|---|---|---|
| `proxy` | a tintable class whose material has `$blendtintbybasealpha` (its tint mask in base alpha) | runtime `$color2` = team colour × `tint_gain`; no texture work |
| `baked` | a tintable class without a mask, whose team texture exists | `$basetexture` swapped for `materials/teamtint/<team>/<base>.vtf` |
| `shade` | skin and hair, or a tintable material not baked yet | TF2's shading terms, its own colours; the overlay marks the unbaked ones red |
| `none` | eyes, teeth, any shader but VertexLitGeneric | left as it is |

The `accent` strategy (self-illuminated eye lenses in the team colour) was
not built: it needs the census to say which materials hold the lenses.

## Debug and tuning parameters (client convars, all `teamtint_*`)

Each knob is live: changing it rewrites every runtime material at once. The
knobs show the values of the scope being edited (`teamtint_scope`: `all`, or
one class: `armor`, `cloth`, `gear`, `hide`, `skin`, `hair`); a class
holds only the values set for it and takes `all`'s for the rest. The team
colours are the same for every class. The tuning is saved per player to
`data/teamtint/tuning.json`. An addon may ship one at
`data_static/teamtint/tuning.json`, which is the starting point.

| Group | Convars (defaults) |
|---|---|
| Team colour | `teamtint_red_color` (184 56 59), `teamtint_blu_color` (88 133 162): TF2's Team Spirit; `teamtint_tint_gain` (1; above 1 lifts dark cloth) |
| Diffuse (Eq. 1) | `teamtint_lightwarp` (`teamtint/lightwarp`, our Fig. 7 warp; a mounted TF2 warp's path works too) |
| Specular (Eq. 2, left) | `teamtint_phong_boost` (1), `teamtint_phong_exponent` (20; ignored where the material has its own exponent texture), `teamtint_fresnel` (0.3 1 8) |
| Rim (Eq. 2, right) | `teamtint_rim` (1), `teamtint_rim_exponent` (4), `teamtint_rim_boost` (2), `teamtint_rim_mask` (1; only where the material has an exponent texture, whose alpha it is) |

Switches: `teamtint_enable` (theme at all), `teamtint_overlay`,
`teamtint_view`, `teamtint_bench_softwareskin`. Commands:
`teamtint_reset_scope`, `teamtint_export`, `teamtint_census`, and on the
server `teamtint_paint red|blu|original|clear` (admins; for modes with no
toolgun).

**Visual debug views (`teamtint_view`)**

| View | What it isolates |
|---|---|
| `0` normal | |
| `1` albedo | the scene unlit (`render.SetLightingMode(1)`): is the team colour in the texture right? |
| `2` tint off | the shading without the team colour or baked texture, to compare against `0` |
| `3` lighting | white albedo: the warp and the ambient cube alone (paper Fig. 6d) |
| `4` spec + rim | black albedo: the view-dependent terms alone (Fig. 6h) |
| `5` value | greyscale of the final image. TF2's rule: the team read must survive desaturation, so RED and BLU must differ in *value* as well as hue |
| `6` silhouette | white albedo times the flat team colour, unlit, no highlights: the read at a distance |

Views 2, 3, 4 and 6 change parameters on the runtime materials (every view
sets the same keys, so leaving one restores them); 1 and 6 also draw the
frame unlit until the HUD; 5 is `DrawColorModify`. The "mask" view first
planned was dropped: a mask lives in a PNG for the bake, not in the game.

`teamtint_overlay 1` labels each themed body: representation, its source
(override / given / team), and each material's class and strategy, with
unbaked and uncatalogued materials in red. It is the first thing to look at
when a body looks wrong.

## The tool (`gmod_tool` mode `teamtint`)

- **Left click**: override to RED. **Right click**: override to BLU.
  **Reload**: clear the override (back to the gamemode's answer).
  **Sprint + left**: spawn a RED and a BLU copy beside the target
  (`prop_dynamic`s in an idle pose, undone together) for an A/B
  comparison.
- **Menu** (also Utilities > Team Tint): the switches, the view, the scope,
  every knob (colour mixers for the team colours), and **Reset this
  scope**, **Copy knobs to clipboard**, **Export** (writes
  `data/teamtint/export/tuning.json` and `<team>/<material>.vmt.txt` per
  themed material; GMod writes only `.txt`/`.json` to `data/`), **Census**,
  and the bench.
- Server side: a gamemode may refuse an override through
  `TeamTintCanOverride`. Sandcastle refuses it to non-admins while the AI
  war is on (an override is false team information in a live match).

## Phases, each with its exit test

**Phase 0: facts (half a day).** These are a script and a screenshot, not
opinions.
- `teamtint_census`: for every model in the war's rosters plus
  `npc_combine_s`, `npc_metropolice`, `npc_citizen` (rebel) and
  `npc_vortigaunt`, list materials and, per VMT, whether it has
  `PlayerColor`, `$blendtintbybasealpha`, `$basemapalphaphongmask`,
  `$phong`, `$rimlight`, `$lightwarptexture`, and what its alpha holds. Run
  it on the dev server (`mcp__gmod__lua_run`), and commit the output to
  `docs/research/teamtint-census.md`.
- Confirm which material paths are shared between player and NPC
  variants.
- Confirm the mounted TF2 lightwarp paths (`models/lightwarps/*`,
  `models/player/pyro/pyro_lightwarp`; names unverified).
- Exit: the strategy column of the catalog is filled from evidence.

**Phase 1: addon skeleton, resolution, shading only.** `catalog`,
`tuning` and `resolve` are written test first. Then `cl_materials` and
`cl_apply` with every body on the shading terms (warp, phong, rim), and
**no recolor** yet. Then the Sandcastle hook and the ragdoll copy.
- Exit: themed war soldiers keep their shading through death, model swap
  and full update; `check_lua.sh` is green.

**Phase 2: tool, convars, views, overlay.**
- Exit: one artist can take a soldier from default to tuned to exported,
  without a map change or a Lua edit.

**Phase 3: recolor.** First the `proxy` path (citizens). Then
`teamtint_bake.py` (built): VPK or file read, mask PNG, then hue-replace
and value-lift inside the mask, then VTF write. VTFs are read and written
by the tool itself (headers by hand, DXT through Pillow's DDS codec), so it
needs neither srctools nor VTFCmd. Hand-painted masks for the Combine sheets, metrocop,
Alyx, Barney and the vortigaunt. Bake order: the home team (Combine BLU,
Resistance RED), then the away team. Auto-generated masks (hue/saturation
threshold) are only a starting point, and look bad as finished masks.
- Exit: at 1500 units, in `teamtint_view 5` (greyscale), a tester names
  the team of every body type correctly.

**Phase 4: ship.** Export the tuning to `data_static/` and the baked
textures to `materials/teamtint/`. Run a GMA via `.devtools/bin/gma.py`.
Measure the memory cost of the baked sheets (two teams × sheets ×
mips) with `ws_analytics_memory`'s client counterpart, or `mat_texture_list`.

**Phase 5 (optional): custom shaders.** There are two independent tracks.

*5a. A team shader for characters, as an alternative to Phase 3's bake.*
Its one real gain is recolor at runtime: hue-replace and value-lift
inside a mask, with no baked textures. That removes the bake tool, the
doubled texture memory, and the re-bake after every colour change. It
would also allow the paper's §7 warp per albedo hue. The design follows
the four texture slots and roughly 16 floats:
- **Textures**: `$basetexture` albedo, `$texture1` normal map, `$texture2`
  packed (R phong exponent, G team mask, B spec mask, A rim mask: our own
  packing, authored with the masks Phase 3 needs anyway), `$texture3`
  lightwarp.
- **Constants**, set per entity in a `RenderOverride` immediately before
  `DrawModel`:
  - a two-term ambient (up and down colours, 6 floats), sampled with
    `render.ComputeLighting` at the body;
  - one key light (direction and colour, 6 floats), from the strongest
    `render.ComputeDynamicLighting` / `util.GetSunInfo`;
  - the team hue and value lift (2 floats), and the rim exponent and
    boost (2 floats).

  That fills `$c0`–`$c3` exactly. The reduction from the paper is fewer
  lights and a two-term ambient instead of the six-term cube.
- **Fog** must be redone in the pixel shader, and TF2 maps use fog
  heavily. **Flashlight and projected textures** are lost. Engine shadows
  are separate materials and are unaffected.
- **Gate, before any shader is written**: put `$softwareskin 1` on
  VertexLitGeneric copies of the war's materials, run 40 soldiers, and
  read `ws_profile` / frame time against the GPU-skinned baseline. If the
  CPU skinning cost is visible at war scale, 5a is dead and baking stands.

*5b. Post-process debug views.* These are low risk and need no skinning:

- a perceptual value view (CIELAB L\* rather than `DrawColorModify`'s
  luma);
- a RED/BLU confusion view that simulates protanopia and deuteranopia. TF2's
  red against blue-grey survives deuteranopia mainly through value, so
  that is a real check;
- a distance blur ("squint") for the read-at-distance test.

Both tracks hinge on one question, answered first: does a `.vcs` mount
from `addons/teamtint/shaders/fxc`, and from a Workshop GMA? If it only
mounts from the game's root `shaders/fxc`, both tracks are for
developers only. The shipped addon then keeps VertexLitGeneric, the
baked textures, and `DrawColorModify`.

## Testing

- **LuaJIT** (`.devtools/bin/check_lua.sh`): the pure modules test first
  (`teamtint_catalog`, `_resolve`, `_tuning`), through `tests/harness.lua`'s
  `T.MODULE_DIRS` as `responserules`' are. `teamtint_client_test` and
  `teamtint_server_test` load the addon under stubbed GMod globals and
  check its wiring: which copy a body wears, knobs and scopes written live,
  views, overrides, the sweep after a full update, ragdolls, the bench,
  export, the tool, `teamtint_paint`, dupes, the permission hook. The
  stubs are not the engine, so they say nothing about how anything draws.
- **Python** (`cd .devtools/bin && python3 -m pytest -q`):
  `test_teamtint_bake.py` on VTFs built in the test: uncompressed and DXT
  round trips, the 7.3 resource layout, mip counts and sizes, the recolor
  inside and outside a mask, value lift, starter masks, the builtins, a
  team bake end to end.
- **In game**: not run. See [Status](#status).

## Faction assignment (gamemode, built)

The war already traded sides when the defenders won (`War:SwapFactions`),
but three things were keyed by team and went wrong after a trade; all are
now the faction's.
- `foundation/aiwar.lua`: `FACTIONS` keyed by faction (`COMBINE`,
  `RESISTANCE`), each with its `home` (BLU, RED). A war seats each on its
  home; `HomeFaction`, `FactionOf`, `War:TeamOf`, and `Sides` for clients.
- `features/aiwar/sv_enlist.lua`: kits by faction. Before, after a trade
  the Combine on RED drew the Resistance's crossbows, crowbars and heroes,
  and its medics the vortigaunt's kit (test: "a soldier's kit is its
  faction's, whichever team the faction fights for").
- `foundation/aiwar/spawns.lua`: HL2 deathmatch spawns by faction (the
  Combine went to `info_player_rebel` after a trade).
- `foundation/kill_feed.lua`: each soldier in its faction's current team,
  from the Combine's team the war publishes (Global2 `ws.aiwar.combine`).
- `ws_drg_*`: default `ENT.Factions` follow home.

Not built: a convar to start a war already swapped (the planned
`aiwar_sides`). The war's own trade on a defenders' win covers "either can
fight for either team"; a convar is a small follow-up if a map should start
with the Combine on RED.

## Decided

1. **Sides**: home teams are Combine BLU and Resistance RED, and either can
   fight for either team (above). Bakes: home first, away second.
2. **Recolor**: bake textures (Phase 3). Run 5a's `$softwareskin`
   benchmark gate alongside, to decide whether the shader route is
   worth reopening.
3. **Scope of v1**: the war's DrGBase soldiers and the vortigaunt.
   Sandbox's HL2 NPCs come after; the catalog is keyed by material so they
   come almost free, but each needs a check in the census.

## Using it

1. **Census** (once, on a client with the content): `teamtint_census`,
   then commit `data/teamtint/census.txt` as
   `docs/research/teamtint-census.md`. Fix any catalog folder or part the
   overlay shows in red.
2. **Tune the shading**: spawn soldiers (or start the war), open the tool's
   menu, pick a scope, drag the knobs; check views 3, 4 and 5. Export.
3. **Paint masks** for each tintable sheet without a tint mask:
   `python3 .devtools/bin/teamtint_bake.py decode <source> sheet.png`, paint
   white where the team colour goes (a starter:
   `teamtint_bake.py mask <source> mask.png --hue 180-260 --sat 0.05-0.6`),
   and keep the mask out of the addon (say `art/teamtint/masks/`): only the
   baked textures ship.
4. **Bake**: `teamtint_bake.py bake <source> <its $basetexture> mask.png
   --tuning tuning.json`, where `tuning.json` is step 2's export, copied
   out of the client's `garrysmod/data/teamtint/export/`. `<source>` is a `.vtf`, or
   `<pak>_dir.vpk:<texture>`. Restart the map (the client caches whether a
   baked texture exists), and the overlay's red "unbaked" goes.
5. **Read at a distance**: view 5 and 6 at 1500 units; adjust
   `--value-bias` / `--saturation` and re-bake.

## Status

Built and tested here (Linux, no GMod): everything above except what
needs the game. Not done, and why:

- **Never run in GMod.** This container has no GMod and no CrossOver; the
  dev server tooling targets the operator's Mac. First run there:
  `teamtint_census`; spawn `ws_drg_combine` and `ws_drg_rebel` and check
  the overlay; paint with the tool; kill one and check its ragdoll; turn
  a knob and watch the bodies change; `teamtint_view 1`..`6`.
- **Things only the game can confirm**: that `GetSubMaterial` returns the
  `!name` it was given (if not, the sweep re-applies every 0.5 s: harmless
  but wasteful); that `ConVar:SetString` works on these client convars;
  that `$lightwarptexture` takes effect on these HL2 sheets (VertexLitGeneric
  reads it on its phong path, which every themed material turns on).
- **Catalog facts**: which sheets carry a tint mask is the census's to say;
  the catalog assumes nothing, so a wrong guess shows up only as a
  strategy in the overlay.
- **Masks and bakes**: art; none shipped. Until then the Combine,
  metrocop, Alyx, Barney and vortigaunt take the shading but not the team
  colour, and the overlay marks them unbaked.
- **The `$softwareskin` benchmark**: `teamtint_bench_softwareskin 1`
  during a 40-soldier war, frame time under `ws_profile`, against `0`.

## Open

1. **Addon name.** `teamtint` is a placeholder.
2. **Download size**: two teams × every tinted sheet, measured in Phase 4.
