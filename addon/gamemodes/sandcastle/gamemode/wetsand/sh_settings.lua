-- The Utilities menu's server settings (foundation.settings): on a
-- dedicated server a client cannot set a server's convar, so its controls
-- send wetsand_server_set, which the server runs for an admin.
local Settings = WETSAND.require("foundation.settings")
local COMMAND = "wetsand_server_set"
local SEND_AFTER = 0.3 -- seconds a slider rests before its value is sent

if SERVER then
	concommand.Add(COMMAND, function(ply, _, args)
		if IsValid(ply) and not ply:IsAdmin() then
			ply:ChatPrint("Settings: only admins may change the server's settings")
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

function WETSAND.SetServerSetting(name, value)
	RunConsoleCommand(COMMAND, name, tostring(value))
end

-- A checkbox over a server setting of 0 or 1, following the server's value
-- (but for a moment after a click, while the server takes it).
local FOLLOW_AFTER = 1

function WETSAND.ServerCheckBox(panel, label, name)
	local box = panel:CheckBox(label)
	box:SetChecked(GetConVar(name):GetBool())
	box.sentAt = -FOLLOW_AFTER
	function box:OnChange(on)
		self.sentAt = RealTime()
		WETSAND.SetServerSetting(name, on and 1 or 0)
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
function WETSAND.ServerSlider(panel, label, name)
	local setting = Settings.SETTINGS[name]
	local slider = panel:NumSlider(label, nil, setting.min, setting.max, 0)
	slider:SetValue(GetConVar(name):GetFloat())
	function slider:OnValueChanged(value)
		timer.Create(COMMAND .. "_" .. name, SEND_AFTER, 1, function() WETSAND.SetServerSetting(name, value) end)
	end
	return slider
end
