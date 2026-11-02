DEFINE_BASECLASS( "player_sandbox" )
local PLAYER = {}

function PLAYER:Loadout()
	self.Player:StripWeapons()
	self.Player:RemoveAllAmmo()
end

function PLAYER:EnterObserver(mode)
	self.Player:StripWeapons()
	self.Player:Spectate(mode)
end

function PLAYER:PlayerSpawnAsSpectator()
	local ply = self.Player
	ply:StripWeapons()
	if ply:Team() == TEAM_UNASSIGNED then
		ply:Spectate(OBS_MODE_FIXED)
		return
	end
	ply:SetTeam(TEAM_SPECTATOR)
	ply:Spectate(OBS_MODE_ROAMING)
end

function PLAYER:DoPlayerDeath(dmg)
	dmg:SetDamageType(bit.bor(dmg:GetDamageType(), DMG_REMOVENORAGDOLL))
end

WS.Spectator = {
	SelectSpawnClass = function(ply, teamPlay, sandboxMode)
		local observing = teamPlay and (ply.wsTeam == WS.TEAM_UNASSIGNED
			or ply:Team() == WS.TEAM_UNASSIGNED or ply:Team() == WS.TEAM_SPECTATOR)
		local class = sandboxMode and "player_sandcastle"
			or observing and "player_spectator"
			or "player_combatant"
		player_manager.SetPlayerClass(ply, class)
		return observing
	end,
	SpawnAsSpectator = function(ply)
		PLAYER.PlayerSpawnAsSpectator({ Player = ply })
	end,
	Enter = function(ply, team)
		player_manager.SetPlayerClass(ply, "player_spectator")
		local mode = team == WS.TEAM_SPECTATOR and OBS_MODE_ROAMING or OBS_MODE_FIXED
		player_manager.RunClass(ply, "EnterObserver", mode)
	end,
	DoPlayerDeath = function(ply, dmg)
		player_manager.SetPlayerClass(ply, "player_spectator")
		player_manager.RunClass(ply, "DoPlayerDeath", dmg)
	end,
}

player_manager.RegisterClass( "player_spectator", PLAYER, "player_sandbox" )
