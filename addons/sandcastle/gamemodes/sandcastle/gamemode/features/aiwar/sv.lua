-- The aiwar feature's controller: a round (payload, control points or King
-- of the Hill) fought by NextSoldier's NextBot soldiers (npc_nextsoldier,
-- each kind a profile). It owns the features.aiwar.model
-- War and the scenario (features.aiwar.scenario) the round's mode picks,
-- spawns each side's soldiers at its team's spawns in TF2's respawn waves,
-- enlists any soldier that appears while the war runs (a player's
-- included), gives each a features.aiwar.orders Behavior over the soldier
-- port (sv_soldier.lua), and sets who is friend or foe. The rules live in
-- the models; this root declares the controller's state and runs its parts,
-- which feed them the round, the carts and the points and turn their
-- answers into the soldiers' goals.

-------------------------------------------------------------------------------
-- Controller

local Controller = {
	war = nil, -- a features.aiwar.model War while the war runs
	soldiers = {}, -- NPC entity or bot player -> { soldier = port, npc = games.npc.nextbot Npc, speaker (sv_speech) }
	bots = {}, -- bot players tf_bot_quota made -> true (sv_bots.lua)
	doorFlags = {}, -- trigger_multiple -> its spawnflags before the war
	tracks = setmetatable({}, { __mode = "k" }), -- a watcher's path node list -> Track
	nextThink = 0,
	nextRelations = 0,
	slots = nil, -- the features.aiwar.slots Plan, read from slotStore when first needed
	slotStore = nil, -- where the slot list is kept between maps (SlotFile, below)
	hazardStore = nil, -- where the map's nav hazards are kept between loads (HazardFile, below)
	paused = false, -- every soldier stands still (ns_soldiers_paused, SetPaused)
	slotViewers = {}, -- admins whose AI War panel shows the slots -> true
	slotSignature = nil, -- what the viewers were last sent, as text
	nextSlotSync = 0,
	-- gadgets = nil, -- a soldier's grenade, turret or manhack -> { owner, team, kind, expires } (AddGadget)
	-- monsters = nil, -- TF NextBots of no faction -> true (NoteMonster)
	-- losers = nil, -- the team humiliated, or nil for none (Humiliate)
	-- winner = nil, -- the round's winner while the winners hunt (RoundWon)
	-- swapFactions = nil, -- the defenders won: the factions trade sides at the next respawn (RoundWon)
	-- heroes = nil, -- a hero's name -> the soldier given its kit (HeroKit)
	-- lanePlans = nil, -- team -> its lane plan being made (UpdateLanes)
	-- laneSets = nil, -- team -> its lanes found (UpdateLanes)
	-- roomExits = nil, -- a nav area in an enemy spawn room -> where a lane stop there ends instead, this round (OutsideRoom)
	-- gates = nil, -- the setup gates, found once per round (FindGates)
	-- cartBounds = nil, -- the carts' widened bounds, refreshed every think (RefreshCartBounds)
	-- trains = nil, -- cart -> its bounds (RefreshCartBounds)
	-- zones = nil, -- team -> its setup zone (SetupZone)
	-- doorOpened = nil, -- door -> when a soldier may open it again (OpenDoorFor)
	-- openedDoors = nil, -- doors soldiers opened, closed again when left (OpenDoorFor)
	-- shutDoors = nil, -- door that stayed shut -> its areas and the teams it holds up (NoteShutDoor)
	-- scenarios = nil, -- the registered scenarios compiled when the war starts and as a game's players are ready (CompileRegistries), what each think decides from
	-- behaviors = nil, -- the registered behaviours (nextsoldier.behaviors) compiled with them, what each soldier enlisted runs
	shutDoorStamp = 0, -- changes when a door is noted shut to a team, or one noted is gone (ShutDoorAreas)
	footAreas = setmetatable({}, { __mode = "k" }), -- soldier -> the nav area id it last stood on, on the ground (NoteFooting)
	-- hazards = nil, -- the map's wartactics.hazards, read from its save when first asked (Hazards)
	-- hazardsSaved = nil, -- the map has a save of its hazards (Hazards, SaveHazards)
	-- newlyDisabled = nil, -- the areas disabled since the last separation judgement, spared if they cut a team off (SpareKeystones)
	-- separationCheck = nil, -- the transaction judging whether the disabled hazards cut a team off, on the slow lane (CheckSeparation)
	-- separationAgain = nil, -- asked again while it was judging: judged once more when done
	-- hazardsApplied = nil, -- the saved hazards were applied and the map judged, once its first field was made (HazardsThink)
	shutDoorAreas = {}, -- team -> { doors, stamp, areas = nav area id -> true }: the areas of the doors noted shut to it
	-- postCache = nil, -- the posts found, by kind, team and key (CachedPosts)
	-- baseCache = nil, -- each team's spawns on the ground and its base, kept until the next round (Bases)
	-- cartEntities = nil, -- team -> its cart in the last field (Field)
	-- waypointCache = nil, -- the waypoints squads explore, sampled once a map (Waypoints)
	-- scenario = nil, -- the round mode's scenario while the war runs (Start)
	-- waitingFor = nil, -- the part of the field the scenario lacks (Survey)
	-- nextWatch = nil, -- when the observer next watches the soldiers (Think)
	-- nextDebug = nil, -- when the debug overlay is next sent (SendDebug)
	-- tuner = nil, -- the tactics tuner of ns_tactics_*, made when first used
	-- probes = nil, -- path probes walking the lanes, with their findings (ProbeLanes)
	-- probeReport = nil, -- the last probe run's report, as lines (StepProbes)
	-- botSerial = nil, -- how many bots it has made, for their names (AddBot)
	-- nextQuota = nil, -- when the quota is next kept (MaintainBotQuota)
}

function Controller:Active()
	return self.war ~= nil
end

local SLOTS_FILE = "ws_aiwar_slots.json" -- under garrysmod/data

local SlotFile = {}

function SlotFile:Read()
	local text = file.Read(SLOTS_FILE, "DATA")
	return text and util.JSONToTable(text)
end

function SlotFile:Write(saved)
	file.Write(SLOTS_FILE, util.TableToJSON(saved, true))
end

Controller.slotStore = SlotFile

-- The map's nav hazards (sv_hazards.lua), kept in data/ between loads.
local HAZARDS_FOLDER = "sandcastle/nav_hazards/"

local HazardFile = {}

function HazardFile:Read()
	return WS.MapData.Read(HAZARDS_FOLDER)
end

function HazardFile:Write(data)
	WS.MapData.Write(HAZARDS_FOLDER, data)
end

Controller.hazardStore = HazardFile

local Part = WS.FeatureParts(getfenv(1), "aiwar")
local Map = Part("sv_map", Controller)
local Soldier, ARRIVED = Part("sv_soldier", Map)
Part("sv_gadgets", Map, Soldier)
Controller.Soldier = Soldier
Controller.BotSoldier = Part("sv_bot_soldier", Map, Soldier)
Part("sv_relations", Controller, Map)
Part("sv_enlist", Controller, Map)
Part("sv_bots", Controller, Map)
Part("sv_speech", Controller)
Part("sv_obstacles", Controller, Map)
local WATCH_INTERVAL = Part("sv_posts", Controller, Map)
Part("sv_lanes", Controller, Map)
Part("sv_probe", Controller, Map)
Part("sv_field", Controller, Map, WATCH_INTERVAL)
Part("sv_slots", Controller, Map)
Part("sv_war", Controller, Map)
Part("sv_report", Controller, Map, ARRIVED)
Part("sv_commands", Controller, Map)
Part("sv_hazards", Controller, Map)

-- A cleanup (every full round reset) removes the soldiers and remakes the
-- map's triggers: the doors are opened again and the first wave comes at once.
hook.Add("PostCleanupMap", "ws_aiwar", function()
	if not Controller.war then return end
	Controller.doorFlags = {}
	Controller:OpenDoorsToSoldiers()
	Controller:SetForcefieldsPassable(true)
	Controller.gates = nil
	Controller.zones = nil
	Controller.shutDoors = nil
	Controller.postCache = nil
	Controller.baseCache = nil
	Controller.war:ResetWaves()
end)

return Controller
