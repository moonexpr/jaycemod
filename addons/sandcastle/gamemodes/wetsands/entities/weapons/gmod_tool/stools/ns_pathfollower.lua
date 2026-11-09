AddCSLuaFile()

-- The Path Follower stool: one probe (npc_pathfollower), one selection, four modes. A mode
-- drives the selected followers its way (their driver): Path, their bench, sent to a goal; Local,
-- their legs alone, told a squad's order and mode; Tactical, the AI war's orders (a bench war
-- when none runs), under conditions the stool sets. Annotate marks the map for the war. Their feet
-- may be held whatever drives them: each then plans and shows its path but does not walk it.
TOOL.Category = "NextSoldier"
TOOL.Name = "#tool.ns_pathfollower.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar = {
	mode = "path",
	model = "models/player/p2_chell.mdl",
	team = "3",
	hold = "1",
	spacing = "1",
	order = "Muster",
	legsmode = "0",
	lanes = "1",
	missions = "1",
	mark = "post",
}

-- The yes-or-no queries a follower answers on its bench, a checkbox each, unchecked by default.
local QUERIES = nextsoldier.behavior.YES_NO_QUERIES
local QUERY_LABELS = {
	ShouldAttack = "Should attack?",
	ShouldHurry = "Should hurry?",
	ShouldRetreat = "Should retreat?",
	ShouldPickUp = "Should pick up?",
}
local QUERY_HELP = {
	ShouldHurry = "Should hurry? (runs when checked, walks when not)",
}

local function QueryConVar(name) return "query_" .. name:lower() end

for _, name in ipairs(QUERIES) do
	TOOL.ClientConVar[QueryConVar(name)] = "0"
end

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" },
}

local FOLLOWER = "npc_pathfollower"
local LIFT = Vector(0, 0, 1)

-- What drives the selected followers in each mode; annotating leaves them as they are.
local MODES = {
	{ "path", "Path: send them to a goal", "path" },
	{ "local", "Local: their legs, a squad's order and mode", "legs" },
	{ "tactical", "Tactical: the AI war's orders", "war" },
	{ "annotate", "Annotate: mark the map for the war" },
}
local DRIVER_OF = {}
for _, entry in ipairs(MODES) do DRIVER_OF[entry[1]] = entry[3] end

local MODELS = {
	"models/player/p2_chell.mdl",
	"models/player/scout.mdl",
	"models/bots/headless_hatman.mdl",
	"models/bots/boss_bot/static_boss_tank.mdl",
	"models/bots/bot_worker/bot_worker.mdl",
	"models/bots/merasmus/merasmus.mdl",
}

local MODEL_NAMES = {
	["models/player/p2_chell.mdl"] = "Chell",
	["models/player/scout.mdl"] = "Scout",
	["models/bots/headless_hatman.mdl"] = "Headless Hatman",
	["models/bots/boss_bot/static_boss_tank.mdl"] = "Tank",
	["models/bots/bot_worker/bot_worker.mdl"] = "Bot Worker",
	["models/bots/merasmus/merasmus.mdl"] = "Merasmus",
}

local MODEL_COLLISION_BOUNDS = {
	["models/player/p2_chell.mdl"] = { x = 13, y = 13, z = 72 },
	["models/player/scout.mdl"] = { x = 19.3, y = 16.6, z = 83.1 },
	["models/bots/headless_hatman.mdl"] = { x = 25.6, y = 38.2, z = 138.5 },
	["models/bots/boss_bot/static_boss_tank.mdl"] = { x = 117.4, y = 79.2, z = 176.2 },
	["models/bots/bot_worker/bot_worker.mdl"] = { x = 34.5, y = 16, z = 54.4 },
	["models/bots/merasmus/merasmus.mdl"] = { x = 92.8, y = 49.7, z = 190.4 },
}

local ORDER_NAMES = {
	Muster = "Muster at the aim",
	FallBack = "Fall back to the aim, away from you",
	Assault = "Assault the room at the aim: stage at its nearest door, then in on the leader's signal",
	Fortify = "Fortify the room at the aim: a builder sets a sentry at its middle, the rest round it",
}

-- The orders given a room, refused without one.
local ROOM_ORDERS = { Assault = true, Fortify = true }

-- The squad's mode (the legs' MODE, one whole number a squad): the menu's names by number.
local LEGS_MODE_NAMES = {
	[0] = "Stationary: rest at seats near their places",
	[1] = "Alert: patrol round the point, each on its side",
	[2] = "Cautious: wander near their places",
	[3] = "Panic: evacuate by the way out furthest from the threat",
	[4] = "Close: stay close to the leader",
}

-- The jobs a squad may be given; the war refuses one its scenario has not.
local JOBS = {
	"push", "escort", "block", "defend", "raid", "support", "capture", "assault", "hold", "explore",
	"courier", "ctf_defend", "operative",
}

-- What annotating places: a mark of the war's by hand, a mission for the selected squads, or a
-- Gameplay tool's objective (the builder's kind).
local MARKS = {
	{ "post", "Post: its team's defenders hold it", "mark" },
	{ "rally", "Rally: its team's recalled squads regroup here", "mark" },
	{ "enemy", "Enemy: its team's squads have seen one here", "mark" },
	{ "avoid", "Avoid: the areas here are closed to every team", "mark" },
	{ "danger", "Danger: its team's squads near it retreat from it", "mark" },
	{ "assault", "Mission: the selection's squads assault the room here", "mission" },
	{ "topple", "Mission: the selection's squads topple the room here", "mission" },
	{ "ambush", "Mission: the selection's squads ambush in the room here", "mission" },
	{ "advance", "Mission: the selection's squads advance as the war has them", "mission" },
	{ "point", "Objective: a control point", "piece" },
	{ "spawn", "Objective: its team's spawner", "piece" },
	{ "room", "Objective: its team's spawn room (two corners)", "piece" },
	{ "flag", "Objective: its team's flag", "piece" },
	{ "zone", "Objective: its team's flag capture zone", "piece" },
	{ "node", "Objective: a cart track's next node", "piece" },
	{ "sign", "Objective: a sign to the objective", "piece" },
}
local MARK_OF = {}
for _, entry in ipairs(MARKS) do MARK_OF[entry[1]] = entry end
-- Reload while annotating takes the marks this near the aim.
local UNMARK_REACH = 96

if CLIENT then
	language.Add("tool.ns_pathfollower.name", "Path Follower")
	language.Add("tool.ns_pathfollower.desc", "Spawn path followers and drive them: a path, their legs, the AI war; or mark the map")
	language.Add("tool.ns_pathfollower.left", "Spawn a follower, or add/remove a follower (or, in Tactical, a soldier of the war) from your selection; annotating, place the annotation")
	language.Add("tool.ns_pathfollower.right", "Path: send the selection here. Local: give its squad the order here. Tactical: report an enemy contact here")
	language.Add("tool.ns_pathfollower.reload", "Release your selection (dissolving its squad's order); annotating, remove the marks or piece here")

	local YES_COLOR, NO_COLOR = Color(120, 255, 120), Color(255, 140, 140)
	local QUERY_LINE_HEIGHT, QUERY_OFFSET = 16, 24
	local MARK_COLORS = { [2] = Color(255, 110, 100), [3] = Color(110, 170, 255) }
	local MARK_NAMES = { post = "POST", rally = "RALLY", enemy = "ENEMY SEEN", avoid = "AVOID" }

	-- What the follower under the crosshair answers, on its bench.
	function TOOL:DrawHUD()
		local follower = self:GetOwner():GetEyeTrace().Entity
		if not IsValid(follower) or follower:GetClass() ~= FOLLOWER then return end
		local x, y = ScrW() / 2 + QUERY_OFFSET, ScrH() / 2 + QUERY_OFFSET
		for i, name in ipairs(QUERIES) do
			local yes = follower:GetNW2Bool("NSQuery" .. name, false)
			draw.SimpleTextOutlined(QUERY_LABELS[name] .. " " .. (yes and "yes" or "no"), "DermaDefaultBold",
				x, y + (i - 1) * QUERY_LINE_HEIGHT, yes and YES_COLOR or NO_COLOR,
				TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
		end
	end

	-- The war's marks by hand, named over their spots for whoever has the stool out.
	hook.Add("HUDPaint", "ns_pathfollower_marks", function()
		local weapon = LocalPlayer():GetActiveWeapon()
		if not (IsValid(weapon) and weapon:GetClass() == "gmod_tool" and weapon:GetMode() == "ns_pathfollower") then return end
		local text = GetGlobal2String("ns_marks", "")
		if text == "" then return end
		for kind, team, x, y, z in text:gmatch("(%a+) (%-?%d+) (%-?%d+) (%-?%d+) (%-?%d+)") do
			local screen = Vector(tonumber(x), tonumber(y), tonumber(z) + 24):ToScreen()
			if screen.visible then
				draw.SimpleTextOutlined(MARK_NAMES[kind] or kind, "DermaDefaultBold", screen.x, screen.y,
					MARK_COLORS[tonumber(team)] or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
			end
		end
	end)
end

-- Selection: a player's followers (and the war's soldiers picked in Tactical), in the order picked.

local selections = setmetatable({}, { __mode = "k" })

local function Selection(ply)
	local selected = selections[ply]
	if not selected then
		selected = { list = {}, applied = {} }
		selections[ply] = selected
	end
	return selected
end

-- The selected still there, the first picked first.
local function Selected(ply)
	local selected = Selection(ply)
	for i = #selected.list, 1, -1 do
		if not IsValid(selected.list[i]) then table.remove(selected.list, i) end
	end
	local list = {}
	for i, ent in ipairs(selected.list) do list[i] = ent end
	return list
end

local function IsFollower(ent) return IsValid(ent) and ent:GetClass() == FOLLOWER and ent.NSToolManaged end

-- The selected followers driven by driver.
local function DrivenBy(ply, driver)
	local list = {}
	for _, ent in ipairs(Selected(ply)) do
		if IsFollower(ent) and ent:NSDriver() == driver then list[#list + 1] = ent end
	end
	return list
end

local function Select(ply, ent, on)
	local selected = Selection(ply)
	for i, other in ipairs(selected.list) do
		if other == ent then table.remove(selected.list, i) break end
	end
	if on then selected.list[#selected.list + 1] = ent end
	ent:SetNW2Bool("NSProbeSelected", on)
	-- the boxes and the mode reach it at the next think
	selected.applied = {}
end

local function Tell(ply, text) ply:ChatPrint("[Path Follower] " .. text) end

-- The war's controller while a war runs, else nil and the player told.
local function War(ply)
	local controller = WS.Feature("aiwar")
	if controller and controller.war then return controller end
	Tell(ply, "No war is running: select or spawn followers in Tactical mode, which starts a bench war.")
	return nil
end

-- The squads of the selected soldiers in the war, each once.
local function FireTeams(ply, controller)
	local seen, list = {}, {}
	for _, ent in ipairs(Selected(ply)) do
		local member = controller.soldiers[ent] and controller.war:Member(ent)
		local fireTeam = member and member.fireTeam
		if fireTeam and not seen[fireTeam] then seen[fireTeam], list[#list + 1] = true, fireTeam end
	end
	return list
end

local function Point(v) return { x = v.x, y = v.y, z = v.z } end

local function PanelTeam(tool)
	return tool:GetClientNumber("team") == WS.TEAM_RED and WS.TEAM_RED or WS.TEAM_BLUE
end

local function Mode(tool) return tool:GetClientInfo("mode") end

-- Driven as the mode drives: whether it could be, told why not.
local function Drive(ply, follower, driver)
	local ok, why = follower:NSSetDriver(driver)
	if not ok then Tell(ply, "Could not drive it by " .. driver .. ": " .. tostring(why)) end
	return ok
end

-- Annotating ----------------------------------------------------------------------

-- A Gameplay tool's objective, placed as that tool places it.
local function PlacePiece(tool, ply, trace, kind)
	local Builder = WS.require("features.builder.model")
	local values = { TeamNum = PanelTeam(tool) }
	local kinds = {
		point = { Builder.POINT }, spawn = { Builder.SPAWN, values }, room = { Builder.ROOM, values },
		flag = { Builder.FLAG, values }, zone = { Builder.ZONE, values }, node = { Builder.NODE }, sign = { Builder.SIGN },
	}
	if kind == "spawn" then values.BodyModel = Builder.SpawnModel(Builder.SPAWN_MODELS[1]) end
	local piece = kinds[kind]
	return WS.Feature("builder"):Do("Place", ply, trace, piece[1], piece[2])
end

local function Annotate(tool, ply, trace)
	local entry = MARK_OF[tool:GetClientInfo("mark")]
	if not entry then return false end
	local kind, what = entry[1], entry[3]
	if what == "piece" then return PlacePiece(tool, ply, trace, kind) end
	local at = Point(trace.HitPos)
	if what == "mark" then
		-- kept by the war's controller with or without a war, for the next one to read
		WS.Feature("aiwar"):Mark(kind, PanelTeam(tool), at)
		return true
	end
	local controller = War(ply)
	if not controller then return false end
	local fireTeams = FireTeams(ply, controller)
	if #fireTeams == 0 then
		Tell(ply, "Select soldiers in a squad first: a mission is a squad's.")
		return false
	end
	for _, fireTeam in ipairs(fireTeams) do
		local ok, why = controller:GiveMission(fireTeam, kind, at)
		Tell(ply, ok and ("a squad's next mission: " .. kind) or why)
		if not ok then return false end
	end
	return true
end

-- Clicks --------------------------------------------------------------------------

local function Spawn(tool, ply, trace)
	local model = tool:GetClientInfo("model")
	if not MODEL_NAMES[model] then return false end
	if not util.IsValidModel(model) then
		Tell(ply, "Model is not mounted: " .. model)
		return false
	end
	local follower = ents.Create(FOLLOWER)
	if not IsValid(follower) then
		Tell(ply, "Could not create " .. FOLLOWER .. ".")
		return false
	end
	follower.NSToolManaged = true
	follower.Model = model
	follower.CollisionBounds = MODEL_COLLISION_BOUNDS[model]
	follower:SetPos(trace.HitPos + LIFT)
	follower:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	follower:Spawn()
	follower:Activate()
	if not IsValid(follower) then
		Tell(ply, "The follower failed to spawn.")
		return false
	end
	follower:NSSetTeam(PanelTeam(tool))
	ply:AddCleanup("ns_pathfollower", follower)
	undo.Create("Path Follower")
	undo.AddEntity(follower)
	undo.SetPlayer(ply)
	undo.Finish()
	local driver = DRIVER_OF[Mode(tool)]
	if driver and not Drive(ply, follower, driver) then return false end
	Select(ply, follower, true)
	return true
end

function TOOL:LeftClick(trace)
	if CLIENT then return true end
	local ply = self:GetOwner()
	if not IsValid(ply) or not trace.Hit or trace.HitSky then return false end
	if Mode(self) == "annotate" then return Annotate(self, ply, trace) end
	local hit = trace.Entity
	local controller = WS.Feature("aiwar")
	if IsFollower(hit) or (Mode(self) == "tactical" and IsValid(hit) and controller.soldiers[hit]) then
		Select(ply, hit, not hit:GetNW2Bool("NSProbeSelected", false))
		return true
	end
	return Spawn(self, ply, trace)
end

-- Local: the selected legs' squad, its order at point.
local function GiveOrder(tool, ply, trace)
	local members = DrivenBy(ply, "legs")
	if #members == 0 then
		Tell(ply, "Spawn or select followers in Local mode first.")
		return false
	end
	local Legs = nextsoldier.behavior.group_identity
	local point = Point(trace.HitPos)
	local positions = {}
	for i, member in ipairs(members) do positions[i] = Point(member:GetPos()) end
	local order
	local kind = tool:GetClientInfo("order")
	local controller = WS.Feature("aiwar")
	local middle = { x = 0, y = 0, z = 0 }
	for _, p in ipairs(positions) do middle.x, middle.y = middle.x + p.x / #positions, middle.y + p.y / #positions end
	if ROOM_ORDERS[kind] and not controller.rooms then controller:FindRoomsNow() end
	-- the room at the aim, its known enemy the squad's team's
	local room = controller:RoomForSquad(point, middle, members[1]:NSTeam())
	if ROOM_ORDERS[kind] and not room then
		Tell(ply, "An order to " .. kind:lower() .. " needs a room with a door at the aim.")
		return false
	end
	if kind == "Assault" then
		order = Legs.Assault(room)
	elseif kind == "Fortify" then
		-- its teleporter's entrance, when worth one, where its leader sets out
		order = nextsoldier.squad.behaviors.fortify.Fortify(room, positions[1])
	elseif kind == "FallBack" then
		order = Legs.FallBack(point, Point(ply:GetPos()))
		if not order then
			Tell(ply, "A fall back needs a point away from you: aim further off.")
			return false
		end
	else
		order = Legs.Muster(point)
	end
	order:SetMode(Legs.MODE(tool:GetClientNumber("legsmode")) or Legs.MODE.STATIONARY)
	-- a panicked squad leaves by the room's doors and hides out of its sight
	if room then order:SetRoom(room) else order:SetExits(controller:ExitsAt(point)) end
	local places = order:Places(positions, nextsoldier.engine.GroupSpacing(), members[1]:NSLegsAdmit(trace.HitPos),
		function(around) return members[1]:NSLegsAdmit(around) end)
	for i, member in ipairs(members) do member:NSLegsGive(order, places[i]) end
	order:Lead(members[1])
	return true
end

function TOOL:RightClick(trace)
	if CLIENT then return true end
	local ply = self:GetOwner()
	if not IsValid(ply) or not trace.Hit or trace.HitSky then return false end
	local mode = Mode(self)
	if mode == "annotate" then
		Tell(ply, "Annotating: left-click places, reload removes; a piece's properties are its Edit Properties (hold C, right-click it).")
		return false
	end
	if mode == "local" then return GiveOrder(self, ply, trace) end
	if mode == "tactical" then
		local controller = War(ply)
		if not controller then return false end
		local fireTeams = FireTeams(ply, controller)
		if #fireTeams == 0 then
			Tell(ply, "Select soldiers in a squad first.")
			return false
		end
		for _, fireTeam in ipairs(fireTeams) do wartactics.fireteam.Report(fireTeam, Point(trace.HitPos), CurTime()) end
		return true
	end
	local followers = DrivenBy(ply, "path")
	if #followers == 0 then
		Tell(ply, "Spawn or select followers in Path mode first.")
		return false
	end
	for _, follower in ipairs(followers) do follower:NSSetGoal(trace.HitPos) end
	return true
end

function TOOL:Reload(trace)
	if CLIENT then return true end
	local ply = self:GetOwner()
	if not IsValid(ply) then return false end
	if Mode(self) == "annotate" then
		if WS.Feature("aiwar"):Unmark(trace.HitPos, UNMARK_REACH) > 0 then return true end
		return WS.Feature("builder"):Do("RemoveAt", ply, trace)
	end
	for _, ent in ipairs(Selected(ply)) do
		if IsFollower(ent) and ent:NSDriver() == "legs" then ent:NSLegsGive(nil) end
		if ent.NSHoldFeet and not IsFollower(ent) then ent:NSHoldFeet(false) end
		Select(ply, ent, false)
	end
	selections[ply] = nil
	return true
end

-- The panel reaches the selection as it changes: its mode drives the followers, their feet are
-- held or not, their answers, their squad's mode, their squads' lanes and missions.
function TOOL:Think()
	if CLIENT then return end
	local ply = self:GetOwner()
	local selected = selections[ply]
	if not selected then return end
	local mode, hold = Mode(self), self:GetClientNumber("hold") ~= 0
	local legsMode = nextsoldier.behavior.group_identity.MODE(self:GetClientNumber("legsmode"))
	local lanesOff, missionsOff = self:GetClientNumber("lanes") == 0, self:GetClientNumber("missions") == 0
	local applied = selected.applied
	if applied.mode ~= mode or applied.hold ~= hold then
		applied.mode, applied.hold = mode, hold
		local driver = DRIVER_OF[mode]
		for _, ent in ipairs(Selected(ply)) do
			if IsFollower(ent) and driver then Drive(ply, ent, driver) end
			if ent.NSHoldFeet then ent:NSHoldFeet(hold) end
		end
	end
	for _, follower in ipairs(DrivenBy(ply, "path")) do
		for _, name in ipairs(QUERIES) do
			follower:NSRespond(name, self:GetClientNumber(QueryConVar(name)) ~= 0)
		end
	end
	-- the menu's mode as it is changed, so a squad's own (its leader's fall back) holds
	if legsMode and applied.legsMode ~= legsMode then
		applied.legsMode = legsMode
		for _, member in ipairs(DrivenBy(ply, "legs")) do
			local order = member:NSLegsOrder()
			if order and order.mode ~= legsMode then order:SetMode(legsMode) end
		end
	end
	local controller = WS.Feature("aiwar")
	if controller.war and (applied.lanesOff ~= lanesOff or applied.missionsOff ~= missionsOff) then
		applied.lanesOff, applied.missionsOff = lanesOff, missionsOff
		for _, fireTeam in ipairs(FireTeams(ply, controller)) do
			fireTeam.lanesOff, fireTeam.missionsOff = lanesOff or nil, missionsOff or nil
		end
	end
end

if SERVER then
	-- A console command on the player's selection in the war: fn(ply, controller, indexes, args) -> lines.
	local function WarCommand(name, fn, help)
		concommand.Add(name, function(ply, _, args)
			if not IsValid(ply) or not ply:IsSuperAdmin() then return end
			local controller = War(ply)
			if not controller then return end
			local indexes = {}
			for _, ent in ipairs(Selected(ply)) do
				if controller.soldiers[ent] then indexes[#indexes + 1] = ent:EntIndex() end
			end
			if #indexes == 0 then
				Tell(ply, "Select soldiers in the war first (Tactical mode).")
				return
			end
			for _, line in ipairs(fn(ply, controller, indexes, args) or {}) do Tell(ply, line) end
			-- the boxes are applied again to what changed
			Selection(ply).applied = {}
		end, nil, help)
	end

	WarCommand("ns_pathfollower_squad", function(_, controller, indexes)
		return controller:FormSquadOf(indexes)
	end, "Form the Path Follower stool's selection in the war into one squad, the first picked leading")

	WarCommand("ns_pathfollower_job", function(_, controller, indexes, args)
		if args[1] == "war" then return controller:ReleaseJob(indexes) end
		return controller:AssignJob(string.lower(args[1] or ""), indexes)
	end, "Give the Path Follower stool's selection in the war a job (war: the war's own again)")

	WarCommand("ns_pathfollower_recall", function(ply, controller)
		local lines = {}
		for _, fireTeam in ipairs(FireTeams(ply, controller)) do
			wartactics.mission.Recall(fireTeam, wartactics.mission.CASUALTIES)
			lines[#lines + 1] = "a squad was recalled to regroup"
		end
		return lines
	end, "Recall the selection's squads to regroup, as heavy casualties do")
end

function TOOL.BuildCPanel(panel)
	panel:Help("Left-click spawns a follower or selects one (a cyan ring); the mode drives the whole selection its way. Their feet held, each plans and draws its path but does not walk it.")
	local mode = panel:ComboBox("Mode", "ns_pathfollower_mode")
	for _, entry in ipairs(MODES) do mode:AddChoice(entry[2], entry[1]) end
	panel:CheckBox("Hold their feet (uncheck: they walk)", "ns_pathfollower_hold")
	local team = panel:ComboBox("Team (new followers, marks, objectives)", "ns_pathfollower_team")
	team:AddChoice("RED", 2)
	team:AddChoice("BLU", 3)
	local models = panel:ComboBox("Model (new followers)", "ns_pathfollower_model")
	for _, model in ipairs(MODELS) do models:AddChoice(MODEL_NAMES[model], model) end

	panel:Help("Path: right-click sends the selection. The path is cyan, an active AI-war lane amber, the local movement command a magenta arrow. What they answer when asked (aim at one to see):")
	for _, name in ipairs(QUERIES) do
		panel:CheckBox(QUERY_HELP[name] or QUERY_LABELS[name], "ns_pathfollower_" .. QueryConVar(name))
	end

	panel:Help("Local: right-click gives the selection's squad the order at the aim. A cross is each member's place (red at its feet where no place near had room), a white ring where its squad's mode sends it now. A panicked squad makes for the doors of its room, where the AI war has found the rooms, else away from you.")
	local order = panel:ComboBox("Order", "ns_pathfollower_order")
	for name, label in pairs(ORDER_NAMES) do order:AddChoice(label, name) end
	local legsMode = panel:ComboBox("Squad mode", "ns_pathfollower_legsmode")
	for number = 0, nextsoldier.behavior.group_identity.MODE:Last() do legsMode:AddChoice(LEGS_MODE_NAMES[number], number) end
	panel:CheckBox("Show spacing (a ring its radius, pink with an arrow when a teammate pushes)", "ns_pathfollower_spacing")

	panel:Help("Tactical: the war's orders (a bench war, with no bots or waves, when none runs). A yellow cross is where its orders send a held soldier. Right-click reports an enemy contact at the aim to their squads.")
	panel:CheckBox("Lanes (uncheck: their squads go straight)", "ns_pathfollower_lanes")
	panel:CheckBox("Missions (uncheck: their squads ask for none)", "ns_pathfollower_missions")
	panel:Button("Form one squad of the selection", "ns_pathfollower_squad")
	local jobs = panel:ComboBox("Job")
	jobs:AddChoice("the war's own", "war")
	for _, job in ipairs(JOBS) do jobs:AddChoice(job, job) end
	function jobs:OnSelect(_, _, job) RunConsoleCommand("ns_pathfollower_job", job) end
	panel:Button("Recall their squads to regroup", "ns_pathfollower_recall")
	panel:Button("Toggle the AI war's overlay", "ws_aiwar_debug")

	panel:Help("Annotate: left-click places, reload removes what is near the aim, for the team above. A mission is the selected squads'.")
	local mark = panel:ComboBox("Annotation", "ns_pathfollower_mark")
	for _, entry in ipairs(MARKS) do mark:AddChoice(entry[2], entry[1]) end
end
