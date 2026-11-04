-- The game builder's controller: what spans the helpers (each does its own work:
-- entities/entities/base_gameplay_piece): placing them, by the tools' rules, and
-- their game's life: its entities made as it starts and again after every cleanup,
-- which removes them, and gone when it stops. The helpers last the whole map, so
-- what is wired to them does too, and Sandbox's saves and dupes carry them.
--
-- Loaded by the first use of a Gameplay tool, or a paste of a helper.
local Model = WS.require("features.builder.model")
local ControlPoints = WS.require("features.rounds.control_points")

local HOOK = "ws_builder"
local PASTED_TIMER = "ws_builder_pasted"
local PREFIX = "[Gameplay] "
local Z_LIFT = 2

local Controller = {
	rounds = WS.Feature("rounds"),
	compiled = {}, -- name -> entity, of the game running
	running = false,
	nextId = 1,
	clicks = setmetatable({}, { __mode = "k" }), -- player -> { piece, at }, a click on a placed helper
}

for _, class in pairs(Model.CLASSES) do Controller.rounds:KeepThroughCleanup(class) end
for _, class in ipairs(Model.WireClasses(table.GetKeys(scripted_ents.GetList()))) do
	Controller.rounds:KeepThroughCleanup(class)
end

local function Class(kind)
	return scripted_ents.GetStored(Model.CLASSES[kind]).t
end

-- The helpers ---------------------------------------------------------------------------

function Controller:PieceEnts()
	local pieces = {}
	for _, class in pairs(Model.CLASSES) do
		for _, ent in ipairs(ents.FindByClass(class)) do pieces[#pieces + 1] = ent end
	end
	return pieces
end

function Controller:PieceOf(trace, kind)
	local ent = trace.Entity
	if IsValid(ent) and ent.Kind and Model.CLASSES[ent.Kind] == ent:GetClass() and (not kind or ent.Kind == kind) then return ent end
	return nil
end

function Controller:Create(ply, kind, pos, ang, box, values)
	local ent = ents.Create(Model.CLASSES[kind])
	ent:SetPos(pos)
	ent:SetAngles(ang)
	ent:SetCreator(ply)
	ent:Configure(self.nextId, box)
	self.nextId = self.nextId + 1
	ent:Spawn()
	ent:Activate()
	if values then ent:Update(values) end
	return ent
end

function Controller:Undoable(ply, label, ...)
	undo.Create(label)
	for _, ent in ipairs({ ... }) do undo.AddEntity(ent) end
	undo.SetPlayer(ply)
	undo.Finish()
	return true
end

-- Whether the map and the moment let the builder run: told if not.
function Controller:Do(method, ply, ...)
	local refusal
	if not GetGlobal2Bool("ws_builder_available", false) then
		refusal = "This map has its own objectives: the Gameplay tools are for maps without."
	elseif self.running or (WS.Active() and not WS.GameplayStopped()) then
		refusal = "A game is running or starting: stop it to build."
	end
	if refusal then
		ply:ChatPrint(PREFIX .. refusal)
		return false
	end
	return self[method](self, ply, ...)
end

-- Where a helper goes that says nothing of its own (Prepare): on the ground it
-- was clicked, facing as the player does. Prepare answers its place, or nil and
-- what the click answers.
local function OnTheGround(ply, trace)
	return trace.HitPos + Vector(0, 0, Z_LIFT), Angle(0, ply:EyeAngles().y, 0)
end

-- A click on a placed helper of the kind places nothing: a second soon after
-- gives it the tool's current settings. Any other click makes one.
function Controller:Place(ply, trace, kind, values)
	local hit = self:PieceOf(trace, kind)
	if hit then
		local last = self.clicks[ply]
		if values and last and last.piece == hit and Model.IsDoubleClick(last.at, CurTime()) then
			self.clicks[ply] = nil
			hit:Update(values)
			ply:ChatPrint(PREFIX .. "Updated.")
		else
			self.clicks[ply] = { piece = hit, at = CurTime() }
		end
		return true
	end
	local pos, ang, box, answer = (Class(kind).Prepare or OnTheGround)(ply, trace)
	if not pos then return answer end
	local ent = self:Create(ply, kind, pos, ang, box, values)
	local extra = ent:OnPlaced(ply)
	return self:Undoable(ply, ent:UndoLabel(), ent, extra)
end

-- A tool's own action, its class's.
function Controller:Act(ply, kind, action, ...)
	return Class(kind)[action](ply, ...)
end

function Controller:RemoveAt(ply, trace)
	local piece = self:PieceOf(trace)
	if not piece then return false end
	piece:Remove()
	timer.Simple(0, Class(Model.NODE).Link)
	return true
end

-- The game's entities -------------------------------------------------------------------

function Controller:Clear()
	for _, ent in pairs(self.compiled) do
		if IsValid(ent) then ent:Remove() end
	end
	self.compiled = {}
end

-- An engine class keeps no keyvalue Lua can read, and a Lua SetKeyValue does
-- not reach EntityKeyValue, so its keyvalues are recorded here as a map's are.
local function SetKeys(ent, spec)
	local engine = not scripted_ents.GetStored(spec.class)
	for key, value in pairs(spec.keys) do
		ent:SetKeyValue(key, value)
		if engine then WS.MapIO:RecordKeyValue(ent, key, value) end
	end
	for _, output in ipairs(spec.outputs or {}) do ent:SetKeyValue(output.key, output.value) end
end

-- DoNotDuplicate: a save holds the helpers, which make these again.
local function Make(spec)
	local ent = ents.Create(spec.class)
	ent.DoNotDuplicate = true
	ent:SetName(spec.name)
	if spec.model then ent:SetModel(spec.model) end
	if spec.pos then ent:SetPos(spec.pos) end
	if spec.ang then ent:SetAngles(spec.ang) end
	SetKeys(ent, spec)
	return ent
end

-- A team with spawners placed spawns at them, not at the spawn bases the AI
-- war generates for a map without any, which a cleanup may have made again.
local function RetireGeneratedSpawns(self)
	local placed, own = {}, {}
	for _, spawner in ipairs(ents.FindByClass(Model.CLASSES[Model.SPAWN])) do placed[spawner:GetTeamNum()] = true end
	for _, ent in pairs(self.compiled) do own[ent] = true end
	for _, spawn in ipairs(ents.FindByClass("info_player_teamspawn")) do
		if not own[spawn] and not spawn:CreatedByMap() and placed[WS.SpawnState(spawn).team] then spawn:Remove() end
	end
end

-- Every entity made before any spawns, and all spawned before any activates:
-- a path_track links to its next node as it activates, and a train finds
-- its first as it does.
function Controller:Build()
	self:Clear()
	local compiled = Model.Compile(self:PieceEnts())
	local made = {}
	for i, spec in ipairs(compiled.specs) do
		made[i] = Make(spec)
		self.compiled[spec.name] = made[i]
	end
	for _, ent in ipairs(made) do ent:Spawn() end
	for i, spec in ipairs(compiled.specs) do
		local ent = made[i]
		if spec.mins then ent:SetCollisionBounds(spec.mins, spec.maxs) end
		if spec.hidden then ent:SetNoDraw(true) end
		if spec.parent then ent:SetParent(self.compiled[spec.parent]) end
		if spec.onParent then
			ent:SetLocalPos(vector_origin)
			ent:SetLocalAngles(angle_zero)
		end
		ent:Activate()
	end
	RetireGeneratedSpawns(self)
	for _, spec in ipairs(compiled.specs) do
		if spec.class == "team_control_point_master" then
			self.rounds:SetMode(ControlPoints.Mode)
			self.hadPoints = true
			WS.Feature("capture"):Rebuild()
		end
	end
	for _, input in ipairs(compiled.rules) do WS.Rules:Fire(input.input, input.param) end
	for _, problem in ipairs(compiled.problems) do PrintMessage(HUD_PRINTTALK, PREFIX .. problem) end
end

local function SetPlaying(self, on)
	self.running = on
	for _, ent in ipairs(self:PieceEnts()) do ent:SetInGame(on) end
end

-- Once a game: a Remove takes effect at the frame's end, so a second build in
-- this frame would find the first's points beside its own, and name them.
local function Start()
	if Controller.running then return end
	SetPlaying(Controller, true)
	Controller:Build()
end

-- As a countdown opens, so it tells the game the layout makes; and as a game
-- begins, for one whose countdown had none.
hook.Add("WSGameStarting", HOOK, Start)
hook.Add("MatchStart", HOOK, Start)

hook.Add("WSGameStopped", HOOK, function()
	SetPlaying(Controller, false)
	Controller:Clear()
	if not Controller.hadPoints then return end
	Controller.hadPoints = false
	-- the points are gone next frame, and the capture set with them
	timer.Simple(0, function() WS.Feature("capture"):Rebuild() end)
end)

hook.Add("PostCleanupMap", HOOK, function()
	if Controller.running then Controller:Build() end
end)

-- Saves and dupes -----------------------------------------------------------------------

-- Helpers arrive one by one: once the paste is over, the track is linked again,
-- and a running game takes them in (a Clear's removal needs its frame's end).
local function AfterPaste(self)
	timer.Create(PASTED_TIMER, 0, 1, function()
		Class(Model.NODE).Link()
		if not self.running then return end
		for _, ent in ipairs(self:PieceEnts()) do ent:SetInGame(true) end
		self:Clear()
		timer.Simple(0, function() self:Build() end)
	end)
end

-- A class's paste: on a scenario's map a save's helpers are no game of its own.
function Controller:Paste(ply, data)
	if not GetGlobal2Bool("ws_builder_available", false) then return end
	local ent = ents.Create(data.Class)
	duplicator.DoGeneric(ent, data)
	ent:Spawn()
	ent:Activate()
	duplicator.DoGenericPhysics(ent, ply, data)
	return ent
end

-- A helper pasted, its saved properties restored: it keeps its id unless another
-- has it, as the order of a track and of points is by id.
function Controller:Adopt(piece)
	local taken = {}
	for _, other in ipairs(self:PieceEnts()) do
		if other ~= piece then taken[other:Id()] = true end
	end
	local id = Model.PastedId(piece:Id(), taken, self.nextId)
	piece:SetPieceId(id)
	self.nextId = math.max(self.nextId, id + 1)
	AfterPaste(self)
end

return Controller
