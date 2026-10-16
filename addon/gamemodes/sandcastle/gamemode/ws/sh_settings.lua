-- The menus' server settings (foundation.settings): on a dedicated server a
-- client cannot set a server's convar, so a menu's control sends
-- ws_server_set, which the server runs for a holder of that setting's
-- privilege. Many of these convars are not replicated, so the server keeps
-- clients told of every setting's value (settings_state: all of them when a
-- client asks, then each as it changes); a setting whose convar this map
-- has not created (its feature not loaded) is left out and its control
-- disabled.
local Settings = WS.require("foundation.settings")
local E = WS.Events
local COMMAND = "ws_server_set"
local SEND_AFTER = 0.3 -- seconds a slider rests before its value is sent
local VALUE_BITS = 32
local COUNT_BITS = 8

E.Define("settings_state", {
	values = E.List(E.Record({
		name = E.String(),
		value = E.Int(VALUE_BITS),
	}), COUNT_BITS),
})

E.Define("settings_request", {}, {
	clientSendable = true,
	rate = {
		count = 4,
		seconds = 5,
	},
})

if SERVER then
	local function Tell(ply, text)
		if IsValid(ply) then ply:ChatPrint("Settings: " .. text) else print("Settings: " .. text) end
	end

	concommand.Add(COMMAND, function(ply, _, args)
		local name = args[1] or ""
		if IsValid(ply) and not Settings.Allowed(name, function(privilege) return WS.Can(ply, privilege) == true end) then
			return Tell(ply, "you may not change " .. name)
		end
		local value, why = Settings.Parse(name, args[2] or "")
		if not value then return Tell(ply, why) end
		RunConsoleCommand(name, value)
	end, nil, "Set a server setting the menus offer: " .. COMMAND .. " <convar> <value>")

	local watched = {}

	-- Every setting whose convar exists, and a watch on each new one, so a
	-- change reaches every client.
	local function Snapshot()
		local values = {}
		for name in SortedPairs(Settings.SETTINGS) do
			local convar = GetConVar(name)
			if convar then
				values[#values + 1] = {
					name = name,
					value = convar:GetInt(),
				}
				if not watched[name] then
					watched[name] = true
					cvars.AddChangeCallback(name, function(_, _, new)
						E.Fire("settings_state", {
							values = {
								{
									name = name,
									value = math.floor(tonumber(new) or 0),
								},
							},
						})
					end, "ws_settings")
				end
			end
		end
		return values
	end

	E.Listen("settings_request", "ws_settings", function(_, ply)
		E.Fire("settings_state", { values = Snapshot() }, ply)
	end)
	E.Listen("client_ready", "ws_settings", function(_, ply)
		E.Fire("settings_state", { values = Snapshot() }, ply)
	end)
	return
end

-- name -> the server's value, as last heard.
WS.ServerSettings = WS.ServerSettings or {}

E.Listen("settings_state", "ws_settings", function(fields)
	for _, v in ipairs(fields.values) do WS.ServerSettings[v.name] = v.value end
	hook.Run("WSServerSettingsChanged")
end)

-- Asks for every setting's value; a panel opening does, since a feature may
-- have created convars since the client loaded.
function WS.RequestServerSettings()
	E.Request("settings_request", {})
end

function WS.SetServerSetting(name, value)
	RunConsoleCommand(COMMAND, name, tostring(value))
end

-- The server's value of a setting, or nil while this map has not created it.
function WS.ServerSetting(name)
	return WS.ServerSettings[name]
end

-- A checkbox over a server setting of 0 or 1, following the server's value
-- (but for a moment after a click, while the server takes it).
local FOLLOW_AFTER = 1

function WS.ServerCheckBox(panel, label, name)
	local box = panel:CheckBox(label)
	box.sentAt = -FOLLOW_AFTER
	function box:OnChange(on)
		self.sentAt = RealTime()
		WS.SetServerSetting(name, on and 1 or 0)
	end
	local think = box.Think
	function box:Think()
		if think then think(self) end
		local value = WS.ServerSetting(name)
		self:SetEnabled(value ~= nil)
		if value == nil or RealTime() - self.sentAt < FOLLOW_AFTER then return end
		if self:GetChecked() ~= (value ~= 0) then self:SetChecked(value ~= 0) end
	end
	return box
end

-- A slider over a server setting, over its range, showing the server's
-- value; it sends once the player stops dragging.
function WS.ServerSlider(panel, label, name)
	local setting = Settings.SETTINGS[name]
	local slider = panel:NumSlider(label, nil, setting.min, setting.max, 0)
	slider.shown = nil
	function slider:OnValueChanged(value)
		if self.following then return end
		timer.Create(COMMAND .. "_" .. name, SEND_AFTER, 1, function() WS.SetServerSetting(name, math.Round(value)) end)
	end
	local think = slider.Think
	function slider:Think()
		if think then think(self) end
		local value = WS.ServerSetting(name)
		self:SetEnabled(value ~= nil)
		if value == nil or value == self.shown or self:IsEditing() then return end
		self.shown = value
		self.following = true
		self:SetValue(value)
		self.following = false
	end
	return slider
end
