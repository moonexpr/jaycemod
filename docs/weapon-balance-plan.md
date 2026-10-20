# Weapon balance, jars, and soldiers' weapon use

Three phases, in order; each lands and is checked in game before the next.

## What is there now

- Damage comes from HL2's skill convars, at GMod's values (read live
  2026-10-20): crossbow 100, .357 40, pistol 5, SMG 4, AR2 8, buckshot 8 × 7
  pellets, crowbar 10, stunstick 10, frag 125, satchel 150, RPG 100,
  SMG grenade 100. None is cheat-flagged; Sandcastle sets none of them.
- `foundation.players` `Hit` crits **every** headshot ×3, from any weapon.
  That, on a 100-damage bolt, is why the crossbow kills outright.
- Fire rate and spread are the engine's (C++ weapons). The only Lua hook on
  them is `ws_fixed_spread` (`ws/sh_toggles.lua`), which re-fires pellets.
- Jarate exists as a projectile (`foundation.projectile.jar`,
  `entities/tf_projectile_jar.lua`), thrown only by the Wheel of Fate.
  `MAD_MILK` is a condition with an overlay and a label, and nothing applies
  it or heals from it.
- Soldiers carry primary, secondary and melee (`foundation.aiwar.arms`,
  `Choose` by distance) and kit gadgets (`grenade`, `turret`, `manhack`,
  `features/aiwar/sv_soldier.lua`). No kit carries the RPG, SLAM or a jar.

## Phase 1: balance

A new model, `foundation.combat.weapon_balance`: one table per weapon class
and pure rules on it; the controller (`ws/sh_weapon_balance.lua`) applies it
through `EntityFireBullets` (damage, spread), `StartCommand` (fire interval:
strips `IN_ATTACK` until the weapon's gate opens, predicted on both realms),
and `EntityTakeDamage` (knockback, shotgun crits). Skill convars carry the
explosives' damage so the Store's tooltip stays right.

| Weapon | Now | Proposed |
|---|---|---|
| Crossbow | 100, headshot ×3 | 40; never crits on a headshot; knockback 700 u/s along the bolt (×1.5 on a headshot) and a 0.5 s stagger |
| Pistol | 5, HL2 spread, ~10 shots/s clicking | 18; spread 0.5°; one shot per 0.3 s |
| .357 | 40 | 75; no spread; one shot per 1.0 s |
| SMG, AR2 | 4, 8 | unchanged up close; falloff past 1024 u to 50 % at 2048 u |
| Shotgun | 8 × 7 | unchanged per pellet; crit chance 0 % at 512 u rising to 40 % at 64 u, one roll per shot |
| Crowbar, stunstick | 10, 10 | unchanged (headshot crits stay) |
| Frag | 125 | 175 |
| SLAM (satchel, tripmine) | 150 | 200 |
| RPG | 100 | 150 |

Pistol and .357 keep their damage at any range, so past 1024 u they out-hit
the automatics.

## Phase 2: Jarate and Mad Milk

- `foundation.projectile.jar` gains a kind: Jarate soaks (`URINE`,
  mini-crits taken), Mad Milk coats (`MAD_MILK`: whoever damages a coated
  enemy heals 60 % of the damage dealt, TF2's). Both 10 s, radius 200.
- Two Support-slot weapons in the Store, `weapon_ws_jarate` and
  `weapon_ws_madmilk`: throw one jar, recharge 20 s (TF2's), no ammo.
- Thrown by the same `tf_projectile_jar` entity, configured by kind.

## Phase 3: soldiers use what they carry

- `arms.WEAPONS` reach, chase and avoid follow the new roles: pistol and
  .357 become the long-range pick past the primary's reach; the shotgunner
  closes; the crossbowman keeps its distance and aims centre mass.
- Alt-fires: an SMG grenade or AR2 ball at a group of enemies or into cover,
  on a cooldown.
- Gadgets: `rpg` (at a group, a turret or an enemy behind light cover),
  `slam` (a tripmine on the route the squad holds), `jarate` (at the
  enemy the squad is focusing), `madmilk` (at an enemy a wounded teammate
  is fighting), each a kit's to carry.
