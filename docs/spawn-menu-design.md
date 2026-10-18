# Spawn menu (Q) and context menu (C): design

Status: design only. Nothing here is implemented. It builds on the first,
uncommitted implementation of the Q menu, which is in the working tree as of
2026-10-10. The operator answered the product questions (§6) on 2026-10-10,
and the decisions are folded into every section below. A second round of
operator changes the same day is also folded in: cosmetics carry stats
(§4.2.1, §4.2.2), every new gameplay name takes `mp_` (Q7), there is no
Operator tab (the stock creation tabs serve admins, §3.1), and admins build
games on any map with a tool-gun tool (§4.3, preliminary). §8 is the
implementation plan.

Paths are relative to `addons/sandcastle/gamemodes/sandcastle/gamemode/` unless they
start with `addons/`, `tests/`, `docs/` or `.devtools/`.

---

## 1. Current state

### 1.1 What exists

| Part | File | What it does today |
|------|------|--------------------|
| Loadout model | `foundation/loadout.lua` | Pure `module(...)`. Five slots (`SLOT_PRIMARY..SLOT_SUPPORT2`) and four kinds. A slot takes one kind, and both support slots take `KIND_SUPPORT`. `Catalog` holds weapon entries. A `Loadout` is an immutable value: `Buy`, `Equip` and `Clear` each return a new loadout or raise a named refusal (`UnknownWeapon`, `UnknownSlot`, `AlreadyOwned`, `NotOwned`, `WrongSlot`, and `BadCatalog` for content mistakes). `Refused(err)` separates the player's mistakes from our bugs. `State`/`FromState` handle the wire form. `PRICE = 10`. |
| Catalog and events | `ws/sh_loadout.lua` | `WS.LoadoutCatalog`: 12 Half-Life 2 weapons, all priced at `PRICE`, with four starters. Client requests: `loadout_buy`, `loadout_equip` and `loadout_clear` (`clientSendable`, 10 per 5 s). Server replies: `loadout_state` and `loadout_refused`. |
| Loadout controller | `ws/sv_loadout.lua` | `WS.Loadouts[ply]`, keyed by entity. `Change` (l.37) runs the model, then for a buy calls `WS.SpendMoney` (l.52) before it commits. A refusal is sent back as `tostring(err)` (l.41). `WS.GiveLoadout` (l.68) gives the equipped weapons plus `RESERVE_CLIPS` of ammo. |
| Spawn hook | `init.lua:74-80` | When `WS.Active()` (a tf_gamerules proxy is bound), `GM:PlayerLoadout` gives `SANDBOX_TOOLS` (camera, toolgun, physgun) plus the loadout. Otherwise it gives Sandbox's own loadout and not the paid one. Decision Q4 changes this: the loadout is given in Sandbox mode too. |
| Gamemode mode | `foundation/gamemode.lua`, `ws/sh_core.lua:211,232` | The gamemode's own modes: `SANDBOX` (no rounds, or rounds halted by Stop Game), `TRANSITION` (the countdown) and `GAMEPLAY`. A map without TF2 rounds stays in Sandbox mode until a game begins (the AI war asks for one), then loads rounds. Clients read `WS.Active()` (Global2 `ws_rounds_active`) and `WS.GameplayStopped()` (Global2 `ws_gameplay_halted`). |
| Admin spawn (deleted) | was `ws/sh_operator_spawn.lua` | Deleted by the operator on 2026-10-10, with the Operator tab. Its `operator_spawn {class}` was the only route to the gamemode's non-spawnable scripted entities (gap 15). Nothing in the tree references it any more. |
| Client loadout | `ws/cl_loadout.lua` | Mirrors the server's loadout (`WS.LocalLoadout`), raises `WSLoadoutChanged`, and shows refusals as notices. |
| Player tab | `ws/cl_menu_player.lua` | Model in the centre, with 3 slot boxes on the left and 2 on the right. The right column lists owned weapons. Clicking a slot filters the list; clicking a weapon equips it. A hint (l.18) says changes apply at the next spawn on a TF2 map. Tab order 300. |
| Inventory tab | `ws/cl_menu_inventory.lua` | A store row per kind with Buy buttons, the balance read from NW2 `ws_money` (polled in `Think`, l.91), a Player models grid that sets `cl_playermodel` for free (l.75), and a stub "Map & server items" section. Order 301. Decision Q5 makes the models grid a paid store section, and cosmetics with stats join it. |
| Operator tab (deleted) | was `ws/cl_menu_operator.lua` | Deleted by the operator on 2026-10-10. Admins use Sandbox's stock creation tabs instead (decision Q10). |
| Options (tool menu) | `ws/cl_menu_options.lua` | Sandcastle > Voting and Sandcastle > Match. All buttons are disabled stubs. |
| Utilities (tool menu) | `ws/cl_menu_utilities.lua` | User > Sandcastle: Stop sounds, Remove ragdolls, and three saved client convars (`cl_reduce_motion`, `cl_reduce_flashing`, `cl_hide_effects`; l.8-13). Nothing reads the convars. |
| Other Utilities panels | `ws/sh_gameplay.lua:137`, `ws/sh_aiwar.lua:215`, `ws/sh_nodegraph.lua:77`, `ws/cl_ns_debug.lua:48` | Admin > Gameplay Settings (Begin/Stop Game). Sandcastle > AI War (with the slot tree from `ws/cl_aiwar_slots.lua`), AI Node Graph, and Debug NextSoldier. |
| Server settings route | `ws/sh_settings.lua`, `foundation/settings.lua` | `ws_server_set <convar> <value>`, admin only, with values clamped to `Settings.SETTINGS` ranges. `WS.ServerCheckBox` and `WS.ServerSlider` build on it. |
| Economy | `foundation/economy.lua`, `ws/sv_economy.lua` | `Bank` with `Open`, `Spend` (which raises `InsufficientFunds` rather than overdraw) and `Earn`. Accounts open at `STARTING_MONEY = 2000` in `PlayerInitialSpawn` and close in `EntityRemoved` (l.41-42). The balance is NW2 `ws_money`. `Economy.Format` mis-renders negative amounts: `-123` becomes `$-,123` and `-5` becomes `$-5` (checked under LuaJIT). No balance can go negative today, so the bug is latent; decision Q4 exposes it. |
| Scoreboard | `ws/cl_scoreboard.lua` | A Money column (`MONEY_W`, l.23) for players and team NPCs, read from NW2 `ws_money` (l.99, l.112) and drawn with `Economy.Format` (l.224). |
| Respawn waves | `foundation/rounds.lua:1093-1151`, `features/rounds/sv.lua:1175`, `features/aiwar/sv.lua:1152` | `Round:WaveMaxLength(team, size, scale)` is TF2's `GetRespawnWaveMaxLength`. `NextRespawn` and `WaveDue` use it for players, and the AI war's `Reinforce` uses it for soldiers. |
| AI war | `foundation/aiwar.lua`, `foundation/aiwar/*`, `features/aiwar/sv.lua` | `War` holds fire teams and settings (`SetSquadsMax`). Tactics, lanes, posts and hearing are pure models. The Commander of `docs/aiwar-command.md` §2 is not built yet (its phase 5). |
| Player attributes | `foundation/players/attributes.lua`, `features/attributes/sv.lua` | TF2's custom player attributes (`AddCustomAttribute`). Pure functions over one player's `attrs` table, `name -> { value, expireAt }`. `Add` (l.52) stomps a second add of the same name. `Supported` (l.47) knows `"dmg taken from fire reduced"` and the Wheel of Fate's `"major move speed bonus"`, `"major increased jump height"`, `"cancel falling damage"` and `"head scale"`. The controller's `Give(ply, name, value)` and `Take` serve the wheel; triggers use `StartTouch`/`EndTouch`. It clears every attribute on `PlayerSpawn` and `PostPlayerDeath` (l.103), syncs speed through NW2 `ws_speed_scale`, and runs a 0.1 s timer (l.99) over the players holding attributes. It is a lazy feature: only `trigger_add_or_remove_tf_player_attributes` and `features/wheel` load it. |
| Conditions and stuns | `foundation/players.lua`, `ws/sv_teams_conditions.lua`, `ws/cl_conditions.lua` | TF2's conditions (`COND`, TF2's numbers) and stuns. `STUN` holds TF2's `TF_STUN_*` flags; `Stun` (l.127) folds stuns into one (the later end, the stronger slow, every flag); `StunHas` and `MaxSpeed` read it. `WS.StunPlayer(ply, duration, reduction, flags)` (l.69) publishes NW2 `ws_stun_end_time`, `ws_stun_speed_reduction` and `ws_stun_flags`. `WS.InCondition(ply, cond)` answers conditions; there is no `COND.STUNNED` (TF2's `TF_COND_STUNNED`, 15), so a stun is not a condition today. Players only: `trigger_stun`, spells, and the Halloween bosses call it. |
| Editors | `addons/sandcastle/.../entities/entities/ws_editor.lua`, `edit_gamerules.lua`, `edit_roundtimer.lua`; `ws/sh_editors.lua`, `ws/sh_editors_cart.lua`, `ws/sh_editors_point.lua`; `features/editors/sv.lua` | Sandbox-style editors (base `base_edit`), `Spawnable` and `AdminOnly` in the Entities tab's "Editors" category, one of each per map (`SpawnFunction`). Their fields mirror and change the game through the editors controller. `WS.EditorAction(name, def)` registers admin-only right-click properties, checked on both realms, and runs them through `WS.Feature("editors")`. Carts and control points get entries through `ws_proxy` boxes (kinds `"cart"` and `"point"`). |
| Feature loader | `foundation/features.lua`, `ws/sh_core.lua:131-137` | `WS.Feature(name)` loads `features/<name>/` on first call, in either realm, and tells clients to load the client part. `WS.FeatureLoaded(name)` asks without loading. Entities ask in `Initialize`, so a map loads only what its entities pull in. Features never unload before map change. |
| Round cleanup | `features/rounds/sv.lua:65,824,1403,1441` | Every round restart runs `game.CleanUpMap(false, CLEANUP_KEEPS)`, which keeps only the proxy and the two editors; any other entity created by Lua is removed. `SetUpMap` decides the rounds mode (a master makes it control points) and makes the tf_gamerules proxy for a map with an objective, once per map (`mapSetUp`). `EnsureRules` makes the proxy when a game is begun on a map without one. `features/capture/sv.lua:1019` rebuilds the point set on `PostCleanupMap`. |
| Defaults | `addons/sandcastle/cfg/sandcastle_defaults.cfg` | Adds the three comfort convars. |
| Tests | `tests/loadout_test.lua`, `tests/economy_test.lua` | The loadout model: slots, catalog, starters, buy, equip and clear, and the State round trip, with prices derived from `Loadout.PRICE`. The economy: opening, earning, spending and refusing to overdraw. The whole suite stands at `TOTAL 1800 passed, 0 failed` (`.devtools/bin/check_lua.sh`, 2026-10-10). `tests/player_attributes_test.lua`, `tests/wheel_test.lua`, `tests/editor_actions_test.lua` and `tests/editor_point_test.lua` cover the attributes and the editors. |

### 1.2 What the C menu has today

- **Properties** (right-click an entity while holding C):
  - `ws_spectate_npc`: admin, living NPC or NextBot (`ws/cl_spectate.lua:132`).
  - `ws_nb_select` and `ws_nb_debug`: superadmin or listen host, NextBots (`ws/cl_nb_menu.lua:122,132`).
  - Editor actions on `ws_editor` entities, payload carts and control points: admin, through `WS.EditorAction` (`ws/sh_editors.lua:10`).
- **None of these**: `list.Set("DesktopWindows", ...)`, a `PopulateMenuBar` hook, or `ContextMenuOpen`, `OnContextMenuOpen` or `ContextMenuShowTool` hooks.
- **What base Sandbox adds anyway:**
  - The desktop icon "Player Model" (`DesktopWindows.PlayerEditor`: model, colour, skin, bodygroups). It sets `cl_playermodel` for free, which decision Q5 forbids.
  - The menu bar's "Drawing" and "NPCs" menus. The NPCs menu toggles `ai_disabled`, `ai_ignoreplayers`, `ai_keepragdolls` and similar convars.
  - The active tool's control panel (`ContextMenuShowTool`).
  - The stock properties (Remove, Ignite, Drive, Bone Manipulate, Collision, Statue and others), each gated by `GM:CanProperty`.

### 1.3 Gaps and risks (design observations, not fixes)

These are ranked by how much they undermine the direction. Numbers are kept stable so other sections can cite them; closed gaps say so.

1. **The store can be bypassed.** In Gameplay mode every player still has:
   - Sandbox's own creation tabs (Spawnlists, Weapons, Entities, NPCs, Vehicles, Dupes, Saves).
   - `gm_giveswep`, `gm_spawn`, `gmod_spawnnpc`, `gm_spawnsent` and `gm_spawnvehicle` from the console.
   - A physgun and toolgun from `SANDBOX_TOOLS`.

   The gamemode has no `PlayerGiveSWEP`, `PlayerSpawnSWEP`, `PlayerSpawnNPC`, `PlayerSpawnSENT`, `PlayerSpawnObject`, `PlayerSpawnProp`, `CanTool`, `CanProperty`, `CanDrive` or `PhysgunPickup` hook. So a $10 SMG competes with a free one a click away, and any player can physgun, Remove or Drive a payload cart or an AI war soldier. Decision Q1 closes all of it for non-admins, props included, and decision Q10 makes that gate the only place admin-only spawning is enforced.
2. **(Closed by deletion.)** The Operator tab's "admins only" was only in the UI. The tab is gone (Q10); Sandbox's own commands are now gated by the Q1 gate.
3. **(Closed by deletion.)** `operator_spawn` accepted any class, including `point_servercommand` and `lua_run`. It is gone. Sandbox's `gm_spawnsent` reaches only scripted entities with a `SpawnFunction`, or entries of the `SpawnableEntities` list (`CanPlayerSpawnSENT`, `gamemodes/sandbox/gamemode/commands.lua:745-771`), so engine command entities are out of reach. Whether an admin's `gm_spawnsent` reaches the gamemode's TF2 logic entities depends on their base classes (research item R13); the gate's round-logic rule (§3.1) covers that case either way.
4. **Money and loadouts are keyed by entity and die on disconnect.** A player who spends down to $0 and reconnects gets a fresh $2,000. Owned weapons are lost the same way. Decision Q3 sets the policy: both last the match, survive reconnects (keyed by SteamID64), and reset when a match starts or the map changes.
5. **Buying is never gated.** A player can buy in Sandbox mode, where the loadout is never given today, so the money is wasted. They can buy mid-firefight, while dead, or during humiliation. An equip only takes effect at the next spawn, and there is no resupply path (TF2's `func_regenerate`, CS's buy zone). Decision Q4 makes the Sandbox-mode purchase real: the loadout is given there too.
6. **Refusal text is the raw `tostring` of the error** (`sv_loadout.lua:41`). Players read text like `already owned: weapon_ar2` and `insufficient funds: 10 wanted, 5 held`. It shows class names and is not localised, although `ws/cl_localization.lua` exists.
7. **Loadouts compare catalog entries by table identity** (`foundation/loadout.lua:209,222`). A live reload of `ws/sh_loadout.lua` (operator rule: reload chunks live, never restart) builds new entry tables. Loadouts kept in `WS.Loadouts` still hold the old ones, and `sv_loadout.lua` captured `CATALOG` when it loaded. After such a reload, `Equip` can leave one weapon in both support slots, and `Owns` and `Equipped` disagree. Compare by `class` instead.
8. **The wire widths cap the catalog.** `WEAPON_COUNT_BITS = 6` (`sh_loadout.lua:91`) allows at most 63 owned items. Map and server items in the same list will hit that.
9. **The comfort convars are client-only** (`CreateClientConVar(..., true, false)`). The server cannot read them through `ply:GetInfoNum`. Server-driven effects (`util.ScreenShake`, `ViewPunch` and `ScreenFade` in `foundation/npc/*`, `features/spells`, `features/hazards`) therefore cannot honour them.
10. **Debug panels show for everyone.** Utilities > Sandcastle > Debug NextSoldier, AI Node Graph and AI War appear for non-admins, whose clicks do nothing. Utilities is meant to hold only client options for non-admins.
11. **There are two free model pickers.** Inventory > Player models and Sandbox's C-menu "Player Model" icon both set `cl_playermodel`, and the server applies it. Neither is gated by team, mode or price. Decision Q5 makes models paid, so both must go through the store and the server must stop trusting `cl_playermodel`.
12. **Sandbox's stock creation tabs are still there for everyone.** Player and Inventory come after Sandbox's tabs (`TAB_ORDER` 300-301), not in their place. Decision Q2 hides the stock tabs for non-admins in Gameplay mode; decision Q10 makes them the admins' spawning surface.
13. **(Closed by deletion.)** The Operator tab reloaded the whole spawn menu on a rank change. The stock-tab hiding of Q2 (§3.1) does the same on `WSRankChanged` and `WSModeChanged`, which is rare and acceptable.
14. **Negative balances are new and the code assumes none** (from decision Q4). `Economy.Format` mis-renders them (§1.1). `Bank:Spend` and `Bank:CanAfford` have no way to allow an overdraft. `ws_money` is a signed 32-bit NW2 int, so a debt below `-2^31` cannot be carried, and the model must stop there rather than wrap.
15. **The gamemode's TF2 map entities cannot be placed by anyone** (from decision Q10). They were reachable only through the Operator tab. They are scripted entities with `Spawnable = false` (only `edit_gamerules`, `edit_roundtimer` and three `ws_drg_*` NPCs are spawnable), and the stock Entities tab lists only spawnable ones. Decision Q11's game builder (§4.3) is the answer: admins place them with the toolgun.
16. **Item attributes have no home in the attributes model** (from decision Q5's addition). `Attributes.Add` stomps a second value of the same name, so two sources of one attribute (a cosmetic and the Wheel of Fate) would overwrite each other. The controller clears every attribute at each spawn and death, so a worn item's stats would vanish at the first respawn. Both need a separate, persistent item layer (§4.2.1).
17. **Lua-placed entities die at every round restart.** `CleanUpMap` keeps only `CLEANUP_KEEPS` (§1.1). A game placed on a non-TF2 map must therefore be rebuilt after every cleanup, from data, not kept alive (§4.3).
18. **The rounds mode is decided once per map** (`SetUpMap`, `mapSetUp`). Objectives placed after it ran do not change the mode until something asks again (§4.3).

---

## 2. Principles every proposal follows

- **Pure models in `foundation/`** (`module(...)`, no GMod globals). They hold the rules: what may be bought, when, by whom, at what price, how far into debt, what a worn item does, what a vote needs to pass, and whether a placed game is playable. Each returns a value or raises a named refusal. Time, the round state and the mode are passed in as arguments.
- **Controllers in `ws/sv_*.lua` and `features/*/sv.lua` only coordinate.** One pass: decode the request (the event schema), build a context from the replicated state, ask the model, charge the economy, commit, publish, and log.
- **Every client action is a `clientSendable` event with a `rate`.** The UI hides what the player cannot do, and the server checks again on every request.
- **Errors split into the client's fault and ours.** A refusal (a named refusal type, `Refused(err)` true) goes back to the player as a kind (§3.2). Anything else is our bug: it propagates, is logged once, and the player sees nothing but a generic notice.
- **No new per-tick server work.** Requests are checked when they arrive. Deadlines (votes, pauses, cooldowns) are timestamps compared when the next request or hit arrives, or a `timer.Create`. State reaches clients as Global2 or NW2 values and events, and clients do their own redrawing.
- **Named constants.** Tests derive from them with `T.defined`, and pin only TF2 and GMod enums. A tuning value (a price, a wave scale, a rate, a stat value) is never written into a test.
- **Reuse before adding.** Stats are TF2 attributes in `features/attributes`; stuns are `WS.StunPlayer`; admin right-clicks are `WS.EditorAction`; placed games are the same entities a TF2 map holds, loaded by the same lazy loader.
- **Console names** take the form `<domain>_<subject>_<verb|specifier>` (decision Q7):
  - `mp_` for every new gameplay command and convar, votes included (`mp_teams_scramble`, `mp_vote_kick`, `mp_vote_duration`).
  - `cl_` for client convars.
  - `ns_` for NextSoldier.
  - `sv_` only for names that already exist (`sv_gameplay_enabled`); nothing new takes it, and TF2's `sv_vote_*` names are not ported.

  New names avoid a bare `ws_` where a Source domain fits, and nothing new uses `wetsand`. Check every new name with `.devtools/bin/check_engine_names.sh`. Every name proposed in this doc printed `free` on 2026-10-10.

### 2.1 Modes: what "TF2 maps" and "Sandbox maps" mean here

The operator's decisions speak of "TF2 maps" and "Sandbox (non-TF2) maps". The code's own split is the gamemode's mode (`foundation/gamemode.lua`), and this doc keys every rule on it:

- **Sandbox mode**: `not WS.Active() or WS.GameplayStopped()`. A map without TF2 rounds, or a TF2 map whose game an admin stopped. "The map plays like Sandbox" (`ws/sh_core.lua:229`).
- **Gameplay mode**: everything else, including the `TRANSITION` countdown. A TF2 map running its rounds, or a non-TF2 map whose game was begun (the AI war's freeform scenario, or a game built with the game builder, §4.3).

So "on TF2 maps" in a decision reads as "in Gameplay mode", and "on Sandbox maps" as "in Sandbox mode". This matches Q1's own wording ("while rounds run"). The operator confirmed it (2026-10-11): rules follow the mode, so a stopped TF2 map brings back free spawning and credit. The alternative, keying on the map's name or on whether it shipped a `tf_gamerules`, would treat a stopped TF2 map as a match and a begun freeform map as a sandbox, both of which contradict what the players see.

**New pure model: `foundation/play_mode.lua`.** One factory for the mode every other model takes:

- Constants: `SANDBOX`, `GAMEPLAY`, `AIWAR`, `ARENA`.
- `Of(facts)`, where `facts = { roundsActive, gameplayStopped, aiwar, arena }` are booleans. Rules, in order: `not roundsActive or gameplayStopped` gives `SANDBOX`; else `aiwar` gives `AIWAR`; else `arena` gives `ARENA`; else `GAMEPLAY`. A stopped game is Sandbox mode even while an AI war is set up.
- `IsSandbox(mode)`: true only for `SANDBOX`.

**Adapter: `WS.PlayMode()`** in `ws/sh_permissions.lua`, built from `WS.Active()`, `WS.GameplayStopped()`, `WS.AiWarActive()` and the rounds mode's arena flag. Both realms call it; nothing else reads those Global2 values to decide a mode.

---

## 3. Cross-cutting flows

### 3.1 Permission model and the Sandbox gate (P0; decisions Q1, Q2, Q10)

**New pure model: `foundation/permissions.lua`.**

- Constants for abilities: `SANDBOX_SPAWN`, `MATCH_CONTROL`, `SERVER_SETTINGS`, `NPC_DEBUG`, `VOTE_CALL`, `GAME_BUILD`.
- Constants for ranks: `RANK_PLAYER`, `RANK_ADMIN`, `RANK_SUPERADMIN`.
- `REQUIRED = { [ability] = rank }`, the rank each ability needs in Gameplay mode. `GAME_BUILD` needs `RANK_ADMIN`.
- `SANDBOX_REQUIRED = { [ability] = rank }`, the overrides in Sandbox mode. Today it holds one entry: `SANDBOX_SPAWN = RANK_PLAYER`. `GAME_BUILD` has no override: building is admin-only in every mode.
- `Allows(rank, ability, mode)`, with `mode` from `foundation/play_mode.lua`. It returns true, or false and a refusal kind (`REASON_RANK`).

`SANDBOX_SPAWN` is the one ability whose answer depends on the mode. **Decision Q1:** in Sandbox mode every player has it; in Gameplay mode (any of `GAMEPLAY`, `AIWAR`, `ARENA`) only `RANK_ADMIN` and above do. There is no prop exception.

**Adapter: `ws/sh_permissions.lua`.**

- `WS.RankOf(ply)` maps `IsSuperAdmin()`, `IsListenServerHost()` and `IsAdmin()` to a rank. It goes through CAMI when CAMI is loaded (ULX and SAM register with it).
- `WS.Can(ply, ability)` asks the model with `WS.RankOf(ply)` and `WS.PlayMode()`.
- Both realms use the same function. The client hides controls; the server enforces.

**Replace the scattered checks:**

| File | Check today | Replace with |
|------|-------------|--------------|
| `ws/sv_nbdebug.lua`, `WS.NpcDebugAllowed` | own check | `WS.Can(ply, NPC_DEBUG)` |
| `ws/sh_settings.lua` | `IsAdmin()` | `WS.Can(ply, SERVER_SETTINGS)` |
| `ws/sh_gameplay.lua`, `ws/sh_aiwar.lua` | `IsAdmin()` | `WS.Can(ply, MATCH_CONTROL)` |
| `ws/sh_editors.lua` `WS.EditorAction` `Filter` | `ply:IsAdmin()` | `WS.Can(ply, MATCH_CONTROL)` (editor actions change the match) |

**The Sandbox gate: the one place admin-only spawning is enforced (gap 1, decisions Q1 and Q10).** There is no Operator tab. Admins spawn through Sandbox's own creation tabs and commands, and a new `ws/sv_sandbox_gate.lua` is the only code that decides who may. It returns `false` from these hooks unless `WS.Can(ply, SANDBOX_SPAWN)`, so admins are allowed in every mode and non-admins are refused in Gameplay mode:

- Spawning, all of it: `PlayerGiveSWEP`, `PlayerSpawnSWEP`, `PlayerSpawnNPC`, `PlayerSpawnSENT`, `PlayerSpawnVehicle`, `PlayerSpawnObject`, `PlayerSpawnProp`, `PlayerSpawnRagdoll`, `PlayerSpawnEffect`. `PlayerSpawnObject` runs before props, ragdolls and effects, so it alone would do; the specific hooks stay as a second line in case an addon calls them directly.
- Dupes and saves: `CanArmDupe`, and the duplicator tool through `CanTool` (research item R8 covers saves).

And these, which refuse only when the target is a gameplay entity:

- `CanTool`, `CanProperty`, `CanDrive`, `PhysgunPickup` and `CanPlayerUnfreeze`.

The physgun and toolgun stay in `SANDBOX_TOOLS`: a non-admin may still move a loose map prop, but not a cart, an objective, a soldier or a player. The game builder's tools (§4.3) are refused in `CanTool` without `GAME_BUILD`, whatever the target.

A pure `foundation/gameplay_entities.lua` holds the gameplay-entity rule and the spawn class rule:

- `IsGameplay(class, facts)`, where `facts = { isPlayer, isAiWarSoldier, isPayloadCart }`. Class prefixes `team_`, `tf_`, `trigger_`, `func_respawnroom`, `item_teamflag` and `ws_` (Sandcastle's own map entities) are gameplay entities, as are players, AI war soldiers and payload carts. The prefixes are a constant list, `GAMEPLAY_PREFIXES`.
- **Round logic, refused for every rank mid-match.** `ROUND_LOGIC_CLASSES` (`tf_gamerules`, `team_round_timer`, `team_control_point_master`, `team_control_point_round`) and `ROUND_LOGIC_PREFIXES` (`tf_logic_`). `SpawnAllowed(class, mode)` refuses them with `REASON_ROUND_LOGIC` in every Gameplay-family mode and allows them in Sandbox mode. The gate's `PlayerSpawnSENT` applies it after the rank check, so even an admin cannot drop a second rules entity into a running round. Placing these is the game builder's job (§4.3), which works in Sandbox mode and rebuilds them after every cleanup.

Judgment call (§9): the round-logic rule is kept even though R13 may show that `gm_spawnsent` cannot reach these classes at all (they have no `SpawnFunction` of their own), because a spawned rules entity breaks the running round and the rule costs one table lookup per spawn. **Decision (operator, 2026-10-11): audit, with a hard block behind a convar.** Every admin spawn of a console-running entity (`point_servercommand`, `point_clientcommand`, `lua_run` and the like, one named list in the gate's model) is written to the admin log with who, what and where, whichever path reached it. A new convar, `mp_spawn_command_entities_block` (default 0; check the name with `.devtools/bin/check_engine_names.sh`), refuses them outright for everyone when set. Sandbox's own spawn commands do not reach engine entities today (gap 3), so the audit mostly guards addons that list them.

**What admins lose with the Operator tab, and where it went.**

| Was in the Operator tab | Now |
|-------------------------|-----|
| NPCs, Weapons, spawnable Entities | Sandbox's stock NPCs, Weapons and Entities tabs, through the gate |
| A "Spawn for" team picker for NPCs | Spawn the NPC from the stock tab, then right-click it, Move to team (§5.3 admin properties) |
| Non-spawnable entities (the gamemode's TF2 map entities, gap 15) | The game builder's tools (§4.3) |
| A planned Bosses sheet | Options > Match control's Bosses row (§4.4), through `admin_boss { boss, level }` |
| A planned AI War sheet | Options > AI War control (§4.4), which already had it |
| A class policy and an audit line per spawn | The round-logic rule above. Stock spawns are not audited (they never were); builder placements and admin properties are (§4.3, §5.3). |

**Decision Q2: stock creation tabs.** On the client, a new `ws/cl_spawnmenu_tabs.lua` removes Sandbox's creation tabs (Spawnlists, Weapons, Entities, NPCs, Vehicles, Dupes, Saves) for players without `SANDBOX_SPAWN`. It keeps the removed entries so it can put them back, and rebuilds on `WSModeChanged` and `WSRankChanged` (through `spawnmenu_reload`, research item R7). So in Gameplay mode a non-admin's left side is Player, Inventory and nothing else; an admin keeps Player, Inventory and every stock tab; in Sandbox mode everyone has every tab. Hiding is presentation only: the server gate above is what enforces Q1.

This is the largest single change and it is P0: without it the economy and the loadout mean nothing in Gameplay mode.

### 3.2 Economy and the purchase flow (P0; decisions Q3, Q4, Q8)

**New pure model: `foundation/store.lua`.** It sits beside `foundation/loadout.lua`, which stays the slot rules, `foundation/wardrobe.lua` (§4.2), which holds models and cosmetics, and `foundation/economy.lua`, which stays the accounts.

**Constants:**

- Window kinds: `WINDOW_ANYWHERE`, `WINDOW_RESPAWN_ROOM`, `WINDOW_SETUP`, `WINDOW_CLOSED`.
- `POLICY[mode] = { window, charges, appliesNow, credit }`, keyed by the `foundation/play_mode.lua` constants. `credit` is how far below zero a purchase may take a balance (below).
- `SELL_SHARE` (P2), and `BuyClosed`, a new refusal.

**`Store.Window(policy, context)`**, where `context = { roundState, inSetup, inRespawnRoom, alive }`. It returns `OPEN`, or raises `BuyClosed` with a reason kind:

| Reason | When |
|--------|------|
| `REASON_DEAD` | the player is dead |
| `REASON_NOT_IN_SPAWN` | outside the respawn room under `WINDOW_RESPAWN_ROOM` |
| `REASON_ROUND_OVER` | `TEAM_WIN`, `BONUS`, `GAME_OVER` or `STALEMATE` |
| `REASON_MODE` | the mode's window is `WINDOW_CLOSED` |

**`Store.Charge(policy, price)`** returns `amount, floor`: the amount to take (`0` when `charges` is false, else `price`) and the lowest balance the spend may leave (`policy.credit`). Every purchase goes through it: loadout weapons, wardrobe items (models and cosmetics, §4.2) and AI war orders (§5.3).

**Decision Q4: debt in Sandbox mode, and where the rule lives.**

Sandbox mode keeps the prices, and anyone may go into debt with no consequences. `foundation/economy.lua`'s `Spend` refuses to overdraw today, so the overdraft rule needs a home. It is split in two:

- **The policy lives in the store:** `POLICY[SANDBOX].credit = Economy.UNLIMITED_CREDIT`, and every other mode's `credit = Economy.NO_CREDIT`. Whether a purchase may go into debt depends on the mode, and the store is the model that already knows modes and windows. One table then answers price, window and floor for every kind of purchase.
- **The mechanism lives in the bank:** `Bank:Spend(key, amount, floor)` refuses with `InsufficientFunds` when `held - amount < floor`, and otherwise subtracts. `floor` is required: the bank never guesses which mode it is in.

Why not put the whole rule in the economy: the bank serves every account, including team NPCs (Q9), and knows nothing of modes. A bank that held a mode flag would have to be told when an admin stops or begins a game, and a mode change mid-map would silently change what every later `Spend` does. Passing the floor per call keeps the bank a plain ledger and keeps "who may borrow" beside "who may buy, where and when".

New economy constants and functions:

- `NO_CREDIT = 0`.
- `BALANCE_MIN = -2^31`, the lowest balance `ws_money` (a signed 32-bit NW2 int) can carry. `UNLIMITED_CREDIT = BALANCE_MIN`: "no consequences" in practice, without wrapping the wire value (gap 14).
- `Affords(balance, amount, floor)`: pure, `balance - amount >= floor`. `Bank:CanAfford(key, amount, floor)` and the client's Buy buttons both use it, so the UI and the server cannot disagree.
- `InDebt(balance)`: `balance < 0`.
- `Format` renders a negative amount as a minus sign before the dollar sign: `-$1,234`, `-$123`, `-$5`.
- A `floor` that is not a whole number at or below `NO_CREDIT` is our bug (a plain `error`), never `InsufficientFunds`.

Earning, the round cash limit (`WSMoneyEarned`) and NPC accounts are unchanged.

**Decision Q8: AI war orders cost money and never borrow.** An order is charged through `Store.Charge(POLICY[mode], ORDER_PRICE)`. Orders are accepted only in `AIWAR` mode (§5.3), whose `credit` is `NO_CREDIT`, so an order the player cannot afford is refused with `INSUFFICIENT_FUNDS` and the balance is untouched. The debt rule of Q4 never reaches orders. The AI war asks for Gameplay mode when it starts, and if an admin stops the game, `play_mode.Of` gives `SANDBOX` and orders are refused with `REASON_MODE`, not taken on credit. This is one rule in one table: credit is a property of the mode, and orders exist in exactly one mode.

**How a negative balance shows.**

- **Scoreboard** (`ws/cl_scoreboard.lua`): the Money cell shows `Economy.Format(row.money)`, now `-$120`, drawn in a named `DEBT_COLOR` when `Economy.InDebt(row.money)`. Sorting and widths are unchanged; check that `MONEY_W` fits `Format(BALANCE_MIN)` or let the cell clip.
- **Store header** (Inventory tab and the C-menu windows): the balance in `DEBT_COLOR` with a line beneath it, "On credit: Sandbox mode lets you buy below $0." Buy buttons stay enabled while `Economy.Affords(balance, amount, floor)` holds, which in Sandbox mode is always. In Gameplay mode a button the player cannot afford is disabled with the tooltip "Not enough money".

**Controller: `ws/sv_loadout.lua` `Change` becomes one pass** (`ws/sv_wardrobe.lua` runs the same pass for models and cosmetics):

1. Build the context and the policy: `POLICY[WS.PlayMode()]`. `inRespawnRoom` is read from NW2 `ws_in_respawn_room` (§3.3).
2. `Store.Window(...)`.
3. `loadout:Buy(weapon)`.
4. `local amount, floor = Store.Charge(policy, weapon.price)`, then `WS.SpendMoney(ply, amount, floor)`.
5. Commit.
6. If `appliesNow` and the player is in a window, re-give: strip the loadout's classes, then call `WS.GiveLoadout`.
7. Publish.

**Decision Q4: the loadout is given in Sandbox mode.** `GM:PlayerLoadout` (`init.lua:76`) in Sandbox mode calls `BaseClass.PlayerLoadout` and then `WS.GiveLoadout(ply)`, selecting the loadout's first weapon. Sandbox's own set stays, since nothing else in Sandbox mode is gated anyway; the paid loadout is added at every spawn and, under `appliesNow`, at once after a change.

**Refusals become data, not prose (gap 6).** `loadout_refused` changes from `{ reason = String }` to `{ kind = UInt(REFUSAL_BITS), subject = String }`. The kind indexes a constant table in a new pure `foundation/refusals.lua`, shared by `foundation/loadout`, `foundation/store`, `foundation/economy`, `foundation/wardrobe`, `foundation/vote`, `foundation/game_layout`, `foundation/gameplay_entities` and the AI war order model. `Refusals.KindOf(err)` returns the kind for a named refusal and nil for anything else, which the controller treats as our bug. The client phrases the kind through `cl_localization`, so the player sees "You already own the Pulse Rifle." rather than a class name.

**Persistence and lifetime (gap 4, decision Q3).** A purchase lasts the match. Money and ownership survive rounds and reconnects, and reset when a match starts and at map change.

- **Keys.** Players' accounts, loadouts and wardrobes are keyed by `ply:SteamID64()` through one factory, `WS.AccountKey(ent)`: a player's SteamID64, or the entity itself for a team NPC. Bots need a distinct key (research item R5).
- `WS.OpenAccount` reopens an existing balance on reconnect. `EntityRemoved` closes only NPC accounts.
- **When a match starts.** The bank, the loadouts, the wardrobes (models and cosmetics, with their stats) and the handicap (§4.4) are rebuilt from nothing, and everyone present gets a fresh account at `STARTING_MONEY` and the starters. A match starts:
  - when Gameplay mode begins (the end of the `TRANSITION` countdown, from Begin Game, `sv_gameplay_enabled 1`, the AI war, or a built game's begin, §4.3);
  - when the rounds restart out of `GAME_OVER` on the same map (`Round:RestartRound`, `foundation/rounds.lua:966`).

  Both raise one hook, `WSMatchStart`, from the controllers that own them (`features/gamemode/sv.lua` and `features/rounds/sv.lua`). The rounds model returns a new `match_start` effect from `RestartRound` when it leaves `GAME_OVER`, so the rule is tested where it lives.
- **Map change** resets everything for free: the Lua state is rebuilt.
- Money is reset when a match starts, not when one ends, so the intermission's scoreboard still shows what everyone held.
- A consequence: debt run up in Sandbox mode never reaches a match, because Begin Game starts one. Nothing is written to disk. A save across maps, if wanted, is P2 and happens at map end only.

**Judgment call: default `POLICY`.**

| Mode | Window | Charges | Applies now | Credit |
|------|--------|---------|-------------|--------|
| `SANDBOX` (no rounds, or stopped) | anywhere | yes (Q4: prices kept) | yes: the loadout is given at once, and at every spawn | `UNLIMITED_CREDIT` (Q4) |
| `GAMEPLAY` | respawn room, or anywhere during setup or preround | yes | in the respawn room (TF2 resupply) | `NO_CREDIT` |
| `AIWAR` | respawn room | yes | in the respawn room | `NO_CREDIT` (Q8) |
| `ARENA` | preround only (CS-style buy time) | yes | yes | `NO_CREDIT` |

### 3.3 How menu state syncs

| State | Carrier | Who listens |
|-------|---------|-------------|
| Loadout (owned, equipped) | `loadout_state` to the owner, on change and on `client_ready` | `cl_loadout.lua` raises `WSLoadoutChanged`; the Player and Inventory tabs redraw |
| Wardrobe (owned items, worn model, worn cosmetics) | `wardrobe_state` to the owner, on change and on `client_ready` | `cl_wardrobe.lua` raises `WSWardrobeChanged`; the Inventory Appearance section, the Player tab's model panel and the C-menu Wardrobe window redraw |
| Others' worn cosmetics | NW2 string `ws_cosmetics` on each player: the worn cosmetic names, joined | `cl_wardrobe.lua` bonemerges their models on every client (§4.2.1). Set on change and at spawn, never per tick. |
| Stat effects | Existing NW2 `ws_speed_scale` (attributes) and `ws_stun_*` (stuns) | `sh_core.lua` movement prediction and `cl_conditions.lua`, unchanged |
| Money | NW2 `ws_money`, now signed and possibly negative | Use `SetNW2VarProxy` → `WSMoneyChanged` on the client in place of Inventory's `Think` poll. The scoreboard reads it per row as today. |
| Mode | `WS.PlayMode()`, from Global2 `ws_rounds_active`, `ws_gameplay_halted` and the AI war and arena flags | Raises `WSModeChanged` on the client when its value changes. The stock tabs (Q2), the store header, the Buy buttons and the builder tools' panels listen. |
| Store window | Computed on the client from Global2 (`ws_round_state`, `ws_round_in_setup`) and a new NW2 bool `ws_in_respawn_room` | The client runs the same `Store.Window` and `Economy.Affords`, so the Buy buttons grey out with the reason. The server sets `ws_in_respawn_room` from `func_respawnroom` `StartTouch`/`EndTouch` (entity I/O, no polling), and once in `PlayerSpawn` if R4 says touches are unreliable. |
| Rank | `WS.RankOf(LocalPlayer())`, read when the menu builds | The stock tabs, the admin sections and the builder tools. A 1 s client timer compares the rank and raises `WSRankChanged`, which rebuilds only the affected panels. |
| Votes | `vote_started`, `vote_tally` (at most `TALLY_SECONDS` apart) and `vote_ended` | The Options > Voting panel and a HUD vote card |
| Handicap | Global2 `ws_handicap_team` (the supported team, or none) | Options > Match info, and the respawn timer's "Supported" tag |
| Match | Existing Global2 `ws_match_*`, plus `ws_match_paused` | Options > Match |
| Game layout (builder) | `layout_state { pieces }` to admins holding `GAME_BUILD`, on change and on `client_ready` | `features/builder/cl.lua` draws the placed pieces' markers and the track for admins (§4.3). Players see only the entities themselves. |

---

## 4. Q menu, tab by tab

Priority key: **P0** makes the direction work and closes its holes. **P1** is the expected next layer. **P2** is nice to have.

**Q menu layout (decisions Q2 and Q10).**

```
+------------------------------------------------------------------------+
| LEFT: creation tabs                     | RIGHT: tool tabs              |
|  [Player] [Inventory]                   |  [Tools] [Options] [Utilities] |
|  + stock tabs (Spawnlists, Weapons,     |  Tools: Sandbox's tools, plus  |
|    Entities, NPCs, Vehicles, Dupes,     |  the "Sandcastle Builder"      |
|    Saves): admins always; everyone in   |  category for GAME_BUILD only  |
|    Sandbox mode; hidden from non-admins |  (§4.3)                        |
|    in Gameplay mode                     |                                |
+------------------------------------------------------------------------+
```

There is no Operator tab.

### 4.1 Player (creation tab, left)

**Layout (kept).** Left 60%: the model, with Primary, Secondary and Melee boxes to its left and Support 1 and Support 2 to its right. Right 40%: the weapon list, titled by the slot picked.

**P0: available weapons, not only owned ones.** The direction says "available weapons". With a slot picked, list every catalog entry of that kind:

- Owned: equip on click (as today).
- Not owned: greyed, showing the price, with one click to buy and equip. In Sandbox mode this is never disabled for money (Q4).
- With no slot picked: owned first, then buyable, grouped by kind.

**Flow.** Extend `loadout_buy` with `slot = E.UInt(SLOT_BITS)`, where `0` means "first empty slot that takes it" (today's `Buy` behaviour). The model gains `Loadout:BuyInto(slot, weapon)`, which is `Buy` then `Equip` inside one value transition, so a refusal leaves nothing half done. The controller goes through the §3.2 pass.

Judgment call: one event with a `0` sentinel, rather than a second event. A separate `loadout_buy_into` is cleaner under parse-don't-validate. Either way, the factory must turn `0` into `nil` at the seam.

**P0: status per slot.** Each slot box shows one of:

- **Ready**: equipped and in hand.
- **Next spawn**: equipped but not yet given.
- **Empty**.

The hint line beneath the list becomes live and shows the §3.2 window reason ("Buy and change weapons in your respawn room"). The wrong-context hint (`cl_menu_player.lua:18`, which mentions "TF2 map") goes away: since Q4 the loadout is given in both modes.

**P0: resupply.** When `POLICY.appliesNow` holds and the player is inside a window, an equip or clear re-gives the loadout at once. No new event: the server decides inside `Change`. This mirrors TF2's `func_regenerate`.

**P1: loadout presets.** Below the model: three preset buttons (`PRESET_COUNT`), each with save and load, stored client-side in `data/sandcastle/presets.json`.

- Loading sends `loadout_preset { equipped = List(Record{slot, weapon}) }`.
- The server applies it with `FromState`-style equips over owned weapons only. Unowned entries are refused as one batch refusal ("2 weapons in this preset aren't owned"). Nothing is bought implicitly.

**P1: the worn model and cosmetics on the model panel.** The model panel shows the worn model with its worn cosmetics bonemerged (§4.2.1), and a "Change" link opens Inventory > Appearance. Beneath it, one line per active stat, phrased from the folded attributes the server last sent ("Move speed +10%", "Primary damage +15%", "Stuns on melee hit"); a stat that does not apply in the current mode is greyed with "Gameplay only". Colour, skin and bodygroups are edited in the Wardrobe panel (§4.2), not here. The model panel bonemerges the picked slot's world model into the hand.

**P1: AI War.** When `WS.AiWarActive()`, add a "Your squad" strip under the model. It shows the friendly fire team the player is attached to (if any), and its leader and job. This is read-only and comes from the `aiwar_slots` data the server already builds. Commanding a squad belongs in the C menu (§5.3).

**P2: drag and drop** from the list onto slot boxes, using `DDragBase` receivers. Same events.

### 4.2 Inventory (creation tab, left)

**Layout.** A `DCategoryList` as today, plus a header bar showing the balance (in `DEBT_COLOR` when negative, §3.2), the store window state and its reason, and a search box. Sections: Weapons (one row per kind), Appearance (models and cosmetics), and Map & server items.

**P0: store gating in the UI.** Buy buttons are disabled with a tooltip giving the §3.2 reason, or "Not enough money" when `Economy.Affords` fails. "Owned" tiles show "Equipped (Primary)" when equipped. The flow is the §3.2 one; nothing new on the wire.

**P1: Appearance, a paid store section (decision Q5).** Player models and cosmetics are store items. The Player models grid becomes the Appearance section of the store.

- **Model: new pure `foundation/wardrobe.lua`.** It is separate from `foundation/loadout.lua`, because neither a model nor a cosmetic takes a weapon slot.
  - Item kinds: `KIND_MODEL` and `KIND_COSMETIC` (§4.2.1).
  - `MODEL_PRICE`, the one price of a model, as `Loadout.PRICE` is of a weapon. Cosmetics carry their own prices (§4.2.1).
  - `Catalog(items, starters)`: the items on sale, each `{ name, kind, price }` plus the cosmetic fields, and the ones owned for free. A malformed entry raises `BadCatalog`.
  - A `Wardrobe` is an immutable value of owned names, the worn model's name and the worn cosmetics' names. `Buy(entry)`, `Wear(entry)` (a model), `WearCosmetic(entry)`, `RemoveCosmetic(entry)` and `Starting(catalog)` each return a new wardrobe or raise a named refusal (`UnknownItem`, `AlreadyOwned`, `NotOwned`, `NotWorn`, `SlotsFull`, `RegionTaken`), all kinds in `foundation/refusals.lua`.
  - `WornFor(wardrobe, catalog)`: the worn model if the catalog still offers it, else the catalog's first starter model. A team change can take a model off the menu without losing its ownership.
  - `CosmeticsFor(wardrobe, catalog)`: the worn cosmetics the catalog still offers, in wear order.
- **Which items are on sale.** `ws/sh_wardrobe.lua` builds the catalog in both realms from shared data, so the client prices it as the server does:
  - In Gameplay mode: the team's model allow-list, `foundation/factions.lua` `MODELS[team]` (a new constant), with `DEFAULT_MODEL[team]` as the free starter; and every cosmetic in `COSMETICS` (a shared data table in `ws/sh_wardrobe.lua`) whose optional `team` matches.
  - In Sandbox mode: every valid player model (`player_manager.AllValidModels()`), with `SANDBOX_DEFAULT_MODEL` as the free starter, and every cosmetic. Prices are kept and debt is allowed, as for weapons (Q4).
- **Events.** `wardrobe_buy { name }`, `wardrobe_wear { name }` (a model is worn in place of the last; a cosmetic is put on) and `wardrobe_remove { name }` (a cosmetic is taken off), `clientSendable` with `WARDROBE_RATE`; `wardrobe_state { owned, worn, cosmetics }` and the shared `refused { kind, subject }` back.
- **Controller: `ws/sv_wardrobe.lua`.** The §3.2 pass (window, `Buy`, `Store.Charge`, `WS.SpendMoney`, commit, publish). Wardrobes are keyed by `WS.AccountKey` and reset when a match starts (Q3). Wearing or removing a cosmetic is under the same window as a buy, and applies at once when `appliesNow` holds, else at the next spawn, as weapons do.
- **Enforcement.** `GM:PlayerSetModel` sets `WornFor(wardrobe, catalog)` and never reads `cl_playermodel`. That alone closes every free path: the stock C-menu editor, a typed `cl_playermodel`, or any addon that sets the convar.
- **What is free.** Colour (`cl_playercolor`), skin (`cl_playerskin`) and bodygroups (`cl_playerbodygroups`) of an owned model stay free and are applied in `PlayerSetModel` as base Sandbox does (research item R6).
- **UI.** One panel, `WS.UI.WardrobePanel`: a tile per model with its price and Buy, or Wear for an owned one; a Cosmetics row of tiles, each with its price, its stat lines (as on the Player tab) and Buy, Wear or Remove; and the worn slots (`COSMETIC_SLOT_COUNT` boxes). Beneath the worn model are the free colour, skin and bodygroup controls. The Inventory section and the C-menu Wardrobe window (§5.2) both embed it.

#### 4.2.1 Cosmetics that carry attributes (decision Q5, addition)

Cosmetics are not only looks: a cosmetic may carry TF2-style attributes that change its wearer's stats. This overrides the earlier judgment call that only models are paid.

**What a cosmetic is.** A wardrobe catalog entry of `KIND_COSMETIC`:

```
{ name, kind = KIND_COSMETIC, price, model (bonemerged on the wearer), region,
  attributes = { [attribute name] = value }, team (optional) }
```

A cosmetic with an empty `attributes` table is a look only. There is no parallel stat system: every value in `attributes` is a TF2 attribute that `foundation/players/attributes.lua` supports, and the attributes feature applies it.

**Attributes used, by TF2 name** (research item R12 confirms each name and its class against TF2's `items_game.txt`):

| Constant | TF2 name (class) | Effect here | Category |
|----------|------------------|-------------|----------|
| `MOVE_SPEED_ITEM` | `"move speed bonus"` (`mult_player_movespeed`) | multiplies top speed, beside the Wheel of Fate's `"major move speed bonus"` | `CATEGORY_MOVEMENT` |
| `DAMAGE_BONUS` | `"damage bonus"` (`mult_dmg`) | multiplies the damage dealt with the weapon in the item's `slot`; the first stat items use `SLOT_PRIMARY` | `CATEGORY_DAMAGE` |
| `STUN_ON_HIT` | Sandcastle's own `"stun on melee hit"`, unless R12 finds a TF2 attribute for it | grants the stun capability (§4.2.2) | `CATEGORY_CAPABILITY` |

A damage attribute names its slot because TF2's `"damage bonus"` lives on a weapon, and a cosmetic is not a weapon: the entry carries `slot = Loadout.SLOT_PRIMARY` and the bonus applies to whatever weapon the wearer has equipped in that slot.

**Slots: separate from the weapon slots.** Cosmetics never take a weapon slot (primary, secondary, melee, support1, support2), and the worn model is not a cosmetic slot.

- `COSMETIC_SLOT_COUNT`: how many cosmetics may be worn at once. TF2's loadout shows three cosmetic slots; the constant starts there and is tuning.
- Each cosmetic names an equip `region` (`REGION_HEAD`, `REGION_FACE`, `REGION_BACK`, `REGION_FEET`, like TF2's equip regions). Two worn cosmetics may not share a region: `WearCosmetic` raises `RegionTaken`, naming the worn one. A full set raises `SlotsFull`.

**Stacking.** As TF2 does for attributes of one class, values multiply:

- `Attributes.FoldItems(lists)` takes the worn cosmetics' attribute tables and returns one table, `name -> product of values`, each clamped to `STACK_LIMITS[name]` (a tuning constant per attribute: the most any set of items may give). A capability (`STUN_ON_HIT`) does not stack: it is present or not.
- The item layer and the trigger layer multiply: `SpeedScale(attrs, now, items)` is the trigger and wheel value (today's `ValueOr`) times the item value. A worn speed cosmetic and the wheel's speed bonus both count.

**Which apply in which mode.**

| Category | Sandbox mode | Gameplay modes (`GAMEPLAY`, `AIWAR`, `ARENA`) |
|----------|--------------|-----------------------------------------------|
| Looks (the bonemerged model) | yes | yes |
| `CATEGORY_MOVEMENT` | yes | yes |
| `CATEGORY_DAMAGE` | no | yes |
| `CATEGORY_CAPABILITY` (stun) | no | yes |

The rule is a constant, `MODE_CATEGORIES[category] = { [mode] = true }`, read by `Attributes.ActiveItems(folded, mode, statsEnabled)`, which drops what does not apply. Judgment call (§9): Sandbox mode is for building and its credit is unlimited (Q4), so damage and stuns there would be free griefing tools; movement is harmless and lets a player feel what they bought. A server setting, `mp_cosmetics_stats` (default 1; 0 makes every cosmetic a look only), turns stats off in every mode; it goes in `foundation/settings.lua` `SETTINGS` and Admin > Store & Economy (§4.5).

**Where it sits.**

- `foundation/wardrobe.lua` (above) holds ownership, wearing, slots and regions. `Wardrobe:Attributes(catalog)` returns the worn cosmetics' attribute tables, in wear order. The wardrobe does not fold or know modes.
- `foundation/players/attributes.lua` gains the item layer: the new names, `Supported` for them, `STACK_LIMITS`, `ATTRIBUTE_MAX[name]` (the most one item may carry), `CATEGORY[name]`, `MODE_CATEGORIES`, `FoldItems`, `ActiveItems`, `SpeedScale(attrs, now, items)` and `DamageDealtScale(items, slot)`. The catalog factory in `foundation/wardrobe.lua` asks it: an attribute it does not support, a value above `ATTRIBUTE_MAX`, or a stat item priced below `StatPriceFloor(attributes)` (below) raises `BadCatalog`.
- `features/attributes/sv.lua` gains `Controller:SetItems(ply, items)`, the folded and filtered item table, kept in `byItems[ply]`. `Clear` (spawn and death) leaves it alone: items last as long as they are worn. `Sync` reads both layers. Its 0.1 s timer still walks only players with timed trigger attributes; item values change only through `SetItems`.
- `ws/sv_wardrobe.lua` calls `WS.Feature("attributes"):SetItems(ply, ...)` after a wear or remove, at `PlayerSpawn`, and on `WSModeChanged` (a mode change turns categories on or off). It loads the attributes feature only when a stat cosmetic is first worn, so a map where nobody wears one never loads it.
- Damage: the attributes controller's `EntityTakeDamage` hook, when the attacker has items, scales by `DamageDealtScale(items, slot)`, where `slot` is the attacker's equipped slot of the inflicting weapon class, from `WS.LoadoutSlotOf(ply, class)` (a new adapter over `WS.Loadouts`). A weapon not in the loadout has no slot and gets no bonus.
- Looks: `ws/cl_wardrobe.lua` bonemerges each worn cosmetic's `model` (a `ClientsideModel` parented with `EF_BONEMERGE`) from NW2 `ws_cosmetics`, and drops them on death and when the string changes.

**Balance: stat items are pay-to-win within a match.** The design keeps that bounded and visible rather than pretending it away:

- **Price grows with power.** `StatPriceFloor(attributes)` is `COSMETIC_BASE_PRICE` plus, per attribute, `STAT_PRICE[name]` times the size of its effect (`|value - 1|` for a multiplier, `1` for a capability). A catalog entry priced under its floor is `BadCatalog`. All the numbers are named tuning constants.
- **The edge is capped.** `STACK_LIMITS` bound what any set of worn items can give, whatever is bought.
- **One budget.** Stat items, weapons and AI war orders (Q8) draw on the same balance, which a match starts at `STARTING_MONEY` and a Gameplay mode never lets go below `NO_CREDIT`. A player who buys speed has less to spend on weapons or on commanding squads.
- **AI war.** AI war soldiers do not buy or wear cosmetics (Q9 stays out of scope), so in `AIWAR` mode stat items tilt players against soldiers, and a team of big spenders against a team that saved. The counter already designed is the support vote (Q6): the other team respawns faster and gains tactics. The design does not scale soldiers by the enemy's worn stats; that is open question C1.
- **Off switch.** `mp_cosmetics_stats 0` makes a match looks-only, for servers that want no pay-to-win.

**Open questions (cosmetics).**

- **C1.** Should the AI war read the enemy team's folded stats (for example, total `DAMAGE_BONUS`) and widen its own allocation? Not designed; the support vote is the counter for now.
- **C2.** Which cosmetic models to ship. TF2's hats need TF2 content mounted and are made for TF2's class skeletons; HL2 player models need bonemerge-friendly props. Content choice, not design.

#### 4.2.2 The stun capability (decision Q5, addition)

"The ability to stun" is a capability a worn item grants (`STUN_ON_HIT`), not a weapon.

**New pure model: `foundation/players/stunner.lua`.**

- Constants, all tuning except the TF2 flags: `STUN_DURATION`, `STUN_SLOW` (the speed share taken), `STUN_FLAGS = Players.STUN.MOVEMENT` (TF2's `TF_STUN_MOVEMENT`: slowed, still able to shoot, as the Sandman's ordinary ball stun), `STUN_COOLDOWN` (per wearer), and `STUN_IMMUNE_AFTER` (how long after a stun ends its victim cannot be stunned by an item again).
- Victim kinds: `VICTIM_PLAYER`, `VICTIM_SOLDIER` (an AI war soldier), `VICTIM_OTHER` (engine NPCs, Halloween bosses, props).
- `Try(wearer, victim, facts, now)`, where `wearer = { readyAt }`, `victim = { immuneUntil }` and `facts = { melee, sameTeam, victimKind, alive, mode, active }`. It returns `stun, wearer', victim'` (the stun `{ duration, reduction, flags }` and the new timestamps) or `nil` with a reason constant (`NO_CAPABILITY`, `NOT_MELEE`, `SAME_TEAM`, `IMMUNE_VICTIM`, `COOLING_DOWN`, `VICTIM_IMMUNE`, `WRONG_MODE`). These are not refusals: no client asked for anything, so the reason is only for tests and the debug log.

**What triggers it.** A melee hit by the wearer: the inflictor is the weapon the wearer has equipped in `SLOT_MELEE` (`WS.LoadoutSlotOf`), the damage is greater than zero, and the victim is a living enemy of kind `VICTIM_PLAYER` or `VICTIM_SOLDIER`. A melee-only trigger keeps it a skill item: it costs the wearer the risk of closing in.

**Cooldown.** `STUN_COOLDOWN` after each stun, per wearer. The model compares timestamps at the next hit; no timer runs. The cooldown and the victim's immunity reset when a match starts, with the wardrobe.

**The condition it applies.** The existing `WS.StunPlayer(victim, STUN_DURATION, STUN_SLOW, STUN_FLAGS)`, folded with any other stun by `Players.Stun` as today. `foundation/players.lua` gains `COND.STUNNED = 15` (TF2's `TF_COND_STUNNED`, which TF2's `StunPlayer` adds), and `WS.InCondition(ply, COND.STUNNED)` answers true while `StunHas(stun, STUN.MOVEMENT, now)` holds, so `filter_tf_condition` and the HUD see it. Clients already predict the slow from NW2 `ws_stun_*`; `cl_conditions.lua` adds the stars over the head (as `features/npc/cl.lua` draws them for a stunned Monoculus).

**How NPCs and NextSoldier soldiers react.**

- **AI war soldiers (NextSoldier).** The soldier port (`foundation/aiwar/soldier.lua`) gains `IsStunned()` and the controller (`features/aiwar/sv.lua`) gains `Soldier:Stun(duration, reduction)`, which scales the DrGBase soldier's move speed by `1 - reduction` until the stun ends and publishes the same NW2 `ws_stun_*` values on the soldier for the client effect. The orders react in one place: `ChaseWanted` answers false while `IsStunned()`, so a stunned soldier keeps its job and fights from where it is but starts no chase. A stun counts as a hit in its `hurtLog` only by the damage dealt, so the retreat rule is unchanged. `TF_STUN_CONTROLS` stuns of soldiers (which would need a `Stunned` action like `Humiliated`) are not part of this: items only slow.
- **Other NPCs and bosses (`VICTIM_OTHER`).** Not stunned. The Halloween bosses have TF2's own stun rules (Monoculus's purgatory), and engine HL2 NPCs have no speed scale Lua can set reliably (open question S1).
- **Players.** Slowed by `STUN_SLOW` for `STUN_DURATION`, then immune to item stuns for `STUN_IMMUNE_AFTER`.

**Server cost.** One table lookup per damage event for attackers holding items, and nothing per tick.

**Open questions (stun).**

- **S1.** Should engine NPCs be slowed (for example, through `SetPlaybackRate` and the movement activity)? Not designed.
- **S2.** Is a stronger, rarer item stun (`TF_STUN_CONTROLS`, the Sandman's moonshot) wanted? It would need the soldiers' `Stunned` action.

#### 4.2.3 Map and server items, consumables, sell back

**P1: map and server items.**

- **Model.** `foundation/loadout.lua`'s catalog entries gain:
  - `source`: `SOURCE_BASE`, `SOURCE_MAP` or `SOURCE_SERVER`.
  - `category`: `CATEGORY_WEAPON` or `CATEGORY_CONSUMABLE`. Cosmetics are not loadout entries: they live in the wardrobe catalog (§4.2.1), and a map or server cosmetic joins that catalog instead.

  `Catalog:With(entries)` returns a merged catalog. A duplicate class raises `BadCatalog`, so a map cannot silently override a base weapon. The wardrobe catalog gets the same `With`.
- **Map items (entity-driven, per project direction).**
  - Add a point entity, `ws_store_item`, with keyvalues `class`, `name`, `kind`, `price` and `team` (optional). A `kind` of `cosmetic` sends it to the wardrobe catalog, with its attributes in keyvalues `attr_<n>_name` and `attr_<n>_value`.
  - Its `Initialize` registers the item. The inputs `Enable`, `Disable` and `SetPrice` let map logic open items per round. For example, the payload's last checkpoint unlocks the RPG.
  - The rounds controller rebuilds the catalog at round start, not per tick.
- **Server items.** `data/sandcastle/store.json` is read once at map start. The one factory parses it through `NewCatalog` (weapons and consumables) and the wardrobe's `Catalog` (cosmetics), so a bad file refuses with `BadCatalog` and is logged, and the base catalogs stay.
- **Wire.**
  - The catalog is now dynamic, so it must reach clients: send `store_catalog { entries = List(Record{class,name,kind,price,category}) }` on `client_ready` and on change, and `wardrobe_catalog` for cosmetics with their attributes.
  - Raise `WEAPON_COUNT_BITS` to a named `CATALOG_COUNT_BITS = 8` (gap 8).
  - The client's `WS.LoadoutCatalog` becomes "the catalog the server last sent".
- **Consumables** (health kit, ammo refill, a Halloween spell from `features/spells`) are bought and used at once, never slotted.
  - Events: `store_use { class }`.
  - The server checks the window and the charge, then runs the effect through the feature that owns it (`features/spells` for spells, `WS.GiveAmmo` for ammo).
  - The effect is a named function in a `CONSUMABLE_EFFECTS` table in the controller, keyed by class.

**P2: sell back.** `loadout_sell { weapon }` refunds `floor(price * SELL_SHARE)`. Same window, and the weapon must be unequipped first. This adds a `Loadout:Sell` value transition and an `Economy` `Earn` that does not count toward `mp_round_cashlimit`. That means a `WSMoneyEarned` reason, or a separate `Refund` call, so a refund cannot win a round. In Sandbox mode a refund simply reduces debt.

### 4.3 Game builder (tool tab, admins; preliminary; decision Q11)

Admins place the gamemode's TF2 map entities with the toolgun, to set up a game on a non-TF2 map: payload on `gm_construct`, or CTF. This section is preliminary; open questions are marked **B1** and up.

**Principle.** The builder places the same entities a TF2 map would hold, with the same keyvalues, so the same features load and run them (the entity-driven direction and `foundation/features.lua`'s lazy loader). It adds no game logic of its own. What it adds is a **layout**: a pure value describing the pieces, which is validated, saved, and turned into entities, and which is rebuilt after every round cleanup (gap 17).

**Entities a game needs, and what the gamemode has today.**

| Piece | TF2 class(es) | Today |
|-------|---------------|-------|
| Rules | `tf_gamerules` | A scripted entity. The rounds controller makes the proxy itself (`MakeProxy`, from `SetUpMap` or `EnsureRules`), so a layout never places one. |
| Team spawns | `info_player_teamspawn` | An engine class Lua cannot query; `ws/sv_world.lua` records its keyvalues (`TeamNum`) in `WS.KV` through `EntityKeyValue`. Whether that hook fires for a Lua `SetKeyValue` is research item R10. |
| Cart path | `path_track` chain | Engine class, recorded the same way (`target`, the next node). `team_train_watcher` and `foundation/aiwar/track.lua` walk it. |
| Cart | `func_tracktrain`, a cart prop, `team_train_watcher`, `trigger_capture_area` | The watcher and the capture area are scripted (the watcher drives the train with `handle_train_movement`). `func_tracktrain` is an engine brush entity: whether one can be created from Lua with a studio model and no brush is research item R11, and open question B1. |
| Checkpoints and points | `team_control_point`, `team_control_point_master` | `team_control_point` is GMod's inert engine class, read by `features/capture`; the master is scripted. |
| Round timer | `team_round_timer` | Scripted. |
| Respawn rooms, resupply | `func_respawnroom`, `func_regenerate` | Scripted brush volumes on `ws_brush_volume`, which takes its bounds from a map brush model. A placed volume needs box bounds instead (`mins`/`maxs` keyvalues; plan step 18). |
| CTF flag | `item_teamflag` | **Not implemented.** `features/gamemode/sv.lua:98` and `foundation/gameplay.lua` only count flags to describe a map. |
| CTF capture zone | `func_capturezone` | **Not implemented.** |

So payload is buildable once B1 is answered; CTF needs a CTF feature first (open question B6), and the layout model already refuses a CTF layout with `REASON_NOT_IMPLEMENTED` until it exists.

**New pure model: `foundation/game_layout.lua`.**

- Game kinds: `GAME_PAYLOAD`, `GAME_CTF` (later: `GAME_CP`, `GAME_KOTH`).
- Piece kinds, by the TF2 class each becomes: `PIECE_SPAWN`, `PIECE_TRACK` (one `path_track`), `PIECE_CART`, `PIECE_POINT`, `PIECE_TIMER`, `PIECE_RESPAWN_ROOM`, `PIECE_REGENERATE`, `PIECE_FLAG`, `PIECE_CAPTURE_ZONE`. `IMPLEMENTED[piece]` says which the gamemode can run today.
- `REQUIRED[game]`: the pieces each game needs. Payload: a spawn per team, a track of at least `TRACK_MIN_NODES` with its last node a checkpoint, one cart on the track's first node, a respawn room per team, and a timer. CTF: a spawn, a flag and a capture zone per team.
- A `Layout` is an immutable value: `{ map, game, pieces = { [id] = piece }, nextId }`, where `piece = { id, kind, pos, ang, team, mins, maxs, next, checkpoint }`. Positions are plain `{ x, y, z }` tables.
- Transitions, each returning a new layout or raising a named refusal: `New(map, game)`, `Place(layout, piece)` (`UnknownPiece`, `OnlyOne` for a second cart or timer), `ExtendTrack(layout, pos)` (appends a node after the track's tail, `TrackEnded` when the tail is the goal), `MarkCheckpoint(layout, id)` (`NotTrack`), `SetTeam(layout, id, team)` (`NoTeam` for a piece without one), and `Remove(layout, id)` (`NoSuchPiece`; removing a middle track node joins its neighbours).
- `Check(layout)`: `OK`, or raises `Unplayable` carrying **every** reason at once, so the admin sees the whole list: `REASON_NO_SPAWN` (per team), `REASON_NO_TRACK`, `REASON_TRACK_SHORT`, `REASON_TRACK_LOOP`, `REASON_NO_GOAL`, `REASON_NO_CART`, `REASON_CART_OFF_TRACK`, `REASON_NO_RESPAWN_ROOM` (per team), `REASON_NO_TIMER`, `REASON_NO_FLAG` and `REASON_NO_CAPTURE_ZONE` (per team), and `REASON_NOT_IMPLEMENTED` (per piece kind). `Unplayable` is the client's fault (their layout) and phrased through `foundation/refusals.lua`.
- `Entities(layout)`: the entity specs to create, in order, each `{ class, name, pos, ang, keyvalues, mins, maxs }`. Names are derived from piece ids (`LAYOUT_NAME_PREFIX .. id`), so links are keyvalues: each `path_track`'s `target` names the next node; the watcher's `train`, `start_node`, `goal_node`, and `linked_pathtrack_<n>`/`linked_cp_<n>` name the track and the checkpoints' `team_control_point`s; the capture area's `area_cap_point` names the cart's point. This is where outputs are wired: a payload needs no hand-wired outputs beyond what the watcher's linked keyvalues give, as in TF2's own payload prefab.
- `ToData(layout)` and `FromData(t)`: the save form. `FromData` is the one factory at the seam, refusing `BadLayout` for a wrong `LAYOUT_VERSION`, a missing field or a dangling `next`.

**Placing and linking: the tools.** A small family under a "Sandcastle Builder" tool category, in `addons/sandcastle/gamemodes/sandcastle/entities/weapons/gmod_tool/stools/` (whether Sandbox loads stools from a derived gamemode's entities folder is research item R9). Each tool's `LeftClick`, `RightClick` and `Reload` send one event to the server; the tool code holds no rules.

Tool modes are named `build_*`, with no `ws` prefix, and any setting a tool adds is an `mp_` convar (operator, 2026-10-11).

| Tool (mode) | Left click | Right click | Reload |
|-------------|------------|-------------|--------|
| `build_spawn` | place a team spawn at the hit point, team from the tool's RED/BLU option | remove the piece under the cursor | (none) |
| `build_track` | extend the track: a new `path_track` node at the hit point, after the tail. The first node also places the cart on it. | mark or unmark the nearest node as a checkpoint (the last node is always the goal) | remove the tail node |
| `build_volume` | first click sets one corner, second sets the opposite corner (raised by `VOLUME_HEIGHT`); the volume kind (respawn room, resupply, later capture zone) and team come from the tool's options | remove the volume under the cursor | cancel a half-placed volume |
| `build_point` (later) | place a standalone control point, for CP and KOTH | remove | (none) |
| `build_flag` (later, B6) | place a team's flag | remove | (none) |

- **Teams.** Set when placing (the tool option), and changed afterwards with a right-click property, "Builder ▸ Team ▸ RED/BLU", registered through `WS.EditorAction` on the pieces' proxies (`ws_proxy`, kind `"build"`), the same way carts and points get theirs. Engine point entities have no body, so the proxy is what the right-click finds.
- **Events.** `build_place { kind, pos, ang, team, option }`, `build_track_extend { pos }`, `build_checkpoint { id }`, `build_team { id, team }`, `build_remove { id }`, `clientSendable` with `BUILD_RATE`; `layout_state { pieces }` back to admins. Every request is checked with `WS.Can(ply, GAME_BUILD)` and refused outside Sandbox mode with `REASON_MODE`.
- **Building happens in Sandbox mode.** Placing logic mid-round breaks the round (§3.1) and is undone by the next cleanup anyway; the admin stops the game, builds, then begins it.
- **Feedback.** `features/builder/cl.lua` draws, for admins, a marker per piece (team-coloured), the track as a line through its nodes with checkpoints marked, and the volumes as boxes, from `layout_state`. A tool's HUD line shows `Check`'s first missing reason ("Needs a BLU spawn").
- **Audit.** Each placement and removal is an `admin_notices` line to admins only and the server log (`BUILD_CHANGED`, a new notice in `foundation/admin_notices.lua`).

**Controller: `features/builder/sv.lua`** (a lazy feature). It holds the map's layout and the entities made from it. Each request: decode, `WS.Can`, the layout transition, then create only the new piece's entities through `Entities` (or remove the piece's), commit, publish, audit. A small always-loaded `ws/sh_builder.lua` holds the console commands and, at map load, loads the feature only if a saved layout exists for the map (one `file.Exists`).

**From placement to a running round.**

1. **Entities appear; features load.** A created `team_train_watcher` calls `WS.Feature("capture")` and `WS.Feature("payload")` in its `Initialize`, as on a TF2 map. The loader loads them mid-map and tells clients to load their client parts (`foundation/features.lua`, `port:TellClients`). Nothing new is needed for loading; features that are loaded stay loaded until map change, even if the layout is cleared.
2. **The rounds mode is decided again (gap 18).** The rounds controller gains `Controller:Redetect()`, which reruns `SetUpMap`'s decisions (the master's mode, `HasObjective`, `MakeProxy` if there are objectives and no rules) whenever the builder applies a layout in Sandbox mode. If the rounds feature is not loaded yet, nothing is needed: its first `SetUpMap` sees the placed objectives.
3. **Begin.** The existing `mp_gameplay_begin` (Begin Game) starts the round. When the builder feature is loaded and its layout has pieces, the gamemode controller asks `Builder:Ready()` before the transition: `Check(layout)`. An `Unplayable` layout refuses the begin with its reasons to the admin who asked, and the map stays in Sandbox mode. A playable one begins as any map does: transition, match start (§3.2), `RestartRound`'s full reset.
4. **Every cleanup rebuilds the layout (gap 17).** The full reset runs `CleanUpMap`, which removes every placed entity. The builder recreates them from the layout in a `PostCleanupMap` listener, then asks the loaded features that index placed classes to re-read them (today `capture:Rebuild()`, which already runs on `PostCleanupMap` and on `RoundSpawn`). Whether a single `PostCleanupMap` pass can be ordered reliably after the builder's, or whether the rounds controller should call a registered restorer inside `CleanUpMap`, is research item R14.

**Saving and loading a layout per map: JSON under `data/`, not dupes or saves.**

- **The choice.** `data/sandcastle/layouts/<map>.json`, the `ToData` form, written and read by the builder controller. Console commands, admin-only (`GAME_BUILD`): `mp_layout_save`, `mp_layout_load`, `mp_layout_clear`, `mp_layout_check` (prints `Check`'s reasons). A saved layout loads at map start when `mp_layout_autoload` is 1 (the default); the map then starts in the mode `sv_gameplay_enabled` holds, as a TF2 map does.
- **Why JSON and not Sandbox dupes or saves:**
  - A layout must be rebuilt after every round cleanup (gap 17). Rebuilding from a value is a loop over `Entities(layout)`; re-pasting a dupe or reloading a save mid-match is neither cheap nor meant for it, and a save restores the whole map, props and all.
  - The validator, the save and the spawn read the same value, so what is checked is what is spawned. A dupe stores entities, not the layout's links and teams as data; it would have to be parsed back into a layout to be checked.
  - Dupes and saves go through Sandbox's spawn path, which the gate (§3.1) and R8 govern for players; layouts are not player content.
  - The file is small, human-readable and diffable, and a server operator can ship one per map.
- **The cost.** A layout is not shareable through the Workshop the way dupes are. Acceptable for a server-side game setup.

**Validation, refusals and errors.**

- The admin's mistakes are refusals, phrased on the client: an `Unplayable` layout, `REASON_MODE` (building mid-round), `REASON_RANK`, `OnlyOne`, `TrackEnded`, `NoSuchPiece`, and `BadLayout` from a hand-edited file (refused, logged, and the map keeps no layout).
- Our bugs propagate: an entity that fails to create from a spec `Check` accepted is logged as ours, not shown as the admin's fault.

**Open questions (game builder).**

- **B1.** The cart. Can `func_tracktrain` take a studio model and run its path without a brush (R11)? If not, the cart needs a Lua train entity that `team_train_watcher` drives, which is a payload feature change.
- **B2.** Payload Race (two tracks, `tf_logic_multiple_escort`) and multi-stage payload: one layout per stage, or one layout with stages? Not designed.
- **B3.** Hand-wired outputs (a door opening at a checkpoint). A later "Wire output" tool could add `{ from piece, output, to piece, input }` links to the layout; `Entities` would write them as output keyvalues. Not designed.
- **B4.** Spawn doors, `func_respawnroomvisualizer` and setup gates. A built map has none; the game runs without setup (`REQUIRED` does not ask for them).
- **B5.** Nav mesh. The AI war needs one (`docs/aiwar-command.md`); a built payload on a map without a nav mesh plays for players only until it is generated.
- **B6.** CTF needs a CTF feature (`item_teamflag`, `func_capturezone`, the flag's carry, drop and return rules) before its pieces can run. The layout already knows its pieces and refuses with `REASON_NOT_IMPLEMENTED`.
- **B7.** Should several layouts per map be kept (a payload and a CTF on `gm_construct`), chosen by name (`mp_layout_load <name>`)? One per map for now.

### 4.4 Options (tool tab, right)

**Layout.** Category Sandcastle. Panels: **Match info** (everyone), **Voting** (everyone), **Match control** (admins), and **AI War control** (admins, when relevant).

**P0: Match info, read-only.** Mode (Sandbox, Gameplay, AI War, Arena, from `WS.PlayMode()`), map, round state, time left (`ws_match_time_end`), win limit, max rounds and rounds played (`ws_match_*`), next map, and the supported team if a support vote passed. Everything is replicated, so there is no server work.

**P0: Voting.**

- **Model.** `foundation/vote.lua`, pure.
  - Kinds: `KIND_MAP`, `KIND_KICK`, `KIND_RESET` (restart the round), `KIND_SCRAMBLE`, `KIND_SUPPORT` ("support the other team").
  - Constants: `DURATION`, `QUORUM_SHARE`, `PASS_SHARE`, `CALLER_COOLDOWN`, `FAILED_COOLDOWN`, and `TEAM_ONLY[kind]` (`KIND_SUPPORT` is voted by the caller's team only).
  - `Call(state, caller, kind, subject, now, electorate, mode)` gives a new state or a refusal: one at a time, a cooldown, an admin who is immune to kick, a self-kick, a kind disabled by its convar, a kind refused in this mode, or a support vote for a team already supported.
  - `Cast(state, voter, choice)` gives a new state.
  - `Result(state, now)` gives `PENDING`, `PASSED` or `FAILED`.
- **Events.**
  - `vote_call { kind, subject }` and `vote_cast { choice }`: `clientSendable`, `VOTE_RATE`.
  - `vote_started { id, kind, subject, caller, ends, team }` and `vote_tally { id, yes, no, needed }`: to the electorate.
  - `vote_ended { id, passed }`.
- **Console commands (decision Q7),** client commands that send `vote_call` or `vote_cast`, so a vote can be called from the console or a bind as in TF2's `callvote`:
  - `mp_vote_kick <player>`, `mp_vote_map <map>`, `mp_vote_reset`, `mp_vote_scramble`, `mp_vote_support`.
  - `mp_vote_cast yes|no`.
- **Controller.** `ws/sv_votes.lua`.
  - The deadline is one `timer.Create` per vote. A tally goes out on each cast, throttled to `TALLY_SECONDS`.
  - A passed vote runs its effect:

    | Kind | Effect |
    |------|--------|
    | Map | the rounds controller's next-level setting |
    | Kick | `game.KickID` |
    | Reset | the rounds controller's restart (`mp_round_restart`'s path) |
    | Scramble | the existing scramble path in `features/rounds/sv.lua` (`mp_teams_scramble`'s); it also clears the support |
    | Support | supports the team opposing the callers (decision Q6, below) |

- **Decision Q6: what "support the other team" does.** The caller's team votes; if it passes, the other team is supported for the rest of the match.
  - **Model: new pure `foundation/handicap.lua`.**
    - `WAVE_SCALE`: the share of its respawn wave a supported team waits. A tuning constant below 1.
    - `NO_SCALE = 1`, what an unsupported team gets.
    - `CAPABILITIES`: the AI capabilities a supported team gains, today `{ Capabilities.AMBUSH }` from `foundation/aiwar/capabilities.lua`.
    - A `Handicap` is an immutable value: `New()`, `Grant(team)` (a new value, or the refusal `AlreadySupported`), `WaveScale(team)` and `Capabilities(team)` (a capability set, empty for an unsupported team).
  - **(a) Faster respawns.** `foundation/rounds.lua` gains `Round:SetWaveScale(team, scale)`. `Round:WaveMaxLength` multiplies its TF2 result by the team's scale, after `MIN_SCALED_WAVE` and the team-size scalar, so the handicap shortens what TF2 would have given. `NextRespawn`, `WaveDue` and `RespawnAt` all go through `WaveMaxLength`, so the players' respawn timer and the AI war's reinforcements (`features/aiwar/sv.lua:1156`) both speed up with no further change. Setup and sudden death are unchanged: setup's waves are already 0, and sudden death has none.
  - **(b) Extra AI tactics.** The controller hands `Handicap:Capabilities(team)` to the AI war (§4.4.1). The supported team's soldiers may then use tactics their opponents' soldiers do not.
  - **Lifetime.** The handicap resets when a match starts (with money, §3.2), and a scramble clears it, because the players it was voted for are no longer one side. Global2 `ws_handicap_team` publishes it.
  - **Mode.** Refused in Sandbox mode with `REASON_MODE`. On a TF2 map without an AI war, only (a) has an effect.
- **Gating.**
  - Kick and map: any mode.
  - Reset, scramble and support: Gameplay mode only, refused in Sandbox mode with `REASON_MODE`.
  - The `VOTE_CALL` ability can be raised to admin by `mp_vote_admin_only`.
- **Convars (decision Q7: `mp_vote_*`, not TF2's `sv_vote_*`).** Each is in `foundation/settings.lua` `SETTINGS`, so `ws_server_set` clamps it:

  | Convar | Replaces TF2's | Meaning |
  |--------|----------------|---------|
  | `mp_vote_enabled` | `sv_allow_votes` | votes at all |
  | `mp_vote_kick_enabled` | `sv_vote_issue_kick_allowed` | kick votes |
  | `mp_vote_map_enabled` | `sv_vote_issue_nextlevel_allowed` | next-map votes |
  | `mp_vote_reset_enabled` | `sv_vote_issue_restart_game_allowed` | restart votes |
  | `mp_vote_scramble_enabled` | `sv_vote_issue_scramble_teams_allowed` | scramble votes |
  | `mp_vote_support_enabled` | (Sandcastle only) | support votes |
  | `mp_vote_duration` | `sv_vote_timer_duration` | seconds a vote runs; default `DURATION` |
  | `mp_vote_quorum` | `sv_vote_quorum_ratio` | the share that must vote; default `QUORUM_SHARE` |
  | `mp_vote_cooldown` | `sv_vote_creation_timer` | seconds between a caller's votes; default `CALLER_COOLDOWN` |
  | `mp_vote_admin_only` | (Sandcastle only) | raises `VOTE_CALL` to admin |

- **Layout.**
  - A kind dropdown. The subject is a map list for map, or a player list for kick (excluding immune players).
  - A Call button, disabled with a reason.
  - The live vote, if any: its kind and subject, a yes/no bar with the "needed" marker, F1/F2 hints, and a countdown. The same card is drawn on the HUD.
  - F1/F2 bind to `vote_cast` while a vote runs. Bind them with `PlayerBindPress`; do not take over `gm_showhelp`.

#### 4.4.1 The AI capability flag (decision Q6 b)

**New pure model: `foundation/aiwar/capabilities.lua`.**

- Constants: `AMBUSH`, the first capability. Later ones join the constant list `KNOWN`.
- A capability set is an immutable value: `None()`, `set:With(capability)` (an unknown capability is our bug: the refusal `UnknownCapability`, never a client error), and `set:Has(capability)`.

**Where it is held and read.**

- `foundation/aiwar.lua`'s `War` gains `War:SetCapabilities(team, set)` and `War:Capabilities(team)`, `None()` until set. The aiwar controller listens for a new `WSHandicapChanged(team)` hook and copies `Handicap:Capabilities(team)` in, at the moment the vote passes and when a match starts. Nothing is read per tick.
- The Commander (`docs/aiwar-command.md` §2, phase 5) reads it into its `Situation` as `situation.capabilities`, and its allocation (§2.2) offers the `ambush` job only to a team whose set `Has(AMBUSH)`. Until the Commander exists the flag is held, tested and published, and changes no behaviour.

**The ambush tactic's inputs.** The tactic itself (where a squad waits, when it rushes, how it gives up) is NextSoldier work and is not designed here. Its inputs, named so that work can start from them:

| Input | Shape | Source |
|-------|-------|--------|
| Passages | `{ id, areas (nav area ids), mouth (a position where the passage opens into a room), room (the nav area ids of that room), width }` | The nav mesh, once per map at war start (as lanes are routed): narrow runs of areas, under `PASSAGE_MAX_WIDTH`, joining two wider regions. "Known" passages are those on the enemy's lanes (`foundation/aiwar/lanes.lua`) or within the team's zone. |
| A player approaching | `{ passage, enemy, seen (a position), time }` | Reports only, per `docs/aiwar-command.md` §0.6 (knowledge is earned): a sighting or heard gunfire (`foundation/aiwar/hearing.lua`) of an enemy player within `APPROACH_RANGE` of a passage's far end, moving toward it. No position is read from an unseen player. |
| The capability | `War:Capabilities(team):Has(AMBUSH)` | The handicap (above) |

Tuning constants the tactic will need, all named, none fixed here: `PASSAGE_MAX_WIDTH`, `APPROACH_RANGE`, `AMBUSH_WAIT_MAX` (how long a squad waits before it gives up), and `AMBUSH_SQUAD_SHARE` (the most of a team's squads that may wait in ambush at once).

**P0: Match control (admins).** These replace the stubs. Each is an event checked with `MATCH_CONTROL`, or an admin console command (decision Q7: `mp_`, subject-verb):

| Control | Mechanism |
|---------|-----------|
| Begin Game / Stop Game | Moved here from Utilities > Admin > Gameplay Settings, which keeps the settings sliders: `mp_gameplay_begin` and `mp_gameplay_stop` (exist). Begin Game starts a match, which resets money and ownership (§3.2); the button's tooltip says so. On a map with a built layout, Begin Game first checks it (§4.3). |
| Restart round | New `mp_round_restart` |
| Scramble teams now | New `mp_teams_scramble` |
| Force win RED/BLU/stalemate | `mp_forcewin` (exists) |
| Extend time | New `mp_round_timer_add <seconds>`. It drives the active `team_round_timer`'s `AddTime` input, which goes through entity I/O. Buttons: +1, +5 and +10 min. |
| Pause | New `mp_match_pause` and `mp_match_resume`. They hold `team_round_timer`s (`Pause` input) and set `tf_player_movement_restart_freeze` plus a Global2 `ws_match_paused` that the HUD shows. `ns_soldiers_paused 1` is set while the AI war runs. A pause is a state toggle, not a tick loop. |
| Bosses (P1) | Buttons for HHH, Monoculus and Merasmus that call the existing `tf_halloween_force_boss_spawn` and `cc_spawn_merasmus_at_level` through one `admin_boss { boss, level }` event, gated by `MATCH_CONTROL` and by the holiday feature being loaded. Moved here from the deleted Operator tab's plan. |

Each action fires an `admin_notices` line to everyone, as TF2 announces a scramble.

**P1: AI War control (admins, `WS.AiWarActive()` or AI war maps).** This is the quick surface of `ws/sh_aiwar.lua`: Start and End (`mp_aiwar_start` and `mp_aiwar_end`), team size (`WS.ServerSlider` over `mp_aiwar_team_size`), "Add soldier to RED/BLU" (sets `mp_aiwar_team_size` to `CUSTOM_SIZE` if needed and adds a slot through `foundation/aiwar/slots`), and the pause switch (`ns_soldiers_paused`). Anything that tests squads stays in Utilities.

**P2: Arena settings.** `mp_arena_round_time` and `mp_arena_preround_time` sliders, added to `foundation/settings.lua` `SETTINGS`.

### 4.5 Utilities (tool tab, right)

**Layout.**

- **User > Sandcastle** (everyone): Comfort, HUD and Audio sub-sections.
- **Admin > Gameplay Settings** (exists), plus new **Admin > Store & Economy**.
- **Sandcastle > AI War, AI Node Graph, Debug NextSoldier**: move these under the Admin category, or register them only for holders of `SERVER_SETTINGS` or `NPC_DEBUG`. `PopulateToolMenu` runs once, so re-run it through `spawnmenu_reload` on `WSRankChanged`, as the stock-tab hiding does (gap 10).

**P0: make the comfort switches real.**

- **Model.** `foundation/comfort.lua`, pure: `MOTION_SCALE_REDUCED`, `FLASH_ALPHA_MAX_REDUCED`, and `Scale(kind, settings)`, the factor an effect applies. Tests derive from these constants.
- **Convars.** Create the three convars with `userinfo = true`, so `ply:GetInfoNum` works on the server for effects only the server can filter. Move them out of `cl_menu_utilities.lua` into a new `ws/sh_comfort.lua` that both realms load.
- **Effects become events (preferred).** This follows the game event library direction: the server fires facts, and clients own the presentation. Server-driven `util.ScreenShake`, `ViewPunch` and `ScreenFade` calls in:
  - `foundation/npc/{headless_hatman,eyeball_boss,merasmus,ghost,zombie}.lua`
  - `foundation/spells/*`
  - `foundation/hazards/zapper.lua`

  become game events (`effect_shake { pos, amplitude, radius }`, `effect_fade { color, duration }`). The client consults `WS.Comfort` before drawing them. Where an effect must stay server-side, the controller checks `ply:GetInfoNum` per recipient.
- **Client consumers.**
  - `ws/cl_conditions.lua` overlays: alpha clamped under reduced flashing, hidden under hide effects. The new stun stars (§4.2.2) are an overlay too.
  - `features/npc/cl.lua` particles: skipped under hide effects.
  - Kill feed and capture HUD flashes: no blinking under reduced flashing.
  - A `CalcView` hook damps the view punch when motion is reduced. Whether Lua can see the engine view punch in `CalcView` needs a quick check (open research item R1).
- **Limits** (write them in the panel's help text):
  - Engine particles from TF2 map entities cannot be fully suppressed from Lua.
  - "Hide special effects" covers Sandcastle's own effects.

**P1: more client options** in User > Sandcastle. Each is a `cl_` convar with a `CreateClientConVar` default mirrored in `addons/sandcastle/cfg/sandcastle_defaults.cfg`:

- `cl_npc_ragdoll_lifetime` slider (exists, not in the menu).
- `cl_hud_round_timer_y` slider (exists).
- Announcer volume (`cl_announcer_volume`) and a hit sound switch (`cl_hitsound_enabled`).
- Kill feed size (`cl_killfeed_max`).
- Colour-blind team colours (`cl_teamcolors_colorblind`).
- Hide other players' cosmetics (`cl_cosmetics_hidden`): looks only; stats still apply.
- "Remove decals" (`r_cleardecals`).

**P1: Admin > Store & Economy.** Through `ws_server_set` and `foundation/settings.lua` `SETTINGS`:

- `mp_store_price_scale` (percent), `mp_store_window` (the `POLICY` override), `mp_economy_start_money`.
- `mp_cosmetics_stats` (§4.2.1).
- Kill and objective rewards, if the economy grows them.
- A "Give money" admin action: `economy_grant { target, amount }`, `MATCH_CONTROL`, audited.

The Sandbox-mode credit rule (Q4), `ORDER_PRICE` (Q8) and the stat price floors (§4.2.1) are not exposed as settings: they are decisions, not tuning a server operator should flip.

**P2: Sandbox server settings** shown only in Sandbox mode: `sbox_max*`, `sbox_godmode` and `sbox_noclip`, through `ws_server_set`. Sandbox's own Admin panels already exist, so only add what they lack.

---

## 5. C menu (held C): preliminary design

### 5.1 What belongs in C, not in Q

Q is for **planning**: what you own, what you will spawn with, what you wear, what you vote, and what the server is set to. You open it, decide, and close it.

C is for **acting on the world in front of you, now**. You hold it, point at something, and right-click. Every C entry should name a target: an entity under the cursor, a place, or "me, here".

So:

- **Properties stay the C menu's main surface.** Each is gated by `WS.Can` in `Filter` (client) and again in `Receive` (server), as `WS.EditorAction` already does.
- **Desktop icons are for small floating windows** that a player keeps open while playing.
- **The menu bar is for quick toggles.**

### 5.2 Remove or gate what Sandbox puts there (P0)

- **Player Model desktop icon (decision Q5).** Replaced, in both modes. `ws/cl_wardrobe.lua` removes `list.GetForEdit("DesktopWindows").PlayerEditor` when it loads (base Sandbox's list is filled before the derived gamemode's files run) and adds a `WSWardrobe` desktop icon, "Wardrobe", in its place. The window embeds `WS.UI.WardrobePanel` (§4.2): buy and wear models and cosmetics, and the free colour, skin and bodygroup controls. Removing the icon is presentation only; the server's `GM:PlayerSetModel` ignores `cl_playermodel`, so neither the stock editor (if an addon brings it back) nor a typed convar can bypass the store.
- **Menu bar "NPCs"** (`ai_disabled`, `ai_ignoreplayers`, keep corpses, join squad). These are server convars, so they work only for a listen host. `ai_disabled` or `ai_ignoreplayers` silently breaks AI War and boss behaviour. In a `PopulateMenuBar` hook, remove that menu for everyone unless `NPC_DEBUG`. For those who keep it, add a Sandcastle submenu next to it (§5.4).
- **Stock properties.** Gate them with the §3.1 `CanProperty`, `CanDrive` and gameplay-entity rule. Remove, Drive, Ignite, Statue, Collision and Bone Manipulate are refused on gameplay entities for everyone below admin in Gameplay mode (Q1).

### 5.3 Proposed contents

**P0: properties on teammates and objects (everyone).**

| Property | Target | Flow |
|----------|--------|------|
| "Spectate" (exists, admin) | living NPC or NextBot | keep. Add a player-facing version for dead players and spectators, limited to own-team targets (`spectate_target` event, checked against `foundation/spectate` rules). |
| "Ping / Mark" | any entity or world point | `world_mark { pos, ent }`, rate `MARK_RATE`. The server rebroadcasts to the marker's team only as a `world_marked` game event, and clients draw a fading marker. Use `util.worldpicker` for world points. Server cost is one event per click. |

**P1: commanding AI war soldiers (AI War mode, own team; decision Q8).** This is where AI War meets the player.

The "commands (pushed down as events)" channel in `docs/aiwar-command.md` §0.5 gets a player source: right-click a friendly soldier → **Squad** → Follow me, Hold here, Push with me, or Release. Each entry shows its price.

- **Event.** `aiwar_order { soldier, order }`, rate `ORDER_RATE`.
- **Model: new pure `foundation/aiwar/player_orders.lua`.** Constants `FOLLOW`, `HOLD`, `PUSH`, `RELEASE` and `ORDER_PRICE` (a tuning constant, the same for every order). `Order(kind, facts)`, where `facts = { mode, callerTeam, soldierTeam, callerAlive }`, returns an order value for the soldier's fire team or raises a named refusal: `REASON_MODE` outside `AIWAR`, `NotYourTeam`, `REASON_DEAD`.
- **Controller pass** (in `features/aiwar/sv.lua`'s event listener, which only coordinates):
  1. Decode; resolve the soldier entity to its fire team.
  2. `PlayerOrders.Order(...)`.
  3. `local amount, floor = Store.Charge(POLICY[WS.PlayMode()], PlayerOrders.ORDER_PRICE)`, then `WS.SpendMoney(ply, amount, floor)`. In `AIWAR` mode the floor is `NO_CREDIT`, so an order the player cannot afford is refused with `INSUFFICIENT_FUNDS` and nothing is charged or delivered (§3.2).
  4. Deliver the order to the squad as a command event. A player order is one input the Commander weighs; it never bypasses `TacticalMonitor` (`docs/aiwar-command.md` §0.2).
  5. Publish the new balance (through `ws_money`) and refuse or confirm to the caller.
- **What the money buys.** The charge is for an order accepted into the squad's command channel. Soldiers that later ignore it (retreating at low health, per §2.3 of the AI war doc) do not earn a refund: commands steer, they do not puppet.
- **Tick cost.** Nothing new per tick; orders are consumed where decisions already run.

Judgment call: orders go to a squad, not a single soldier. The property targets one soldier but acts on that soldier's fire team, so the model stays "a team decides together".

**P1: Loadout quick-swap desktop window (Gameplay).** A desktop icon, "Loadout", opens a small always-on-top `DFrame` showing the five slots, the balance (in `DEBT_COLOR` when negative) and the store window state. Clicking a slot cycles through the owned weapons of its kind (`loadout_equip`). Same events as the Player tab. It is for re-equipping in the respawn room without opening Q.

**P1: Admin properties.** Registered through `WS.EditorAction`, so each is checked on both realms. The events take the `admin_` prefix; there is no Operator any more.

| Property | Target | Event / permission |
|----------|--------|--------------------|
| Move to team ▸ RED/BLU/Spectator | player or team NPC (including an NPC just spawned from the stock NPCs tab) | `admin_set_team { ent, team }`, `MATCH_CONTROL`; NPCs go through `WS.SetTeamMember`, so they fight for that team and hold an account |
| Give money ▸ +100/+500 | player | `economy_grant`, `MATCH_CONTROL`, audited |
| Give loadout weapon ▸ | player | `admin_give { class, target }`, `MATCH_CONTROL`, audited |
| Slay / Respawn | player | `admin_player { ent, action }`, `MATCH_CONTROL` |
| AI war: Pin as leader, Remove slot | AI war soldier | reuse the `ns_squads_*` and `mp_aiwar_slots_*` commands, as the slot tree does. Sits beside the existing "Debug NPC". |
| Builder ▸ Team ▸ RED/BLU, Checkpoint, Remove | a placed builder piece (its `ws_proxy`, kind `"build"`) | the §4.3 events, `GAME_BUILD`, Sandbox mode only |

**P1: Sandcastle menu bar entry** (`PopulateMenuBar`, `menubar:AddOrGetMenu("Sandcastle")`):

- Everyone: the comfort toggles (`AddCVar` on `cl_reduce_motion`, `cl_reduce_flashing` and `cl_hide_effects`), Stop sounds, and Remove ragdolls. These are one press from play, where the player needs them most.
- `NPC_DEBUG`: Show All and Clear All debug, and the overlay parts (now in `cl_ns_debug.lua`).

**P2: Tool panel visibility.** In Gameplay mode, return `false` from `ContextMenuShowTool` for players without `SANDBOX_SPAWN`. The toolgun works only on non-gameplay entities there (Q1), and the panel only takes up space. Admins keep it, which is where the builder tools' panels show while they hold the toolgun.

### 5.4 C menu layout summary

```
+--------------------------------------------------------------------+
| [Sandcastle v] [Drawing v] [NPCs v (NPC_DEBUG only)]     menu bar  |
+--------------------------------------------------------------------+
| (Wardrobe) (Loadout) (AI War orders*)           |  active tool's   |
| desktop icons, top-left; no "Player Model"      |  panel (Sandbox  |
|                                                 |  mode / admins;  |
|                                                 |  builder tools)  |
|        world: right-click an entity -> properties                  |
|        (Ping, Squad > orders ($), Spectate,                        |
|         admin: Team/Money/Weapon/Slay, Builder > Team/Remove)      |
+--------------------------------------------------------------------+
* an optional desktop window: a list of your team's fire teams with
  one-click orders, each priced, for players who command more than
  they fight (P2).
```

---

## 6. Product decisions (answered by the operator, 2026-10-10)

- **Q1. Sandbox freedoms in Gameplay mode.** *Decided: yes, all of it.* Non-admins lose all free Sandbox spawning while rounds run: weapons, NPCs, entities, props, and the physgun on gameplay entities. Props are no longer an exception. Folded into §3.1 (the gate), §5.2 and §5.3 P2.
- **Q2. Sandbox's stock creation tabs.** *Decided: hidden for non-admins in Gameplay mode; everyone keeps them in Sandbox mode.* Folded into §3.1 and the §4 layout.
- **Q3. What a purchase lasts.** *Decided: the match.* Money and ownership survive rounds and reconnects (keyed by SteamID64) and reset at match end or map change. Folded into §3.2 (persistence and lifetime), §4.2 and §4.4.
- **Q4. The loadout in Sandbox mode.** *Decided: prices kept; everyone may go into debt, with no consequences; the loadout is given at spawn as in Gameplay mode.* Folded into §1.1, §1.3 gap 14, §3.2 (where the debt rule lives, how debt shows) and §4.1.
- **Q5. Paid player models or cosmetics?** *Decided: paid, bought in the store.* Inventory > Player models becomes the Appearance store section, and the C-menu Player Model icon is replaced so it cannot bypass it. **Addition (2026-10-10): cosmetics carry stats** (faster movement, a damage multiplier on the primary weapon, the ability to stun), which overrides the earlier judgment call that only models are paid. Built on the existing TF2 attributes and stuns, not a parallel system. Folded into §1.1, §1.3 gap 16, §4.1, §4.2 (through §4.2.3), §5.2 and §8 steps 9, 10 and 17.
- **Q6. What "support the other team" does.** *Decided: (a) the other team respawns faster; (b) its AI gains extra tactics, such as squads ambushing from known passageways.* Respawn timing and capability values are named tuning constants. Folded into §4.4 and §4.4.1.
- **Q7. TF2 command names or subject-verb?** *Decided: use `mp_`.* Every new gameplay command and convar takes the `mp_` domain with subject-verb naming, votes included (`mp_teams_scramble`, `mp_vote_kick`, `mp_vote_map`, `mp_vote_support`, `mp_vote_reset`, and `mp_vote_*` settings in place of TF2's `sv_vote_*`). Client convars stay `cl_`; NextSoldier's stay `ns_`. The earlier "keep TF2's `sv_vote_*` verbatim" call is dropped. Folded into §2, §4.4, §4.5 and every name in §8, where each step checks its new names with `check_engine_names.sh`.
- **Q8. Should ordering AI war squads cost money?** *Decided: yes,* at a named constant price, refused when the player cannot afford it. The Q4 debt rule does not apply: orders exist only in AI War mode, whose credit is none. Folded into §3.2 and §5.3.
- **Q9. Can team NPCs spend their money** (buy kit from the same catalog)? The economy already gives them accounts. *Unchanged: out of scope here; noted for AI War.* The bank's explicit `floor` (§3.2) means an NPC purchase would also have to name its credit, so nothing can borrow by accident. Soldiers therefore wear no cosmetics (§4.2.1, balance).
- **Q10. An Operator tab?** *Decided: none.* The operator deleted `ws/cl_menu_operator.lua` and `ws/sh_operator_spawn.lua`. Admins use Sandbox's standard creation tabs, visible to admins always and hidden from non-admins in Gameplay mode (Q2). The left-side Sandcastle tabs are Player and Inventory. The Sandbox gate is the single place admin-only spawning is enforced. Folded into §1.1, §1.3 gaps 2, 3, 12, 13 and 15, §3.1, §4, §5.3 and §8.
- **Q11. Placing TF2 map entities on other maps.** *Decided: a game-builder tool for the toolgun, admin-only; preliminary.* It answers the loss of Q10 (non-spawnable map entities) and lets admins set up payload or CTF on a non-TF2 map. Folded into §1.3 gaps 15, 17 and 18, §4.3, §5.3 and §8 step 18; its open questions are B1-B7.

## 7. Research items (technical, for the implementer)

- **R1.** Whether `CalcView` sees or can cancel the engine's view punch and screen shake on the client. Check this before choosing between the "event" and "GetInfoNum" routes for each effect in §4.5.
- **R2.** Whether NextBots honour `ai_disabled` in GMod, which decides how dangerous the stock NPCs menu is.
- **R3.** Whether Sandbox's default `CanProperty` lets non-owners Remove or Drive map-created entities on a dedicated server. Confirm before writing the gameplay-entity filter.
- **R4.** Whether `func_respawnroom` `StartTouch`/`EndTouch` fire reliably for players on a respawn, or whether the room should be tested once in `PlayerSpawn` as well.
- **R5.** What `SteamID64()` returns for bots and in single player. If bots share a value, `WS.AccountKey` gives a bot `"bot:" .. ply:UserID()`; bots never reconnect, so they lose nothing by it.
- **R6.** Which of `cl_playercolor`, `cl_playerskin` and `cl_playerbodygroups` base Sandbox's player class applies, and where (`player_sandbox` `SetModel` or `Spawn`), so `GM:PlayerSetModel` replaces only the model choice and keeps the free variants.
- **R7.** The keys of Sandbox's stock creation tabs in `spawnmenu.GetCreationTabs()`, and whether removing them and running `spawnmenu_reload` is enough, or whether `PopulateContent`/`PopulatePropMenu` hooks rebuild them.
- **R8.** Whether Sandbox's Saves (`gm_save` loading) and the Dupes tab spawn through `PlayerSpawnObject`/`PlayerSpawnSENT`, or need their own refusal (`CanArmDupe` and a save-loading hook).
- **R9.** Whether Sandbox's `gmod_tool` loads stools from a derived gamemode's `entities/weapons/gmod_tool/stools/`. Its loader runs `file.Find(SWEP.Folder .. "/stools/*.lua", "LUA")` (`gamemodes/sandbox/entities/weapons/gmod_tool/stool.lua:146`); confirm the gamemode's folder is on that path, else ship the stools under `addons/sandcastle/lua/weapons/gmod_tool/stools/`.
- **R10.** Whether `ents.Create` works for the engine classes a layout places (`info_player_teamspawn`, `path_track`, `team_control_point`), and whether `EntityKeyValue` fires for a Lua `SetKeyValue`, so `WS.KV` records their keyvalues as it does a map's. If not, the builder writes `WS.KV` for the entities it creates.
- **R11.** Whether a Lua-created `func_tracktrain` with a studio model (the cart prop) and no brush model follows its `path_track` chain and answers the watcher's speed inputs (open question B1).
- **R12.** The exact TF2 attribute names and classes for move speed (`"move speed bonus"`, `mult_player_movespeed`), damage (`"damage bonus"`, `mult_dmg`), and any stun-on-hit attribute, from TF2's `items_game.txt`; and whether the Wheel of Fate's `"major move speed bonus"` is the same class (if so, items and the wheel multiply, as §4.2.1 assumes).
- **R13.** Whether an admin's `gm_spawnsent` reaches the gamemode's `base_point` and `base_nextbot` scripted entities: `CanPlayerSpawnSENT` requires a `SpawnFunction` (`commands.lua:762-763`), and among the gamemode's entities only `ws_editor` defines one; whether a base class supplies one decides whether §3.1's round-logic rule is reachable today.
- **R14.** The order of `PostCleanupMap` listeners: whether the builder can recreate its pieces before `features/capture`'s `Rebuild` reads them, or whether the rounds controller should run registered restorers inside `CleanUpMap` right after `game.CleanUpMap` and before its round listeners.

## 8. Implementation plan

Every step follows the same rule: tests first, seen failing, then the model, then its controller and UI. Each step names its scope (files and modules), what it depends on, and acceptance criteria that can be checked by running something.

**Checks used below.**

- **Unit:** `.devtools/bin/run_lua_tests.sh`, LuaJIT, exit 0.
- **Totals:** `.devtools/bin/check_lua.sh` prints `TOTAL n passed, 0 failed` with no `FAIL` and no `NO SUMMARY` line, and `n` above the previous step's. The baseline on 2026-10-10 is `TOTAL 1800 passed, 0 failed`.
- **Names:** `.devtools/bin/check_engine_names.sh NAME...` prints `NAME: free` for every new console name and exits 0. `.devtools/bin/check_names.py` exits 0, so every new hook and networked var has both ends.
- **In-game:** a check file under `.devtools/bin/ingame/checks/`, run with `.devtools/bin/ingame_tests.py --maps <map>` (which starts its own dedicated server and writes a report under `.devtools/artifacts/`), or a stated manual check on a running server after a live reload of the changed chunks. Never restart the operator's server to load an edit.
- **Constants, not numbers.** Every test reads its values from the model's named constants (`T.defined` first) or derives them (`price + 1`, `STARTING_MONEY - total`, a product of two catalog values). No test pins a price, a scale, a rate, a duration or a stat value. Only TF2 and GMod enums are pinned (such as `COND.STUNNED = 15`).

### Step 1. Play mode and permissions (P0)

- **Scope.** New `foundation/play_mode.lua`, `foundation/permissions.lua`, `ws/sh_permissions.lua` (`WS.PlayMode`, `WS.RankOf`, `WS.Can`, `WSModeChanged` and `WSRankChanged` on the client). Swap the four checks in the §3.1 table. New `tests/play_mode_test.lua` and `tests/permissions_test.lua`.
- **Depends on.** Nothing.
- **Accepted when:**
  - `play_mode_test`: every combination of the four facts maps to the mode the §2.1 rules give, including "stopped with an AI war set up" → `SANDBOX`.
  - `permissions_test`: for every ability in `REQUIRED` and every rank, `Allows` in each Gameplay-family mode is true exactly when the rank reaches `REQUIRED[ability]`; in `SANDBOX` the same holds with `SANDBOX_REQUIRED` overriding. `SANDBOX_SPAWN` is allowed for `RANK_PLAYER` in `SANDBOX` and refused in `GAMEPLAY`, `AIWAR` and `ARENA`, and allowed for `RANK_ADMIN` in all four. `GAME_BUILD` is refused for `RANK_PLAYER` and allowed for `RANK_ADMIN` in every mode. No ability named `OPERATOR_*` exists.
  - `tests/editor_actions_test.lua` still passes with `WS.EditorAction`'s filter on `MATCH_CONTROL`.
  - Totals rise, 0 failed.
  - In-game (manual): a non-admin `ws_server_set mp_respawnwavetime 1` is still refused after the swap; an admin's is applied.

### Step 2. The Sandbox gate (P0, decisions Q1 and Q10)

- **Scope.** New `foundation/gameplay_entities.lua` (`IsGameplay`, `GAMEPLAY_PREFIXES`, `ROUND_LOGIC_CLASSES`, `ROUND_LOGIC_PREFIXES`, `SpawnAllowed`) and `tests/gameplay_entities_test.lua`; new `ws/sv_sandbox_gate.lua` with the §3.1 hooks. Answer R3, R8 and R13 first.
- **Depends on.** Step 1.
- **Accepted when:**
  - `gameplay_entities_test`: every prefix in `GAMEPLAY_PREFIXES` makes a sample class a gameplay entity; players, AI war soldiers and payload carts are; `prop_physics` and `prop_dynamic` are not. `SpawnAllowed` refuses every class in `ROUND_LOGIC_CLASSES`, and a class starting with each of `ROUND_LOGIC_PREFIXES`, with `REASON_ROUND_LOGIC` in `GAMEPLAY`, `AIWAR` and `ARENA`, allows them in `SANDBOX`, and allows `edit_gamerules` and a `ws_drg_*` class in every mode.
  - Totals rise, 0 failed.
  - In-game check `sandbox_gate.lua` on a TF2 map (for example `pl_badwater`) in Gameplay mode, with a bot as the non-admin: `hook.Run` of each spawning hook in §3.1 (`PlayerGiveSWEP` with `weapon_rpg`, `PlayerSpawnSWEP`, `PlayerSpawnNPC`, `PlayerSpawnSENT`, `PlayerSpawnProp`, `PlayerSpawnObject`, `PlayerSpawnVehicle`) returns `false`; `PhysgunPickup` of the payload cart returns `false`; `PhysgunPickup` of a loose `prop_physics` does not. With the bot's rank stubbed to admin through the `WS.RankOf` seam, the same spawning hooks do not return `false`, and `PlayerSpawnSENT` with `team_round_timer` still does. After `mp_gameplay_stop`, the spawning hooks no longer return `false` for the non-admin.
  - In-game (manual): a non-admin client in Gameplay mode runs `gm_giveswep weapon_rpg` and `gm_spawn models/props_c17/oildrum001.mdl`, and neither appears; an admin's Weapons and NPCs tabs spawn as in Sandbox.

### Step 3. Economy: credit floors and negative balances (P0, decision Q4)

- **Scope.** `foundation/economy.lua`: `NO_CREDIT`, `BALANCE_MIN`, `UNLIMITED_CREDIT`, `Affords`, `InDebt`, `Spend(key, amount, floor)`, `CanAfford(key, amount, floor)`, and `Format` for negatives. `ws/sv_economy.lua`: `WS.SpendMoney(ent, amount, floor)` and `WS.CanAfford(ent, amount, floor)`. `ws/sv_loadout.lua`'s one call passes `Economy.NO_CREDIT` until step 5. `ws/cl_scoreboard.lua`: `DEBT_COLOR` on a negative Money cell. Tests in `tests/economy_test.lua`.
- **Depends on.** Nothing (it can land beside step 1).
- **Accepted when** `economy_test` shows:
  - Spending `STARTING_MONEY + 1` with floor `NO_CREDIT` raises `InsufficientFunds` and leaves the balance at `STARTING_MONEY` (the existing case, now with an explicit floor).
  - With floor `UNLIMITED_CREDIT`, spending `STARTING_MONEY + k` leaves `-k`, and `InDebt` is true.
  - No spend can take a balance below `BALANCE_MIN`: spending past it with `UNLIMITED_CREDIT` raises `InsufficientFunds`.
  - `Affords(balance, amount, floor)` agrees with `Bank:CanAfford` for balances at, above and below `floor + amount`.
  - A floor above `NO_CREDIT`, or not a whole number, raises an error that is not `InsufficientFunds`.
  - For every `n = 10^k` with `k` from 0 to 7, `Format(-n) == "-" .. Format(n)`, and `Format(n)` starts with `$`. This catches today's `$-,123`.
  - Totals rise, 0 failed.
  - In-game (manual): after `lua_run WS.SpendMoney(Entity(1), WS.Money(Entity(1)) + 5, -2^31)` on a test server, the scoreboard shows `-$5` in the debt colour.

### Step 4. Store policy, refusal kinds and the match lifetime (P0, decisions Q3, Q4, Q8)

- **Scope.**
  - New `foundation/store.lua` (`POLICY`, `Window`, `Charge`, `BuyClosed`) and `tests/store_test.lua`.
  - New `foundation/refusals.lua` (kinds, `KindOf`) and `tests/refusals_test.lua`; `foundation/loadout.lua`, `foundation/economy.lua` and `foundation/gameplay_entities.lua` register their refusals there.
  - `foundation/loadout.lua`: compare catalog entries by `class` (gap 7), with cases in `tests/loadout_test.lua`.
  - `foundation/rounds.lua`: the `match_start` effect from `RestartRound` out of `GAME_OVER`, with a case in `tests/rounds_game_test.lua`.
  - `ws/sv_economy.lua` and `ws/sv_loadout.lua`: `WS.AccountKey`, keys by SteamID64, NPC-only closing in `EntityRemoved`, and the rebuild on `WSMatchStart`. `features/gamemode/sv.lua` and `features/rounds/sv.lua` raise `WSMatchStart`.
  - Answer R5 first.
- **Depends on.** Steps 1 and 3.
- **Accepted when:**
  - `store_test`: every mode in `play_mode` has a `POLICY` entry. `Charge` returns `price` when `charges` is true and `0` otherwise, for a price read from `Loadout.PRICE`. The floor is `Economy.UNLIMITED_CREDIT` for `SANDBOX` and `Economy.NO_CREDIT` for every other mode (Q4, Q8). `Window` raises `BuyClosed` with each reason in the §3.2 table under the context that causes it, and returns `OPEN` otherwise.
  - `refusals_test`: every named refusal in loadout, economy, store and gameplay_entities has a distinct kind; `KindOf` of a plain error is nil; every kind fits in `REFUSAL_BITS`.
  - `loadout_test`: a loadout built against one catalog stays consistent against a rebuilt catalog of equal classes: `Owns` and `Equipped` agree, and no weapon can sit in both support slots.
  - `rounds_game_test`: `RestartRound` from `GAME_OVER` returns a `match_start` effect; from `RND_RUNNING` and from `BETWEEN_RNDS` it does not.
  - `check_names.py` exits 0 (`WSMatchStart` is raised and listened to).
  - Totals rise, 0 failed.
  - In-game (manual, two clients or one client with `retry`): buy a weapon, `retry`, and the balance and ownership are unchanged. Then `mp_gameplay_stop` and `mp_gameplay_begin`: at the countdown's end the balance is `STARTING_MONEY` again and only the starters are owned.

### Step 5. The purchase pass, Sandbox-mode loadout and refusals as kinds (P0, decision Q4)

- **Scope.** `ws/sv_loadout.lua` `Change` as the §3.2 pass; `loadout_refused` becomes `{ kind, subject }` in `ws/sh_loadout.lua`; `ws/cl_loadout.lua` phrases kinds through `ws/cl_localization.lua`; `init.lua` `GM:PlayerLoadout` gives the loadout in Sandbox mode too; NW2 `ws_in_respawn_room` from `func_respawnroom` touches (R4). `ws/cl_menu_inventory.lua`: the header (balance, debt line, window reason) and Buy buttons through `Store.Window` and `Economy.Affords`, and the `Think` poll replaced by `WSMoneyChanged`.
- **Depends on.** Step 4.
- **Accepted when:**
  - `tests/localization_test.lua` has a phrase for every kind in `foundation/refusals.lua`.
  - `check_names.py` exits 0 (`ws_in_respawn_room` is set and read).
  - Totals rise, 0 failed.
  - In-game check `store_sandbox.lua` on `gm_construct` (Sandbox mode), with a bot, through the controller's request entry point (the function the `loadout_buy` listener calls): spend the bot's whole balance with `WS.SpendMoney(bot, WS.Money(bot), Economy.NO_CREDIT)`, then buy one non-starter catalog entry; the bot's balance is minus that entry's `price`, NW2 `ws_money` equals it, and after `bot:Spawn()` the bot holds every equipped class.
  - In-game check `store_gameplay.lua` on a TF2 map in Gameplay mode, with a bot inside its respawn room: the same buys stop at the first one the bot cannot afford, which is refused with the `INSUFFICIENT_FUNDS` kind, and the balance never goes below 0. Outside the respawn room after setup, a buy is refused with `REASON_NOT_IN_SPAWN`.

### Step 6. Player tab: available weapons, buy-into-slot, resupply (P0)

- **Scope.** `foundation/loadout.lua` `BuyInto` with cases in `tests/loadout_test.lua`; `loadout_buy` gains `slot` in `ws/sh_loadout.lua` (the factory maps `0` to nil); `ws/sv_loadout.lua` resupply under `appliesNow`; `ws/cl_menu_player.lua` list, slot status and live hint.
- **Depends on.** Step 5.
- **Accepted when:**
  - `loadout_test`: `BuyInto(slot, weapon)` owns and equips in one value; a refusal from either half (`WrongSlot`, `AlreadyOwned`) leaves the original loadout unchanged; slot `nil` behaves as `Buy`.
  - Totals rise, 0 failed.
  - In-game (manual): in a respawn room on a TF2 map, buying into an empty Primary slot puts the weapon in hand at once; outside the room, an equip shows "Next spawn".

### Step 7. Stock creation tabs hidden (P0, decisions Q2 and Q10)

- **Scope.** New `ws/cl_spawnmenu_tabs.lua`. Answer R7 first.
- **Depends on.** Step 1 (`SANDBOX_SPAWN`, `WSModeChanged`, `WSRankChanged`).
- **Accepted when:**
  - `tests/client_load_order_test.lua` still passes with the new file; totals rise or hold, 0 failed.
  - In-game (manual): a non-admin client in Gameplay mode sees only Player and Inventory on the left; after `mp_gameplay_stop`, every stock tab returns without reconnecting; an admin sees Player, Inventory and every stock tab in both modes, and no Operator tab exists for anyone.

### Step 8. Wardrobe: paid player models (P1, decision Q5)

- **Scope.** New `foundation/wardrobe.lua` (models only in this step: `KIND_MODEL`, `MODEL_PRICE`, `Catalog`, `Buy`, `Wear`, `Starting`, `WornFor`) and `tests/wardrobe_test.lua`; `foundation/factions.lua` `MODELS[team]` and `DEFAULT_MODEL[team]` with cases in `tests/factions_test.lua`; new `ws/sh_wardrobe.lua`, `ws/sv_wardrobe.lua` (with `GM:PlayerSetModel`), `ws/cl_wardrobe.lua` (removes `DesktopWindows.PlayerEditor`, adds `WSWardrobe`, defines `WS.UI.WardrobePanel`); `ws/cl_menu_inventory.lua` Appearance section. Answer R6 first.
- **Depends on.** Steps 4 and 5.
- **Accepted when:**
  - `wardrobe_test`: `Starting` owns exactly the starters and wears the first; `Buy` of an unowned entry owns it and its charge is the entry's price, which equals `MODEL_PRICE`; `Buy` of an owned one raises `AlreadyOwned`; `Wear` of an unowned one raises `NotOwned`; `WornFor` falls back to the first starter when the catalog no longer offers the worn model, and ownership is kept.
  - `factions_test`: every playing team has a non-empty `MODELS[team]` that contains its `DEFAULT_MODEL[team]`.
  - Totals rise, 0 failed.
  - In-game check `wardrobe.lua` on a TF2 map: `hook.Run("PlayerSetModel", bot)` gives the bot its worn model (`WornFor`), never the one `cl_playermodel` names; after a `wardrobe_buy` and `wardrobe_wear` through the controller entry point and a respawn, `bot:GetModel()` is the bought model's path, and the balance fell by `MODEL_PRICE`.
  - In-game (manual): the C menu has a "Wardrobe" icon and no "Player Model" icon; `cl_playermodel alyx` followed by `kill` respawns the player in their worn model.

### Step 9. Cosmetics that carry attributes (P1, decision Q5 addition)

- **Scope.**
  - `foundation/wardrobe.lua`: `KIND_COSMETIC`, `COSMETIC_SLOT_COUNT`, the `REGION_*` constants, `WearCosmetic`, `RemoveCosmetic`, `CosmeticsFor`, `Wardrobe:Attributes(catalog)`, and the catalog checks (`BadCatalog` for an unsupported attribute, a value above `ATTRIBUTE_MAX`, or a price below `StatPriceFloor`). Refusals `SlotsFull`, `RegionTaken`, `NotWorn` registered in `foundation/refusals.lua`. Cases in `tests/wardrobe_test.lua`.
  - `foundation/players/attributes.lua`: `MOVE_SPEED_ITEM`, `DAMAGE_BONUS`, `STUN_ON_HIT` (names per R12), `CATEGORY`, `MODE_CATEGORIES`, `STACK_LIMITS`, `ATTRIBUTE_MAX`, `COSMETIC_BASE_PRICE`, `STAT_PRICE`, `StatPriceFloor`, `FoldItems`, `ActiveItems`, `SpeedScale(attrs, now, items)` and `DamageDealtScale(items, slot)`. Cases in `tests/player_attributes_test.lua`.
  - `features/attributes/sv.lua`: `SetItems`, `byItems`, `Sync` over both layers, the dealt-damage scale in its `EntityTakeDamage` hook; `Clear` leaves items.
  - `ws/sv_loadout.lua`: `WS.LoadoutSlotOf(ply, class)`.
  - `ws/sh_wardrobe.lua` (`COSMETICS` data, at least one look-only, one speed, one primary-damage and one stun item), `ws/sv_wardrobe.lua` (`wardrobe_remove`, `SetItems` on wear, remove, spawn and `WSModeChanged`, NW2 `ws_cosmetics`), `ws/cl_wardrobe.lua` (bonemerge, `cl_cosmetics_hidden`), the Wardrobe panel's Cosmetics row and the Player tab's stat lines.
  - `mp_cosmetics_stats` in `foundation/settings.lua` `SETTINGS` with a case in `tests/settings_test.lua`.
  - Answer R12 first.
- **Depends on.** Step 8.
- **Accepted when:**
  - `wardrobe_test`: an owner can wear up to `COSMETIC_SLOT_COUNT` cosmetics of distinct regions, and one more raises `SlotsFull`; two cosmetics sharing a region raise `RegionTaken`; `WearCosmetic` of an unowned cosmetic raises `NotOwned`; `RemoveCosmetic` of one not worn raises `NotWorn`; a catalog entry with an attribute `Attributes.Supported` rejects, a value above `ATTRIBUTE_MAX[name]`, or a price of `StatPriceFloor(attributes) - 1` raises `BadCatalog`, and the same entry at `StatPriceFloor(attributes)` is accepted; `Attributes(catalog)` returns the worn cosmetics' tables in wear order.
  - `player_attributes_test`: `FoldItems` of two tables with the same multiplier `a` and `b` (values derived as `STACK_LIMITS[name]^(1/4)`, so their product stays under the limit) gives `a * b`; three items whose product exceeds `STACK_LIMITS[name]` give exactly `STACK_LIMITS[name]`; `STUN_ON_HIT` in two items folds to present once. `ActiveItems` keeps `MOVE_SPEED_ITEM` and drops `DAMAGE_BONUS` and `STUN_ON_HIT` in `SANDBOX`, keeps all three in `GAMEPLAY`, `AIWAR` and `ARENA`, and drops all of them when `statsEnabled` is false. `SpeedScale(attrs, now, items)` with an item value `a` and the wheel's `MOVE_SPEED_BONUS` at `b` is `a * b`, and with no items equals today's result. `DamageDealtScale(items, SLOT_PRIMARY)` is the item's value and `DamageDealtScale(items, SLOT_SECONDARY)` is 1.
  - `check_engine_names.sh mp_cosmetics_stats cl_cosmetics_hidden` prints `free` for each; `check_names.py` exits 0 (`ws_cosmetics` is set and read).
  - Totals rise, 0 failed.
  - In-game check `cosmetics.lua` on a TF2 map in Gameplay mode, with a bot, through the wardrobe controller's entry points: buy and wear the speed cosmetic; after `bot:Spawn()`, NW2 `ws_speed_scale` equals that cosmetic's value as read from the catalog, and the balance fell by its price. Buy and wear the damage cosmetic; a `DamageInfo` from the bot with its equipped primary weapon as inflictor, run through `hook.Run("EntityTakeDamage", victim, dmg)`, is scaled by the cosmetic's value; one from its secondary is not. After `mp_gameplay_stop`, the speed scale is unchanged and the damage scale is 1. With `mp_cosmetics_stats 0`, the speed scale is 1.
  - In-game (manual): a second client sees the bot's worn cosmetic models; `cl_cosmetics_hidden 1` hides them.

### Step 10. The stun capability (P1, decision Q5 addition)

- **Scope.**
  - New `foundation/players/stunner.lua` and `tests/stunner_test.lua`.
  - `foundation/players.lua`: `COND.STUNNED`; `ws/sv_teams_conditions.lua`: `WS.InCondition` answers it from the stun; `ws/cl_conditions.lua`: the stun stars.
  - `features/attributes/sv.lua`: on a melee hit by a holder of `STUN_ON_HIT`, ask `Stunner.Try` and apply `WS.StunPlayer` or `Soldier:Stun`.
  - `foundation/aiwar/soldier.lua` port gains `IsStunned()`; `tests/fake_soldier.lua` implements it; `features/aiwar/sv.lua` `Soldier:Stun` and `Soldier:IsStunned`; `foundation/aiwar/orders.lua` `ChaseWanted` refuses while stunned.
- **Depends on.** Step 9.
- **Accepted when:**
  - `stunner_test`: a melee hit on a living enemy `VICTIM_PLAYER` in `GAMEPLAY` by a ready wearer returns a stun of `STUN_DURATION`, `STUN_SLOW` and `STUN_FLAGS`, and a wearer whose `readyAt` is `now + STUN_COOLDOWN`; a second hit before `readyAt` returns nil with `COOLING_DOWN`, and one at `readyAt` stuns; a `VICTIM_SOLDIER` is stunned the same way; a same-team victim (`SAME_TEAM`), a non-melee hit (`NOT_MELEE`), a `VICTIM_OTHER` (`IMMUNE_VICTIM`), any hit in `SANDBOX` (`WRONG_MODE`) and a wearer without the capability (`NO_CAPABILITY`) return nil; a victim hit again before `stun end + STUN_IMMUNE_AFTER` returns nil with `VICTIM_IMMUNE`, by a different ready wearer.
  - `tests/player_attributes_test.lua` or a players test: `COND.STUNNED == 15` (TF2's enum).
  - `aiwar_soldier_contract_test` passes with `IsStunned` in the port and the fake; `aiwar_orders_test`: `ChaseWanted` is false for a stunned fake soldier that would otherwise chase, and true again once the stun ends.
  - Totals rise, 0 failed.
  - In-game check `stun.lua` on a TF2 map in Gameplay mode, with two bots on opposite teams, the first wearing the stun cosmetic: a `DamageInfo` from the first with its equipped melee weapon as inflictor, applied to the second through `TakeDamageInfo`, leaves `WS.InCondition(second, COND.STUNNED)` true and NW2 `ws_stun_end_time` at `CurTime() + STUN_DURATION` (within one tick); a second such hit at once leaves `ws_stun_end_time` unchanged. During an AI war on `pl_badwater`, the same hit on an enemy soldier makes `Soldier:IsStunned()` true.

### Step 11. Comfort switches made real (P0)

- **Scope.** `foundation/comfort.lua` and `tests/comfort_test.lua`; `ws/sh_comfort.lua` (userinfo convars); the consumers in `ws/cl_conditions.lua` and `features/npc/cl.lua`; the server effects moved to `effect_shake`/`effect_fade` events. Answer R1 first.
- **Depends on.** Nothing in this plan.
- **Accepted when:** `comfort_test` derives every expected factor from `MOTION_SCALE_REDUCED` and `FLASH_ALPHA_MAX_REDUCED`; `tests/cfg_defaults_test.lua` still passes; totals rise, 0 failed; in-game (manual): with `cl_reduce_motion 1`, a Merasmus bomb's shake is visibly damped.

### Step 12. Options: Match info and Match control (P0)

- **Scope.** `ws/cl_menu_options.lua` panels; new `mp_round_restart`, `mp_teams_scramble`, `mp_round_timer_add`, `mp_match_pause` and `mp_match_resume` in the rounds controller; `admin_notices` lines; the P1 Bosses row (`admin_boss`) and AI War control's "Add soldier" buttons.
- **Depends on.** Step 1.
- **Accepted when:** `check_engine_names.sh mp_round_restart mp_teams_scramble mp_round_timer_add mp_match_pause mp_match_resume` prints `free` for each; `check_names.py` exits 0 (`ws_match_paused` is set and read); totals hold, 0 failed; in-game check `match_control.lua` on a TF2 map: `mp_round_timer_add 60` raises the active timer's remaining time by 60 s, `mp_match_pause` then `mp_match_resume` sets and clears Global2 `ws_match_paused`, and `mp_teams_scramble` with four bots leaves the team sizes within one of each other.

### Step 13. Voting and the support vote's faster respawns (P0, decision Q6 a)

- **Scope.** New `foundation/vote.lua`, `foundation/handicap.lua`, `tests/vote_test.lua`, `tests/handicap_test.lua`; `foundation/rounds.lua` `SetWaveScale` with cases in `tests/rounds_rules_test.lua`; `ws/sv_votes.lua`, the Voting panel and the HUD card; the `mp_vote_*` commands and convars (§4.4) in `ws/sh_votes.lua` and `foundation/settings.lua` `SETTINGS`; Global2 `ws_handicap_team`; the handicap reset on `WSMatchStart` and on scramble.
- **Depends on.** Steps 1, 4 (`WSMatchStart`) and 12 (scramble, restart).
- **Accepted when:**
  - `handicap_test`: `T.defined(Handicap.WAVE_SCALE)` and `WAVE_SCALE < NO_SCALE`; an unsupported team's `WaveScale` is `NO_SCALE` and its capabilities are empty; after `Grant(team)` that team's `WaveScale` is `WAVE_SCALE` and its capabilities contain every entry of `CAPABILITIES`, while the other team is unchanged; a second `Grant(team)` raises `AlreadySupported`.
  - `rounds_rules_test`: in `RND_RUNNING`, with a wave scale set for one team, that team's `WaveMaxLength` equals the unscaled value (from an identical round without the scale) times the scale, and the other team's is unchanged; `NextRespawn` for a death at the same time is no later for the supported team; in setup both are unchanged.
  - `vote_test`: quorum and pass thresholds derived from `QUORUM_SHARE` and `PASS_SHARE` over a generated electorate; `KIND_SUPPORT` refused in `SANDBOX` with `REASON_MODE` and limited to the caller's team; `KIND_RESET` and `KIND_SCRAMBLE` refused in `SANDBOX`; a kind whose enabled setting is off refused; cooldowns derived from `CALLER_COOLDOWN` and `FAILED_COOLDOWN`.
  - `settings_test`: every `mp_vote_*` convar of §4.4 is in `SETTINGS`, and the defaults of `mp_vote_duration`, `mp_vote_quorum` and `mp_vote_cooldown` equal `Vote.DURATION`, `Vote.QUORUM_SHARE` and `Vote.CALLER_COOLDOWN`.
  - `check_engine_names.sh mp_vote_kick mp_vote_map mp_vote_reset mp_vote_scramble mp_vote_support mp_vote_cast mp_vote_enabled mp_vote_kick_enabled mp_vote_map_enabled mp_vote_reset_enabled mp_vote_scramble_enabled mp_vote_support_enabled mp_vote_duration mp_vote_quorum mp_vote_cooldown mp_vote_admin_only` prints `free` for each; no `sv_vote_` name appears under `addons/sandcastle/` (`grep -rn sv_vote_ addons/sandcastle` prints nothing); `check_names.py` exits 0.
  - Totals rise, 0 failed.
  - In-game (manual): with two clients on one team, `mp_vote_support` and two `mp_vote_cast yes` pass a support vote that sets `ws_handicap_team` to the other team, and that team's respawn timer is visibly shorter than before the vote.

### Step 14. The AI capability flag (P1, decision Q6 b)

- **Scope.** New `foundation/aiwar/capabilities.lua` and `tests/aiwar_capabilities_test.lua`; `foundation/aiwar.lua` `War:SetCapabilities`/`War:Capabilities` with cases in `tests/aiwar_test.lua`; `features/aiwar/sv.lua` listens to `WSHandicapChanged`. The ambush tactic is not part of this step.
- **Depends on.** Step 13.
- **Accepted when:**
  - `aiwar_capabilities_test`: `None():Has(c)` is false for every `c` in `KNOWN`; `With(c)` returns a new set that has `c` and leaves the original without it; `With` of a name not in `KNOWN` raises `UnknownCapability`.
  - `aiwar_test`: a new `War` reports `None()` for both teams; after `SetCapabilities(team, set)` only that team has the set.
  - Totals rise, 0 failed.
  - In-game (manual): during an AI war, after a passed support vote, `lua_run print(WS.AiWar.war:Capabilities(<other team>):Has(...AMBUSH))` prints `true` (or the equivalent `ns_` print command, if one is added for it).

### Step 15. C menu P0/P1 (P0/P1)

- **Scope.** `PopulateMenuBar` (Sandcastle menu, NPCs menu removal), Ping (`world_mark`, `world_marked`), the admin properties of §5.3 (`admin_set_team`, `admin_give`, `admin_player`, `economy_grant`) through `WS.EditorAction`, the Loadout desktop window.
- **Depends on.** Steps 1, 5 and 12.
- **Accepted when:** totals hold, 0 failed; `check_names.py` exits 0; in-game check `admin_properties.lua` on a TF2 map: an `npc_combine_s` spawned through Sandbox's `Spawn_NPC` path by an admin, then sent `admin_set_team` through the property's `Receive` with RED, is a RED team member with an open account; in-game (manual): a non-admin's C menu has no NPCs menu, and a Ping on a wall draws a marker for teammates only.

### Step 16. AI war orders from the C menu (P1, decision Q8)

- **Scope.** New `foundation/aiwar/player_orders.lua` and `tests/aiwar_player_orders_test.lua`; the `aiwar_order` event and its listener in `features/aiwar/sv.lua`; the Squad property.
- **Depends on.** Step 4 (store and floors) and the Commander of `docs/aiwar-command.md` (its phase 5) to deliver orders to.
- **Accepted when:**
  - `aiwar_player_orders_test`: `T.defined(PlayerOrders.ORDER_PRICE)`; every order kind is accepted in `AIWAR` for a living caller on the soldier's team; each is refused with `REASON_MODE` in every other mode, `NotYourTeam` across teams, and `REASON_DEAD` for a dead caller.
  - `store_test` gains: `Store.Charge(POLICY[AIWAR], ORDER_PRICE)` returns a floor of `NO_CREDIT`, and a bank holding `ORDER_PRICE - 1` refuses the spend with `InsufficientFunds` and keeps its balance.
  - Totals rise, 0 failed.
  - In-game (manual): with the balance set below `ORDER_PRICE` through `economy_grant`, a Squad order is refused with "Not enough money" and the squad's command channel receives nothing.

### Step 17. Map and server items, consumables (P1)

- **Scope.** §4.2.3 P1 items: catalog `source` and `category`, `Catalog:With` (loadout and wardrobe), `ws_store_item` (weapons, consumables and cosmetics), `store.json`, `store_catalog` and `wardrobe_catalog`, `CATALOG_COUNT_BITS`, `store_use`.
- **Depends on.** Steps 4, 5 and 9.
- **Accepted when:** `loadout_test` covers `With` (a merge, and `BadCatalog` on a duplicate class); `wardrobe_test` covers the wardrobe's `With` the same way, and a merged cosmetic whose price is below its `StatPriceFloor` raises `BadCatalog`; a malformed `store.json` fixture under `tests/fixtures/` is refused with `BadCatalog`; totals rise, 0 failed.

### Step 18. Game builder, preliminary (P1, decision Q11)

This step is planned in outline: answer B1 and R9-R11, R14 first, then split it into sub-steps with their own criteria. The criteria below are the ones the outline already fixes.

- **Scope.**
  - New `foundation/game_layout.lua` and `tests/game_layout_test.lua`, with fixtures under `tests/fixtures/layouts/` (one playable payload, one with a bad `LAYOUT_VERSION`, one with a dangling `next`). Its refusals registered in `foundation/refusals.lua`, with phrases in `ws/cl_localization.lua`.
  - New `features/builder/sv.lua` and `features/builder/cl.lua`; new always-loaded `ws/sh_builder.lua` (`mp_layout_save`, `mp_layout_load`, `mp_layout_clear`, `mp_layout_check`, `mp_layout_autoload`, and the autoload `file.Exists`).
  - New stools `build_spawn`, `build_track`, `build_volume` (R9 decides the folder); the "Builder" properties through `WS.EditorAction` and a `ws_proxy` kind `"build"`.
  - `addons/sandcastle/gamemodes/sandcastle/entities/entities/ws_brush_volume.lua` (and `trigger_capture_area.lua`): box bounds from `mins`/`maxs` keyvalues when no brush model is given.
  - `features/rounds/sv.lua`: `Controller:Redetect()`, and the restore hook point R14 decides. `features/gamemode/sv.lua`: Begin asks `Builder:Ready()`.
  - The `BUILD_CHANGED` notice in `foundation/admin_notices.lua` with a case in `tests/admin_notices_test.lua`.
- **Depends on.** Steps 1 (`GAME_BUILD`, `WS.Can`), 2 (the gate's `CanTool`), 4 (refusal kinds) and 12 (`mp_round_restart`).
- **Accepted when:**
  - `game_layout_test`:
    - `Check` of `New(map, GAME_PAYLOAD)` raises `Unplayable` whose reasons cover every entry of `REQUIRED[GAME_PAYLOAD]` (derived from the table, per team where it says so).
    - Building the playable payload piece by piece removes exactly the reason each piece answers, and the complete layout (spawns and respawn rooms for both teams, a track of `TRACK_MIN_NODES` with its last node the goal, a cart on its first node, a timer) passes `Check`.
    - A track whose tail links to its head raises `REASON_TRACK_LOOP`; `ExtendTrack` past the goal raises `TrackEnded`; `Remove` of a middle node joins its neighbours, and a second `Place` of a cart raises `OnlyOne`.
    - `Check` of a CTF layout holding a flag and a capture zone per team raises `Unplayable` with `REASON_NOT_IMPLEMENTED` for `PIECE_FLAG` and `PIECE_CAPTURE_ZONE` while `IMPLEMENTED` says they are not.
    - `Entities` of the playable payload: each `path_track`'s `target` is the next node's name and the goal's is empty; the watcher's `start_node` and `goal_node` are the first and last nodes' names; every checkpoint node appears in a `linked_pathtrack_<n>` with a `team_control_point` named in the matching `linked_cp_<n>`; every name starts with `LAYOUT_NAME_PREFIX`.
    - `FromData(ToData(layout))` equals `layout`; each bad fixture raises `BadLayout`.
  - `check_engine_names.sh mp_layout_save mp_layout_load mp_layout_clear mp_layout_check mp_layout_autoload build_spawn build_track build_volume` prints `free` for each; `check_names.py` exits 0.
  - Totals rise, 0 failed.
  - In-game check `builder_payload.lua` on `gm_construct`, in Sandbox mode, building the fixture's playable payload through the builder controller's request entry points (not the toolgun): `mp_layout_check` reports it playable; `mp_layout_save` writes `data/sandcastle/layouts/gm_construct.json`; `WS.FeatureLoaded("payload")` and `WS.FeatureLoaded("capture")` are true once the watcher exists; `mp_gameplay_begin`, then after the transition `WS.Active()` is true and a `team_train_watcher` exists; after `mp_round_restart` the watcher, the track and the spawns exist again with the same names. After `mp_gameplay_stop`, `mp_layout_clear` and `mp_layout_load`, the piece count equals the file's. With one spawn removed, `mp_gameplay_begin` is refused with `REASON_NO_SPAWN` and `WS.PlayMode()` stays `SANDBOX`. A build request from a bot without `GAME_BUILD` is refused with `REASON_RANK`, and one made in Gameplay mode with `REASON_MODE`.
  - In-game (manual): an admin with the track tool clicks a route on `gm_construct`, marks two checkpoints, places spawns and respawn rooms with the other tools, begins the game, and BLU can push the cart to the goal.

### Step 19. Remaining P1 and P2 items

Admin > Store & Economy (`mp_store_price_scale`, `mp_store_window`, `mp_economy_start_money`, each checked with `check_engine_names.sh`), sell back, drag and drop, presets saved across maps, the AI war orders window, tool panel visibility, arena settings, and the CTF feature (B6) with the builder's flag tool. Each gets its own acceptance criteria when it is planned.

## 9. Judgment calls made in this doc

- **"TF2 maps" read as Gameplay mode, "Sandbox maps" as Sandbox mode** (§2.1). A stopped TF2 map is Sandbox mode (free spawning, stock tabs, credit); a non-TF2 map whose game was begun is Gameplay mode. The `TRANSITION` countdown counts as Gameplay mode, so the gate closes as the countdown starts.
- **The debt rule is split:** the store's `POLICY` decides how far each mode may go below zero, and the bank's `Spend` takes that floor as a required argument (§3.2). The bank never knows the mode.
- **"No consequences" stops at `BALANCE_MIN`**, the lowest value the signed 32-bit `ws_money` can carry, so a debt never wraps on the wire.
- **A match starts** when Gameplay mode begins and when the rounds restart out of `GAME_OVER`; money, ownership, wardrobes and the handicap reset then, not at match end, so the intermission still shows the final balances. Begin Game after Stop Game therefore wipes purchases made in Sandbox mode, including any debt.
- **Sandbox mode keeps Sandbox's own loadout** and adds the paid one on top, since nothing else is gated there.
- **AI war orders are charged on acceptance** into the squad's command channel and not refunded if soldiers later ignore them. They live in a new `foundation/aiwar/player_orders.lua`, not in `foundation/aiwar/orders.lua`, which stays the soldiers' own actions.
- **Colour, skin and bodygroups of an owned model are free.** Models and cosmetics live in `foundation/wardrobe.lua`, not in loadout slots; cosmetics have their own `COSMETIC_SLOT_COUNT` slots and TF2-style equip regions.
- **Cosmetic stats are TF2 attributes applied by the attributes feature**, through a new item layer that survives spawn and death; values of one attribute multiply across items and with the trigger layer, as TF2's do, and are capped by `STACK_LIMITS` (Sandcastle's own cap).
- **In Sandbox mode only movement stats apply;** damage and stun stats apply only in Gameplay modes, because Sandbox mode's unlimited credit would make them free griefing tools. `mp_cosmetics_stats 0` turns every stat off.
- **A damage cosmetic names a weapon slot** (the first ones `SLOT_PRIMARY`) and boosts whatever is equipped there, since a cosmetic is not a weapon.
- **Stat items' prices have a floor** that grows with the size of their effect (`StatPriceFloor`); the catalog refuses an item priced under it. AI war soldiers wear no cosmetics, and the support vote is the counter to a team that out-spends; soldiers are not scaled by enemy stats (open question C1).
- **The stun is a slow, not a disable:** `TF_STUN_MOVEMENT` on a melee hit, with a per-wearer cooldown and a short immunity for the victim. Players and AI war soldiers can be stunned; engine NPCs and Halloween bosses cannot. A stunned soldier keeps its job and starts no chase.
- **`COND.STUNNED` (TF2's 15) is added** so `WS.InCondition` and `filter_tf_condition` see a stun, read from the existing stun fold.
- **The handicap lasts the rest of the match** and a scramble clears it. A team can be supported once per match.
- **The wave scale applies after TF2's own wave rules** (`MIN_SCALED_WAVE` and the team-size scalar), so a supported team can respawn faster than TF2's minimum.
- **The physgun and toolgun stay in `SANDBOX_TOOLS`** in Gameplay mode; Q1 is met by refusing them on gameplay entities, not by taking them away.
- **The gate keeps a round-logic rule for admins:** `tf_gamerules`, `team_round_timer`, `team_control_point_master`, `team_control_point_round` and `tf_logic_*` are refused for every rank in Gameplay mode, even if R13 shows Sandbox cannot reach them today. No deny list for engine command entities is kept, since Sandbox's spawn commands cannot reach them.
- **Editor actions check `MATCH_CONTROL`** rather than a bare `IsAdmin()`, so one permission model covers them.
- **Admin properties' events take the `admin_` prefix** (`admin_set_team`, `admin_give`, `admin_player`, `admin_boss`), now that there is no Operator.
- **The Bosses buttons move to Options > Match control**, and the AI War quick-add to Options > AI War control.
- **The game builder places real TF2 entities and stores a layout, not entities;** the layout is rebuilt after every round cleanup.
- **Layouts are JSON under `data/sandcastle/layouts/`, one per map, autoloaded by default** (`mp_layout_autoload 1`), rather than Sandbox dupes or saves.
- **Building happens only in Sandbox mode,** and Begin Game checks the layout first, refusing with every missing piece at once.
- **The builder is a family of small tools** (`build_spawn`, `build_track`, `build_volume`, later `build_point` and `build_flag`), one per kind of placement, as Sandbox groups its own tools. They take a `ws_` mode name because Sandbox derives each tool's client convars from it (`<mode>_<option>`), so they cannot be `cl_`; no Source domain fits a tool mode.
- **The cart is placed by the track tool** on the track's first node, rather than by its own tool.
- Purchase rules live in a new `foundation/store.lua`, not in `foundation/loadout.lua`, so the slot rules stay independent of rounds and modes.
- `loadout_buy` gains an optional slot (`0` for automatic) instead of a second event.
- The default `POLICY` table in §3.2, especially resupply in the respawn room and an immediate, charged loadout on credit in Sandbox mode.
- **Vote kinds are renamed to match their commands** (`KIND_MAP`, `KIND_RESET`, `KIND_SUPPORT`), and the four example commands are read as client commands that call a vote, with `mp_vote_cast` for the ballot and `mp_vote_*_enabled` for the per-kind switches.
- Player orders to AI war soldiers act on the fire team, as an input the Commander weighs, never as a direct override.
- Refusals travel as kinds and are phrased on the client.
- One wardrobe panel serves both the Inventory tab and the C-menu Wardrobe window, which replaces Sandbox's Player Model icon in both modes.

## 10. Operator decisions, 2026-10-16 (Q menu and admin redesign)

The mockups are on the design canvas (claude.ai artifact 1rFapf81dfSew33rz6NvR9). Where these differ from §1–§9, these win.

**Status (2026-10-16): built on main, 29e5087..df05628, covered by the LuaJIT suite; not yet checked in game.** Not built: the Help Other Team and Soldier Difficulty votes (shown as coming soon; no handicap or difficulty system yet), the match winners' reward (a stub), Pause Cart, and the player menu on Sandbox's own scoreboard (Sandcastle's scoreboard shows only while teams play).

**Tabs.** The left creation tabs are **Loadout**, **Store** and **Server**, ordered ahead of Sandbox's stock tabs. Player becomes Loadout; Inventory becomes Store; Server is new. No tab holds admin controls.

- **Loadout:** a slot lists every weapon that fits it; an unowned one buys and equips in one click (`BuyInto`, §4.1).
- **Store:** one grid of icon tiles (GMod spawn icons, `entities/<class>.png`), no rows or sections. Each tile carries a slot badge; a heart favorites it, and favorites sort first. Favorites are per player, stored on the client. Click buys. Hover shows a TF2-style item tooltip: name, slot and cost, stats (damage from `sk_plr_dmg_*`, ammo as clip + `RESERVE_CLIPS` clips, both read at run time), upside lines blue, downside red, description.
- **Slot badges:** Primary `1` in a bevelled triangle, Secondary `2` in a square, Melee `3` in a circle, Support `S` in a star, the glyph knocked out of a solid shape. Shown before slot names everywhere.
- **Server:** vote tiles (Soldier Difficulty, Next Map, Help Other Team, Restart Round, Scramble Teams); a vote with a choice is called by clicking the choice. Wording follows TF2's strings (§ Wording board).
- **Three clicks at most** for any one task, counting the tab click.

**No player-called kick votes.** The scoreboard's player menu (right-click) has Copy Steam3 ID, Report ▸ reason (TF2's four), Transfer Money ▸ amount and Mute; clicking the avatar opens the Steam profile. Reports from different players start a kick vote automatically: `mp_reports_kick_count` (default 3), and 2 when the server has exactly three players.

**Admin controls are a baseline that admin mods extend.** Every control checks a named CAMI privilege with a default rank; ULX, SAM or ServerGuard may give it to any rank. CAMI is vendored as `ws/sh_cami.lua` (upstream glua/CAMI 4b0eb86, version 20211019), so the checks work with no admin mod installed. Rewards, ban lengths and extra settings are hooks or `[ADDED BY ADMIN MOD]` slots, not fixed by Sandcastle. Admin controls live in:

- **Options › Admin › Gameplay Rules:** winning (`mp_winlimit`, `mp_maxrounds`, `mp_timelimit`, `mp_match_end_at_timelimit`), bonus rounds (`mp_stalemate_enable`, `mp_stalemate_timelimit`, `mp_round_fraglimit`, `mp_round_cashlimit`, `mp_bonusroundtime`), teams (`mp_autoteambalance`, `mp_teams_unbalance_limit`, `mp_scrambleteams_auto`, `mp_scrambleteams_auto_windifference`, `mp_allowspectators`), votes and reports (`mp_reports_kick_count`, `mp_vote_*_enabled`, `mp_vote_duration`, `mp_vote_cooldown`), respawns.
- **Utilities › Admin › Match Control:** round (sudden death now, restart to Pregame, reward the round winner with money plus server-defined rewards), match (begin/stop, force a winner or decide by sudden death, reward the match winner: a stub), gameplay tampering (payload, round clock, respawns), NextSoldier (start/end, pause, soldiers per side, squad sizes).
- **Scoreboard player menu, admin part:** Kick, Ban ▸ (lengths from the admin mod), Spectate, Give Money.
- **C menu bar:** superadmin **Economy** (Allow Deficit Spending `mp_economy_credit_enabled`; Disable Economy `mp_economy_enabled 0`, which hides Loadout and Store) and **Gameplay** (Disable Gameplay Tampering `mp_tampering_enabled 0`; Disable NextSoldier `ns_soldiers_enabled 0`; Disable Weapon Criticals `tf_weapon_criticals 0`; Disable Random Spread `tf_use_fixed_weaponspreads 1`; Disable Sandbox Mode `sv_gameplay_disable_sandbox 1`; Force Gameplay Mode `sv_gameplay_enabled 1`). GMod's own **NPCs** and **Server** menus, host-only today, are proxied: each toggle goes to the server as an event, checked against a privilege.
- **C-click:** player (Spectate, Bring, Go To, Respawn, Slay, Switch Team, Give Money, Kick, Ban), payload cart, control point, round timer and soldier options.

**Privileges and default ranks.** `sandcastle.round`, `sandcastle.match`, `sandcastle.tamper`, `sandcastle.nextsoldier`, `sandcastle.rules`, `sandcastle.players`, `sandcastle.server_options`: admin. `sandcastle.economy`, `sandcastle.gameplay`, `sandcastle.npc_debug`: superadmin. While `mp_tampering_enabled` is 0, no player may tamper, superadmins included; a holder of `sandcastle.gameplay` may switch it back on. These replace the ability constants of §3.1 one for one: `MATCH_CONTROL` is `sandcastle.match`, `SERVER_SETTINGS` is `sandcastle.rules`, `NPC_DEBUG` is `sandcastle.npc_debug`; `SANDBOX_SPAWN`, `GAME_BUILD` keep their §3.1 rules under `sandcastle.spawn` and `sandcastle.build` (admin). `VOTE_CALL` is everyone unless `mp_vote_admin_only`.

Every new console name above printed `free` from `check_engine_names.sh` on 2026-10-16.
