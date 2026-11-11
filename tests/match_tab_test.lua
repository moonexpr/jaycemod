-- ws/cl_admin_panels.lua: the Match tab in ULX's menu (XGUI), added when the
-- menu first opens for a holder of the match privilege, its controls the
-- commands and settings the spawn menu's panels use. Run against a fake XGUI
-- and fake panels.
local T = dofile ("tests/harness.lua")
local Permissions = system.permissions

local function Control (t)
	local c = { parent = t.parent, label = t.label, min = t.min, max = t.max }
	function c:SetTooltip (text) self.tooltip = text end
	function c:SetSize () end
	function c:SetVisible (on) self.visible = on end
	return c
end

-- XGUI's xlib, as far as the tab uses it: the list and panes kept in s.
local function Xlib (s)
	return
	{
		makepanel = function (t)
			local pane = Control (t)
			if t.x then s.panes [#s.panes + 1] = pane end
			return pane
		end,
		makelistview = function (t)
			local list = Control (t)
			list.Columns = {}
			function list:AddColumn (title) self.Columns [#self.Columns + 1] = { title = title } end
			function list:AddLine (title) s.rows [#s.rows + 1] = title end
			function list:SelectFirstItem () self.selected = 1 end
			s.list = list
			return list
		end,
		makebutton = function (t)
			local button = Control (t)
			s.buttons [t.label] = button
			return button
		end,
		makelabel = function (t)
			local label = Control (t)
			s.labels [#s.labels + 1] = label
			return label
		end,
		makeslider = function (t)
			local slider = Control (t)
			s.slidersMade [#s.slidersMade + 1] = slider
			return slider
		end
	}
end

-- Loads the panels; opts.xgui false leaves ULX out, opts.held the privileges.
local function Load (opts)
	local s =
	{
		hooks = {},
		buttons = {},
		sliders = {},
		slidersMade = {},
		labels = {},
		panes = {},
		rows = {},
		ran = {},
		modules = {},
		processed = 0,
		asked = 0,
		opened = {},
		drawn = {}
	}
	local order = { "Cmds", "Groups", "Maps", "Settings", "Bans" }
	local xgui = opts.xgui ~= false and
		{
			null = {},
			settings = { moduleOrder = order },
			hookEvent = function (dtype, event, fn, name)
				T.eq (dtype, "onOpen")
				T.eq (event, nil)
				s.opened [name] = fn
			end,
			addModule = function (name, panel, icon, access) s.modules [#s.modules + 1] = { name = name, panel = panel, icon = icon, access = access } end,
			-- as XGUI's: a module is drawn only if moduleOrder, filled at its start, names it
			processModules = function ()
				s.processed = s.processed + 1
				s.drawn = {}
				for _, name in ipairs (order) do
					for _, m in ipairs (s.modules) do
						if m.name == name then s.drawn [#s.drawn + 1] = name end
					end
				end
			end
		} or nil
	local env = setmetatable (
		{
			WS =
			{
				Can = function (_, privilege) return opts.held [privilege] == true end,
				-- as the real one: its slider is whatever the panel's NumSlider makes
				ServerSlider = function (panel, label, convar)
					s.sliders [convar] = label
					return panel:NumSlider (label, nil, 0, 1000, 0)
				end,
				ServerCheckBox = function () return Control ({}) end,
				RequestServerSettings = function () s.asked = s.asked + 1 end
			},
			LocalPlayer = function () return {} end,
			table = setmetatable (
				{
					HasValue = function (list, value)
						for _, v in ipairs (list) do
							if v == value then return true end
						end
						return false
					end
				}, { __index = table }),
			RunConsoleCommand = function (...) s.ran [#s.ran + 1] = table.concat ({ ... }, " ") end,
			hook = { Add = function (name, _, fn) s.hooks [name] = fn end },
			xgui = xgui,
			xlib = Xlib (s)
		}, { __index = _G })
	setfenv (assert (loadfile ("addons/sandcastle/gamemodes/sandcastle/gamemode/cl_admin_panels.lua")), env) ()
	s.hooks.Initialize ()
	function s.Open () s.opened.ws_match_tab () end
	function s.Order (name) order [#order + 1] = name end
	return s
end

local ALL = { [Permissions.ROUND] = true, [Permissions.MATCH] = true, [Permissions.RULES] = true }

local function Press (s, label)
	s.ran = {}
	s.buttons [label].DoClick ()
	return s.ran [1]
end

T.test ("without ULX there is no tab, and nothing to go wrong", function ()
	local s = Load ({ xgui = false, held = ALL })
	T.eq (next (s.opened), nil)
end)

T.test ("a player without the match privilege gets no tab", function ()
	local s = Load ({ held = { [Permissions.ROUND] = true } })
	s.Open ()
	T.eq (#s.modules, 0)
	T.eq (s.processed, 0)
end)

T.test ("the tab is added once, named Match, as the menu first opens", function ()
	local s = Load ({ held = ALL })
	T.eq (#s.modules, 0)
	s.Open ()
	s.Open ()
	T.eq (#s.modules, 1)
	T.eq (s.modules [1].name, "Match")
	T.eq (s.processed, 1)
end)

T.test ("the tab is drawn though XGUI listed its modules before it was added", function ()
	local s = Load ({ held = ALL })
	s.Open ()
	T.eq (table.concat (s.drawn, ","), "Match")
end)

T.test ("a saved order naming the tab keeps its place, not a second entry", function ()
	local s = Load ({ held = ALL })
	s.Order ("Match")
	s.Open ()
	T.eq (s.drawn [1], "Match")
	T.eq (#s.drawn, 1)
end)

T.test ("a privilege gained later adds the tab at the next opening", function ()
	local held = {}
	local s = Load ({ held = held })
	s.Open ()
	T.eq (#s.modules, 0)
	held [Permissions.MATCH] = true
	s.Open ()
	T.eq (#s.modules, 1)
end)

T.test ("each opening asks the server's settings, so the sliders show what is set", function ()
	local s = Load ({ held = ALL })
	s.Open ()
	s.Open ()
	T.eq (s.asked, 2)
end)

T.test ("the game starts and stops, the teams scramble, the round and match restart", function ()
	local s = Load ({ held = ALL })
	s.Open ()
	T.eq (Press (s, "Start Game"), "mp_gameplay_begin")
	T.eq (Press (s, "Stop Game"), "mp_gameplay_stop")
	T.eq (Press (s, "Scramble Teams"), "mp_teams_scramble")
	T.eq (Press (s, "Restart Round"), "mp_round_restart")
	T.eq (Press (s, "Restart Match"), "mp_match_restart")
end)

T.test ("every win condition has its slider, frags and credit among them", function ()
	local s = Load ({ held = ALL })
	s.Open ()
	for _, convar in ipairs ({ "mp_winlimit", "mp_maxrounds", "mp_timelimit", "mp_fraglimit", "mp_creditlimit" }) do
		T.eq (s.sliders [convar] ~= nil, true, convar)
	end
	T.eq (s.sliders.mp_creditlimit, "Credit to win a round")
end)

T.test ("a section shows only to holders of its own privilege", function ()
	local s = Load ({ held = { [Permissions.MATCH] = true } })
	s.Open ()
	T.eq (s.buttons ["Start Game"] ~= nil, true)
	T.eq (s.buttons ["Restart Round"], nil)
	T.eq (s.sliders.mp_fraglimit, nil)
end)

T.test ("the list names a row for each section the player may use, under a title", function ()
	local s = Load ({ held = ALL })
	s.Open ()
	T.eq (s.list.Columns [1].title, "Match Control")
	T.eq (table.concat (s.rows, ","), "Game,Round,Win conditions")
	local matchOnly = Load ({ held = { [Permissions.MATCH] = true } })
	matchOnly.Open ()
	T.eq (table.concat (matchOnly.rows, ","), "Game")
end)

T.test ("the tab opens on the first row, with only its pane showing", function ()
	local s = Load ({ held = ALL })
	s.Open ()
	T.eq (s.list.selected, 1)
	T.eq (s.panes [1].visible, true)
	T.eq (s.panes [2].visible, false)
	T.eq (s.panes [3].visible, false)
end)

T.test ("choosing a row shows its pane and hides the others", function ()
	local s = Load ({ held = ALL })
	s.Open ()
	s.list:OnRowSelected (3)
	T.eq (s.panes [1].visible, false)
	T.eq (s.panes [3].visible, true)
	s.list:OnRowSelected (2)
	T.eq (s.panes [2].visible, true)
	T.eq (s.panes [3].visible, false)
end)

T.test ("each control sits on its own section's pane", function ()
	local s = Load ({ held = ALL })
	s.Open ()
	T.eq (s.buttons ["Start Game"].parent, s.panes [1])
	T.eq (s.buttons ["Restart Round"].parent, s.panes [2])
	T.eq (s.slidersMade [1].parent, s.panes [3])
end)

T.test ("a slider is XGUI's, over the setting's range, with its name on a label above", function ()
	local s = Load ({ held = ALL })
	s.Open ()
	T.eq (#s.slidersMade, 5)
	T.eq (s.slidersMade [1].min, 0)
	T.eq (s.slidersMade [1].max, 1000)
	local named = {}
	for _, label in ipairs (s.labels) do named [label.label] = label.parent end
	T.eq (named ["Credit to win a round:"], s.panes [3])
end)

T.test ("what a tooltip alone would hide is written on the pane", function ()
	local s = Load ({ held = ALL })
	s.Open ()
	local text = {}
	for _, label in ipairs (s.labels) do
		if label.parent == s.panes [1] then text [#text + 1] = label.label end
	end
	T.eq (table.concat (text, " "):find ("next round", 1, true) ~= nil, true)
end)

T.finish ()
