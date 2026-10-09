-- The AI war's soldiers in the kill feed (foundation.kill_feed): each class
-- named by its display name, not "#wetsand_drg_rebel", and drawn in its
-- side's team colour.
local Feed = WETSAND.require("foundation.kill_feed")

-- The soldiers' entities register after the gamemode, so their names are
-- read once every entity has.
hook.Add("InitPostEntity", "wetsand_kill_feed_names", function()
	for class in pairs(Feed.SOLDIERS) do
		local stored = scripted_ents.GetStored(class)
		if stored then language.Add(class, stored.t.PrintName) end
	end
end)

function GM:AddDeathNotice(attacker, attackerTeam, inflictor, victim, victimTeam)
	return self.BaseClass.AddDeathNotice(self, attacker, Feed.Team(attacker, attackerTeam), inflictor,
		victim, Feed.Team(victim, victimTeam))
end
