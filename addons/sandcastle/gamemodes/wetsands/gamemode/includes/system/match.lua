-- What the game is running, asked of the systems that run it, so nothing has
-- to reach into one of them. The rest of the game asks the match, in a
-- transaction; the match asks each subscriber, in a transaction of its own. A
-- subscriber that breaks fails only its own: it is reported, once an error,
-- and counts as not running. One that never subscribed, because its system
-- failed to load, is simply not running.
--   New(report) -> a match; report(name, err) hears a subscriber's bug
--   match:Subscribe(name, running): running() says whether it is running; a
--     name again replaces it, as a reload does
--   match:Running() -> a transaction committing with name -> true for those
--     running
--   match:IsRunning(name) -> whether that one is
local pairs, setmetatable, tostring = pairs, setmetatable, tostring
local Transaction = transaction
module (...)

local Match = {}
Match.__index = Match

function New (report)
	return setmetatable (
		{
			report = report,
			subscribers = {}
		}, Match)
end

function Match:Subscribe (name, running)
	self.subscribers [name] = { running = running }
end

-- A subscriber's failure, told unless it is the error it told last.
local function Tell (self, name, subscriber, err)
	local text = tostring (err)
	if subscriber.told == text then return end
	subscriber.told = text
	self.report (name, err)
end

local function Ask (_, self)
	local running = {}
	for name, subscriber in pairs (self.subscribers) do
		local asked = Transaction.Run (subscriber.running)
		local state = asked:State ()
		if state == Transaction.COMMITTED then
			if asked:Value () then running [name] = true end
		elseif state == Transaction.FAILED then
			Tell (self, name, subscriber, asked:Error ())
		end
	end
	return running
end

function Match:Running ()
	return Transaction.Run (Ask, self)
end

function Match:IsRunning (name)
	return self:Running ():Value () [name] == true
end
