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
it: in `sg_draw` frame 0 the gun is 40 units from the right hand.

Which hand lets go in the reload, read in the weapon bone's axes (`rig_view.py where`;
this corrects the first version of this note, which had the left hand leaving):

| | TF2 right hand | TF2 left hand |
|---|---|---|
| `sg_idle`, `sg_fire` | (−2.01, 3.52, −6.67), on the grip | (3.32, −0.77, 6.93), on the fore-end |
| `sg_reload_start` | eases off the grip | slides 2 units up the gun to (4.41, 0.00, 8.55) |
| `sg_reload_loop` | leaves the grip, up to 9.7 units, loading shells | holds (4.41, 0.00, 8.55), within 0.2 |
| `sg_reload_end` | back on the grip by frame 10 | back to the fore-end by frame 10 |

So the left hand never leaves the gun: it holds it while the right hand loads. A left
hand "letting go during the reload" is not in TF2's data; the right hand's IK weight is
the one that must ease off through `sg_reload_loop` (and be 0 at the start of
`sg_draw`), and the left hand's grip target moves between two places on the gun rather
than releasing.

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
  grip by that much until IK pins it, the left about 1.3 to 2.1 above the fore-end.

## The TF2 arm mesh has no upper arm

No vertex of `c_scout_arms.mdl` is weighted to `bip_upperArm_*` or the collars: the
sleeve is a straight tube on the forearm, running back past the elbow toward the eye,
so TF2 never shows its elbow bend or its upper arm. The c_arms mesh bends at the elbow
and has an upper arm, so the hands show a pose of the TF2 skeleton that TF2's own mesh
hides; where the animators did not care where the upper arm points, ours will point
there anyway. At the game's framing it stays mostly off screen; in `sg_reload_loop` the
right upper arm reaches into the picture's right edge.

## Seeing it

`.devtools/bin/rig_view.py` skins the three models' meshes (`.mdl`, `.vvd`, `.dx90.vtx`)
with the bones as `mdl_rig.solve` places them and draws them: the viewmodel's eye at the
game's field of view, or framed on the meshes (`--fit`), over three plans with a 5-unit
ruler; the TF2 arms translucent green (`--ghost`), both skeletons, and marks for the
hands (R/L TF2's, r/l ours), the weapon bone (W) and the muzzle (M). `sheet` lays a
sequence's frames side by side, `--ascii` prints the eye's view as characters, and
`where` tabulates the hands against the weapon bone, frame by frame. Pictures go to
`.devtools/artifacts/rig_view/`.

    rig_view.py frame ARMS ANIMS HANDS GUN sg_reload_loop@4 --ghost --fit
    rig_view.py sheet ARMS ANIMS HANDS GUN sg_reload_loop --count 8 --fit
    rig_view.py where ARMS ANIMS HANDS GUN sg_reload_loop

In game, `tf_weapons_dump [name]` saves the next drawn frame, every bone of the arms,
the hands and the weapon in the viewmodel's axes, to
`data/tf_weapons/dumps/<name>.json`; `rig_view.py dump` draws it with the same meshes, so
what the game did can be put beside what the oracle says it should.

## The gate: no more deformation than GMod's own animations make

`.devtools/bin/rig_gate.py SWEP.lua` fails (exit 1) a weapon whose retarget goes past the
evidence, over every frame of every sequence its `TFAnimations` can play (read from the
weapon's file, so what ships is what is gated):

- **streams**: no frame's animation data is empty.
- **lengths**: every hands bone at its own rest distance from its parent (worst 5e-7 units).
- **mesh**: the c_arms mesh deforms no more than GMod's own animations deform it. The
  envelope is measured, not chosen: per region (the edges whose ends are weighted most to
  the same two bones), the largest change of an edge's length over 7,349 frames of the
  fists' and the 16 HL2 c_ weapons' animations, bone-merged onto the hands by name as the
  engine merges them. An excess fails once it reaches 1 px through the game's camera at
  1920x1080.

The fists alone were the wrong yardstick: their hands never open round a grip, and against
them 24 of 86 regions of the Scattergun's frames looked over-stretched.

**The Scattergun fails the gate.** An earlier version of this note said it passed, by 0.53
px; that envelope was wrong. It read the HL2 weapons' delta sequences (their `adjustment`
layers, made to re-grip the c_arms for other hand models) on top of the bind pose, a pose
the engine never shows, and those phantom poses widened the envelope. Without them (their
real base unknown, they are left out), the right hand's index-middle web passes native by
0.142 units, 6.0 px on screen, at `sg_reload_loop@4`, and its middle knuckle by 3.1 px.
`test_rig_gate.py`'s `test_the_scattergun_passes` fails, as it should, until that is fixed.

What was tried against it, measured and refuted:

- each joint clamped into its own native range of turn (per axis, in its own frame, over
  the same 6,791 native frames): the web got worse, 7.2 px. The fingers each stay in
  range; what native animation never does is the pair together.
- the angle between neighbouring fingers on the palm's plane: ours, 33 degrees at that
  frame, is inside the native maximum, 85; the measure itself breaks down on curled
  fingers, whose projections are degenerate. No explanation of the web is in hand.

The phase plan's own answer is per-weapon finger curl overrides (phase 3's panel), which a
gate run can then hold.

Copying the fingers' motion from rest (a delta through the same corrections) instead of
their direction was measured and rejected: 21 regions over the fists' envelope instead of
24, its worst worse (0.76 against 0.70), and fingers up to 31 degrees off TF2's.

`test_rig_gate.py` holds the gate to its job: the Scattergun passes; an index finger turned
25 degrees fails the mesh (11.8 px); a hand moved 0.5 units off its forearm fails the
lengths. It runs where TF2's and GMod's VPKs are (`MDL_RIG_VPKS`, or the CrossOver installs)
and says it skipped where they are not.

Two decoder faults found on the way, both fixed in `mdl_rig.py`: a long animation's last
frame is a section of its own (`mstudioanimdesc_t::pAnim`), which it had read as the
section after; and a stream of a lone 255 holds no bone, which is now refused
(`EmptyStream`) rather than read as the bind pose. No TF2 Scout frame has one; five
frames of the HL2 weapons do, and the envelope leaves them out. Every section boundary of
the sectioned sequences now steps within 0.8 to 1.4 times its neighbouring frames.

## Third person: the per-character transformer

GMod's player models have no `weapon_bone` and the c_model none of theirs, so the engine's
bone merge puts the Scattergun nowhere near the hand. TF2 holds it rigidly in `bip_hand_R`
through every base pose (`weapon_bone` against the hand: 0.000 units, 0.00 degrees over
`stand`, `crouch`, `run`, `crouch_walk`, `swim` and the jumps; `airwalk` drifts 0.28), so
the weapon goes where the hand's TF2 axes say, times that grip.

What drives the hand decides how that looks. On GMod's own shotgun animations the grip
points the barrel 34 to 53 degrees off straight ahead (TF2's grip expects TF2's wrist). Through
`.devtools/bin/body_rig.py` (TF2's player animation on the GMod model: each bone turned as
TF2's, corrected by the same axis method as the viewmodel's, extended to the pelvis, spine,
neck, head, clavicles and legs with the body's left as the second axis, the pelvis placed by
the ratio of leg lengths), the barrel is 9.6 degrees off ahead in `stand_PRIMARY`, TF2's own
stance. Bones stay at their own lengths (2e-6 units).

TF2's player animation is a stack, evaluated as the engine does (`mdl_rig.Sampler`): a base
whose locomotion is a 3x3 grid over `move_x` and `move_y`, autolayers the model declares
(`PRIMARY_aimmatrix_*`, a 3x4 delta grid over `body_yaw` and `body_pitch`, faded by `move_x`
through start, peak, tail and end; `layer_idleNoise`), and gestures (attack, reload) added as
deltas. Reading the grid's first blend alone shows a different run: forward and that blend
are 134 degrees apart somewhere in the body.

`rig_gate.py SWEP.lua --third MODEL` judges the weapon's `TFPlayerAnimations` (every base
frame at the 9 move directions, stand at 12 aims, every gesture frame on stand; 1,338
frames) against the player model's own animations (9,855 frames of `m_anm` on kleiner),
through an eye 100 units off at 1080p. It fails: the left arm at the aim corner (`body_pitch`
+90, `body_yaw` -45), 3.9 px; the right hip seam running diagonally, 3.8 px; a shoulder
helper in `airwalk`, 1.0 px. The left hand's IK has up to 6.9 units to close. Which sign of
`body_pitch` is looking up is not known here: the in-game mapping must be checked.

Decoder work on the way: animations in an external `.ani` (GMod's `m_anm.ani`) are read;
a delta animation starts every bone it leaves out at identity rather than at rest, and a delta
whose stream is empty is a zero (TF2's aim matrix has one at its middle), where an empty
stream of a plain animation is still refused.

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
