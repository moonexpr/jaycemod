-- The observer's HUD: the killer during the death cameras, then who or what
-- is being watched and how, with the keys that change it. Also plays TF2's
-- freezecam sound so it ends as the camera locks on the killer. And the
-- NPC context menu's "Spectate NPC", for admins (ws_spectate_npc,
-- ws/sv_spectate.lua).
local Spec = WS.require("foundation.spectate")

surface.CreateFont("Sandcastle.Spectate.Title", { font = "Roboto", size = 26, weight = 800 })
surface.CreateFont("Sandcastle.Spectate.Hint", { font = "Roboto", size = 16, weight = 600 })

local MODE_NAMES = {
	[OBS_MODE_FIXED] = "Camera",
	[OBS_MODE_IN_EYE] = "First person",
	[OBS_MODE_CHASE] = "Third person",
	[OBS_MODE_ROAMING] = "Free look",
}

local function Name(ent)
	if ent:IsPlayer() then return ent:Nick() end
	if ent:GetClass() == "func_tracktrain" then return "the payload" end
	if ent:IsNPC() or ent:IsNextBot() then
		local stored = scripted_ents.Get(ent:GetClass())
		local name = stored and stored.PrintName or language.GetPhrase(ent:GetClass())
		return name .. " #" .. ent:EntIndex()
	end
	return language.GetPhrase(ent:GetClass())
end

local function TargetColor(ent)
	if ent:IsPlayer() then return team.GetColor(ent:Team()) end
	return color_white
end

local HINT_COLOR = Color(200, 200, 200)

local function Key(binding)
	return string.upper(input.LookupBinding(binding) or binding)
end

local function Line(text, font, color, w, y)
	draw.SimpleTextOutlined(text, font, w / 2, y, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
end

-- Below cl_hud's respawn countdown (0.7 h), above the cart bar (h - 120).
local function Draw(w, h)
	local ply = LocalPlayer()
	local mode = ply:GetObserverMode()
	if mode == OBS_MODE_NONE then return end
	local y = h * 0.78
	local target = ply:GetObserverTarget()
	local watching = IsValid(target) and target ~= ply
	if mode == OBS_MODE_DEATHCAM or mode == OBS_MODE_FREEZECAM then
		if watching then Line("Killed by " .. Name(target), "Sandcastle.Spectate.Title", TargetColor(target), w, y) end
		return
	end
	local label = MODE_NAMES[mode] or ""
	if watching and mode ~= OBS_MODE_ROAMING then
		Line("Spectating " .. Name(target) .. "  (" .. label .. ")", "Sandcastle.Spectate.Title", TargetColor(target), w, y)
	else
		Line(label, "Sandcastle.Spectate.Title", color_white, w, y)
	end
	local hint = string.format("%s / %s: change target    %s: camera mode", Key("+attack"), Key("+attack2"), Key("+jump"))
	Line(hint, "Sandcastle.Spectate.Hint", HINT_COLOR, w, y + 26)
end

WS.HUD:Add("player.spectate", WS.HUD_ORDER.NOTICES, Draw, WS.Active)

-- CTFPlayer::StateThinkDYING starts TFPlayer.FreezeCam so it ends at the
-- lock-on; the client sees the freezecam begin and plays it for itself.
local SOUND_DELAY = Spec.TIMES.freezeTravel - Spec.TIMES.freezeSoundLength
local lastMode = OBS_MODE_NONE
hook.Add("Think", "ws_spectate", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local mode = ply:GetObserverMode()
	if mode == OBS_MODE_FREEZECAM and lastMode ~= OBS_MODE_FREEZECAM then
		timer.Simple(SOUND_DELAY, function()
			if IsValid(ply) and ply:GetObserverMode() == OBS_MODE_FREEZECAM then ply:EmitSound("TFPlayer.FreezeCam") end
		end)
	end
	lastMode = mode
end)

-- Watching an NPC: the engine's observer camera sits at a non-player's
-- origin, its feet; ours follows its model (WS.NpcCamera,
-- ws/sh_spectate.lua): first person from its eyes, third person over
-- its shoulder.
local function WatchedNpc(ply)
	local mode = ply:GetObserverMode()
	if mode ~= OBS_MODE_IN_EYE and mode ~= OBS_MODE_CHASE then return nil, mode end
	local target = ply:GetObserverTarget()
	if IsValid(target) and (target:IsNPC() or target:IsNextBot()) then return target, mode end
	return nil, mode
end

hook.Add("CalcView", "ws_spectate_npc", function(ply, origin, angles, fov)
	local npc, mode = WatchedNpc(ply)
	if npc == nil then return end
	local camera, facing = WS.NpcCamera(npc, mode == OBS_MODE_IN_EYE, angles)
	return {
		origin = camera,
		angles = facing,
		fov = fov,
		drawviewer = false,
	}
end)

-- In first person the watched NPC (and what it holds) is hidden, and shown
-- again once the view moves on.
local hidden = nil

local function SetHidden(ent, hide)
	ent:SetNoDraw(hide)
	if ent.GetActiveWeapon then
		local weapon = ent:GetActiveWeapon()
		if IsValid(weapon) then weapon:SetNoDraw(hide) end
	end
end

hook.Add("Think", "ws_spectate_npc", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local npc, mode = WatchedNpc(ply)
	local now = mode == OBS_MODE_IN_EYE and npc or nil
	if now == hidden then return end
	if IsValid(hidden) then SetHidden(hidden, false) end
	if now then SetHidden(now, true) end
	hidden = now
end)

-- Hold C and right-click a living NPC: watch it (in play, reload comes back).
properties.Add("ws_spectate_npc", {
	MenuLabel = "Spectate NPC",
	MenuIcon = "icon16/eye.png",
	Order = 8998,
	Filter = function(self, ent, ply)
		return IsValid(ent) and (ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0 and IsValid(ply)
			and WS.Can(ply, WS.require("foundation.permissions").PLAYERS) == true
	end,
	Action = function(self, ent)
		RunConsoleCommand("ws_spectate_npc", tostring(ent:EntIndex()))
	end,
})
