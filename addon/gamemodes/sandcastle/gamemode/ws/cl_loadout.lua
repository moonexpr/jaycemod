-- The local player's loadout (foundation.loadout) as the server last told
-- it (loadout_state, ws/sv_loadout.lua); the catalog's starters until then.
-- WSLoadoutChanged tells the spawn menu's Player and Inventory tabs to
-- redraw; a refused request shows as a notice.
local Loadout = WS.require("foundation.loadout")
local E = WS.Events

local REFUSED_SECONDS = 4
local REFUSED_SOUND = "buttons/button10.wav"

local ICON_FALLBACK = "vgui/avatar_default"

-- A catalog weapon's spawn icon, size pixels square; clicks pass through it.
function WS.WeaponIcon(parent, weapon, size)
	local icon = vgui.Create("DImage", parent)
	icon:SetImage("entities/" .. weapon.class .. ".png", ICON_FALLBACK)
	icon:SetSize(size, size)
	icon:SetMouseInputEnabled(false)
	return icon
end

local loadout = Loadout.Starting(WS.LoadoutCatalog)

function WS.LocalLoadout()
	return loadout
end

E.Listen("loadout_state", "ws_loadout", function(fields)
	loadout = Loadout.FromState(WS.LoadoutCatalog, fields.owned, fields.equipped)
	hook.Run("WSLoadoutChanged", loadout)
end)

-- class -> { damage, pellets }, for the Store's tooltips.
WS.WeaponStats = WS.WeaponStats or {}

E.Listen("loadout_stats", "ws_loadout", function(fields)
	WS.WeaponStats = {}
	for _, s in ipairs(fields.weapons) do
		WS.WeaponStats[s.class] = {
			damage = s.damage,
			pellets = s.pellets,
		}
	end
	hook.Run("WSLoadoutChanged", loadout)
end)

E.Listen("loadout_refused", "ws_loadout", function(fields)
	notification.AddLegacy(fields.reason, NOTIFY_ERROR, REFUSED_SECONDS)
	surface.PlaySound(REFUSED_SOUND)
end)
