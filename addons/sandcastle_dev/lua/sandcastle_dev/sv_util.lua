-- The workbench's shared pieces: who may use it, console commands that
-- print their function's table as JSON, and errors that say what to do.

-- An error the caller can act on, raised at its caller's line.
function dev.Fail(message)
	error("dev: " .. message, 3)
end

-- The server console and RCON (no player) or a superadmin.
function dev.Allowed(ply)
	return not IsValid(ply) or ply:IsSuperAdmin()
end

local function Reply(ply, text)
	if IsValid(ply) then
		for line in string.gmatch(text, "[^\n]+") do ply:PrintMessage(HUD_PRINTCONSOLE, line) end
	else
		print(text)
	end
end

-- A console command running fn(args, ply), which returns a table; the
-- command prints it as JSON, or the error. usage is shown with help.
function dev.Command(name, fn, help)
	concommand.Add(name, function(ply, _, args)
		if not dev.Allowed(ply) then return Reply(ply, name .. ": the dev workbench is for the console and superadmins") end
		local ok, result = pcall(fn, args, ply)
		if not ok then return Reply(ply, name .. ": " .. tostring(result)) end
		Reply(ply, util.TableToJSON(result or {}, true))
	end, nil, help)
end

-- A player or entity as text a trace can hold: class, index and name.
function dev.Describe(ent)
	if not IsValid(ent) then return tostring(ent) end
	local name = ent:GetName()
	if ent:IsPlayer() then name = ent:Nick() end
	return string.format("%s#%d%s", ent:GetClass(), ent:EntIndex(), name ~= "" and ("(" .. name .. ")") or "")
end

function dev.Rounds()
	local rounds = WS and WS.Feature("rounds")
	if not rounds then dev.Fail("the rounds feature is not loaded; is the gamemode up?") end
	return rounds
end

-- fn once the gamemode and the map's entities are up: now when they are
-- (a reload of the workbench), else at InitPostEntity.
function dev.WhenReady(id, fn)
	if WS and WS.gamemodeLoaded and #ents.GetAll() > 1 then
		fn()
		return
	end
	hook.Add("InitPostEntity", "sandcastle_dev_" .. id, fn)
end
