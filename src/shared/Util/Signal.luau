--!strict
--[[
	Signal
	======
	Minimal script-side event (Roblox runtime only: listeners run with task.spawn so a
	yielding or erroring listener can never block or break the code that fires the signal).

	local s = Signal.new()
	local conn = s:Connect(function(a, b) ... end)
	s:Fire(1, 2)
	conn:Disconnect()
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	_listeners: { [Connection]: (...any) -> () },
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
}

local Signal = {}

local function connect(self: Signal, fn: (...any) -> ()): Connection
	local listeners = self._listeners
	local connection: Connection
	connection = {
		Connected = true,
		Disconnect = function(_conn: Connection)
			connection.Connected = false
			listeners[connection] = nil
		end,
	}
	listeners[connection] = fn
	return connection
end

local function fire(self: Signal, ...: any)
	-- Snapshot so listeners that connect/disconnect during Fire don't disturb iteration.
	local snapshot = {}
	for _, fn in self._listeners do
		table.insert(snapshot, fn)
	end
	for _, fn in snapshot do
		task.spawn(fn, ...)
	end
end

local function disconnectAll(self: Signal)
	for connection in self._listeners do
		connection.Connected = false
	end
	table.clear(self._listeners)
end

function Signal.new(): Signal
	return {
		_listeners = {},
		Connect = connect,
		Fire = fire,
		DisconnectAll = disconnectAll,
	}
end

return Signal
