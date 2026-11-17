--!strict
--[[
	SessionStore
	============
	A session-locked document store on top of a DataStore-like object (anything with
	UpdateAsync). This is the core that keeps player data and purchases safe.

	WHY SESSION LOCKING
	  A player can hop servers faster than the old server finishes saving. Without a lock,
	  the new server could load stale data and later overwrite newer data (lost progress) or
	  both servers could grant the same purchase (dupes). With a lock, exactly ONE server owns
	  a player's record at a time.

	RECORD FORMAT (one DataStore key per player)
	  {
	    data = <PlayerData>,
	    lock = { sessionId = "<guid>", loadId = "<guid>#<n>", jobId = "<game.JobId>",
	             time = <os.time()> } | nil,
	    meta = { createdAt, updatedAt, saves, loads },
	  }

	RULES
	  * ALL reads/writes use UpdateAsync, so "check the lock + write" is atomic.
	  * Transform functions never yield; results are copied out through upvalues (Roblox may
	    run a transform more than once - the last run is the one that committed).
	  * Load: a lock held by another session is respected until it is `lockStaleSeconds` old
	    (its owner refreshes it on every autosave; a stale lock means the owner crashed).
	  * Save: refuses to write unless the lock is still ours. If it isn't, the profile is
	    marked LOST and `onLost` fires (DataService kicks the player to stop any dupes).
	  * Release: final write that clears the lock.
	  * The lock belongs to ONE LOAD (loadId), not to the server: a save or release only writes
	    while the record still carries its own loadId. A same-server rejoin whose earlier
	    profile is still releasing waits like any other locked load ("Locked", retried), so it
	    can never load pre-release data and then lose the lock to that release (BUG-07). A lock
	    of this server whose load is no longer active (a release whose write failed) is taken
	    over at once.
	  * A record that isn't a table is reported as "Corrupt" and is NEVER overwritten.

	Dependencies (store, clock, wait, ids, logging) are injected so this module runs under the
	offline unit tests with a MockDataStore and a controllable clock.
]]

export type Store = {
	UpdateAsync: (self: any, key: string, transform: (any, any) -> ...any) -> ...any,
}

export type LogLevel = "info" | "warn" | "error"

export type Options = {
	store: Store,
	sessionId: string, -- unique per server process (HttpService:GenerateGUID)
	jobId: string, -- game.JobId (informational, for debugging stolen locks)
	now: () -> number, -- os.time
	wait: (seconds: number) -> (), -- task.wait
	sanitize: (raw: any, now: number) -> any,
	log: ((level: LogLevel, message: string) -> ())?,
	lockStaleSeconds: number,
	loadRetries: number,
	loadRetryDelay: number,
	writeRetries: number,
	writeRetryDelay: number?, -- base for exponential backoff (default 1 s)
	pollInterval: number?, -- how often waiters re-check a busy profile (default 0.1 s)
}

export type Profile = {
	key: string,
	data: any,
	userIds: { number },
	onLost: ((profile: Profile) -> ())?,

	IsActive: (self: Profile) -> boolean,
	IsLost: (self: Profile) -> boolean,
	SaveAsync: (self: Profile) -> boolean,
	ReleaseAsync: (self: Profile) -> boolean,
}

export type LoadError = "Locked" | "Corrupt" | "Failed"

export type SessionStore = {
	LoadAsync: (self: SessionStore, key: string, userIds: { number }?) -> (Profile?, LoadError?),
}

-- Internal mutable state per profile (kept out of the public type).
type State = {
	saving: boolean, -- a write is in flight (acts as a mutex)
	releasing: boolean,
	released: boolean,
	lost: boolean,
	releaseOk: boolean,
	requestGen: number, -- incremented on every save request
	savedGen: number, -- highest requestGen covered by a successful write
}

local SessionStore = {}

function SessionStore.new(options: Options): SessionStore
	local log: (level: LogLevel, message: string) -> () = function(_level: LogLevel, _message: string) end
	if options.log ~= nil then
		log = options.log
	end
	local writeRetryDelay = options.writeRetryDelay or 1
	local pollInterval = options.pollInterval or 0.1

	--[[
		One UpdateAsync write with retries. Returns true only if the record was committed with
		our lock still in place.
	]]
	-- loadIds of this server's profiles that may still write (loaded, not yet released).
	local activeLoads: { [string]: boolean } = {}
	local loadCounter = 0

	local function write(profile: Profile, state: State, release: boolean, loadId: string): boolean
		for attempt = 1, options.writeRetries do
			local outcome: string? = nil
			local ok, err = pcall(function()
				options.store:UpdateAsync(profile.key, function(old: any)
					outcome = nil
					if type(old) ~= "table" then
						outcome = "lost" -- the record vanished: we no longer own anything
						return nil
					end
					local lock = old.lock
					if type(lock) ~= "table" or lock.loadId ~= loadId then
						outcome = "lost" -- another load (any server) took the record over
						return nil
					end
					local now = options.now()
					old.data = profile.data
					old.lock = if release
						then nil
						else {
							sessionId = options.sessionId,
							loadId = loadId,
							jobId = options.jobId,
							time = now,
						}
					local meta = if type(old.meta) == "table" then old.meta else {}
					meta.updatedAt = now
					meta.saves = (if type(meta.saves) == "number" then meta.saves else 0) + 1
					old.meta = meta
					outcome = "ok"
					return old, profile.userIds
				end)
			end)

			if ok and outcome == "ok" then
				return true
			elseif ok and outcome == "lost" then
				if not state.lost then
					state.lost = true
					activeLoads[loadId] = nil
					log(
						"warn",
						string.format(
							"[SessionStore] %s: session lock lost, profile is now inactive",
							profile.key
						)
					)
					local onLost = profile.onLost
					if onLost ~= nil then
						local callbackOk, callbackErr = pcall(onLost :: any, profile)
						if not callbackOk then
							log("error", "[SessionStore] onLost callback failed: " .. tostring(callbackErr))
						end
					end
				end
				return false
			end

			log(
				"warn",
				string.format(
					"[SessionStore] %s: write attempt %d/%d failed: %s",
					profile.key,
					attempt,
					options.writeRetries,
					tostring(err or "transform did not run")
				)
			)
			if attempt < options.writeRetries then
				options.wait(writeRetryDelay * 2 ^ (attempt - 1))
			end
		end
		return false
	end

	local function newProfile(key: string, data: any, userIds: { number }, loadId: string): Profile
		local state: State = {
			saving = false,
			releasing = false,
			released = false,
			lost = false,
			releaseOk = false,
			requestGen = 0,
			savedGen = 0,
		}

		local profile: Profile
		profile = {
			key = key,
			data = data,
			userIds = userIds,
			onLost = nil,

			IsActive = function(_self: Profile): boolean
				return not (state.lost or state.released or state.releasing)
			end,

			IsLost = function(_self: Profile): boolean
				return state.lost
			end,

			--[[
				Persists the current in-memory data. Coalesces concurrent calls: a request is
				satisfied by ANY write that started after the request was made (that write
				already contains the caller's changes). Returns true when the caller's changes
				are durably stored.
			]]
			SaveAsync = function(_self: Profile): boolean
				if state.lost or state.released then
					return false
				end
				state.requestGen += 1
				local myGen = state.requestGen

				while state.saving or state.releasing do
					options.wait(pollInterval)
				end
				if state.savedGen >= myGen then
					return true -- a write that started after our request succeeded (save or release)
				end
				if state.lost or state.released then
					return false
				end

				-- No yield between the check above and taking the mutex (cooperative scheduler).
				state.saving = true
				local startedGen = state.requestGen
				local callOk, written = pcall(write, profile, state, false, loadId)
				state.saving = false
				if callOk and written then
					state.savedGen = math.max(state.savedGen, startedGen)
					return true
				end
				if not callOk then
					log("error", "[SessionStore] unexpected save error: " .. tostring(written))
				end
				return false
			end,

			--[[
				Final save + unlock. Safe to call more than once and concurrently; later callers
				wait for the first release and get its result. After this, the profile is inactive.
			]]
			ReleaseAsync = function(_self: Profile): boolean
				if state.released or state.releasing then
					while state.releasing do
						options.wait(pollInterval)
					end
					return state.releaseOk
				end
				state.releasing = true
				while state.saving do
					options.wait(pollInterval)
				end

				local ok = false
				if not state.lost then
					state.saving = true
					state.requestGen += 1
					local startedGen = state.requestGen
					local callOk, written = pcall(write, profile, state, true, loadId)
					state.saving = false
					ok = callOk and written == true
					if ok then
						state.savedGen = math.max(state.savedGen, startedGen)
					elseif not callOk then
						log("error", "[SessionStore] unexpected release error: " .. tostring(written))
					end
				end

				state.releaseOk = ok
				state.released = true
				state.releasing = false
				activeLoads[loadId] = nil -- this load will never write again
				return ok
			end,
		}
		return profile
	end

	local function loadAsync(_self: SessionStore, key: string, userIds: { number }?): (Profile?, LoadError?)
		local lastProblem: LoadError = "Failed"
		loadCounter += 1
		local loadId = options.sessionId .. "#" .. tostring(loadCounter)

		for attempt = 1, options.loadRetries do
			local outcome: string? = nil
			local loaded: any = nil
			local takenFrom: string? = nil

			local ok, err = pcall(function()
				options.store:UpdateAsync(key, function(old: any)
					outcome, loaded, takenFrom = nil, nil, nil
					local now = options.now()

					if old ~= nil and type(old) ~= "table" then
						outcome = "corrupt"
						return nil
					end
					if old ~= nil and old.data ~= nil and type(old.data) ~= "table" then
						outcome = "corrupt"
						return nil
					end

					local record = old or {}
					local lock = record.lock
					if type(lock) == "table" and lock.loadId ~= loadId then
						-- One of OUR loads that can no longer write (its release already ended)
						-- is an orphan: take it at once. Any other lock, including one of this
						-- server's profiles that is still releasing, is respected until stale.
						local orphan = lock.sessionId == options.sessionId and not activeLoads[lock.loadId]
						if not orphan then
							local lockTime = if type(lock.time) == "number" then lock.time else 0
							-- math.abs: a lock time far in the future (clock skew / garbage) also expires.
							if math.abs(now - lockTime) < options.lockStaleSeconds then
								outcome = "locked"
								return nil
							end
							takenFrom = tostring(lock.jobId)
						end
					end

					record.lock =
						{ sessionId = options.sessionId, loadId = loadId, jobId = options.jobId, time = now }
					record.data = options.sanitize(record.data, now)
					local meta = if type(record.meta) == "table"
						then record.meta
						else { createdAt = now, saves = 0 }
					meta.updatedAt = now
					meta.loads = (if type(meta.loads) == "number" then meta.loads else 0) + 1
					record.meta = meta

					outcome = "ok"
					loaded = record
					return record, userIds
				end)
			end)

			if ok and outcome == "ok" then
				if takenFrom ~= nil then
					log(
						"warn",
						string.format(
							"[SessionStore] %s: took over a stale lock from server %s",
							key,
							takenFrom
						)
					)
				end
				activeLoads[loadId] = true
				return newProfile(key, loaded.data, userIds or {}, loadId), nil
			elseif ok and outcome == "corrupt" then
				log(
					"error",
					string.format(
						"[SessionStore] %s: record is corrupt; refusing to load or overwrite it",
						key
					)
				)
				return nil, "Corrupt"
			elseif ok and outcome == "locked" then
				lastProblem = "Locked"
				log(
					"info",
					string.format("[SessionStore] %s: locked by another server (attempt %d)", key, attempt)
				)
			else
				lastProblem = "Failed"
				log(
					"warn",
					string.format(
						"[SessionStore] %s: load attempt %d failed: %s",
						key,
						attempt,
						tostring(err)
					)
				)
			end

			if attempt < options.loadRetries then
				options.wait(options.loadRetryDelay)
			end
		end

		return nil, lastProblem
	end

	return {
		LoadAsync = loadAsync,
	}
end

return SessionStore
