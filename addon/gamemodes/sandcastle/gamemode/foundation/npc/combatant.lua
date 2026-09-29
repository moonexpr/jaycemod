-- The combatant port: what an NPC that takes sides may ask beyond the actor
-- port (foundation.npc.actor). wetsand_combat_nextbot implements it through
-- the combat, holiday and npc controllers, and tests/fake_combatant.lua
-- fakes it. Method names are TF2's wherever TF2 has one.
--
-- Teams are foundation.teams numbers; conditions and stun flags are
-- foundation.players' COND and STUN; holidays are foundation.holiday's.
--   GetTeamNumber() -> my team
--   TeamOf(t) -> t's team (UNASSIGNED for an entity with none)
--   CollectPlayers(team) -> the living players of team; nil means RED and BLU
--   CollectNPCs(kind) -> the NPCs of that registry kind (foundation.npc KIND)
--   CollectMembers(team) -> the living non-players fighting for team (the
--     AI war's soldiers: WETSAND.SetTeamMember)
--   InCond(t, cond), IsInvulnerable(t) (foundation.npc.targeting's rule),
--   InRespawnRoom(t) (inside an active func_respawnroom)
--   StunPlayer(t, duration, reduction, flags), AddCond(t, cond, duration)
--   RoundHasBeenWon(), DropSpellPickup(v, tier), HolidayActive(h)
--   Explode(config): a foundation.combat Explosion config, run by the combat
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
