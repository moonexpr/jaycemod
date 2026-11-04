-- The gamemode as the host of NextSoldier's soldiers: all a soldier needs of
-- it, handed over here and nowhere else (nextsoldier.host's port).
local Factions = WS.require("includes.factions")
local Movement = gameplay.movement

-- HL2's two sides, hostile on sight.
local ENEMY_FACTION = {
	[Factions.HL2_COMBINE] = Factions.HL2_REBELS,
	[Factions.HL2_REBELS] = Factions.HL2_COMBINE,
}

local Host = {}

-- A TF2 player's: a stair step, and a crouch jump's reach.
function Host:Movement()
	return Movement.TF2.stepHeight, Movement.CrouchJump(Movement.TF2)
end

-- A player's faction is its team's.
function Host:PlayerFactions(ply)
	local faction = Factions.Of(WS.TeamOf(ply))
	return faction and { faction } or {}
end

function Host:FactionEnemy(faction) return ENEMY_FACTION[faction] end

function Host:PathClearance(bot) return WS.NavHullClearance(bot, WS.ClipMasks().brushes) end

function Host:PathDebug() return WS.require("features.nbdebug.model") end

function Host:GazeUpdate(...) return WS.GazeUpdate(...) end

function Host:SolidMask() return WS.ClipMasks().solid end

nextsoldier.host.Install(Host)
