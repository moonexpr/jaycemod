-- GLua Best Practices - compact reference for AI agents
-- A condensed version of the full guide (SKILL.md / README.md).
-- Every example below is valid per the guidelines. Use them as your template.

-- tabs for indentation, never spaces
if condition then
	doThing()
end

-- spaces around operators: a + b, not a+b
local sum = a + b

-- no spaces inside parens/braces: f(x), {5, {}}; empty pairs stay tight
local x = (3 * myFunc()) + 5
local data = {5, {}}
myFunc(10, {3, 5})

-- no spaces inside square brackets
local val = tab[5] + tab[3]

-- comments: single space after -- and before inline comments
-- This is a comment
local a = 3 -- inline comment

-- newlines: 1 blank line between blocks; never more than 1 consecutive blank line;
-- don't add restating header comments (-- Section name --)
-- one blank line before return unless the block is a single line;
-- no blank line needed in guard-clause chains (consecutive early returns)
local function test()
	local a = 3

	return a
end

-- no GMod operators (&& || ! !=): use and, or, not, ~=
if a ~= b and not b then end

-- no GMod comments (/* */ //): use -- and --[[ ]]
--[[
	Multiline comment
]]

-- continue is fine for simple filters (GMod extension).
-- explicit comparisons preferred: == false / ~= true for boolean values;
-- not x only when the value may be nil
for _, item in ipairs(tab) do
	if IsValid(item) == false then continue end
	item:Process()
end

-- naming: camelCase locals, SCREAMING_SNAKE constants, PascalCase globals
-- constants = fixed by design (literals, config, lookup tables, cached objects);
-- mutable state (counters, accumulators) is regular locals
local myVariable = 10
local MAXIMUM_VALUE = 25
GlobalVariable = 10

-- object methods: PascalCase
function classTable:SetHealth(amount)
end

-- table keys via dot notation: only a-z A-Z 0-9, '.' and '_', no leading digits;
-- bracket-only keys and integer array indices are unrestricted
myTable.myValue = 4 -- good
myTable["my-value"] = 4 -- bad: requires brackets and quotes

-- throwaway values use _
for _, ply in ipairs(player.GetAll()) do
end

-- hooks: orgName/productName/eventPurpose - namespaced paths, slashes and hyphens,
-- no event name in the identifier
hook.Add("PlayerInitialSpawn", "gmod.one/myaddon/track-players", function(ply) end)

-- net messages: same namespaced style
net.Start("gmod.one/myaddon/player-count")

-- util.AddNetworkString: server-side only, at the top of the file / init,
-- never inside hooks or dynamic functions
if SERVER then
	util.AddNetworkString("gmod.one/myaddon/player-count")
end

-- realm separation: never do `if SERVER then return end` at the top of a file.
-- Use file placement instead: autorun/*.lua runs on both realms,
-- autorun/server/* only server, autorun/client/* only client.
-- Server-only files must never be sent to clients (no AddCSLuaFile for them).

-- hot code (Think, hooks, render loops): localize frequently used globals
-- at the top of the file to skip global table lookups
-- (LuaJIT caps upvalues per function at 60 - don't overdo it)
local IsValid = IsValid
local RealTime = RealTime

-- quotes: always double, one style for the whole codebase, no mixing;
-- escape inner ones with backslashes
myFunc("hello ", "world!")
local warning = "say \"hi\" instead of 'hi'"

-- no redundant parentheses around conditions
if x == y then end
-- acceptable when precedence is clearer:
local amount = (quantity * modifier) + baseAmount

-- multiline tables: elements on own lines, indented once, closing bracket alone
local tbl = {
	v1 = c,
	v2 = d,
	v3 = k,
}

-- multiline table as an argument: elements on new lines, closing bracket alone
surface.CreateFont("MyFont", {
	font = "Arial",
	size = 13,
	weight = 500,
})

-- short nested table/argument passed compactly
myFunc("First arg", secondArg, {
	v1 = firstValue,
	v2 = secondValue,
})

-- multiline function calls: same as tables, but no trailing comma -
-- a comma before ) is a syntax error (legal in table constructors only)
myFunc(
	"First arg",
	secondArg,
	{third, arg}
)

-- return early
local function test()
	if not myThing then return end

	-- do the real work
end

-- no magic numbers: pull them into named variables
-- applies to bare literals in logic; config data in named tables is fine
local maxX = 25

if x > maxX then end

-- complex expressions: multiple named steps
local widthModifier = amount * damageMult
local age = 1 - lifetime / duration
local width = widthModifier * age

-- never use semicolons
local a = 3
print(a)

-- use existing constants instead of literals
local circumference = radius * math.pi * 2
local radians = math.rad(deg)

-- long conditions: pull into named variables
local entValid = IsValid(ent)
local ownerCapable = ent:IsAdmin() or ent.canDoThing

if entValid and ownerCapable then
end

-- if splitting a condition across lines, operators go at the start of each line
if
	IsValid(ent) and
	ent:IsPlayer() and
	(ent:IsAdmin() or ent:IsSuperAdmin())
then
end

-- numbers: 0.5 not .5, 420 not 00420, 0.2 not 0.200
local num = 0.5
local factor = 420
local decimal = 0.2

-- no useless comments: self-documenting code
-- bad: local ply = v -- set player

-- avoid unnecessary IsValid: only guard where the entity can become invalid
timer.Create("gmod.one/myaddon/delayed", 5, 1, function()
	if IsValid(ply) == false then return end -- player may have disconnected
end)

-- print varargs instead of string concatenation
print("Health:", ply:Health(), "Pos:", ply:GetPos())

-- string.format when you need control over the output (precision, alignment)
print(string.format("%s | HP: %d | Speed: %.2f", ply, ply:Health(), ply:GetVelocity():Length()))

-- no tostring on numbers when concatenating
print("Line #" .. i, line)

-- globals: use deliberately - one namespace per addon, org name embedded
-- (ValvePrinters, RubatSkillsSystem), soft cap 5, data inside the table
ValvePrinters = ValvePrinters or {}

ValvePrinters.playerCount = 0

-- keep state file-local when nothing outside the file needs it
local playerCount = 0

-- share via module returns when other files need the value
-- (a module returns its table at the end of the file, after all definitions)
local MyAddon = {}

function MyAddon:GetPlayerCount()
	return playerCount
end

-- require only what you need
local hmac = require("openssl").hmac.hmac
hmac("data", "key")

-- nesting depth: max 3 levels; if a function can't stay flat,
-- split it into compact sub-functions, each doing one thing
local function processPlayer(ply)
	if (IsValid(ply) and ply:Alive()) == false then return end

	local weapon = ply:GetActiveWeapon()
	if IsValid(weapon) == false then return end

	weapon:SetClip1(weapon:Clip1() + 1)
end

-- hooks: return nothing unless you intend to block the default behaviour
hook.Add("PlayerUse", "gmod.one/myaddon/vending-gate", function(ply, ent)
	if ent:GetClass() ~= "myaddon_vending_machine" then return end
	if ply:IsAdmin() == false then return false end

	return true
end)

-- detours must call the original function
local originalFunc = someLib.DoSomething

function someLib.DoSomething(...)
	-- extend the behaviour here (side effects)
	return originalFunc(...)
end

-- net: typed writers over WriteType/WriteTable (expensive)
net.Start("gmod.one/myaddon/player-count")
net.WriteUInt(playerCount, 16)
net.Send(ply)

-- net: rate-limit player messages server-side (cooldown), validate types server-side, never SendLua

-- caching: construct Color/Vector/Material once, never per frame
local PLAYER_COLOR = Color(255, 200, 100)

-- iteration: ipairs / numeric for over pairs on sequential tables
for i = 1, #items do
	processItem(items[i])
end

-- lookup tables over table.HasValue scans
local ALLOWED_ROLES = {["admin"] = true, ["superadmin"] = true}

-- memory: cap tables that grow with unbounded input
local MAX_LOGS = 200
local logs = {}

local function addLog(entry)
	table.insert(logs, entry)

	if #logs > MAX_LOGS then
		table.remove(logs, 1)
	end
end

-- file structure: one autorun file per addon, never autorun/init.lua,
-- all files inside your own uniquely named folder

-- deprecated APIs: umsg -> net library
net.Start("gmod.one/myaddon/shot-fired")
net.WriteUInt(amount, 16)
net.Send(ply)

-- code safety: validate state; SafeRemoveEntityDelayed in touch/collision hooks.
-- touch/collision callbacks are ENTITY: methods, not hook.Add events
local SAFE_REMOVE_DELAY = 0 -- you can keep it as 0, it means: remove entity in next tick.

function ENT:StartTouch(other)
	if other:GetClass() ~= "myaddon_pickup" then return end

	SafeRemoveEntityDelayed(other, SAFE_REMOVE_DELAY)
end

-- hot loops: player.Iterator() instead of player.GetAll() in Think.
-- Iterator() returns the same three values as ipairs - index first, player second
for _, ply in player.Iterator() do
	if IsValid(ply) == false then continue end
end

-- error handling: no pcall by default - a Lua error prints to console and aborts
-- only the current call, it does not crash the process. Use pcall only where the
-- function must complete anyway, and always report what you catch
for _, ply in player.Iterator() do
	local ok, err = pcall(savePlayerData, ply)

	if ok == false then
		ErrorNoHalt("myaddon: failed to save " .. ply:SteamID64() .. ": " .. tostring(err) .. "\n")
	end
end

-- strings with many quotes or line breaks: long brackets instead of escaping
local notice = [[Say "hi" - no escaping needed]]

-- complex Lua patterns: build with table.concat at file scope (constant),
-- each piece visible; long brackets break on newlines - avoid for patterns
local avatarPattern = table.concat({
	"<avatarIcon>",
		"<%!%[", "CDATA%[",
			"(.-)",
		"%]%]>",
	"</avatarIcon>"
})
