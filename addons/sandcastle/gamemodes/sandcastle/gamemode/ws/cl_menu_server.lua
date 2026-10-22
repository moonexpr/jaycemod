-- The spawn menu's Server tab: the votes players call (ws/sh_votes.lua).
-- A tile a vote; picking one shows its choices, and clicking a choice
-- calls the vote (a map vote's maps, or Call Vote). Votes the server
-- disabled, or that have no system behind them yet, stay on show but say
-- so. Players are reported, never voted off, from the scoreboard.
local Vote = WS.require("games.gameplay.vote")
local UI = WS.UI
local THEME = UI.THEME
local E = WS.Events

local TAB_NAME = "Server"
local TAB_ICON = "icon16/group.png"
local TAB_ORDER = -20 -- after Loadout (-40) and Store (-30), ahead of Sandbox's Spawnlists (-10)

local GAP = 8
local TILE_H = 64
local CHOICE_H = 40
local CHOICE_W = 200
local REFRESH_SECONDS = 1 -- how often the tab rereads the vote settings

-- What each vote does, for its tile's tooltip.
local ABOUT = {
	[Vote.KIND_DIFFICULTY] = "How hard the AI soldiers fight, on both teams.",
	[Vote.KIND_MAP] = "Sets the map that follows this one.",
	[Vote.KIND_SUPPORT] = "The other team respawns faster and its soldiers can set ambushes, for the rest of the match. Your team votes.",
	[Vote.KIND_RESET] = "Starts this round over. Money and weapons are kept.",
	[Vote.KIND_SCRAMBLE] = "Deals players to RED and BLU afresh at the next round.",
}

local NOT_READY = "Coming soon."
local DISABLED = "Server has disabled that issue."
local RUNNING = "A vote is currently in progress."
local NO_MAPS = "No maps available"

local function Call(kind, subject)
	E.Request("game_vote_call", {
		kind = WS.VoteKindIndex(kind),
		subject = subject or "",
	})
end

-- Why a kind cannot be called now, or nil.
local function Blocked(kind)
	if not WS.VOTE_READY[kind] then return NOT_READY end
	if not WS.VoteEnabled(kind) then return DISABLED end
	if WS.VoteState.running then return RUNNING end
end

UI.Define("ServerMenu", "DPanel", {
	Init = function(self)
		self:DockPadding(GAP, GAP, GAP, GAP)
		UI.Title(self, "Call Vote")
		self.tiles = vgui.Create("DPanel", self)
		self.tiles:SetPaintBackground(false)
		self.tiles:Dock(TOP)
		self.tiles:SetTall(TILE_H)
		self.tiles:DockMargin(0, GAP, 0, GAP)
		self.buttons = {}
		for _, kind in ipairs(Vote.CALLABLE) do
			local tile = vgui.Create(UI.Name("Button"), self.tiles)
			tile:SetText(WS.VOTE_NAMES[kind])
			tile:SetFont(THEME.titleFont)
			tile:SetTooltip(ABOUT[kind])
			tile.DoClick = function()
				self.picked = kind
				self:Refresh()
			end
			self.buttons[kind] = tile
		end
		self.tiles.PerformLayout = function(tiles, w)
			local n = #Vote.CALLABLE
			local tw = (w - GAP * (n - 1)) / n
			for i, kind in ipairs(Vote.CALLABLE) do
				self.buttons[kind]:SetPos((i - 1) * (tw + GAP), 0)
				self.buttons[kind]:SetSize(tw, TILE_H)
			end
		end
		self.prompt = vgui.Create(UI.Name("Label"), self)
		self.prompt:SetContentAlignment(4)
		self.prompt:Dock(TOP)
		self.choices = vgui.Create("DIconLayout", self)
		self.choices:Dock(TOP)
		self.choices:DockMargin(0, GAP, 0, 0)
		self.choices:SetSpaceX(GAP)
		self.choices:SetSpaceY(GAP)
		local hint = vgui.Create(UI.Name("Label"), self)
		hint:SetTextColor(THEME.muted)
		hint:SetContentAlignment(4)
		hint:SetText("To report a player, hold Tab and right-click them.")
		hint:Dock(BOTTOM)
		self.picked = Vote.CALLABLE[1]
		hook.Add("WSVoteChanged", self, function() self:Refresh() end)
		self.refreshAt = 0
		self:Refresh()
	end,

	Paint = function(self, w, h)
		surface.SetDrawColor(THEME.background)
		surface.DrawRect(0, 0, w, h)
	end,

	Think = function(self)
		if CurTime() < self.refreshAt then return end
		self.refreshAt = CurTime() + REFRESH_SECONDS
		self:Refresh()
	end,

	Choice = function(self, text, onClick, enabled)
		local button = self.choices:Add(UI.Name("Button"))
		button:SetSize(CHOICE_W, CHOICE_H)
		button:SetText(text)
		button:SetEnabled(enabled)
		button.DoClick = onClick
		return button
	end,

	Refresh = function(self)
		for kind, tile in pairs(self.buttons) do tile:SetSelected(kind == self.picked) end
		local kind = self.picked
		local blocked = Blocked(kind)
		self.choices:Clear()
		if blocked == NOT_READY then
			self.prompt:SetText(WS.VOTE_NAMES[kind] .. ": " .. NOT_READY)
		elseif kind == Vote.KIND_MAP then
			self.prompt:SetText(blocked or "Set the next map to:")
			if #WS.VoteMaps == 0 then self.prompt:SetText(NO_MAPS) end
			for _, map in ipairs(WS.VoteMaps) do self:Choice(map, function() Call(kind, map) end, blocked == nil) end
		else
			self.prompt:SetText(blocked or WS.VoteQuestion(kind, "", nil))
			self:Choice("Call Vote", function() Call(kind) end, blocked == nil)
		end
		self.choices:InvalidateLayout(true)
		self.choices:SizeToChildren(false, true)
	end,
})

spawnmenu.AddCreationTab(TAB_NAME, function()
	return vgui.Create(UI.Name("ServerMenu"))
end, TAB_ICON, TAB_ORDER)
