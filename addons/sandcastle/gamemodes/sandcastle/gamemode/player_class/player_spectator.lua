DEFINE_BASECLASS( "player_sandbox" )
local PLAYER = {}

function PLAYER:Loadout()
	self.Player:StripWeapons()
	self.Player:RemoveAllAmmo()
end

function PLAYER:EnterObserver(mode)
	local ply = self.Player
	ply:StripWeapons()
	ply:AddFlags(FL_NOTARGET)
	ply:Spectate(mode)
end

function PLAYER:Observe(target)
	local ply = self.Player
	ply:AddFlags(FL_NOTARGET)
	ply.wsSpectatorNoTarget = true
	if IsValid(target) and target:IsPlayer() then
		local mode = ply:GetObserverMode()
		if mode ~= OBS_MODE_IN_EYE and mode ~= OBS_MODE_CHASE then mode = OBS_MODE_CHASE end
		ply:Spectate(mode)
		ply:SpectateEntity(target)
		return
	end

	if IsValid(target) then
		ply:Spectate(OBS_MODE_FIXED)
		ply:SpectateEntity(target)
		ply:SetPos(target:GetPos())
		ply:SetEyeAngles(target:GetAngles())
		ply:SetFOV(target.FOV and target:FOV() or 0, 0)
		return
	end

	ply:Spectate(OBS_MODE_FIXED)
	ply:SpectateEntity(NULL)
end

function PLAYER:PlayerSpawnAsSpectator()
	local ply = self.Player
	ply:StripWeapons()
	ply:AddFlags(FL_NOTARGET)
	ply.wsSpectatorNoTarget = true
	if ply:Team() == TEAM_UNASSIGNED then
		ply:Spectate(OBS_MODE_FIXED)
		return
	end
	ply:SetTeam(TEAM_SPECTATOR)
	ply:Spectate(OBS_MODE_ROAMING)
end

WS.Spectator = {
	PrepareSpawn = function(ply)
		if ply.wsSpectatorNoTarget then
			ply:RemoveFlags(FL_NOTARGET)
			ply.wsSpectatorNoTarget = nil
		end
	end,
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
		ply:AddFlags(FL_NOTARGET)
		ply.wsSpectatorNoTarget = true
		local mode = team == WS.TEAM_SPECTATOR and OBS_MODE_ROAMING or OBS_MODE_FIXED
		player_manager.RunClass(ply, "EnterObserver", mode)
	end,
	Observe = function(ply, target) player_manager.RunClass(ply, "Observe", target) end,
	AfterPlayerDeath = function(ply)
		if ply.wsChangingTeam then return end
		timer.Simple(0, function()
			if not IsValid(ply) or ply:Alive() then return end
			player_manager.SetPlayerClass(ply, "player_spectator")
			ply:AddFlags(FL_NOTARGET)
			ply.wsSpectatorNoTarget = true

			if not WS.TeamPlay() or ply:Team() == WS.TEAM_SPECTATOR
				or ply:Team() == WS.TEAM_UNASSIGNED then
				return
			end
			local targets = WS.Spectator.Targets(ply)
			local target
			for _, candidate in ipairs(targets) do
				if candidate:IsPlayer() then
					target = candidate
					break
				end
			end
			WS.Spectator.Observe(ply, target or targets[1])
		end)
	end,
}

player_manager.RegisterClass( "player_spectator", PLAYER, "player_sandbox" )

if SERVER then
	local function IsSpectating(ply)
		return IsValid(ply) and player_manager.GetPlayerClass(ply) == "player_spectator"
			and ply:GetObserverMode() ~= OBS_MODE_NONE
	end

	function WS.Spectator.CanUsePoint(ply, point)
		if not point:IsEnabled() then return false end
		if ply:Team() == WS.TEAM_SPECTATOR then return true end

		local pointTeam = point:TeamNum()
		if pointTeam ~= WS.TEAM_UNASSIGNED and pointTeam ~= ply:Team() then return false end
		local associated = point:AssociatedEntity()
		if not IsValid(associated) or associated:GetClass() ~= "team_control_point"
			or not WS.FeatureLoaded("capture") then
			return true
		end
		return WS.Feature("capture"):Owner(associated) == ply:Team()
	end

	function WS.Spectator.Targets(ply)
		local targets = {}
		for _, point in ipairs(ents.FindByClass("info_observer_point")) do
			if IsValid(point) and WS.Spectator.CanUsePoint(ply, point) then targets[#targets + 1] = point end
		end

		local players = player.GetAll()
		table.sort(players, function(a, b) return a:EntIndex() < b:EntIndex() end)
		for _, other in ipairs(players) do
			if other ~= ply and other:Alive()
				and (ply:Team() == WS.TEAM_SPECTATOR or other:Team() == ply:Team()) then
				targets[#targets + 1] = other
			end
		end
		return targets
	end

	function WS.Spectator.CycleTarget(ply, reverse)
		if not IsSpectating(ply) then return end
		local targets = WS.Spectator.Targets(ply)
		if #targets == 0 then return end

		local current = ply:GetObserverTarget()
		local index = 0
		for i, target in ipairs(targets) do
			if target == current then
				index = i
				break
			end
		end
		local step = reverse and -1 or 1
		local nextIndex = index + step
		if nextIndex < 1 then nextIndex = #targets end
		if nextIndex > #targets then nextIndex = 1 end
		WS.Spectator.Observe(ply, targets[nextIndex])
		return targets[nextIndex]
	end

	hook.Add("KeyPress", "player_spectator", function(ply, key)
		if key ~= IN_ATTACK and key ~= IN_ATTACK2 then return end
		WS.Spectator.CycleTarget(ply, key == IN_ATTACK2)
	end)

	hook.Add("PlayerUse", "player_spectator", function(ply)
		if IsSpectating(ply) then return false end
	end)

	hook.Add("Think", "player_spectator_point_camera", function()
		for _, ply in ipairs(player.GetAll()) do
			if IsSpectating(ply) and ply:GetObserverMode() == OBS_MODE_FIXED then
				local point = ply:GetObserverTarget()
				if IsValid(point) and point:GetClass() == "info_observer_point" then
					ply:SetPos(point:GetPos())
					ply:SetEyeAngles(point:GetAngles())
				end
			end
		end
	end)
end
