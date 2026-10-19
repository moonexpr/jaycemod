-- The nav mesh progress box on each client (ws/sh_nav_progress.lua
-- defines its event, the server's progress alone). Everything else is this
-- client's, timed by its own RealTime from when its box first showed (never
-- the server's clock, which stalls while the mesh generates): the time
-- taken, the music, the lingering once done. In the middle of the screen
-- in TF2's look: a dark
-- brown rounded panel, the title in TF2 Build, the stage after TF2's HUD
-- stopwatch and in TF2 Secondary, both in TF2's light tan, the player's
-- instructions smaller in the darker tan, over a tan bar on a darker track,
-- to the engine's progress through its step, full when done and a moving
-- band otherwise while the work runs. While it shows, the engine's own
-- progress box (CNavProgress, the viewport panel named nav_progress,
-- uncentred) is hidden wherever it is found, and its step (its TextLabel)
-- and progress (its ProgressBar's width of its ProgressBarSizer's) are
-- read from it. MvM's upgrade station music plays meanwhile at
-- foundation.nav_progress's volume on a BASS channel looping it (the file
-- has no loop of its own, and a sound patch restarted at its end did not
-- play again in game), and fades out once done.
local P = WS.require("foundation.nav_progress")
local E = WS.Events

-- TF2's 480-tall units; its scheme's colours, WS.UI's theme.
local WIDE, TALL, BAR_TALL, PAD, CORNER = 360, 104, 10, 10, 6
local TITLE_TALL, BODY_TALL, NOTE_TALL, GAP = 14, 10, 9, 6
local THEME = WS.UI.THEME
local DARK_BROWN, TRACK, TAN_LIGHT, TAN_DARK = THEME.background, THEME.track, THEME.text, THEME.edge
local TITLE_FONT, BODY_FONT, NOTE_FONT = "WS.NavProgress.Title", "WS.NavProgress.Body", "WS.NavProgress.Note"
local BAND, BAND_SPEED = 0.25, 0.6
-- TF2's HUD stopwatch (tan, tinted by the draw colour), before the stage.
local CLOCK = Material("hud/ico_time_none")

-- The engine's box (Source's PANEL_NAV_PROGRESS), by its panel name or class.
local ENGINE_BOX = { nav_progress = true, NavProgress = true, CNavProgress = true }
local HIDE_EVERY = 1
local MUSIC_FADE_OUT = 3

local fontsFor

local function Fonts(unit)
	if fontsFor == unit then return end
	surface.CreateFont(TITLE_FONT, { font = "TF2 Build", size = math.Round(TITLE_TALL * unit), weight = 500 })
	surface.CreateFont(BODY_FONT, { font = "TF2 Secondary", size = math.Round(BODY_TALL * unit), weight = 500 })
	surface.CreateFont(NOTE_FONT, { font = "TF2 Secondary", size = math.Round(NOTE_TALL * unit), weight = 500 })
	fontsFor = unit
end

-- Hides the engine's box among panel's descendants (not ours); answers it,
-- nil if it is not there.
local function HideEngineBox(panel, own)
	local found
	for _, child in ipairs(panel:GetChildren()) do
		if child ~= own and (ENGINE_BOX[child:GetName()] or ENGINE_BOX[child:GetClassName()]) then
			child:SetVisible(false)
			found = child
		end
		found = HideEngineBox(child, own) or found
	end
	return found
end

-- The engine box's child named name, nil if it has none.
local function Part(engine, name)
	for _, child in ipairs(engine:GetChildren()) do
		if child:GetName() == name then return child end
	end
end

-- The engine box's step ("" before it reports one) and the fraction of it
-- done (nil before it reports).
local function EngineStep(engine)
	if not IsValid(engine) then return "", nil end
	local text, bar, sizer = Part(engine, "TextLabel"), Part(engine, "ProgressBar"), Part(engine, "ProgressBarSizer")
	local fraction = bar and sizer and sizer:GetWide() > 0 and math.Clamp(bar:GetWide() / sizer:GetWide(), 0, 1) or nil
	return text and text:GetText() or "", fraction
end

WS.UI.Define("NavProgress", "DPanel", {
	Init = function(self)
		self:SetMouseInputEnabled(false)
		self:SetKeyboardInputEnabled(false)
		self.nextHide = 0
		self.step = ""
		self.shownAt = RealTime()
	end,
	-- The server's latest progress, now (RealTime); a run begun again
	-- after one done starts the clock and the music over.
	Show = function(self, fields, now)
		if self.doneAt and fields.stage ~= P.DONE then self.shownAt, self.doneAt = now, nil end
		self.fields = fields
		if fields.stage == P.DONE then self.doneAt = self.doneAt or now end
	end,
	Think = function(self)
		local f, now = self.fields, RealTime()
		if not P.Showing(f.stage, self.doneAt or now, now) then return self:Remove() end
		local unit = ScrH() / 480
		self:SetSize(WIDE * unit, TALL * unit)
		self:SetPos((ScrW() - WIDE * unit) / 2, (ScrH() - TALL * unit) / 2)
		if now >= self.nextHide then
			self.nextHide = now + HIDE_EVERY
			self.engine = HideEngineBox(vgui.GetWorldPanel(), self) or self.engine
		end
		self.step, self.stepFraction = EngineStep(self.engine)
		self:Music(P.MusicVolume(f.stage, now - self.shownAt))
	end,
	-- Plays the music looping at volume; at none, fades out what plays over
	-- MUSIC_FADE_OUT and stops it. A BASS channel, which loops by itself.
	Music = function(self, volume)
		if volume <= 0 then
			if not self.music then return end
			local left = self.music:GetVolume() - FrameTime() / MUSIC_FADE_OUT
			if left > 0 then return self.music:SetVolume(left) end
			return self:StopMusic()
		end
		if self.music then return self.music:SetVolume(volume) end
		if self.musicLoading then return end
		self.musicLoading = true
		sound.PlayFile("sound/" .. P.MUSIC, "noplay", function(channel, code, err)
			if not IsValid(channel) then error("nav progress music: " .. tostring(err)) end
			if not IsValid(self) then return channel:Stop() end
			channel:EnableLooping(true)
			channel:SetVolume(0)
			channel:Play()
			self.music, self.musicLoading = channel, false
		end)
	end,
	StopMusic = function(self)
		if not self.music then return end
		self.music:Stop()
		self.music = nil
	end,
	OnRemove = function(self) self:StopMusic() end,
	Paint = function(self, w, h)
		local f, now = self.fields, RealTime()
		local unit = h / TALL
		Fonts(unit)
		local pad, corner = PAD * unit, CORNER * unit
		draw.RoundedBox(corner, 0, 0, w, h, TAN_DARK)
		draw.RoundedBox(corner, unit, unit, w - 2 * unit, h - 2 * unit, DARK_BROWN)
		draw.SimpleText(string.upper(P.TITLE), TITLE_FONT, pad, pad, TAN_LIGHT)
		local y = pad + (TITLE_TALL + GAP) * unit
		local clock = (BODY_TALL + 2) * unit
		surface.SetMaterial(CLOCK)
		surface.SetDrawColor(TAN_LIGHT)
		surface.DrawTexturedRect(pad, y - unit, clock, clock)
		draw.SimpleText(P.Body(f.stage, (self.doneAt or now) - self.shownAt, f.areas, self.step), BODY_FONT, pad + clock + 3 * unit, y, TAN_LIGHT)
		-- the description, a step down in size and colour
		y = y + (BODY_TALL + GAP) * unit
		for i, line in ipairs(P.DESCRIPTION) do
			draw.SimpleText(line, NOTE_FONT, pad, y + (i - 1) * (NOTE_TALL + 2) * unit, TAN_DARK)
		end
		-- the bar: a darker track, tan to its fraction, or a band moving while it runs
		local barX, barY, barW, barH = pad, h - pad - BAR_TALL * unit, w - 2 * pad, BAR_TALL * unit
		draw.RoundedBox(corner / 2, barX, barY, barW, barH, TRACK)
		local fraction = P.Fraction(f.stage, self.stepFraction)
		local from, to = 0, fraction
		if not fraction then
			local at = (now * BAND_SPEED) % (1 + BAND) - BAND
			from, to = math.max(at, 0), math.min(at + BAND, 1)
		end
		if to > from then
			surface.SetDrawColor(TAN_LIGHT)
			surface.DrawRect(barX + barW * from, barY, barW * (to - from), barH)
		end
	end,
})

-- One box, kept on WS so a Lua refresh keeps it (and its music) going.
E.Listen("game_nav_progress", "ws_nav_progress", function(fields)
	if not IsValid(WS.NavProgressBox) then WS.NavProgressBox = vgui.Create(WS.UI.Name("NavProgress")) end
	WS.NavProgressBox:Show(fields, RealTime())
end)
