-- The game builder on a live server, with no client. builder_check() lays a
-- payload out as the Gameplay tools do; then mp_gameplay_begin starts the game,
-- and builder_status() and builder_push() check it as data: the helpers outlast
-- the cleanup, their entities are made again, and a bot on the cart pushes it to
-- the win. builder_lay_points() and builder_lay_flags() lay the other games out,
-- each on a fresh map, as the mode only rises. Use on a server of your own.
local Builder = WS.Feature("builder")
local Model = WS.require("features.builder.model")

local function Open()
	local bot = player.GetBots()[1] or player.CreateNextBot("builder_check")
	local tr = util.TraceLine({ start = Vector(-1800, 0, 0), endpos = Vector(-1800, 0, -16000), mask = MASK_SOLID_BRUSHONLY })
	return bot, function(x, y)
		return { HitPos = Vector(tr.HitPos.x + x, y, tr.HitPos.z), HitNormal = Vector(0, 0, 1), Hit = true }
	end
end

local function Problems()
	return Model.Compile(Builder:PieceEnts()).problems
end

function builder_check()
	local bot, Trace = Open()
	Builder:Place(bot, Trace(0, 0), Model.SPAWN, { TeamNum = 2, BodyModel = "models/player/heavy.mdl" })
	Builder:Place(bot, Trace(0, 300), Model.SPAWN, { TeamNum = 3 })
	Builder:Place(bot, Trace(-100, -100), Model.ROOM, { TeamNum = 2 })
	Builder:Place(bot, Trace(100, 100), Model.ROOM, { TeamNum = 2 })
	Builder:Place(bot, Trace(300, 0), Model.NODE)
	Builder:Place(bot, Trace(300, 200), Model.NODE)
	Builder:Place(bot, Trace(300, 400), Model.NODE)
	Builder:Act(bot, Model.NODE, "ToggleHelper", Trace(300, 200))
	Builder:Place(bot, Trace(600, 0), Model.SIGN)
	for _, point in ipairs(ents.FindByClass(Model.CLASSES[Model.POINT])) do point:SetPrintName("Bridge") end
	local editor = Builder:Create(bot, Model.SCENARIO, Trace(700, 0).HitPos + Vector(0, 0, 16), angle_zero)
	editor:SetCapLayout("0, 1")
	editor:SetScoreStyle(1)
	editor:SetRedRespawn(4)
	return util.TableToJSON({ pieces = #Builder:PieceEnts(), problems = Problems() })
end

-- What the helpers are now: kinds, ids, a helper's node and name, the editor's.
function builder_report()
	local out = { pieces = {}, compiled = table.Count(Builder.compiled) }
	for _, piece in ipairs(Builder:PieceEnts()) do
		local node = piece:GetNodeId()
		out.pieces[#out.pieces + 1] = piece.Kind .. "#" .. piece:Id() .. (node ~= 0 and (" node " .. node) or "")
		if piece.Kind == Model.POINT then out.name, out.owner = piece:GetPrintName(), piece:GetDefaultOwner() end
		if piece.Kind == Model.SCENARIO then out.layout, out.style, out.respawn = piece:GetCapLayout(), piece:GetScoreStyle(), piece:GetRedRespawn() end
		if piece.Kind == Model.NODE then out.linked = (out.linked or 0) + (IsValid(piece:GetNextNode()) and 1 or 0) end
	end
	table.sort(out.pieces)
	out.rules = IsValid(WS.Rules) and WS.Rules:GetClass()
	return util.TableToJSON(out)
end

function builder_save()
	builder_saved = gmsave.SaveMap(player.GetBots()[1])
	local classes = {}
	for _, ent in pairs(util.JSONToTable(builder_saved).Entities or {}) do classes[ent.Class] = (classes[ent.Class] or 0) + 1 end
	return util.TableToJSON(classes)
end

function builder_load()
	gmsave.LoadMap(builder_saved, player.GetBots()[1])
	return "loading"
end

function builder_status()
	local capture = WS.Feature("capture")
	local train = ents.FindByClass("func_tracktrain")[1]
	local watcher = ents.FindByClass("team_train_watcher")[1]
	local owners = {}
	for _, point in ipairs(ents.FindByClass("team_control_point")) do owners[point:GetName()] = capture:Owner(point) end
	local spawnTeams = { [2] = 0, [3] = 0 }
	for _, spawn in ipairs(ents.FindByClass("info_player_teamspawn")) do
		local team = WS.SpawnState(spawn).team
		spawnTeams[team] = (spawnTeams[team] or 0) + 1
	end
	return util.TableToJSON({
		running = Builder.running,
		active = WS.Active(),
		halted = WS.GameplayStopped(),
		state = WS.State(),
		mode = WS.Feature("rounds"):Mode().NAME,
		pieces = #Builder:PieceEnts(),
		red_spawns = spawnTeams[2],
		blu_spawns = spawnTeams[3],
		train_path = IsValid(train) and tostring(train:GetInternalVariable("m_ppath")),
		train_speed = IsValid(train) and train:GetInternalVariable("m_flSpeed"),
		progress = IsValid(watcher) and watcher:IsActive() and watcher:HudState().progress,
		owners = owners,
		timers = #ents.FindByClass("team_round_timer"),
		winner = GetGlobal2Int("ws_round_winner", -1),
	})
end

-- The properties as the game took them.
function builder_applied()
	local capture = WS.Feature("capture")
	local out = {
		caplayout = capture.master and capture.master:CapLayout(),
		per_capture = capture.master and capture.master:ScorePerCapture(),
		red_wave = WS.Rules:TeamRespawnWaveTime(WS.TEAM_RED),
		mode = WS.Feature("rounds"):Mode().NAME,
		names = {},
		plates = 0,
		cart_prop = IsValid(WS.FindByName("build_cart_prop")),
		rails = {},
	}
	for _, point in ipairs(ents.FindByClass("team_control_point")) do
		out.names[#out.names + 1] = point:GetName() .. "=" .. capture:Set():PrintName(point) .. " " .. point:GetModel()
	end
	for _, prop in ipairs(ents.FindByClass("prop_dynamic")) do
		if string.find(prop:GetModel() or "", "cap_point_base", 1, true) then out.plates = out.plates + 1 end
	end
	for _, node in ipairs(ents.FindByClass(Model.CLASSES[Model.NODE])) do out.rails[#out.rails + 1] = tostring(node:GetNoDraw()) end
	return util.TableToJSON(out)
end

-- Keeps a BLU bot on the cart until stopped.
function builder_push(on)
	timer.Remove("builder_push")
	if not on then return "stopped" end
	local bot = player.GetBots()[1]
	WS.SetPlayerTeam(bot, WS.TEAM_BLUE, true)
	bot:Spawn()
	timer.Create("builder_push", 0.1, 0, function()
		local train = ents.FindByClass("func_tracktrain")[1]
		if IsValid(train) and IsValid(bot) then
			if not bot:Alive() then bot:Spawn() end
			bot:SetPos(train:GetPos() + Vector(0, 0, 40))
		end
	end)
	return "pushing as " .. bot:Nick()
end

-- Spawners for one team, or both, and the war asked to start before any game:
-- what it answers, and what it left.
function builder_war_start(teams)
	local bot, Trace = Open()
	for i, team in ipairs(teams) do Builder:Place(bot, Trace(i * 200, 0), Model.SPAWN, { TeamNum = team }) end
	local war = WS.Feature("aiwar")
	local ok, why = war:Start()
	local spawns = {}
	for _, spawn in ipairs(ents.FindByClass("info_player_teamspawn")) do spawns[#spawns + 1] = WS.SpawnState(spawn).team end
	return util.TableToJSON({ ok = ok, why = why, running = Builder.running, compiled = table.Count(Builder.compiled), spawns = #spawns, mode = WS.Feature("rounds"):Mode().NAME, war = WS.AiWarActive() })
end

return "loaded"
