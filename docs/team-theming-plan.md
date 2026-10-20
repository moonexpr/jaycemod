# Team theming: RED and BLU NPCs in TF2's illustrative style

A plan for a standalone addon, `addons/teamtint/`. It recolors NPCs for
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
  - Swappable sides is a gamemode change that this addon does not make.
    The faction-to-team binding is hard-wired today in four places:
    `FACTIONS` keyed by team (`foundation/aiwar.lua:81`), the class-to-team
    table in `foundation/kill_feed.lua:13`, each `ws_drg_*`'s default
    `ENT.Factions`, and `KITS` / `MEDIC_KITS` keyed by RED/BLUE in
    `features/aiwar/sv_enlist.lua`. It becomes a faction table with a home
    team plus a per-war assignment (a convar or map setting), with kits
    keyed by faction rather than by team. That is tracked separately as
    "Faction assignment" below. The addon is unaffected: it only ever
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

The addon knows nothing of Sandcastle. Sandcastle knows one hook name and
one function of the addon. The dependency points one way.

```
addons/teamtint/
  addon.json                          type "tool"
  lua/autorun/teamtint.lua            loader: AddCSLuaFile + includes per realm
  lua/teamtint/
    catalog.lua        pure: material path -> { class, strategy, mask, defaults }
    tuning.lua         pure: parameter schema, clamps, defaults, merge, to/from JSON, VMT text export
    resolve.lua        pure: (override, hook answer, model) -> representation (RED/BLU/NONE/ORIGINAL)
    sh.lua             NW2 keys, constants, team palettes (TF2 Team Spirit: RED 184,56,59 / BLU 88,133,162)
    sv.lua             override setter (tool, console), admin gate, persistence of overrides on dupes
    cl_materials.lua   CreateMaterial per (team, source material), live SetFloat/SetVector/SetTexture from tuning
    cl_apply.lua       per-entity SetSubMaterial(i, "!teamtint_...") on NW change, model change, ragdoll copy
    cl_debug.lua       view modes, overlay, A/B and readability aids
    cl_panel.lua       Utilities > Team Tint panel (same controls as the tool, without a tool out)
  lua/weapons/gmod_tool/stools/teamtint.lua
  materials/teamtint/<team>/...       baked VTF/VMT (Phase 3), shipped
  data_static/teamtint/tuning.json    shipped defaults (exported from the tool)
tests/teamtint_catalog_test.lua, teamtint_tuning_test.lua, teamtint_resolve_test.lua
.devtools/bin/teamtint_bake.py (+ test_teamtint_bake.py)
```

**Representation resolution, per entity, each time it changes**

1. A debug override (`NW2Int "teamtint"`: RED, BLU, ORIGINAL), set by the
   tool, wins. It is shown in the overlay as an override.
2. Otherwise `hook.Run("TeamTintTeamOf", ent)` decides. Sandcastle answers
   it from `ws_team` in a ten-line `ws/cl_teamtint.lua`. Sandbox has no
   answer, so the entity stays ORIGINAL.
3. An entity whose materials match nothing in the catalog is left alone.

**Why `SetSubMaterial` with runtime `!` materials, client-side**

- One `CreateMaterial` per (team, source material) means that moving a
  slider rewrites that material, and every body using it updates at once.
  That is the fine-tuning loop the request is after.
- Client-side only: a server-set `!name` may arrive before the client
  has created the material, and would show the error checkerboard.
- Costs and hazards, named:
  - `SetModel` (the kits swap models) clears sub-materials, so
    `cl_apply` re-applies when the model path changes. That needs a
    cheap per-entity check, piggybacked on the NW var proxy and a 1 s
    sweep, not a Think per NPC.
  - Ragdolls: Sandcastle's `cl_npc_ragdolls.lua` calls
    `TeamTint.CopyTo(body, ragdoll)` when the addon is present. Sandbox's
    engine ragdolls use `CreateClientsideRagdoll(owner, ragdoll)`.
  - `RenderOverride` with `render.MaterialOverrideByIndex` was
    considered and rejected. It fights DrGBase's own `Draw`, and does
    not follow the body to its ragdoll.

**Tint strategies (per catalog material)**

| Strategy | When | How |
|---|---|---|
| `proxy` | the sheet already has a tint mask in base alpha (citizen clothing, if Phase 0 confirms) | runtime `$color2` = team colour × artist gain; no texture work |
| `baked` | no mask, or the alpha is taken (`$basemapalphaphongmask`, alpha test), or the area is too dark for a multiply | offline: mask PNG → hue-replace + value-lift inside the mask → `materials/teamtint/<team>/…vtf`; runtime swaps `$basetexture` |
| `accent` | small high-value cues: Combine eye lenses, armbands | `$selfillum` / `$selfillummask` in team colour; the cheapest team read at distance |
| `none` | skin, hair, eyes (`Eyes` shader), teeth | shading terms only; never tinted |

## Debug and tuning parameters (client convars, all `teamtint_*`)

Grouped as the tool panel shows them. Each one is live: a convar change
callback rewrites the runtime materials.

| Group | Convars |
|---|---|
| Team colour | `teamtint_red_color`, `teamtint_blu_color` (r g b), `teamtint_tint_gain` (proxy overbright), `teamtint_bake_preview` (preview a baked team colour by runtime multiply before re-baking) |
| Diffuse (Eq. 1) | `teamtint_lightwarp` (texture path; TF2's own warps when mounted, and our painted ones), `teamtint_halflambert` |
| Specular (Eq. 2, left) | `teamtint_phong_boost`, `teamtint_phong_exponent`, `teamtint_fresnel` (three values for `$phongfresnelranges`) |
| Rim (Eq. 2, right) | `teamtint_rim`, `teamtint_rim_exponent` (`k_rim`), `teamtint_rim_boost`, `teamtint_rim_mask` (on/off, to see what the mask removes) |
| Accent | `teamtint_accent_glow` |
| Scope | `teamtint_scope` (which catalog class the sliders edit: `all`, `armor`, `cloth`, `skin`…); per-class values persist separately |

**Visual debug views (`teamtint_view`)**

| View | What it isolates |
|---|---|
| `0` normal | |
| `1` albedo | unlit base, tinted: is the team colour in the texture right? |
| `2` mask | the tint/bake mask as unlit white-on-black: is the mask clean? |
| `3` lighting | white albedo: the warp + ambient cube alone (paper Fig. 6d) |
| `4` spec+rim | the view-dependent terms alone (Fig. 6h) |
| `5` value | greyscale of the final image. TF2's rule: the team read must survive desaturation, so RED and BLU must differ in *value* as well as hue |
| `6` silhouette | flat team colour, unlit, as a read-at-distance check |

Views 1 to 4 swap textures and flags on the runtime materials (`$basetexture`
→ white, `$phongboost` 0, and so on). Views 5 and 6 are post-process on the
client (`DrawColorModify`, flat material override). None of them touch the
server.

`teamtint_overlay 1` labels each themed body: representation, source
(override / hook / original), strategy per material, and catalog misses
in red. It is the first thing to look at when a body looks wrong.

## The tool (`gmod_tool` mode `teamtint`)

- **Left click**: override to RED. **Right click**: override to BLU.
  **Reload**: clear the override (back to the hook's answer). **Shift +
  left**: spawn a RED and a BLU copy beside the target, posed and frozen,
  for an A/B turntable (Sandbox, or Sandcastle's sandbox mode only).
- **CPanel**: every convar above, the view selector, a palette swatch row,
  and the buttons **Export** (writes `data/teamtint/export/tuning.json` and
  one `<material>.vmt.txt` per edited material; GMod writes only
  `.txt`/`.json` to `data/`, so the bake tool renames), **Reset scope**,
  and **Copy convars** (for pasting into a cfg).
- Server side: overrides need admin in Sandcastle (an override is false
  team information in a live match). In Sandbox they follow the tool's
  usual owner/prop-protection checks.

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
`teamtint_bake.py`: VPK read, mask PNG, then hue-replace and value-lift in
HSV inside the mask, then VTF write. The VTF writer is the open question:
`srctools` is a candidate, or VTFCmd under CrossOver; verify before
committing to it. Hand-painted masks for the Combine sheets, metrocop,
Alyx, Barney and the vortigaunt. Bake order: the home team (Combine BLU,
Resistance RED), then the away team. Auto-generated masks (hue/saturation
threshold) are only a starting point, and look bad as finished masks.
Then the `accent` glows.
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

- **LuaJIT, test first**:
  - `catalog`: lookup by material path, strategy per class, no game nouns
    leaking in.
  - `tuning`: clamps, defaults, merge of per-class values, JSON
    round-trip, VMT text export with exact keys.
  - `resolve`: override beats hook beats original; an unknown team is
    ORIGINAL.
  - These are pure modules under `addons/teamtint/lua/teamtint/`.
    `tests/harness.lua`'s `T.require` roots at the gamemode, so it needs
    a second root (a small harness change), or the tests set
    `package.path`.
- **Python**: `test_teamtint_bake.py` on a synthetic 4×4 VTF and mask.
- **In game**: an `.devtools/bin/ingame` check spawns one of each themed
  body on each team, asserts `GetSubMaterial` per index on a client, kills
  it, and asserts the ragdoll copy.

## Faction assignment (gamemode, separate track)

This change is a prerequisite for showing a faction on its away team in a
real war. It is not a prerequisite for the addon, whose tool can already
paint any body either team.
- `foundation/aiwar.lua`: `FACTIONS` becomes keyed by faction (`combine`,
  `resistance`), each with `home`. `War` takes an assignment of faction
  to team, defaulting to home. `FactionTeam(class)` reads the assignment.
- `features/aiwar/sv_enlist.lua`: `KITS` / `MEDIC_KITS` keyed by faction.
- `foundation/kill_feed.lua`: the team comes from the assignment (or the
  body's `ws_team`), not from a class table.
- `ws_drg_combine` / `ws_drg_rebel` / `ws_drg_vortigaunt`: their default
  `ENT.Factions` follow home. The war already moves enlisted bodies
  (`RelateToFactions`).
- An `aiwar_sides` convar (`home` / `swapped`). Tests:
  `tests/aiwar_*_test.lua` cover both assignments.

## Decided

1. **Sides**: home teams are Combine BLU and Resistance RED, and either can
   fight for either team (above). Bakes: home first, away second.
2. **Recolor**: bake textures (Phase 3). Run 5a's `$softwareskin`
   benchmark gate alongside, to decide whether the shader route is
   worth reopening.
3. **Scope of v1**: the war's DrGBase soldiers and the vortigaunt.
   Sandbox's HL2 NPCs come after; the catalog is keyed by material so they
   come almost free, but each needs a check in the census.

## Open

1. **Addon name.** `teamtint` is a placeholder.
2. **Download size**: two teams × every tinted sheet, measured in Phase 4.
