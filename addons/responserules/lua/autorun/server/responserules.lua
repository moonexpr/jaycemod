-- The response rules service: TF2's response rules (require "responserules")
-- read from talker script files (require "responserules_script") under
-- scripts/responserules/ on the GAME path (this addon's own, and any other
-- addon's of the same path), starting from response_rules.txt and what it
-- #includes. Every speaker shares one memory of the groups, as TF2's players
-- do; a reload starts it over.
--
--   ResponseRules:Speaker() -> a speaker, its own contexts
--   ResponseRules:Speak(speaker, concept, criteria, now, label)
--     -> { rule, response = { kind, value }, delay, soundLevel } or nil
--
-- responserules_reload reads the files again (a refused file leaves the
-- rules as they were and says why); responserules_print says what is
-- loaded; responserules_debug 1 prints each line said, with its rule.
-- GMod's require returns nothing: each module is the global module() made
require("responserules")
require("responserules_script")
local Response, Script = responserules, responserules_script

local SCRIPTS = "scripts/"
local ROOT = "responserules/response_rules.txt"

local DEBUG = CreateConVar("responserules_debug", "0", { FCVAR_ARCHIVE },
	"1: print each line a speaker says by the response rules, and the rule that chose it", 0, 1)

ResponseRules = ResponseRules or {}
local Service = ResponseRules

-- The rules from the files, and the files read; or an error naming the
-- file and line refused.
local function Build()
	local files = {}
	local defs = Script.Load(ROOT, function(path)
		files[#files + 1] = path
		return file.Read(SCRIPTS .. path, "GAME")
	end)
	return Response.System(defs), files
end

function Service:Load()
	self.system, self.files = Build()
	self.memory = Response.Memory()
end

-- A speaker: its own contexts (the rules' ApplyContext).
function Service:Speaker()
	return { contexts = Response.Contexts() }
end

-- The speaker speaks concept with its criteria set: what it says, or nil.
-- label names the speaker in the debug print.
function Service:Speak(speaker, concept, criteria, now, label)
	local said = self.system:Speak({ memory = self.memory, contexts = speaker.contexts }, concept, criteria, math.random, now)
	if said and DEBUG:GetBool() then
		print(string.format("[responserules] %s, %s: %s %s (%s)", label, concept, said.response.kind, said.response.value, said.rule))
	end
	return said
end

function Service:Describe()
	local rules, groups = self.system:Counts()
	return string.format("%d rules, %d groups, from %s", rules, groups, table.concat(self.files, ", "))
end

local function Tell(ply, text)
	print(text)
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, text) end
end

local function Admin(ply) return not IsValid(ply) or ply:IsSuperAdmin() end

concommand.Add("responserules_reload", function(ply)
	if not Admin(ply) then return end
	local ok, system, files = pcall(Build)
	if not ok then
		Tell(ply, "responserules_reload: refused, the rules stay as they were: " .. tostring(system))
		return
	end
	Service.system, Service.files, Service.memory = system, files, Response.Memory()
	Tell(ply, "responserules_reload: " .. Service:Describe())
end, nil, "Read the response rules (scripts/responserules/) again")

concommand.Add("responserules_print", function(ply)
	Tell(ply, "response rules: " .. Service:Describe())
end, nil, "Say what response rules are loaded, and from which files")

Service:Load()
