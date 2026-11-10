--!strict
--[[
	RunGate
	=======
	One driver per key (a Player): the hard mutex behind ScriptService's program runs. Pure
	(task / coroutine only), so the offline tests drive it with real Interpreter runs.

	  gate:start(key, body) -> Run
	    1. Cancels the key's previous run: sets run.cancelled, then task.cancel()s its thread.
	       That thread is always suspended while another thread runs (in task.wait inside an
	       action, the CPU throttle, or simulate()), so the kill is immediate and the killed run
	       is released at once: none of its code can ever run again.
	    2. The new run's thread waits, with NO timeout, until no other run drives the key. (Only
	       if a kill failed does it wait for the old run to stop on its own via run.cancelled.)
	    3. Then it becomes the driver and calls body(run). When body returns, or errors, the run
	       is released.
	  gate:stop(key) -> (Run?, killed: boolean)   Stop button / player leaving
	  gate:current(key) -> Run?                   the newest run (waiting or driving)
	  gate:driver(key) -> Run?                    the run that owns the drone right now

	WHY A KILL IS SAFE: every builtin applies its effect BEFORE its wait (move publishes the new
	cell, harvest banks the cargo, ...), and the economy/data calls never yield. A thread killed
	while suspended therefore never leaves a half-done action or a half-written PlayerData.
]]

export type Run = {
	id: number,
	cancelled: boolean, -- cooperative stop flag (read by shouldStop)
	finished: boolean, -- released: will never touch the drone or the data again
	driving: boolean, -- currently owns the key's drone
	thread: thread?,
}

export type Gate = {
	start: (self: Gate, key: any, body: (run: Run) -> ()) -> Run,
	stop: (self: Gate, key: any) -> (Run?, boolean),
	current: (self: Gate, key: any) -> Run?,
	driver: (self: Gate, key: any) -> Run?,
}

local RunGate = {}

function RunGate.new(): Gate
	local latest: { [any]: Run } = {}
	local drivers: { [any]: Run } = {}
	local nextId = 0

	local function release(key: any, run: Run)
		run.finished = true
		run.driving = false
		if drivers[key] == run then
			drivers[key] = nil
		end
		if latest[key] == run then
			latest[key] = nil
		end
	end

	-- Cancels a run; returns true if its thread was killed (and the run released).
	local function cancel(key: any, run: Run): boolean
		run.cancelled = true
		local thread = run.thread
		if run.finished or thread == nil or coroutine.status(thread) ~= "suspended" then
			return false
		end
		local ok = pcall(task.cancel, thread)
		if ok then
			release(key, run)
		end
		return ok
	end

	local gate: Gate
	gate = {
		start = function(_self: Gate, key: any, body: (run: Run) -> ()): Run
			local previous = latest[key]
			if previous ~= nil then
				cancel(key, previous)
			end
			-- An older run whose kill failed may still drive: cancel it as well.
			local driver = drivers[key]
			if driver ~= nil and driver ~= previous then
				cancel(key, driver)
			end

			nextId += 1
			local run: Run =
				{ id = nextId, cancelled = false, finished = false, driving = false, thread = nil }
			latest[key] = run
			run.thread = task.spawn(function()
				-- The hard mutex: never two drivers. No timeout.
				while drivers[key] ~= nil and not run.cancelled do
					task.wait()
				end
				if run.cancelled then
					release(key, run)
					return
				end
				drivers[key] = run
				run.driving = true
				local ok, err = xpcall(function(): any
					body(run)
					return nil
				end, debug.traceback)
				release(key, run)
				if not ok then
					error(err, 0)
				end
			end)
			return run
		end,

		stop = function(_self: Gate, key: any): (Run?, boolean)
			local run = latest[key] or drivers[key]
			if run == nil then
				return nil, false
			end
			local killed = cancel(key, run)
			local driver = drivers[key]
			if driver ~= nil and driver ~= run then
				cancel(key, driver)
			end
			return run, killed
		end,

		current = function(_self: Gate, key: any): Run?
			return latest[key]
		end,

		driver = function(_self: Gate, key: any): Run?
			return drivers[key]
		end,
	}
	return gate
end

return RunGate
