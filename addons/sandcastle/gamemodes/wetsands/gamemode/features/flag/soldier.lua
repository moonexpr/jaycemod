-- What a soldier's behaviours ask of the flags (nextsoldier.behavior.ctfbot), for any
-- body: Apply(class) gives a class HasTheFlag and the rest, on its FlagCarrier(), the
-- entity that carries.
local FlagModel = WS.require("features.flag.model")
local WS, ents, ipairs = WS, ents, ipairs
module(...)

-- The flag it may carry: its entity, and its model.
local function FlagOf(self)
	local team = WS.TeamNumber(self:FlagCarrier())
	for _, ent in ipairs(ents.FindByClass("item_teamflag")) do
		local model = ent.flag:FlagAt(ent)
		if model:Enabled() and FlagModel.MayCarry(model:Team(), team, ent.flag:Rules().ownersCarry) then return ent, model end
	end
	return nil
end

function Apply(class)
	function class:HasTheFlag()
		local _, model = FlagOf(self)
		return model ~= nil and model:Carrier() == self:FlagCarrier()
	end

	function class:IsFlagHome()
		local _, model = FlagOf(self)
		return model ~= nil and model:State() == FlagModel.HOME
	end

	-- MvM's bomb, its team's own, goes to a robot as it spawns.
	function class:GetsFlagAsItSpawns()
		local ent = FlagOf(self)
		return ent ~= nil and ent.flag:Rules().ownersCarry == true
	end

	function class:PickUpFlag()
		local ent = FlagOf(self)
		return ent ~= nil and ent.flag:Give(ent, self:FlagCarrier())
	end

	-- Where to walk for it: nowhere when it is carried, or MvM's bomb is home.
	function class:FlagToFetch()
		local ent, model = FlagOf(self)
		if not model or model:State() == FlagModel.CARRIED then return nil end
		if model:State() == FlagModel.HOME and ent.flag:Rules().ownersCarry then return nil end
		return ent:GetPos()
	end

	function class:FlagCaptureZone()
		local team = WS.TeamNumber(self:FlagCarrier())
		for _, zone in ipairs(ents.FindByClass("func_capturezone")) do
			if FlagModel.MayCapture(zone.flag:ZoneTeam(zone), team) then return zone:LocalToWorld(zone:OBBCenter()) end
		end
		return nil
	end
end
