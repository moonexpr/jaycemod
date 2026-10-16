-- The Utilities menu's server settings (foundation.settings): on a
-- dedicated server a client cannot set a server's convar, so its controls
-- send ws_server_set, which the server runs for a holder of the rules
-- privilege.
local Settings = WS.require("foundation.settings")
local Permissions = WS.require("foundation.permissions")
local COMMAND = "ws_server_set"
local SEND_AFTER = 0.3 -- seconds a slider rests before its value is sent

if SERVER then
	concommand.Add(COMMAND, function(ply, _, args)
		if not WS.Can(ply, Permissions.RULES) then
			ply:ChatPrint("Settings: you may not change the server's settings")
			return
		end
		local name = args[1] or ""
		local value, why = Settings.Parse(name, args[2] or "")
		if not value then
			if IsValid(ply) then ply:ChatPrint("Settings: " .. why) else print("Settings: " .. why) end
			return
		end
		RunConsoleCommand(name, value)
	end, nil, "Set a server setting the Utilities menu offers: " .. COMMAND .. " <convar> <value>")
	return
end

function WS.SetServerSetting(name, value)
	RunConsoleCommand(COMMAND, name, tostring(value))
end

-- A checkbox over a server setting of 0 or 1, following the server's value
-- (but for a moment after a click, while the server takes it).
local FOLLOW_AFTER = 1

function WS.ServerCheckBox(panel, label, name)
	local box = panel:CheckBox(label)
	box:SetChecked(GetConVar(name):GetBool())
	box.sentAt = -FOLLOW_AFTER
	function box:OnChange(on)
		self.sentAt = RealTime()
		WS.SetServerSetting(name, on and 1 or 0)
	end
	local think = box.Think
	function box:Think()
		if think then think(self) end
		if RealTime() - self.sentAt < FOLLOW_AFTER then return end
		local on = GetConVar(name):GetBool()
		if self:GetChecked() ~= on then self:SetChecked(on) end
	end
	return box
end

-- A slider over a server setting, over its range, showing the server's
-- value; it sends once the player stops dragging.
function WS.ServerSlider(panel, label, name)
	local setting = Settings.SETTINGS[name]
	local slider = panel:NumSlider(label, nil, setting.min, setting.max, 0)
	slider:SetValue(GetConVar(name):GetFloat())
	function slider:OnValueChanged(value)
		timer.Create(COMMAND .. "_" .. name, SEND_AFTER, 1, function() WS.SetServerSetting(name, value) end)
	end
	return slider
end
