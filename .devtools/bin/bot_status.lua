-- The AI war's bot soldiers at a glance (features/aiwar/sv_bots.lua), on
-- the dev server: dt lua -f .devtools/bin/bot_status.lua. Defines the global
-- BotStatus() and returns its report: each bot's team, life, enlistment,
-- role, weapon, distance to its move target, speed, contact, whether it may
-- fire, kills and deaths, health.
BotStatus = function()
	local C = WS.Feature("aiwar")
	local lines = {}
	for bot in pairs(C.bots) do
		if IsValid(bot) then
			local entry = C.soldiers[bot]
			local s = entry and entry.soldier
			local member = C.war and C.war:Member(bot)
			local wep = bot:GetActiveWeapon()
			local enemy = s and s:Enemy()
			local target = s and s.moveTarget
			lines[#lines + 1] = string.format("%-14s team %d %s %s role %-7s wep %-16s target %5s spd %3.0f contact %-22s fire %-5s K/D %d/%d hp %d",
				bot:Nick(), bot:Team(), bot:Alive() and "alive" or "dead ", entry and "enlisted" or "free    ",
				tostring(member and member.role), IsValid(wep) and wep:GetClass() or "-",
				target and string.format("%.0f", bot:GetPos():Distance(Vector(target.x, target.y, target.z))) or "-",
				bot:GetVelocity():Length2D(), enemy and tostring(enemy) or "-", tostring(s and s.mayFire), bot:Frags(), bot:Deaths(), bot:Health())
		end
	end
	table.sort(lines)
	local npcs = 0
	for ent in pairs(C.soldiers) do
		if IsValid(ent) and not ent:IsPlayer() then npcs = npcs + 1 end
	end
	return string.format("%s %s, paused %s, NPC soldiers %d, players %d\n", game.GetMap(), table.KeyFromValue(WS.STATE, WS.State()) or "?",
		tostring(C.paused), npcs, #player.GetAll()) .. table.concat(lines, "\n")
end
return BotStatus()
