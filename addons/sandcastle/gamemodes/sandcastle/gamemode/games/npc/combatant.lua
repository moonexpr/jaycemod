-- The combatant port: what an NPC that takes sides may ask beyond the actor
-- port (games.npc.actor). ws_combat_nextbot implements it through
-- the combat, holiday and npc controllers, and tests/fake_combatant.lua
-- fakes it. Method names are TF2's wherever TF2 has one.
--
-- Teams are games.gameplay.teams numbers; conditions and stun flags are
-- games.gameplay.players' COND and STUN; holidays are features.holiday.model's.
--   GetTeamNumber() -> my team
--   TeamOf(t) -> t's team (UNASSIGNED for an entity with none)
--   CollectPlayers(team) -> the living players of team; nil means RED and BLU
--   CollectNPCs(kind) -> the NPCs of that registry kind (games.npc.nextbot KIND)
--   CollectMembers(team) -> the living non-players fighting for team (the
--     AI war's soldiers: WS.SetTeamMember)
--   InCond(t, cond), IsInvulnerable(t) (games.npc.targeting's rule),
--   InRespawnRoom(t) (inside an active func_respawnroom)
--   StunPlayer(t, duration, reduction, flags), AddCond(t, cond, duration)
--   RoundHasBeenWon(), DropSpellPickup(v, tier), HolidayActive(h)
--   Explode(config): a games.gameplay.combat Explosion config, run by the combat
--   controller
--   Tag() -> the tag controller, SetBossHealth(fraction) (0 hides the bar),
--   SpawnPoints(name) -> the origins of the info_targets of that name
module(...)

METHODS = {
	-- sides
	"GetTeamNumber",
	"TeamOf",
	"CollectPlayers",
	"CollectNPCs",
	"CollectMembers",
	-- conditions
	"InCond",
	"IsInvulnerable",
	"InRespawnRoom",
	"StunPlayer",
	"AddCond",
	-- the game
	"RoundHasBeenWon",
	"DropSpellPickup",
	"Explode",
	"HolidayActive",
	"Tag",
	"SetBossHealth",
	"SpawnPoints",
}
