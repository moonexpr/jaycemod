-- Part of the capture controller (sv.lua): its state as plain data and
-- back, for the dev workbench's capture and restore: the point set (owners,
-- locks, unlock times), the master's mini-round, each capture area's
-- progress and switches, the tf_logic_cp_timers and what the HUD hides.
-- Entities go through refs (Encode(ent) -> key, Decode(key) -> the entity
-- or nil); an area or timer whose key no longer resolves is reported
-- missing, not restored.
local Controller, Points = ...
local Area = WS.require("games.gameplay.capture.area")

local function Keyed(refs, map, value)
	local out = {}
	for ent, item in pairs(map) do
		if IsValid(ent) then out[refs:Encode(ent)] = value(item, ent) end
	end
	return out
end

-- fn(ent, data) for each key that resolves; fn returns false when the
-- entity is not the controller's. Either way the key is reported missing.
local function Each(refs, map, missing, fn)
	for key, data in pairs(map) do
		local ent = refs:Decode(key)
		if not (IsValid(ent) and fn(ent, data) ~= false) then missing[#missing + 1] = key end
	end
end

function Controller:Snapshot(now, refs)
	return {
		set = self.set and self.set:Snapshot(now, refs) or nil,
		master = self.master and self.master:Snapshot(now, refs) or nil,
		areas = Keyed(refs, self.areas, function(area)
			return {
				enabled = area.enabled,
				pointName = area.pointName,
				canCap = table.Copy(area.canCap),
				state = Area.Snapshot(area.state, now, refs),
			}
		end),
		cpTimers = Keyed(refs, self.cpTimers, function(timer) return timer.model:Snapshot(now) end),
		pointTimers = Keyed(refs, self.pointTimers, function(endTime) return endTime - now end),
		hudHidden = Keyed(refs, self.hudHidden, function(hidden) return hidden end),
	}
end

-- The state put back in place; returns { missing = { keys } }.
function Controller:Restore(snapshot, now, refs)
	local missing = {}
	if snapshot.set then self:Set():Restore(snapshot.set, now, refs) end
	if snapshot.master and self.master then self.master:Restore(snapshot.master, now, refs) end
	Each(refs, snapshot.areas, missing, function(ent, data)
		local area = self.areas[ent]
		if not area then return false end
		area.enabled, area.pointName, area.canCap = data.enabled, data.pointName, table.Copy(data.canCap)
		Area.Restore(area.state, data.state, now, refs)
	end)
	Each(refs, snapshot.cpTimers, missing, function(ent, data)
		if not self.cpTimers[ent] then return false end
		self.cpTimers[ent].model:Restore(data, now)
	end)
	self.pointTimers = {}
	Each(refs, snapshot.pointTimers, missing, function(ent, left) self.pointTimers[ent] = now + left end)
	self.hudHidden = {}
	Each(refs, snapshot.hudHidden, missing, function(ent, hidden) self.hudHidden[ent] = hidden end)
	if self.set then
		for _, point in ipairs(self.set:Ids()) do
			if IsValid(point) then Points.ApplyPointModel(self, point) end
		end
	end
	Points.PublishStage(self)
	self.nextPublish = 0
	return { missing = missing }
end
