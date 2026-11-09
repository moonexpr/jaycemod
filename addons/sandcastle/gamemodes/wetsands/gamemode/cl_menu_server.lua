-- The spawn menu's Server tab: the votes players call (ws/sh_votes.lua).
-- A tile a vote; picking one shows its choices, and clicking a choice
-- calls the vote (a map vote's maps, or Call Vote). Votes the server
-- disabled, or that have no system behind them yet, stay on show but say
-- so. Players are reported, never voted off, from the scoreboard. Maps are
-- shown as the spawn menu shows entities: an icon a map (ContentIcon), its
-- thumbnail (maps/thumb/<map>.png, GMod's "no icon" where it has none) and
-- its name, a search box over them; while the next-map vote runs, the tab
-- is its ballot, the maps it offers as icons, the player's pick outlined.
local Vote = gameplay.vote
local UI = WS.UI
local THEME = UI.THEME
local E = WS.Events

local TAB_NAME = "Server"
local TAB_ICON = "icon16/group.png"
local TAB_ORDER = 10000 -- the last tab on the left, after Sandbox's own

local LAYOUT = core.constants.New("server tab layout", {
	GAP = 8,
	TILE_H = 64,
	CHOICE_H = 40,
	CHOICE_W = 200,
})
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
local THUMB, NO_THUMB = "maps/thumb/%s.png", "maps/thumb/noicon.png"
local PICKED_EDGE, PICKED_WIDTH = Color(255, 210, 60), 3
local DIMMED = 90 -- a map's icon while no vote can be called
local DIFFICULTY = GetConVar("tf_bot_difficulty")
local OTHER_TEAM = {
	[WS.TEAM_RED] = WS.TEAM_BLUE,
	[WS.TEAM_BLUE] = WS.TEAM_RED,
}

-- A map's thumbnail, or GMod's "no icon".
local function Thumb(map)
	local path = THUMB:format(map)
	return file.Exists(path, "GAME") and path or NO_THUMB
end

-- The running next-map vote, if the player may vote in it: its state.
local function NextMapBallot()
	local state = WS.VoteState
	if not (state.running and state.mine and #state.options > 0) then return nil end
	if WS.VOTE_KINDS[state.kind + 1] ~= Vote.KIND_NEXTMAP then return nil end
	return state
end

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
		self:DockPadding(LAYOUT.GAP, LAYOUT.GAP, LAYOUT.GAP, LAYOUT.GAP)
		UI.Title(self, "Call Vote")
		self.tiles = vgui.Create("DPanel", self)
		self.tiles:SetPaintBackground(false)
		self.tiles:Dock(TOP)
		self.tiles:SetTall(LAYOUT.TILE_H)
		self.tiles:DockMargin(0, LAYOUT.GAP, 0, LAYOUT.GAP)
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
			local tw = (w - LAYOUT.GAP * (n - 1)) / n
			for i, kind in ipairs(Vote.CALLABLE) do
				self.buttons[kind]:SetPos((i - 1) * (tw + LAYOUT.GAP), 0)
				self.buttons[kind]:SetSize(tw, LAYOUT.TILE_H)
			end
		end
		self.prompt = vgui.Create(UI.Name("Label"), self)
		self.prompt:SetContentAlignment(4)
		self.prompt:Dock(TOP)
		self.search = vgui.Create("DTextEntry", self)
		self.search:Dock(TOP)
		self.search:DockMargin(0, LAYOUT.GAP, 0, 0)
		self.search:SetPlaceholderText("Search maps...")
		self.search:SetUpdateOnType(true)
		self.search.OnValueChange = function() self:Refresh() end
		local hint = vgui.Create(UI.Name("Label"), self)
		hint:SetTextColor(THEME.muted)
		hint:SetContentAlignment(4)
		hint:SetText("To report a player, hold Tab and right-click them.")
		hint:Dock(BOTTOM)
		self.scroll = vgui.Create("DScrollPanel", self)
		self.scroll:Dock(FILL)
		self.scroll:DockMargin(0, LAYOUT.GAP, 0, 0)
		self.choices = self.scroll:Add("DIconLayout")
		self.choices:Dock(TOP)
		self.choices:SetSpaceX(LAYOUT.GAP)
		self.choices:SetSpaceY(LAYOUT.GAP)
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
		button:SetSize(LAYOUT.CHOICE_W, LAYOUT.CHOICE_H)
		button:SetText(text)
		button:SetEnabled(enabled)
		button.DoClick = onClick
		return button
	end,

	-- A map as the spawn menu shows an entity: its thumbnail and name; a
	-- click runs onClick while enabled; picked, it is outlined.
	MapChoice = function(self, map, onClick, enabled, picked)
		local icon = self.choices:Add("ContentIcon")
		icon:SetContentType("map")
		icon:SetSpawnName(map)
		icon:SetName(map)
		icon:SetMaterial(Thumb(map))
		icon:SetTooltip(map)
		icon:SetAlpha(enabled and 255 or DIMMED)
		icon.DoClick = function()
			if enabled then onClick() end
		end
		icon.OpenMenu = function() end
		if picked then
			icon.PaintOver = function(_, w, h)
				surface.SetDrawColor(PICKED_EDGE)
				for i = 0, PICKED_WIDTH - 1 do surface.DrawOutlinedRect(i, i, w - i * 2, h - i * 2) end
			end
		end
		return icon
	end,

	-- The map list's search, or nil when empty.
	Wanted = function(self)
		local text = string.Trim(self.search:GetValue() or ""):lower()
		return text ~= "" and text or nil
	end,

	Refresh = function(self)
		for kind, tile in pairs(self.buttons) do tile:SetSelected(kind == self.picked) end
		local kind = self.picked
		local blocked = Blocked(kind)
		self.choices:Clear()
		self.search:SetVisible(false)
		local ballot = NextMapBallot()
		if ballot then
			self.prompt:SetText("Vote for the next map:")
			for i, map in ipairs(ballot.options) do
				self:MapChoice(map, function() E.Request("game_vote_cast", { yes = false, choice = i }) end, true,
					ballot.cast == i)
			end
		elseif blocked == NOT_READY then
			self.prompt:SetText(WS.VOTE_NAMES[kind] .. ": " .. NOT_READY)
		elseif kind == Vote.KIND_MAP then
			self.prompt:SetText(blocked or "Set the next map to:")
			if #WS.VoteMaps == 0 then self.prompt:SetText(NO_MAPS) end
			self.search:SetVisible(#WS.VoteMaps > 0)
			local wanted = self:Wanted()
			for _, map in ipairs(WS.VoteMaps) do
				if not wanted or map:find(wanted, 1, true) then
					self:MapChoice(map, function() Call(kind, map) end, blocked == nil, false)
				end
			end
		elseif kind == Vote.KIND_DIFFICULTY then
			local now = Vote.DIFFICULTIES[DIFFICULTY:GetInt() + 1]
			self.prompt:SetText(blocked or ("Set the soldiers' difficulty (now " .. now .. ") to:"))
			for _, level in ipairs(Vote.DIFFICULTIES) do
				self:Choice(string.upper(level:sub(1, 1)) .. level:sub(2), function() Call(kind, level) end, blocked == nil and level ~= now)
			end
		elseif kind == Vote.KIND_SUPPORT then
			local other = OTHER_TEAM[LocalPlayer():Team()]
			if not other then
				self.prompt:SetText("Join RED or BLU to call this vote.")
			else
				self.prompt:SetText(blocked or WS.VoteQuestion(kind, team.GetName(other), nil))
				self:Choice("Call Vote", function() Call(kind) end, blocked == nil and GetGlobal2Int("ws_handicap_team", 0) ~= other)
			end
		else
			self.prompt:SetText(blocked or WS.VoteQuestion(kind, "", nil))
			self:Choice("Call Vote", function() Call(kind) end, blocked == nil)
		end
		self:InvalidateLayout(true)
		self.choices:InvalidateLayout(true)
		self.choices:SizeToChildren(false, true)
	end,
})

spawnmenu.AddCreationTab(TAB_NAME, function()
	return vgui.Create(UI.Name("ServerMenu"))
end, TAB_ICON, TAB_ORDER)
