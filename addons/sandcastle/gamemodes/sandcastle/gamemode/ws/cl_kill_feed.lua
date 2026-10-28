-- The kill feed, in TF2's look (WS.UI's theme), in place of GMod's death
-- notices: top right, newest at the bottom, each kill a box holding its
-- killer and victim in their teams' colours (features.aiwar.kill_feed: the AI
-- war's soldiers in their sides') either side of TF2's kill icon for what
-- made it (games.gameplay.kill_icons, from TF2's own scripts/mod_textures.txt and
-- Sandcastle's own in its look, ws/kill_icons_sheet.lua).
-- A kill the player took part in is a light tan box with the dark icon, as
-- TF2 marks its own; a death with no killer shows the victim and the icon
-- alone. A control point's capture or defense is a row of its own, as in
-- TF2: who did it, the team's icon, "captured" or "defended" and the point
-- (WS.KillFeedObjective, from the capture view). A death to the world
-- credited to an enemy reads "finished off" under the skull, as TF2's
-- assisted suicide. An assisted kill names its assister beside the killer,
-- "killer + assister" (game_kill_assist). Each shows for LIFETIME
-- seconds (hud_deathnotice_time).
local Feed = WS.require("features.aiwar.kill_feed")
local AiWar = WS.require("features.aiwar.model")
local Icons = gameplay.kill_icons
local THEME = WS.UI.THEME
local E = WS.Events

-- Each kind of soldier's name, as its notices name it (Feed.Notice).
local Profiles = WS.require("features.aiwar.profiles")
for kind in pairs(Feed.SOLDIERS) do language.Add(kind, Profiles.PROFILES[kind].PrintName) end

local ICONS = Icons.Over(Icons.Parse(file.Read("scripts/mod_textures.txt", "tf")),
	Icons.Parse(WS.require("ws.kill_icons_sheet").TEXT))

local LIFETIME, MOST = 6, 6
-- TF2's 480-tall units: a row, the gap under it, its icon, its padding and
-- how far in from the screen's top right corner the feed starts.
local ROW_TALL, ROW_GAP, ICON_TALL, PAD, EDGE = 16, 2, 12, 5, 8
local NAME_FONT = "WS.KillFeed.Name"
local NAME_TALL = 9
local NEUTRAL = Color(200, 190, 170)
local ASSIST_JOIN = " + " -- CTFHudDeathNotice's "%s + %s"

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
local function Me()
	local ply = LocalPlayer()
	return IsValid(ply) and ply:Nick() or nil
end

local function Push(notice)
	notice.at = CurTime()
	notices[#notices + 1] = notice
	while #notices > MOST do table.remove(notices, 1) end
end

-- A credited death's icon; else the one the flags choose (an impact's),
-- else by what struck, or the boss who killed.
local function NoticeIcon(credited, flags, inflictor, attacker)
	if credited then return Icons.For(ICONS, credited.icon) end
	return Icons.For(ICONS, Feed.Icon(flags) or inflictor, Class(attacker))
end

function GM:AddDeathNotice(attacker, attackerTeam, inflictor, victim, victimTeam, flags)
	local me = Me()
	local killer = Name(attacker)
	if killer == Name(victim) then killer = nil end
	local sides = AiWar.Sides(GetGlobal2Int(AiWar.SIDES_KEY, AiWar.FACTIONS[AiWar.COMBINE].home))
	-- a death to the world credited to an enemy (ws/sv_kill_credit.lua)
	local credited = Feed.Credited(flags or 0)
	Push({
		killer = killer,
		killerTeam = Feed.Team(attacker, attackerTeam, sides),
		victim = Name(victim),
		victimTeam = Feed.Team(victim, victimTeam, sides),
		icon = NoticeIcon(credited, flags or 0, inflictor, attacker),
		info = credited and credited.info or nil,
		mine = Feed.Mine(me, attacker, victim),
	})
end

-- The assister of the kill just told: it follows its death notice, so it
-- joins the newest row when that row is its victim's.
E.Listen("game_kill_assist", "ws_kill_feed", function(fields)
	local row = notices[#notices]
	if row == nil or row.victim ~= Name(fields.victim) then return end
	local sides = AiWar.Sides(GetGlobal2Int(AiWar.SIDES_KEY, AiWar.FACTIONS[AiWar.COMBINE].home))
	Feed.WithAssister(row, Name(fields.assister), Feed.Team(fields.assister, fields.team, sides), Me())
end)

-- A point captured or defended (features.aiwar.kill_feed's Objective): kind,
-- the team, names who did it as death notices name them, point its name.
function WS.KillFeedObjective(kind, team, names, point)
	local shown = {}
	for i, name in ipairs(names) do shown[i] = Name(name) end
	local row = Feed.Objective(kind, team, shown, WS.TeamName[team], point, Me())
	row.icon = Icons.For(ICONS, row.icon)
	Push(row)
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
		local joinW = n.assister and surface.GetTextSize(ASSIST_JOIN) or 0
		local assisterW = n.assister and surface.GetTextSize(n.assister) or 0
		local infoW = n.info and surface.GetTextSize(n.info) + pad or 0
		local victimW = surface.GetTextSize(n.victim or "")
		local w = pad + killerW + joinW + assisterW + iconW + pad + infoW + victimW + pad
		local x = right - w
		draw.RoundedBox(THEME.corner, x, y, w, rowH, n.mine and THEME.text or THEME.background)
		local mid, cx = y + rowH / 2, x + pad
		if n.killer then
			draw.SimpleText(n.killer, NAME_FONT, cx, mid, NameColor(n.killerTeam, n.mine), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			cx = cx + killerW
		end
		if n.assister then
			-- the killer's padding falls after the assister
			cx = cx - pad
			draw.SimpleText(ASSIST_JOIN, NAME_FONT, cx, mid, NameColor(nil, n.mine), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			cx = cx + joinW
			draw.SimpleText(n.assister, NAME_FONT, cx, mid, NameColor(n.assisterTeam, n.mine), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			cx = cx + assisterW + pad
		end
		local icon = n.icon
		surface.SetMaterial(sheet.material)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRectUV(cx, mid - iconH / 2, iconW, iconH, icon.x / sheet.w, icon.y / sheet.h,
			(icon.x + icon.w) / sheet.w, (icon.y + icon.h) / sheet.h)
		cx = cx + iconW + pad
		if n.info then
			draw.SimpleText(n.info, NAME_FONT, cx, mid, NameColor(nil, n.mine), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			cx = cx + infoW
		end
		draw.SimpleText(n.victim or "", NAME_FONT, cx, mid, NameColor(n.victimTeam, n.mine), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		y = y + rowH + ROW_GAP * unit
	end
end
