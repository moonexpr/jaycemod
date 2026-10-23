-- The C menu's bar (GMod's menubar): Sandcastle's Economy and Gameplay
-- menus, shown only to holders of their privileges (superadmins by
-- default), and GMod's own NPCs and Server menus made to work on a
-- dedicated server. GMod's options there set the convar on the client,
-- which works only for a listen server's host; Sandcastle's send it to the
-- server (ws_server_set, ws/sh_settings.lua), which checks the
-- server_options privilege. Every option follows the server's value.
local Settings = WS.require("ws.settings")
local Permissions = WS.require("games.system.permissions")

local NOT_LOADED = "This map has not loaded what this switches."
local NOT_ALLOWED = "You may not change this."

local PROXIED = {}
for _, name in ipairs(Settings.PROXIED) do PROXIED[name] = true end

local function Allowed(name)
	return Settings.Allowed(name, function(privilege) return WS.Can(LocalPlayer(), privilege) == true end)
end

-- An option follows the server's value of its setting and sets it there;
-- on is the value that checks it ("1", or "0" for a "Disable" switch).
local function Follow(option, name, on)
	option.Think = function(self)
		local value = WS.ServerSetting(name)
		local allowed = IsValid(LocalPlayer()) and Allowed(name)
		self:SetEnabled(value ~= nil and allowed)
		self:SetTooltip(value == nil and NOT_LOADED or (not allowed and NOT_ALLOWED or nil))
		if value ~= nil and (self._NextThink or 0) <= RealTime() then self:SetChecked(tostring(value) == on) end
	end
	option.OnChecked = function(self, checked)
		self._NextThink = RealTime() + 1
		local off = on == "1" and "0" or "1"
		WS.SetServerSetting(name, checked and on or off)
	end
end

local MENUS = {
	{
		label = "Economy",
		privilege = Permissions.ECONOMY,
		options = {
			{
				text = "Allow Deficit Spending",
				name = "mp_economy_credit_enabled",
				on = "1",
			},
			{
				text = "Disable Economy",
				name = "mp_economy_enabled",
				on = "0",
			},
		},
	},
	{
		label = "Gameplay",
		privilege = Permissions.GAMEPLAY,
		options = {
			{
				text = "Disable Gameplay Tampering",
				name = "mp_tampering_enabled",
				on = "0",
			},
			{
				text = "Disable NextSoldier",
				name = "ns_soldiers_enabled",
				on = "0",
			},
			{ spacer = true },
			{
				text = "Disable Weapon Criticals",
				name = "tf_weapon_criticals",
				on = "0",
			},
			{
				text = "Disable Random Spread",
				name = "tf_use_fixed_weaponspreads",
				on = "1",
			},
			{ spacer = true },
			{
				text = "Disable Sandbox Mode",
				name = "sv_gameplay_disable_sandbox",
				on = "1",
			},
			{
				text = "Force Gameplay Mode",
				name = "sv_gameplay_enabled",
				on = "1",
			},
		},
	},
}

local function AddMenus(bar)
	for _, def in ipairs(MENUS) do
		local menu = bar:AddMenu(def.label)
		local children = bar:GetChildren()
		local button = children[#children]
		button.Think = function(self)
			local show = IsValid(LocalPlayer()) and WS.Can(LocalPlayer(), def.privilege) == true
			if self:IsVisible() ~= show then
				self:SetVisible(show)
				bar:InvalidateLayout()
			end
		end
		for _, o in ipairs(def.options) do
			if o.spacer then
				menu:AddSpacer()
			else
				Follow(menu:AddCVar(o.text, o.name, o.on, o.on == "1" and "0" or "1"), o.name, o.on)
			end
		end
	end
end

-- GMod's own NPCs and Server options, made to set the server's convar.
local function ProxyStock(bar)
	for _, menu in pairs(bar.Menus) do
		if IsValid(menu) then
			for _, option in ipairs(menu:GetCanvas():GetChildren()) do
				local name = option.GetConVar and option:GetConVar()
				if name and PROXIED[name] then Follow(option, name, option:GetValueOn()) end
			end
		end
	end
end

hook.Add("PopulateMenuBar", "ws_menubar", function(bar)
	AddMenus(bar)
	-- GMod's own menus may be added after this hook runs: proxy them once all have.
	timer.Simple(0, function()
		if IsValid(bar) then ProxyStock(bar) end
	end)
end)
