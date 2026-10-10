-- func_croc (CFuncCroc): a trigger bound to a foundation.hazards.croc model
-- through the hazards controller. Keyvalues TeamNum, StartDisabled,
-- filtername and croc_model; inputs Enable, Disable and Toggle (the
-- trigger's; Kill and AddOutput are the engine's); outputs OnEat, OnEatRed
-- and OnEatBlue. Living players who pass the filter are its touches
-- (SF_TRIGGER_ALLOW_CLIENTS). CFuncCroc's ShouldCollide, which only matters
-- for a croc with a team, is left out: pl_terror_event's has none.
ENT.Type = "brush"
ENT.Base = "ws_trigger_volume"

local VARIANT = "foundation.hazards.croc"
local CONTENT_PATH = "GAME"

-- GetCrocModel: croc_model only when the file exists.
local function CrocModel(name, default)
	if name and file.Exists(name, CONTENT_PATH) then return name end
	return default
end

function ENT:TriggerInit()
	local model = CrocModel(self:Key("croc_model"), WS.require(VARIANT).MODEL)
	util.PrecacheModel(model)
	self.hazards = WS.Feature("hazards")
	self.hazards:Bind(self, VARIANT, {
		team = self.team,
		model = model,
	})
end

function ENT:OnRemove()
	self.hazards:Unbind(self)
end

function ENT:PlayerStartTouch(ply)
	if not self:PassesTriggerFilters(ply) then return end
	self.hazards:Touched(self, ply)
end

function ENT:PlayerEndTouch(ply)
	self.hazards:Left(self, ply)
end

function ENT:TriggerThink()
	self.hazards:Think(self)
end
