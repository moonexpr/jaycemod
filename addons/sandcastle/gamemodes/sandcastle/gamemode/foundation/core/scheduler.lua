-- Cooperative tasks that share a slice of time: each task is a coroutine,
-- and long work checks the clock as it goes (CheckYield), giving the rest
-- of its work to the next run once the slice is spent. So a budget holds
-- to within one step of the work, not one chunk of it, and work too long
-- for a tick is spread over ticks without a hitch.
--
-- New(clock) with clock:Now() in seconds. The scheduler:
--   Spawn(fn, ...) -> the task: fn(...) in a coroutine, run from the next Run
--   Run(seconds)   runs the tasks in turn until the slice is spent or none is
--                  left; a task that yields goes behind the others. A task's
--                  error is raised here, the task removed first.
--   CheckYield()   in a task: yields when the slice is spent; whether it did
--   Yield()        in a task: gives up its turn now; false outside a task
--   Count()        the tasks not yet finished
local coroutine, error, select, setmetatable, tostring, unpack = coroutine, error, select, setmetatable, tostring, unpack
local traceback = debug.traceback
local Queue = require("foundation.core.structs.queue")
module(...)

local Scheduler = {}
Scheduler.__index = Scheduler

function New(clock)
	return setmetatable({
		clock = clock,
		tasks = Queue.New(),
		current = nil, -- the task running, while Run resumes one
		deadline = 0,
	}, Scheduler)
end

function Scheduler:Spawn(fn, ...)
	local co = coroutine.create(fn)
	local task = {
		co = co,
		args = { ... },
		n = select("#", ...),
		started = false,
	}
	self.tasks:PushBack(task)
	return task
end

-- Whether the code calling is the running task itself, not a coroutine of
-- its own inside it, which a yield here would suspend instead.
local function InTask(self)
	return self.current ~= nil and coroutine.running() == self.current.co
end

function Scheduler:Yield()
	if not InTask(self) then return false end
	coroutine.yield()
	return true
end

function Scheduler:CheckYield()
	if not InTask(self) or self.clock:Now() < self.deadline then return false end
	coroutine.yield()
	return true
end

local function Resume(task)
	if task.started then return coroutine.resume(task.co) end
	task.started = true
	return coroutine.resume(task.co, unpack(task.args, 1, task.n))
end

function Scheduler:Run(seconds)
	local tasks = self.tasks
	if tasks:Size() == 0 then return end
	self.deadline = self.clock:Now() + seconds
	repeat
		local task = tasks:PopFront()
		self.current = task
		local ok, err = Resume(task)
		self.current = nil
		if not ok then error(traceback(task.co, tostring(err)), 0) end
		if coroutine.status(task.co) ~= "dead" then tasks:PushBack(task) end
	until tasks:Size() == 0 or self.clock:Now() >= self.deadline
end

function Scheduler:Count()
	return self.tasks:Size()
end
