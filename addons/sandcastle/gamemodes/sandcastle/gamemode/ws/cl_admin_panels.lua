-- The admins' panels in the spawn menu's tool tabs, a collapsible section
-- each, shown only to holders of the section's privilege (an admin mod
-- decides who holds what):
-- - Options > Admin > Gameplay Rules: the rules' settings (foundation.settings),
--   each following the server's value; hover one for what it does and its
--   console variable.
-- - Utilities > Admin > Match Control: round, match, tampering and
--   NextSoldier controls (ws/sv_match_control.lua and the commands they
--   already had).
-- An admin mod or server adds its own sections through the hooks
-- WSGameplayRulesPanel(panel) and WSMatchControlPanel(panel).
local Permissions = WS.require("foundation.permissions")

local NOT_ALLOWED = "Your rank may not change these. An admin mod can give it the privilege "

-- A collapsible section of panel; its controls build into the returned form.
local function Section(panel, title, expanded)
	local form = vgui.Create("DForm", panel)
	form:SetName(title)
	form:SetExpanded(expanded)
	panel:AddItem(form)
	return form
end

local function Tip(control, help, convar)
	control:SetTooltip(help .. (convar and ("\n" .. convar) or ""))
	return control
end

local function Slider(form, label, convar, help)
	return Tip(WS.ServerSlider(form, label, convar), help, convar)
end

local function Check(form, label, convar, help)
	return Tip(WS.ServerCheckBox(form, label, convar), help, convar)
end

local function Buttons(form, buttons)
	for _, b in ipairs(buttons) do
		local button = form:Button(b.label)
		button.DoClick = function() RunConsoleCommand(unpack(b.command)) end
		Tip(button, b.help, table.concat(b.command, " "))
	end
end

-- Builds the sections the local player's privileges allow.
local function Build(panel, sections, hookName)
	panel:ClearControls()
	WS.RequestServerSettings()
	local shown = 0
	for i, section in ipairs(sections) do
		if WS.Can(LocalPlayer(), section.privilege) then
			section.build(Section(panel, section.title, i <= 2))
			shown = shown + 1
		end
	end
	if shown == 0 then panel:Help(NOT_ALLOWED .. sections[1].privilege .. ".") end
	hook.Run(hookName, panel)
end

local RULES = {
	{
		title = "Winning",
		privilege = Permissions.RULES,
		build = function(f)
			Slider(f, "Rounds to win the match", "mp_winlimit", "The match ends when a team wins this many rounds. 0: no limit.")
			Slider(f, "Most rounds in a match", "mp_maxrounds", "The match ends after this many rounds. 0: no limit.")
			Slider(f, "Time limit (minutes)", "mp_timelimit", "The map changes after this long. 0: no limit.")
			Check(f, "End the match at the time limit", "mp_match_end_at_timelimit", "Otherwise the round in progress finishes first.")
		end,
	},
	{
		title = "Votes and reports",
		privilege = Permissions.RULES,
		build = function(f)
			Slider(f, "Reports that start a kick vote", "mp_reports_kick_count",
				"Different players reporting the same player. On a server of exactly three players, two are enough.")
			Check(f, "Players may vote: Next Map", "mp_vote_map_enabled", "The Server tab's Next Map vote.")
			Check(f, "Players may vote: Restart Round", "mp_vote_reset_enabled", "The Server tab's Restart Round vote.")
			Check(f, "Players may vote: Scramble Teams", "mp_vote_scramble_enabled", "The Server tab's Scramble Teams vote.")
			Check(f, "Players may vote: Help Other Team", "mp_vote_support_enabled", "The Server tab's Help Other Team vote.")
			Check(f, "Players may vote: Soldier Difficulty", "mp_vote_difficulty_enabled", "The Server tab's Soldier Difficulty vote.")
			Slider(f, "Vote length (seconds)", "mp_vote_duration", "How long a vote runs.")
			Slider(f, "Wait between a player's votes (seconds)", "mp_vote_cooldown", "After calling a vote, a player waits this long to call another.")
		end,
	},
	{
		title = "Bonus rounds",
		privilege = Permissions.RULES,
		build = function(f)
			Check(f, "Sudden death after a stalemate", "mp_stalemate_enable", "No respawns; the last team standing wins.")
			Slider(f, "Sudden death length (seconds)", "mp_stalemate_timelimit", "How long sudden death lasts before a draw.")
			Slider(f, "Frags to win a round", "mp_round_fraglimit", "A team wins the round at this many kills. 0: off.")
			Slider(f, "Money to win a round", "mp_round_cashlimit", "A team wins the round when it earns this much. 0: off.")
			Slider(f, "Bonus time after a win (seconds)", "mp_bonusroundtime", "The winners hunt the losers before the next round.")
		end,
	},
	{
		title = "Teams and scrambles",
		privilege = Permissions.RULES,
		build = function(f)
			Check(f, "Balance teams automatically", "mp_autoteambalance", "Moves players when one team has too many.")
			Slider(f, "Most extra players on one team", "mp_teams_unbalance_limit", "0: never balance.")
			Check(f, "Scramble after a lopsided match", "mp_scrambleteams_auto", "Scrambles when one team wins by too much.")
			Slider(f, "Win margin that triggers a scramble", "mp_scrambleteams_auto_windifference", "In rounds.")
			Check(f, "Allow spectators", "mp_allowspectators", "Players may join Spectator.")
		end,
	},
	{
		title = "Respawns",
		privilege = Permissions.RULES,
		build = function(f)
			Slider(f, "Respawn wave (seconds)", "mp_respawnwavetime", "How often dead players come back.")
		end,
	},
}

local MATCH = {
	{
		title = "Round",
		privilege = Permissions.ROUND,
		build = function(f)
			Buttons(f, {
				{
					label = "Start Sudden Death",
					command = { "mp_round_suddendeath" },
					help = "Ends the round in a bonus round: no respawns, the last team standing wins.",
				},
				{
					label = "Restart to Pregame",
					command = { "mp_round_restart" },
					help = "Starts the round over. Money and weapons are kept.",
				},
			})
			Slider(f, "Reward the round's winners ($)", "mp_round_reward_money", "Money for every player on the team that wins a round. 0: none.")
			f:Help("Servers and admin mods can add their own round rewards (hook WSRoundRewards).")
		end,
	},
	{
		title = "Match",
		privilege = Permissions.MATCH,
		build = function(f)
			Buttons(f, {
				{
					label = "Begin Game",
					command = { "mp_gameplay_begin" },
					help = "Counts down to Gameplay mode. Money and weapons reset.",
				},
				{
					label = "Stop Game",
					command = { "mp_gameplay_stop" },
					help = "Back to Sandbox mode.",
				},
				{
					label = "RED Wins the Match",
					command = { "mp_match_forcewin", "red" },
					help = "Ends the match now, won by RED.",
				},
				{
					label = "BLU Wins the Match",
					command = { "mp_match_forcewin", "blue" },
					help = "Ends the match now, won by BLU.",
				},
				{
					label = "Decide by Sudden Death",
					command = { "mp_match_forcewin", "sudden" },
					help = "Sudden death now; its winner wins the match.",
				},
			})
			local reward = f:Button("Reward the Match's Winners (coming later)")
			reward:SetEnabled(false)
			Tip(reward, "Match rewards come later. Admin mods can add their own.", nil)
		end,
	},
	{
		title = "Gameplay tampering",
		privilege = Permissions.TAMPER,
		build = function(f)
			Buttons(f, {
				{
					label = "Advance the Cart",
					command = { "mp_cart_advance" },
					help = "Every payload cart to its next checkpoint.",
				},
				{
					label = "Retract the Cart",
					command = { "mp_cart_retract" },
					help = "Every payload cart back to its previous checkpoint.",
				},
				{
					label = "Add 1 Minute",
					command = { "mp_round_timer_add", "60" },
					help = "One minute more on the round clock.",
				},
				{
					label = "Take 1 Minute",
					command = { "mp_round_timer_add", "-60" },
					help = "One minute off the round clock.",
				},
				{
					label = "Pause or Resume the Clock",
					command = { "mp_round_timer_pause" },
					help = "Holds the round clock, or lets it run again.",
				},
				{
					label = "Respawn Everyone",
					command = { "mp_respawn_all" },
					help = "Every dead player comes back now.",
				},
				{
					label = "Use the Map's Respawn Times",
					command = { "mp_respawn_maptimes" },
					help = "Respawn waves as the map set them.",
				},
			})
			f:Help("Control points: hold C and right-click a point.")
		end,
	},
	{
		title = "NextSoldier",
		privilege = Permissions.NEXTSOLDIER,
		build = function(f)
			Buttons(f, {
				{
					label = "Start the AI War",
					command = { "mp_aiwar_start" },
					help = "Soldiers join both teams.",
				},
				{
					label = "End the AI War",
					command = { "mp_aiwar_end" },
					help = "The soldiers leave.",
				},
			})
			Check(f, "Pause the soldiers", "ns_soldiers_paused", "Soldiers stand still and hold fire.")
			Slider(f, "Soldiers per side", "mp_aiwar_team_size", "-1: the slot list decides.")
			Check(f, "Size squads automatically", "ns_squads_auto_enabled", "The war groups its soldiers into squads itself.")
			Slider(f, "Fewest squads a team", "ns_squads_min", "")
			Slider(f, "Most squads a team", "ns_squads_max", "")
			f:Help("Debugging: Utilities > Sandcastle > Debug NextSoldier.")
		end,
	},
}

hook.Add("PopulateToolMenu", "ws_admin_panels", function()
	spawnmenu.AddToolMenuOption("Options", "Admin", "ws_gameplay_rules", "Gameplay Rules", "", "",
		function(panel) Build(panel, RULES, "WSGameplayRulesPanel") end)
	spawnmenu.AddToolMenuOption("Utilities", "Admin", "ws_match_control", "Match Control", "", "",
		function(panel) Build(panel, MATCH, "WSMatchControlPanel") end)
end)
