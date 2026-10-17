-- The local player's loadout (foundation.loadout) as the server last told
-- it (loadout_state, ws/sv_loadout.lua); the catalog's starters until then.
-- WSLoadoutChanged tells the spawn menu's Player and Inventory tabs to
-- redraw. Requests are transactions (WS.LoadoutRequest); a declined or
-- failed one shows as a notice.
local Loadout = WS.require("foundation.loadout")
local Transaction = WS.require("foundation.core.transaction")
local E = WS.Events

local REFUSED_SECONDS = 4
local REFUSED_SOUND = "buttons/button10.wav"
local FAILED_TEXT = "That did not go through. Try again."

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

local function Notice(text)
	notification.AddLegacy(text, NOTIFY_ERROR, REFUSED_SECONDS)
	surface.PlaySound(REFUSED_SOUND)
end

-- A loadout request (loadout_buy, _buy_into, _equip, _clear) as a
-- transaction: a decline shows its refusal, a failure says it did not go
-- through; a commit shows itself, as loadout_state arrives.
function WS.LoadoutRequest(name, fields)
	E.Transact(name, fields):OnSettle(function(tx)
		if tx:State() == Transaction.DECLINED then
			Notice(Transaction.Message(tx:Refusal()))
		elseif tx:State() == Transaction.FAILED then
			Notice(FAILED_TEXT)
		end
	end)
end
