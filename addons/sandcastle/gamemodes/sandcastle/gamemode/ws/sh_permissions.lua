-- Who may do what (foundation.permissions), on both realms: the client hides
-- what a player cannot do, the server refuses it. Each privilege is
-- registered with CAMI (ws/sh_cami.lua, or a newer copy an admin mod loaded),
-- so ULX, SAM or ServerGuard can give it to any rank; without an admin mod,
-- CAMI's fallback grants it by its default rank.
local Permissions = WS.require("foundation.permissions")
local PlayMode = WS.require("foundation.play_mode")

local TAMPERING = CreateConVar("mp_tampering_enabled", "1", { FCVAR_REPLICATED, FCVAR_NOTIFY, FCVAR_ARCHIVE },
	"0: only superadmins may tamper with live gameplay (move the payload, change the clock, respawns)", 0, 1)

for _, p in ipairs(Permissions.PRIVILEGES) do
	CAMI.RegisterPrivilege({
		Name = p.name,
		MinAccess = p.rank,
		Description = p.description,
	})
end

function WS.PlayMode()
	return PlayMode.Of({
		roundsActive = WS.Active(),
		gameplayStopped = WS.GameplayStopped(),
		aiwar = WS.AiWarActive(),
		arena = GetGlobal2Bool("ws_round_arena", false),
	})
end

-- Whether ply may use the privilege name (a Permissions constant): true, or
-- false and a Permissions.REASON_. The server console may do anything.
function WS.Can(ply, name)
	if not IsValid(ply) then return true end
	local function Holds(privilege) return (CAMI.PlayerHasAccess(ply, privilege)) end
	return Permissions.Allows(name, Holds, {
		mode = WS.PlayMode(),
		tamperingEnabled = TAMPERING:GetBool(),
	})
end
