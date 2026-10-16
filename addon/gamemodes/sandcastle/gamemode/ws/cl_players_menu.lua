-- The scoreboard's player menu (ws/sh_players_menu.lua): right-click a
-- player's row. Everyone may copy a player's Steam3 ID, report them, give
-- them money and mute them; holders of the players privilege may also kick,
-- ban and grant money. The server answers each request with
-- players_menu_said, shown as a notice.
local Reports = WS.require("foundation.reports")
local Economy = WS.require("foundation.economy")
local Permissions = WS.require("foundation.permissions")
local E = WS.Events

local SAID_SECONDS = 4
local REFUSED_SOUND = "buttons/button10.wav"
local AMOUNT_MAX = 2 ^ 24 - 1 -- money_transfer's and admin_player's 24 bits

-- [U:1:<account id>], Steam's third ID format.
local function Steam3(ply)
	return "[U:1:" .. ply:AccountID() .. "]"
end

-- Asks for a whole number of dollars, then sends it.
local function AskAmount(title, send)
	Derma_StringRequest(title, "How many dollars?", "", function(text)
		local amount = tonumber(text)
		if amount and amount >= 1 and amount <= AMOUNT_MAX and amount == math.floor(amount) then
			send(amount)
			return
		end
		notification.AddLegacy("Give a whole number of dollars.", NOTIFY_ERROR, SAID_SECONDS)
	end)
end

local function Submenu(menu, label, icon)
	local sub, option = menu:AddSubMenu(label)
	option:SetIcon(icon)
	return sub
end

local function Amounts(menu, amounts, title, send)
	for _, amount in ipairs(amounts) do
		menu:AddOption(Economy.Format(amount), function() send(amount) end)
	end
	menu:AddOption("Other amount…", function() AskAmount(title, send) end)
end

local function AdminPart(menu, target, me)
	local function Act(action, value)
		E.Request("admin_player", {
			target = target,
			action = action,
			value = value,
		})
	end
	menu:AddSpacer()
	if target ~= me then
		menu:AddOption("Kick", function() Act(WS.ADMIN_KICK, 0) end):SetIcon("icon16/door_out.png")
		local bans = Submenu(menu, "Ban", "icon16/delete.png")
		for i, ban in ipairs(WS.PLAYERS_MENU_BANS) do
			bans:AddOption(ban.label, function() Act(WS.ADMIN_BAN, i - 1) end)
		end
	end
	Amounts(Submenu(menu, "Give Money", "icon16/coins_add.png"), WS.PLAYERS_MENU_GRANTS, "Give Money",
		function(amount) Act(WS.ADMIN_GRANT, amount) end)
end

function WS.OpenPlayerMenu(target)
	local me = LocalPlayer()
	local menu = DermaMenu()
	if not target:IsBot() then
		menu:AddOption("Copy Steam3 ID", function()
			SetClipboardText(Steam3(target))
			notification.AddLegacy("Copied " .. Steam3(target) .. ".", NOTIFY_GENERIC, SAID_SECONDS)
		end):SetIcon("icon16/page_copy.png")
	end
	if target ~= me then
		local report = Submenu(menu, "Report", "icon16/flag_red.png")
		for i, reason in ipairs(Reports.REASONS) do
			report:AddOption(WS.REPORT_LABELS[reason], function()
				E.Request("player_report", {
					target = target,
					reason = i - 1,
				})
			end)
		end
		Amounts(Submenu(menu, "Transfer Money", "icon16/coins.png"), WS.PLAYERS_MENU_GIFTS, "Transfer Money",
			function(amount)
				E.Request("money_transfer", {
					target = target,
					amount = amount,
				})
			end)
		menu:AddOption(target:IsMuted() and "Unmute" or "Mute", function() target:SetMuted(not target:IsMuted()) end)
			:SetIcon(target:IsMuted() and "icon16/sound.png" or "icon16/sound_mute.png")
	end
	if WS.Can(me, Permissions.PLAYERS) then AdminPart(menu, target, me) end
	menu:Open()
end

E.Listen("players_menu_said", "ws_players_menu", function(fields)
	notification.AddLegacy(fields.text, fields.refused and NOTIFY_ERROR or NOTIFY_GENERIC, SAID_SECONDS)
	if fields.refused then surface.PlaySound(REFUSED_SOUND) end
end)
