--[[
	Roblox-style module loader for Lune.

	Game code uses Roblox requires (`require(script.Parent.Lexer)`,
	`game:GetService("ReplicatedStorage").Shared...`). Lune has no DataModel, so this loader
	builds a tiny fake instance tree that mirrors default.project.json:

	  ReplicatedStorage.Shared      -> src/shared
	  ServerScriptService.Server    -> src/server

	and loads each ModuleScript with luau.load, injecting `script`, `require` and `game`.
	Only pure modules are loaded this way (anything touching real Roblox services would fail,
	which is exactly the point: it proves those modules are pure).

	Run tests from the repository root:  lune run tests/run
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task") -- the same API as Roblox's task library

local MOUNTS = {
	ReplicatedStorage = { Shared = "src/shared" },
	ServerScriptService = { Server = "src/server" },
}

local Loader = {}

-- Lune's fs functions yield, and yielding inside a metamethod (__index) is not allowed, so
-- the whole source tree is scanned once up front and lookups use these sets.
local knownFiles = {}
local knownDirs = {}
local fileContents = {}

local function scan(dir)
	knownDirs[dir] = true
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			scan(path)
		else
			knownFiles[path] = true
			if string.sub(path, -5) == ".luau" then
				fileContents[path] = fs.readFile(path)
			end
		end
	end
end

for _, mount in MOUNTS do
	for _, path in mount do
		scan(path)
	end
end

local nodeCache = {}
local moduleCache = {}
local loading = {}

local nodeMeta = {}

local function makeNode(name, parent, path, kind)
	local cacheKey = path or ("service:" .. name)
	if nodeCache[cacheKey] then
		return nodeCache[cacheKey]
	end
	local node = setmetatable({
		Name = name,
		Parent = parent,
		_path = path,
		_kind = kind, -- "service" | "folder" | "module"
	}, nodeMeta)
	nodeCache[cacheKey] = node
	return node
end

local function findChild(node, childName)
	if node._kind == "service" then
		local mount = MOUNTS[node.Name]
		local path = mount and mount[childName]
		if path and knownDirs[path] then
			return makeNode(childName, node, path, "folder")
		end
		return nil
	elseif node._kind == "folder" then
		local filePath = node._path .. "/" .. childName .. ".luau"
		if knownFiles[filePath] then
			return makeNode(childName, node, filePath, "module")
		end
		local dirPath = node._path .. "/" .. childName
		if knownDirs[dirPath] then
			return makeNode(childName, node, dirPath, "folder")
		end
	end
	return nil
end

local methods = {}

function methods.FindFirstChild(self, childName)
	return findChild(self, childName)
end

function methods.WaitForChild(self, childName)
	local child = findChild(self, childName)
	if child == nil then
		error(string.format("loader: %s has no child %s", self.Name, childName), 2)
	end
	return child
end

function methods.GetFullName(self)
	if self.Parent then
		return methods.GetFullName(self.Parent) .. "." .. self.Name
	end
	return self.Name
end

nodeMeta.__index = function(self, key)
	if methods[key] then
		return methods[key]
	end
	local child = findChild(self, key)
	if child == nil then
		error(string.format("%s is not a valid member of %s", tostring(key), methods.GetFullName(self)), 2)
	end
	return child
end

nodeMeta.__tostring = function(self)
	return methods.GetFullName(self)
end

local services = {}
local fakeGame = {
	GetService = function(_self, serviceName)
		if MOUNTS[serviceName] == nil then
			error(
				"loader: service "
					.. tostring(serviceName)
					.. " is not available in tests (module is not pure)",
				2
			)
		end
		if not services[serviceName] then
			services[serviceName] = makeNode(serviceName, nil, nil, "service")
		end
		return services[serviceName]
	end,
}

local function requireNode(node)
	if type(node) ~= "table" or getmetatable(node) ~= nodeMeta or node._kind ~= "module" then
		error("loader: require() expects a ModuleScript, got " .. tostring(node), 2)
	end
	local path = node._path
	if moduleCache[path] ~= nil then
		return moduleCache[path]
	end
	if loading[path] then
		error("loader: cyclic require of " .. path, 2)
	end
	loading[path] = true
	local source = fileContents[path]
	local chunk = luau.load(source, {
		debugName = path,
		environment = {
			script = node,
			require = requireNode,
			game = fakeGame,
			task = task, -- Roblox's task library (Lune provides the same API)
		},
	})
	local result = chunk()
	loading[path] = nil
	moduleCache[path] = result
	return result
end

-- Loader.get("ReplicatedStorage.Shared.DroneScript.Lexer") -> the module's return value
function Loader.get(dottedPath)
	local parts = string.split(dottedPath, ".")
	local node = fakeGame:GetService(parts[1])
	for i = 2, #parts do
		node = node[parts[i]]
	end
	return requireNode(node)
end

return Loader
