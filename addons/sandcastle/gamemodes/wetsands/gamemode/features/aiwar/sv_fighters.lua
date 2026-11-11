-- Part of the AI war controller (sv.lua): who a bot's look is shown (sv_bots.lua's LookAround). The
-- live fighters of each game team: players (bots included), the war's NPC soldiers, the map's
-- buildings and monsters, and those a mode adds. Players and soldiers are read at every asking; the
-- buildings and monsters take a walk of every entity, kept a while (features.aiwar.looks' Roster),
-- each of them still checked alive at every asking.
local Controller, Map = ...
local Looks = WS.require ("features.aiwar.looks")
local RED, BLUE = Map.RED, Map.BLUE

-- How long what the walk found is kept: a look's interval, so a new building is seen no later
-- than a bot's next look would have seen it.
local STANDING_TERM = 0.2

local function IsGM13Entity (ent)
	local class = ent:GetClass ()
	return string.sub (class, 1, 5) == "gm13_" or string.sub (class, 1, 4) == "sev_"
end

-- The map's buildings and monsters, whoever they fight for and alive or not.
local function Standing ()
	local found = {}
	for _, ent in ents.Iterator () do
		if IsValid (ent) and (ent.GetObjTeam or ent:IsNPC () or ent:IsNextBot () or IsGM13Entity (ent)) then
			found [#found + 1] = ent
		end
	end
	return found
end

local standing = Looks.Roster (STANDING_TERM)

-- The live fighters of each game team, players (bots included), the war's
-- NPC soldiers, its buildings, and those a hook WSWarFighters(fighters) adds.
function Controller:Fighters (now)
	local fighters = { [RED] = {}, [BLUE] = {} }
	for _, ply in ipairs (player.GetAll ()) do
		local list = fighters [WS.TeamOf (ply)]
		if list and ply:Alive () then list [#list + 1] = ply end
	end
	for ent, entry in pairs (self.soldiers) do
		local list = fighters [entry.soldier.team]
		if list and IsValid (ent) and not ent:IsPlayer () and ent:Health () > 0 then list [#list + 1] = ent end
	end
	local function Fights (ent) return IsValid (ent) and not self.soldiers [ent] and ent:Health () > 0 end
	for _, ent in ipairs (standing:Of (now, Standing, Fights)) do
		if ent.GetObjTeam then
			-- a building (base_obj) fights for its team, an enemy the other's soldiers target
			local list = fighters [ent:GetObjTeam ()]
			if list then list [#list + 1] = ent end
		else
			fighters [RED] [#fighters [RED] + 1] = ent
			fighters [BLUE] [#fighters [BLUE] + 1] = ent
		end
	end
	-- others a mode makes fight for a side (an armed hostage: features.hostage)
	hook.Run ("WSWarFighters", fighters)
	return fighters
end
