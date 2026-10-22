-- The kill feed, in TF2's look (WS.UI's theme), in place of GMod's death
-- notices: top right, newest at the bottom, each kill a box holding its
-- killer and victim in their teams' colours (foundation.kill_feed: the AI
-- war's soldiers in their sides') either side of TF2's kill icon for what
-- made it (foundation.kill_icons, from TF2's own scripts/mod_textures.txt and
-- Sandcastle's own in its look, ws/kill_icons_sheet.lua).
-- A kill the player took part in is a light tan box with the dark icon, as
-- TF2 marks its own; a death with no killer shows the victim and the icon
-- alone. Each shows for LIFETIME seconds (hud_deathnotice_time).
local Feed = WS.require("foundation.kill_feed")
local AiWar = WS.require("foundation.aiwar")
local Icons = WS.require("foundation.kill_icons")
local THEME = WS.UI.THEME

-- The soldiers' entities register after the gamemode, so their names are
-- read once every entity has.
hook.Add("InitPostEntity", "ws_kill_feed_names", function()
	for class in pairs(Feed.SOLDIERS) do
		local stored = scripted_ents.GetStored(class)
		if stored then language.Add(class, stored.t.PrintName) end
	end
end)

local ICONS = Icons.Over(Icons.Parse(file.Read("scripts/mod_textures.txt", "tf")),
	Icons.Parse(WS.require("ws.kill_icons_sheet").TEXT))

local LIFETIME, MOST = 6, 6
-- TF2's 480-tall units: a row, the gap under it, its icon, its padding and
-- how far in from the screen's top right corner the feed starts.
local ROW_TALL, ROW_GAP, ICON_TALL, PAD, EDGE = 16, 2, 12, 5, 8
local NAME_FONT = "WS.KillFeed.Name"
local NAME_TALL = 9
local NEUTRAL = Color(200, 190, 170)

local notices = {}
local sheets = {} -- sheet path -> { material, w, h }

local fontFor

local function Font(unit)
	if fontFor == unit then return end
	surface.CreateFont(NAME_FONT, { font = "TF2 Build", size = math.Round(NAME_TALL * unit), weight = 500 })
	fontFor = unit
end

local function Sheet(path)
	if not sheets[path] then
		local material = Material(path, "smooth") -- filters a PNG sheet; a VMT keeps its own
		local texture = material:GetTexture("$basetexture")
		sheets[path] = { material = material, w = texture:Width(), h = texture:Height() }
	end
	return sheets[path]
end

-- A name as GMod's notices give it: "#<class>" for an NPC, its display name.
local function Name(name)
	if name == nil or name == "" then return nil end
	if string.sub(name, 1, 1) == "#" then return language.GetPhrase(string.sub(name, 2)) end
	return name
end

-- A killer's class, from an NPC's "#<class>"; nil for a player's name.
local function Class(name)
	if name and string.sub(name, 1, 1) == "#" then return string.sub(name, 2) end
	return nil
end

-- Notices come as soon as the client can read them, before its own player
-- exists (LocalPlayer is NULL while it loads).
function GM:AddDeathNotice(attacker, attackerTeam, inflictor, victim, victimTeam)
	local ply = LocalPlayer()
	local me = IsValid(ply) and ply:Nick() or nil
	local killer = Name(attacker)
	if killer == Name(victim) then killer = nil end
	local sides = AiWar.Sides(GetGlobal2Int(AiWar.SIDES_KEY, AiWar.FACTIONS[AiWar.COMBINE].home))
	notices[#notices + 1] = {
		at = CurTime(),
		killer = killer,
		killerTeam = Feed.Team(attacker, attackerTeam, sides),
		victim = Name(victim),
		victimTeam = Feed.Team(victim, victimTeam, sides),
		icon = Icons.For(ICONS, inflictor, Class(attacker)),
		mine = Feed.Mine(me, attacker, victim),
	}
	while #notices > MOST do table.remove(notices, 1) end
end

local function NameColor(t, mine)
	if mine then return THEME.background end
	return WS.TeamColor[t] or NEUTRAL
end

function GM:DrawDeathNotice()
	local now = CurTime()
	for i = #notices, 1, -1 do
		if now - notices[i].at >= LIFETIME then table.remove(notices, i) end
	end
	if #notices == 0 then return end
	local unit = ScrH() / 480
	Font(unit)
	local rowH, pad = ROW_TALL * unit, PAD * unit
	local right, y = ScrW() - EDGE * unit, EDGE * unit
	for _, n in ipairs(notices) do
		local sheet = Sheet(n.mine and n.icon.negative or n.icon.file)
		local iconH = ICON_TALL * unit
		local iconW = iconH * n.icon.w / n.icon.h
		surface.SetFont(NAME_FONT)
		local killerW = n.killer and surface.GetTextSize(n.killer) + pad or 0
		local victimW = surface.GetTextSize(n.victim or "")
		local w = pad + killerW + iconW + pad + victimW + pad
		local x = right - w
		draw.RoundedBox(THEME.corner, x, y, w, rowH, n.mine and THEME.text or THEME.background)
		local mid, cx = y + rowH / 2, x + pad
		if n.killer then
			draw.SimpleText(n.killer, NAME_FONT, cx, mid, NameColor(n.killerTeam, n.mine), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			cx = cx + killerW
		end
		local icon = n.icon
		surface.SetMaterial(sheet.material)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRectUV(cx, mid - iconH / 2, iconW, iconH, icon.x / sheet.w, icon.y / sheet.h,
			(icon.x + icon.w) / sheet.w, (icon.y + icon.h) / sheet.h)
		cx = cx + iconW + pad
		draw.SimpleText(n.victim or "", NAME_FONT, cx, mid, NameColor(n.victimTeam, n.mine), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		y = y + rowH + ROW_GAP * unit
	end
end
