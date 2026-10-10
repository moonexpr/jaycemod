-- The team scoreboard (foundation.scoreboard): Sandbox's scoreboard (base's
-- cl_scoreboard.lua, its fonts and grey rows of avatar, name, kills, deaths,
-- ping and mute, with money (foundation.economy) beside the name), split
-- into TF2's columns, BLU left and RED right, each
-- under its team's name, points, player count and goal, with the column
-- names above its rows. A team's NPCs are rows in its column (ping "BOT", as
-- TF2 shows bots). Below: anyone on no team, the spectators, the map, and the
-- match's win conditions. Shown wherever teams play (a TF2 map's rounds, the
-- AI war); elsewhere Sandbox's own.
local Scoreboard = WS.require("foundation.scoreboard")
local Teams = WS.require("foundation.teams")
local Economy = WS.require("foundation.economy")

local UNASSIGNED = Teams.UNASSIGNED
local GATHER = 1 -- seconds between snapshots of who is on the board

-- base's scoreboard: 700 wide, 100 down, its rows an avatar of 32 padded by 3
local WIDTH_MAX, SIDE_GUTTER, BOARD_Y = 1000, 16, 100 -- not TOP: that is the dock enum
local TITLE_H, TEAM_H, GOAL_H, LABELS_H, FOOTER_LINE_H, FOOTER_PAD = 44, 52, 18, 22, 18, 4
local COLUMN_GAP, ROW_GAP, ROW_PAD, AVATAR, STAT_W, TEAM_EDGE = 12, 2, 3, 32, 50, 4
local ROW_H = AVATAR + ROW_PAD * 2
local UNASSIGNED_ROWS_SHOWN = 3
local MONEY_W = 80

-- The stat columns, right to left as they dock: Name | Money | Kills | Deaths | Ping.
local STATS = {
	{
		key = "Ping",
		width = STAT_W,
	},
	{
		key = "Deaths",
		width = STAT_W,
	},
	{
		key = "Kills",
		width = STAT_W,
	},
	{
		key = "Money",
		width = MONEY_W,
	},
}
local CORNER = 4

local WHITE = Color(255, 255, 255)
local ROW = Color(230, 230, 230) -- base's PLAYER_LINE colours
local ROW_DEAD = Color(230, 200, 200)
local ROW_ADMIN = Color(230, 255, 230)
local ROW_TEXT = Color(93, 93, 93)
local PANEL = Color(0, 0, 0, 160)
local NEUTRAL = Color(120, 120, 120)
local BOT_PING = "BOT"
local NO_DEATHS = "-"

surface.CreateFont("Sandcastle.Scoreboard.Row", {
	font = "Helvetica",
	size = 22,
	weight = 800,
})
surface.CreateFont("Sandcastle.Scoreboard.Title", {
	font = "Helvetica",
	size = 32,
	weight = 800,
})
surface.CreateFont("Sandcastle.Scoreboard.Score", {
	font = "Helvetica",
	size = 44,
	weight = 800,
})
surface.CreateFont("Sandcastle.Scoreboard.Small", {
	font = "Helvetica",
	size = 16,
	weight = 800,
})

local function TeamColor(t)
	return WS.TeamColor[t] or NEUTRAL
end

local function TeamName(t)
	return WS.TeamName[t] or team.GetName(t)
end

local function NpcName(ent)
	return ent.PrintName or language.GetPhrase(ent:GetClass())
end

-- Everyone the board lists: every player, and every NPC fighting for a team.
local function Rows()
	local rows = {}
	for _, ply in player.Iterator() do
		rows[#rows + 1] = {
			ent = ply,
			name = ply:Nick(),
			team = ply:Team(),
			kills = ply:Frags(),
			deaths = ply:Deaths(),
			money = ply:GetNW2Int("ws_money", 0),
			npc = false,
		}
	end
	for _, ent in ents.Iterator() do
		local t = ent:GetNW2Int("ws_team", UNASSIGNED)
		if t ~= UNASSIGNED and (ent:IsNPC() or ent:IsNextBot()) then
			rows[#rows + 1] = {
				ent = ent,
				name = NpcName(ent),
				team = t,
				kills = ent:GetNW2Int("ws_kills", 0),
				deaths = 0,
				money = ent:GetNW2Int("ws_money", 0),
				npc = true,
			}
		end
	end
	return rows
end

local function Limits()
	local ends = GetGlobal2Float("ws_match_time_end", 0)
	return {
		winlimit = GetGlobal2Int("ws_match_winlimit", 0),
		maxrounds = GetGlobal2Int("ws_match_maxrounds", 0),
		timelimit = GetGlobal2Int("ws_match_timelimit", 0),
		roundsPlayed = GetGlobal2Int("ws_match_rounds_played", 0),
		timeLeft = math.max(0, ends - CurTime()),
	}
end

-- A snapshot of everything the board shows, taken every GATHER seconds
-- whether or not it is open, so opening it never waits on a scan of the
-- entities; the board redraws only when a new snapshot arrives.
local snapshot = { serial = 0 }

local function TeamsPlay()
	return WS.Active() or WS.AiWarActive()
end

local function Gather()
	local goals = {}
	for _, t in ipairs(Scoreboard.COLUMN_TEAMS) do
		goals[t] = WS.Localize(GetGlobal2String("ws_round_goal_" .. t, ""))
	end
	snapshot = {
		serial = snapshot.serial + 1,
		host = GetHostName(),
		board = Scoreboard.Build(Rows()),
		conditions = Scoreboard.WinConditions(Limits()),
		goals = goals,
	}
end

timer.Create("ws_scoreboard_gather", GATHER, 0, function()
	if TeamsPlay() then Gather() end
end)

-- SetText relays a label out even when its text is the same.
local function Text(label, text)
	text = tostring(text)
	if label:GetText() ~= text then label:SetText(text) end
end

local function Shadowed(parent, font, dock, align)
	local label = parent:Add("DLabel")
	label:SetFont(font)
	label:SetTextColor(WHITE)
	label:SetExpensiveShadow(2, Color(0, 0, 0, 200))
	label:SetContentAlignment(align)
	label:Dock(dock)
	return label
end

-- A row ------------------------------------------------------------------------------

local LINE = {}

function LINE:Init()
	self:DockPadding(ROW_PAD + TEAM_EDGE, ROW_PAD, ROW_PAD, ROW_PAD)
	self:SetTall(ROW_H)
	self:Dock(TOP)
	self:DockMargin(2, 0, 2, ROW_GAP)

	self.Mute = self:Add("DImageButton")
	self.Mute:SetSize(AVATAR, AVATAR)
	self.Mute:Dock(RIGHT)
	for _, stat in ipairs(STATS) do
		local label = self:Add("DLabel")
		label:Dock(RIGHT)
		label:SetWidth(stat.width)
		label:SetFont("Sandcastle.Scoreboard.Row")
		label:SetTextColor(ROW_TEXT)
		label:SetContentAlignment(5)
		self[stat.key] = label
	end
end

function LINE:Setup(row)
	self.ent = row.ent
	if row.npc then
		self.Icon = self:Add("DImage")
		self.Icon:SetImage("entities/" .. row.ent:GetClass() .. ".png", "icon16/user_gray.png")
		-- NPCs can't be muted: the slot stays, empty, so the stats line up under their names
		self.Mute:SetMouseInputEnabled(false)
	else
		self.Icon = self:Add("AvatarImage")
		self.Icon:SetPlayer(row.ent, AVATAR)
		self.Mute.DoClick = function() row.ent:SetMuted(not row.ent:IsMuted()) end
	end
	self.Icon:SetSize(AVATAR, AVATAR)
	self.Icon:Dock(LEFT)
	self.Name = self:Add("DLabel")
	self.Name:Dock(FILL)
	self.Name:SetFont("Sandcastle.Scoreboard.Row")
	self.Name:SetTextColor(ROW_TEXT)
	self.Name:DockMargin(8, 0, 0, 0)
	self:Update(row)
end

function LINE:Update(row)
	self.row = row
	Text(self.Name, row.name)
	Text(self.Kills, row.kills)
	Text(self.Money, Economy.Format(row.money))
	if row.npc then
		Text(self.Deaths, NO_DEATHS)
		Text(self.Ping, BOT_PING)
		return
	end
	Text(self.Deaths, row.deaths)
	Text(self.Ping, row.ent:IsBot() and BOT_PING or row.ent:Ping())
	local muted = row.ent:IsMuted()
	if self.muted ~= muted then
		self.muted = muted
		self.Mute:SetImage(muted and "icon32/muted.png" or "icon32/unmuted.png")
	end
end

function LINE:Paint(w, h)
	local ent, row = self.ent, self.row
	if not IsValid(ent) then return end
	local fill = ROW
	if ent:IsPlayer() and not ent:Alive() then
		fill = ROW_DEAD
	elseif ent:IsPlayer() and ent:IsAdmin() then
		fill = ROW_ADMIN
	end
	draw.RoundedBox(CORNER, 0, 0, w, h, fill)
	draw.RoundedBoxEx(CORNER, 0, 0, TEAM_EDGE, h, TeamColor(row.team), true, false, true, false)
end

vgui.Register("SandcastleScoreboardLine", LINE, "DPanel")

-- A list of rows, kept in the board's order --------------------------------------------

local LIST = {}

function LIST:Init()
	self.lines = {} -- entity -> its line
end

-- rows in order: lines for new entities, gone ones removed, the rest reordered.
function LIST:SetRows(rows)
	local seen = {}
	for i, row in ipairs(rows) do
		if IsValid(row.ent) then
			local line = self.lines[row.ent]
			if not line then
				line = self:Add("SandcastleScoreboardLine")
				line:Setup(row)
				self.lines[row.ent] = line
			else
				line:Update(row)
			end
			if line:GetZPos() ~= i then line:SetZPos(i) end
			seen[row.ent] = true
		end
	end
	for ent, line in pairs(self.lines) do
		if not seen[ent] then
			line:Remove()
			self.lines[ent] = nil
		end
	end
end

vgui.Register("SandcastleScoreboardList", LIST, "DScrollPanel")

-- A team's column ------------------------------------------------------------------------

local COLUMN = {}

function COLUMN:Setup(t)
	self.team = t
	local header = self:Add("Panel")
	header:Dock(TOP)
	header:SetTall(TEAM_H)
	header:DockPadding(8, 0, 8, 0)
	header.Paint = function(_, w, h) draw.RoundedBox(CORNER, 0, 0, w, h, TeamColor(t)) end
	-- TF2 sets each team's score on the side facing the other team
	local inner = t == Scoreboard.COLUMN_TEAMS[1] and RIGHT or LEFT
	self.Score = Shadowed(header, "Sandcastle.Scoreboard.Score", inner, 5)
	self.Score:SetWide(TEAM_H * 2)
	local name = Shadowed(header, "Sandcastle.Scoreboard.Title", FILL, inner == RIGHT and 7 or 9)
	name:SetText(TeamName(t))
	self.Count = Shadowed(name, "Sandcastle.Scoreboard.Small", BOTTOM, inner == RIGHT and 1 or 3)
	self.Count:SetTall(GOAL_H)

	self.Goal = Shadowed(self, "Sandcastle.Scoreboard.Small", TOP, 5)
	self.Goal:SetTall(GOAL_H)

	local labels = self:Add("Panel")
	labels:Dock(TOP)
	labels:SetTall(LABELS_H)
	labels:DockPadding(ROW_PAD + TEAM_EDGE + AVATAR + 8 + 2, 0, ROW_PAD + AVATAR + 2, 0)
	for _, stat in ipairs(STATS) do
		local label = Shadowed(labels, "Sandcastle.Scoreboard.Small", RIGHT, 5)
		label:SetWide(stat.width)
		label:SetText(stat.key)
	end
	Shadowed(labels, "Sandcastle.Scoreboard.Small", FILL, 4):SetText("Name")

	self.List = self:Add("SandcastleScoreboardList")
	self.List:Dock(FILL)
end

function COLUMN:SetRows(rows, goal)
	local players = 0
	for _, row in ipairs(rows) do
		if not row.npc then players = players + 1 end
	end
	Text(self.Score, team.GetScore(self.team))
	Text(self.Count, string.format("%d %s, %d NPCs", players, players == 1 and "player" or "players",
		#rows - players))
	Text(self.Goal, goal or "")
	if self.Goal:IsVisible() ~= (goal ~= nil) then self.Goal:SetVisible(goal ~= nil) end
	self.List:SetRows(rows)
end

vgui.Register("SandcastleScoreboardColumn", COLUMN, "Panel")

-- The board -------------------------------------------------------------------------------

local BOARD = {}

function BOARD:Init()
	self.Title = Shadowed(self, "Sandcastle.Scoreboard.Title", TOP, 5)
	self.Title:SetTall(TITLE_H)

	self.Footer = self:Add("Panel")
	self.Footer:Dock(BOTTOM)
	self.Footer:DockMargin(0, COLUMN_GAP, 0, 0)
	self.Footer:DockPadding(8, FOOTER_PAD, 8, FOOTER_PAD)
	self.Footer.Paint = function(_, w, h) draw.RoundedBox(CORNER, 0, 0, w, h, PANEL) end
	self.Left = Shadowed(self.Footer, "Sandcastle.Scoreboard.Small", LEFT, 7)
	self.Left:SetWrap(true)
	self.Right = Shadowed(self.Footer, "Sandcastle.Scoreboard.Small", FILL, 9)

	self.Unassigned = self:Add("Panel")
	self.Unassigned:Dock(BOTTOM)
	self.Unassigned:DockMargin(0, COLUMN_GAP, 0, 0)
	Shadowed(self.Unassigned, "Sandcastle.Scoreboard.Small", TOP, 4):SetText("Unassigned")
	self.UnassignedList = self.Unassigned:Add("SandcastleScoreboardList")
	self.UnassignedList:Dock(FILL)

	self.Columns = self:Add("Panel")
	self.Columns:Dock(FILL)
	self.Columns:DockMargin(0, COLUMN_GAP, 0, 0)
	self.columns = {}
	for i, t in ipairs(Scoreboard.COLUMN_TEAMS) do
		local column = self.Columns:Add("SandcastleScoreboardColumn")
		column:Setup(t)
		column:Dock(i == 1 and LEFT or FILL)
		if i == 1 then column:DockMargin(0, 0, COLUMN_GAP, 0) end
		self.columns[t] = column
	end
	self:Apply(snapshot)
end

function BOARD:PerformLayout(w, h)
	local width = math.min(WIDTH_MAX, ScrW() - SIDE_GUTTER * 2)
	self:SetSize(width, ScrH() - BOARD_Y * 2)
	self:SetPos((ScrW() - width) / 2, BOARD_Y)
	local first = self.columns[Scoreboard.COLUMN_TEAMS[1]]
	first:SetWide((width - COLUMN_GAP) / 2)
	self.Left:SetWide(width / 2)
end

-- Shows a snapshot (Gather); one shown already, or none taken yet, is left as it is.
function BOARD:Apply(shot)
	if shot.serial == 0 or self.applied == shot.serial then return end
	self.applied = shot.serial
	local board = shot.board
	Text(self.Title, shot.host)
	for t, column in pairs(self.columns) do column:SetRows(board.teams[t], shot.goals[t]) end

	local unassigned = #board.unassigned
	if self.Unassigned:IsVisible() ~= (unassigned > 0) then self.Unassigned:SetVisible(unassigned > 0) end
	local tall = GOAL_H + math.min(unassigned, UNASSIGNED_ROWS_SHOWN) * (ROW_H + ROW_GAP)
	if self.Unassigned:GetTall() ~= tall then self.Unassigned:SetTall(tall) end
	self.UnassignedList:SetRows(board.unassigned)

	local left = { "Map: " .. game.GetMap() }
	if #board.spectators > 0 then left[#left + 1] = "Spectators: " .. table.concat(board.spectators, ", ") end
	Text(self.Left, table.concat(left, "\n"))
	Text(self.Right, table.concat(shot.conditions, "\n"))
	tall = FOOTER_PAD * 2 + math.max(#left, #shot.conditions) * FOOTER_LINE_H
	if self.Footer:GetTall() ~= tall then self.Footer:SetTall(tall) end
end

function BOARD:Think()
	self:Apply(snapshot)
end

vgui.Register("SandcastleScoreboard", BOARD, "EditablePanel")

-- Showing it ----------------------------------------------------------------------------

function GM:ScoreboardShow()
	if not TeamsPlay() then return self.BaseClass.ScoreboardShow(self) end
	if not IsValid(self.sandcastleScoreboard) then self.sandcastleScoreboard = vgui.Create("SandcastleScoreboard") end
	if snapshot.serial == 0 then Gather() end -- the first opening on a map, before the timer's first snapshot
	self.sandcastleScoreboard:Show()
	self.sandcastleScoreboard:MakePopup()
	self.sandcastleScoreboard:SetKeyboardInputEnabled(false)
end

function GM:ScoreboardHide()
	self.BaseClass.ScoreboardHide(self)
	if IsValid(self.sandcastleScoreboard) then self.sandcastleScoreboard:Hide() end
end
