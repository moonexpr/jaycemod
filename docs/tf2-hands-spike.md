# TF2 weapons with the player's c_arms: the phase 1 spike

What the models hold, read from the files themselves, and what it decides for the
hands addon (a Sandbox addon: TF2 weapons drawn with the player's own
`player_manager.TranslatePlayerHands` hands, retargeted from the TF2 class arms
skeleton at run time, tuned live). No feature code yet.

## How the names were read

TF2's and GMod's dedicated-server depots (anonymous, apps 232250 and 4020) ship the
same `tf2_misc_dir.vpk` and `garrysmod_dir.vpk` trees as the clients. Only the VPK
directories and the three archives holding these models were fetched
(`tf2_misc_001.vpk`, `tf2_misc_021.vpk`, `garrysmod_002.vpk`), and GMod's shipped
`gamemodes/base` and `lua/` for the hands' own code. `.devtools/bin/mdl_rig.py` reads
studiohdr v48 (bones, attachments, sequences, procedural bones, in-file animation
frames) and checks the retarget offline; every number below is its output.

    mdl_rig.py bones|sequences|attachments|procedural MODEL...
    mdl_rig.py corrections ARMS HANDS
    mdl_rig.py check ARMS ANIMS HANDS [LABEL...]

The models are studio version 48. `c_scout_arms.mdl` is the mesh and skeleton, with
one `$includemodel`, `c_scout_animations.mdl`, holding the 91 animated sequences; its
own 46 sequences besides its reference are `STUDIO_OVERRIDE` (0x800) stubs whose
labels the include resolves. The order the engine merges them in is the engine's:
the addon reads sequences and activities from the entity at run time
(`GetSequenceCount`, `GetSequenceActivityName`), never this list.

## The TF2 Scout arms (`models/weapons/c_models/c_scout_arms.mdl`, 58 bones)

| Index | Bone | Parent | Rest offset (parent space) |
|---|---|---|---|
| 0 | `root` | | (0, 67.31, -5.55) |
| 1, 2 | `bip_collar_L`, `bip_collar_R` | `root` | (±1.45, -2.07, -2.74) |
| 3, 4 | `bip_upperArm_L`, `bip_upperArm_R` | collar | (0, ∓7.95, 0) |
| 5, 6 | `bip_lowerArm_L`, `bip_lowerArm_R` | upper arm | (0, ∓13.12, 0) |
| 7, 8 | `bip_hand_L`, `bip_hand_R` | lower arm | (0, ∓9.52, 0) |
| 28–33 | `bip_thumb_{0,1,2}_{L,R}` | hand, then each other | |
| 34–39 | `bip_index_{0,1,2}_{L,R}` | | |
| 40–45 | `bip_middle_{0,1,2}_{L,R}` | | |
| 46–51 | `bip_ring_{0,1,2}_{L,R}` | | |
| 52–57 | `bip_pinky_{0,1,2}_{L,R}` | | |

Helpers, none of them skinned: `effect_hand_{L,R}`; on `bip_hand_R`,
`vm_weapon_bone`, `vm_weapon_bone_1`…`_7` and `weapon_bone`, `weapon_bone_1`…`_4`
(flag 0x40200: bone merge and attachment); on `bip_hand_L`, `weapon_bone_L`,
`vm_weapon_bone_L`, `_L_1`, `_L_2`. Attachments: `weapon_bone`, `weapon_bone_1`…`_4`,
`effect_hand_R`, `weapon_bone_L`, `effect_hand_L`, `vm_weapon_bone_L`, `_L_1`, `_L_2`.
One body part (`body`, one model): there is no body group to hide the mesh with.

Every arm bone's length runs along local **+Y** (right side) or **−Y** (left); the
elbow and the finger joints hinge about local **X**: over all 90 animated Scout
sequences the elbow's own rotation is a pure X hinge (one exception below), and the
finger joints are within 0.03° of one but for `PASSTIME_ball_catch2` (12°). No arm
bone is translated by any animation: bone lengths are constant, so copying rotations
loses nothing.

## The Scattergun (`models/weapons/c_models/c_scattergun.mdl`)

Bones `weapon_bone` (root, 0x43f00), `weapon_bone_1` at (0, 2.37, 3.77) under it,
`c_weapon_stattrack`. It bone-merges onto the arms by `weapon_bone` and
`weapon_bone_1` (the names match). Attachments, all on `weapon_bone`: `muzzle`,
`eject_brass`, `pedestal_0`, `unusual_0`…`_5`, `icon_camera`. One sequence, `idle`.

`weapon_bone_1` never moves against `weapon_bone` in any `sg_` sequence: there is no
pump stroke to follow. `weapon_bone` is a child of `bip_hand_R` but animated against
it: in `sg_draw` frame 0 the gun is 40 units from the right hand, and through
`sg_reload_loop` the gun turns in the hand, the hand's place on it moving up to 9.7
units. TF2's left hand holds a fixed point on `weapon_bone_1` (3.32, −3.14, 3.16)
through idle and fire, leaves it by up to 5.3 units through the reload loop (2.1 in
`sg_reload_start`), and is back on it by `sg_reload_end` frame 10. So the right hand's
IK weight needs a curve too (0 at the start of `sg_draw`, eased off through the
reload loop), not only the left's.

## Scout sequences and activities (`c_scout_animations.mdl`)

The Scattergun's, at 30 fps unless noted:

| Sequence | Activity | Frames | SWEP activity it stands for |
|---|---|---|---|
| `sg_draw` | `ACT_PRIMARY_VM_DRAW` | 31 | `ACT_VM_DRAW` |
| `sg_idle` | `ACT_PRIMARY_VM_IDLE` | 57, loops | `ACT_VM_IDLE` |
| `sg_fire` | `ACT_PRIMARY_VM_PRIMARYATTACK` | 19 | `ACT_VM_PRIMARYATTACK` |
| `sg_reload_start` | `ACT_PRIMARY_RELOAD_START` | 7 | `ACT_SHOTGUN_RELOAD_START` |
| `sg_reload_loop` | `ACT_PRIMARY_VM_RELOAD` | 16 | `ACT_VM_RELOAD` (a shell) |
| `sg_reload_end` | `ACT_PRIMARY_RELOAD_FINISH` | 16 at 26 fps | `ACT_SHOTGUN_RELOAD_FINISH` |
| `primary_inspect_start`, `_idle`, `_end` | `ACT_PRIMARY_VM_INSPECT_START`, `_IDLE`, `_END` | 45 at 35 fps, 59, 91 | (none in GMod; a command) |

The rest, for the other Scout weapons: `p_*`/`ss_*` (`ACT_SECONDARY_VM_*`, `_2`),
`b_*` (`ACT_MELEE_VM_*`), `wb_*` (`ACT_VM_*_SPECIAL`), `melee_allclass_*`,
`cleave_*` (`ACT_ITEM3_VM_*`), `ed_*` (`ACT_ITEM1_VM_*`), `db_*` (`ACT_ITEM2_VM_*`),
`throw_*`, `spell_*`, `bm_*`, `grapple_*`, the inspects, and `PASSTIME_ball_*`
(`ACT_BALL_VM_CATCH` weighted 100 and 1 across two sequences). TF2's activity names
are the model's; whether GMod's activity list knows them, or registers them as
private activities with ids of its own, was not checked, and does not matter: the
SWEP maps `ACT_VM_*` to a sequence by the activity *name* the entity reports.

## The hands (`models/weapons/c_arms_citizen.mdl`, 43 bones)

`ValveBiped.Bip01_Spine4` (root); per side `Clavicle`, `UpperArm` (6.03 from the
clavicle), `Forearm` (11.69), `Hand` (11.48), and `Finger0`/`01`/`02` (thumb),
`Finger1`/`11`/`12` (index), `Finger2`/`21`/`22` (middle), `Finger3`/`31`/`32` (ring),
`Finger4`/`41`/`42` (pinky); and four procedural bones, `ValveBiped.Bip01_{L,R}_Ulna`
(under the forearm at 5.74) and `ValveBiped.Bip01_{L,R}_Wrist` (at 11.48), skinned
(0x504: always procedural, LOD0 vertices). Each is a quaternion-interpolation bone
driven by the hand, seven triggers at 90° tolerance: the wrist takes the hand's twist
about the forearm, the ulna half of it. `c_arms_dod.mdl` adds
`ValveBiped.Bip01_{L,R}_Elbow` (two triggers, driven by the forearm);
`c_arms.mdl` and `c_arms_hev.mdl` have none. Every hands model includes
`c_arms_animations.mdl` (39 bones: the same without the procedural ones).

ValveBiped arm bones run along local **+X** on both sides and hinge about local
**−Z** (elbow and fingers alike), the 3ds Max biped's convention.

## Rest poses: different axes, and different postures

| | TF2 Scout arms | ValveBiped hands |
|---|---|---|
| Bone length axis | +Y right, −Y left | +X both |
| Elbow and finger hinge | X | −Z |
| Elbow bend at rest | 32.7° | 3.5° |
| Hand against forearm at rest | identity | 90° about the forearm's axis |
| Upper arm / forearm length | 13.12 / 9.52 | 11.69 / 11.48 |

The two rest poses are different postures, not one posture in different axes. A
correction taken as the difference of the rest poses (`inv(R_tf2_rest) · R_hands_rest`)
would carry the 29° of elbow bend and the 90° of wrist twist into every frame. So
each correction is built from the bones' own axes instead, from the rest data of
each skeleton alone: a bone's frame is its length axis (the offset to its child) and
its bend axis (the axis of its child's rest rotation; for a hand, the index→pinky
axis across the palm; for a thumb, the palm normal), and the correction is
`C = F_tf2 · inv(F_hands)`, with `R_hands_world = R_tf2_world · C`. For the upper arm
and forearm it comes out exactly 120° about (1, 1, 1)/√3: a permutation of the axes.

Retargeting all 90 Scout sequences, every frame, onto `c_arms_citizen.mdl`
(`mdl_rig.py check`):

| Measure | Worst |
|---|---|
| Elbow rotation off the hands' hinge, beyond TF2's own | 0.06° |
| Elbow bend lost | 0.00° |
| Finger joint off its hinge, beyond TF2's own | 0.08° |
| Finger curl lost | 0.00° |
| Palm normal against TF2's | 0.03° |
| Hand position against TF2's (upper arms anchored) | 3.28 units in the `sg_` sequences; 16.46 in `secondary_alt1_inspect_end` |

No bone is inverted or stretched: lengths are the hands' own and only rotations move.
The flexion the retarget passes on is TF2's own, including its 8° of finger
hyperextension in `p_reload` frame 23. Two things it passes on faithfully that will
look wrong:

- TF2's `secondary_alt1_inspect_end` frame 74 turns the right elbow 97° off its hinge
  (TF2's skinning hides it). Copied, it will show on the c_arms mesh.
- With the upper arms anchored, the hands' longer forearm leaves the hand up to 3.3
  units from where TF2's is in the Scattergun's sequences: the right hand off the
  grip by that much until IK pins it.

## What this decides

**Drawing the hands: a clientside model of our own, drawn in `SWEP:PostDrawViewModel`,
its bones set by a `BuildBonePositions` callback that copies matrices solved before
the draw.** The SWEP sets `UseHands = false`. Checked in GMod's shipped Lua:
`gmod_hands.lua` parents the stock hands to the viewmodel with `EF_BONEMERGE`, and
the TF2 arms have no ValveBiped bone, so the merge matches nothing; base
`GM:PostDrawViewModel` draws the hands itself (`hands:DrawModel()`) only when
`wep.UseHands`, *before* it calls `wep:PostDrawViewModel`. Driving the stock hands
would mean a callback on a server-made entity remade every spawn
(`ply:SetupHands`), run for every weapon, a solve squeezed into `PreDrawPlayerHands`,
and an engine bone merge with nothing to merge whose interplay with the callback
cannot be checked here. Our own model puts the whole frame in one function in a
fixed order: viewmodel bones (already set up when it was drawn), the c_model
bone-merged onto it, the grip targets read off it, the solve, the hands drawn, the
debug drawn. What the stock hands gave for free is a few lines: model, skin and body
groups copied from `ply:GetHands()` (so a gamemode's `PlayerSetHandsModel` still
decides, `TranslatePlayerHands` the fallback), `GetPlayerColor` on the model (the
`PlayerColor` proxy calls `ent.GetPlayerColor` when it exists, checked in
`lua/matproxy/player_color.lua`), the cull mode flipped for `ViewModelFlip`.

**The rest poses come from the entities, not the files.** No Lua API gives a bind
pose, but on every model checked, sequence 0 is it: only the root differs (studiomdl's
up-axis turn), every other bone within 0.1°. So the rebuild sets up a hidden copy of
each model at sequence 0 and reads parent-relative transforms from its bone
matrices; the root, which the corrections never read, does not matter.

**The procedural bones are ours to solve.** The callback overwrites the forearm and
hand; the ulna and wrist the engine computed from the old ones would stay behind, and
their vertices with them. Their triggers are only in the `.mdl`, so the rebuild reads
them from the file (`file.Open(model, "rb", "GAME")`, one struct per bone found with
`BONE_ALWAYS_PROCEDURAL`) and the frame evaluates them as `DoQuatInterpBone` does.

## Not verified

- Whether GMod runs the `BuildBonePositions` callback before or after it evaluates
  procedural bones. Solving them ourselves is right either way.
- That `file.Open` with `"GAME"` reads a model out of a mounted TF2's VPKs.
- How to hide the TF2 arms mesh while its bones still set up: `render.SetBlend(0)`
  around the viewmodel draw is the usual way (SWEP Construction Kit's), untested here;
  `PreDrawViewModel` returning true may skip `PostDrawViewModel` too, also untested.
- `SendViewModelMatchingSequence` and the sequence numbering on a listen server
  with TF2 mounted only on the host.
- Everything here is the dedicated-server depots' copy of the content. The client's
  `tf2_misc` VPKs should be the same files; not compared.
