-- Players move as TF2's players do while the TF2 layer runs (WS.Active),
-- and as GMod's in Sandbox mode (games.gameplay.movement): their hulls,
-- eyes, jump and step, and the server's movement convars. A body is put on
-- a player when it spawns (WS.ApplyMovement, GM:PlayerSpawn after the
-- player class's own), its hull again on either realm whenever the layer
-- has changed since (SetupMove: the client predicts with the server's hull),
-- and the convars kept to the layer's every CONVAR_CHECK seconds. A jump
-- attribute scales the jump power set here (features/attributes).
local Movement = gameplay.movement

local CONVAR_CHECK = 1

local function V(p) return Vector(p.x, p.y, p.z) end

local function ApplyHull(ply, body)
	ply:SetHull(V(body.hullMin), V(body.hullMax))
	ply:SetHullDuck(V(body.duckHullMin), V(body.duckHullMax))
	ply.wsMovementBody = body
end

hook.Add("SetupMove", "ws_movement", function(ply)
	local body = Movement.For(WS.Active())
	if ply.wsMovementBody ~= body then ApplyHull(ply, body) end
end)

if CLIENT then return end

function WS.ApplyMovement(ply)
	local body = Movement.For(WS.Active())
	ApplyHull(ply, body)
	ply:SetViewOffset(Vector(0, 0, body.view))
	ply:SetViewOffsetDucked(Vector(0, 0, body.duckView))
	ply:SetJumpPower(body.jumpSpeed)
	ply:SetStepSize(body.stepHeight)
end

timer.Create("ws_movement_convars", CONVAR_CHECK, 0, function()
	for name, value in pairs(Movement.For(WS.Active()).convars) do
		if GetConVarString(name) ~= value then RunConsoleCommand(name, value) end
	end
end)
