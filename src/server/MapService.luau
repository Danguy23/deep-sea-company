--!strict
-- Owns the generated map: builds a random branching layout from the room pool
-- off the Submarine's Hatch, tears it down again, and answers "where is the map"
-- for loot and the creature. RoomStitcher does the placement math.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RoomStitcher = require(script.Parent:WaitForChild("RoomStitcher"))
local settings = Config.MapGen

type PoolEntry = {name: string, weight: number, template: Model, connectorIds: {string}}
type Doorway = {room: Model, id: string}
type BuildResult = {seed: number, target: number, placed: number, rejected: number}

local MAP_FOLDER_NAME = "GeneratedMap"
local START_CONNECTOR_ID = "Hatch"

local MapService = {}

-- Generated rooms only; the Submarine is never in this list.
local generatedRooms = {} :: {Model}

local function sortedConnectorIds(room: Model): {string}
	local ids = {}
	for id in pairs(RoomStitcher.GetConnectors(room)) do
		table.insert(ids, id)
	end
	-- GetConnectors returns a dictionary; sorting keeps a seed's layout reproducible.
	table.sort(ids)
	return ids
end

local function loadPool(): {PoolEntry}
	local templates = ServerStorage:FindFirstChild("RoomTemplates")
	if not templates then
		warn("[Map] MISSING ServerStorage.RoomTemplates; no map can be generated.")
		return {}
	end
	local names = {}
	for name in pairs(settings.RoomPool) do
		table.insert(names, name)
	end
	table.sort(names)

	local pool = {}
	for _, name in ipairs(names) do
		local template = templates:FindFirstChild(name)
		local weight = settings.RoomPool[name]
		if not template or not template:IsA("Model") then
			warn(string.format("[Map] MISSING room template %q in ServerStorage.RoomTemplates; skipping it.", name))
		elseif weight > 0 then
			local connectorIds = sortedConnectorIds(template)
			if #connectorIds == 0 then
				warn(string.format("[Map] Room template %q has no Connectors; skipping it.", name))
			else
				table.insert(pool, {name = name, weight = weight, template = template, connectorIds = connectorIds})
			end
		end
	end
	return pool
end

local function pickWeighted(pool: {PoolEntry}, rng: Random): PoolEntry
	local total = 0
	for _, entry in ipairs(pool) do
		total += entry.weight
	end
	local roll = rng:NextNumber() * total
	for _, entry in ipairs(pool) do
		roll -= entry.weight
		if roll < 0 then
			return entry
		end
	end
	return pool[#pool]
end

local function removeDevParts(room: Model)
	for _, descendant in ipairs(room:GetDescendants()) do
		local name = descendant.Name
		if descendant.Parent and (string.sub(name, 1, 13) == "TEMP_SafeZone" or string.sub(name, 1, 10) == "TEMP_Spawn") then
			descendant:Destroy()
		end
	end
end

-- One layout attempt from a single seed. Every random choice comes from one Random.
local function generate(submarine: Model, pool: {PoolEntry}, seed: number): BuildResult
	local rng = Random.new(seed)
	local folder = Instance.new("Folder")
	folder.Name = MAP_FOLDER_NAME
	folder.Parent = workspace
	RoomStitcher.RegisterExisting(submarine)

	local target = rng:NextInteger(settings.MinRooms, settings.MaxRooms)
	local frontier: {Doorway} = {{room = submarine, id = START_CONNECTOR_ID}}
	local rejected = 0

	while #generatedRooms < target and #frontier > 0 do
		-- A random doorway, not the newest one, is what makes the map branch.
		local doorway = table.remove(frontier, rng:NextInteger(1, #frontier)) :: Doorway
		for _ = 1, settings.PlacementAttemptsPerDoorway do
			local entry = pickWeighted(pool, rng)
			local connectorId = entry.connectorIds[rng:NextInteger(1, #entry.connectorIds)]
			local room = RoomStitcher.Attach(doorway.room, doorway.id, entry.template, connectorId, folder)
			if room then
				table.insert(generatedRooms, room)
				for _, id in ipairs(entry.connectorIds) do
					if id ~= connectorId then
						table.insert(frontier, {room = room, id = id})
					end
				end
				break
			end
			rejected += 1
		end
		-- A doorway that ran out of attempts just drops out and stays capped.
	end

	return {seed = seed, target = target, placed = #generatedRooms, rejected = rejected}
end

function MapService.Build(seed: number?): boolean
	local submarine = workspace:FindFirstChild("Submarine")
	if not submarine or not submarine:IsA("Model") then
		warn("[Map] MISSING Workspace.Submarine; the map has nothing to dock to.")
		return false
	end
	if not RoomStitcher.GetConnectors(submarine)[START_CONNECTOR_ID] then
		warn(string.format("[Map] MISSING Connector %q on Workspace.Submarine; no map can be generated.", START_CONNECTOR_ID))
		return false
	end
	local pool = loadPool()
	if #pool == 0 then
		warn("[Map] Room pool is empty; no map can be generated.")
		return false
	end

	local baseSeed = seed or settings.Seed or Random.new():NextInteger(1, 2 ^ 31 - 1)
	print(string.format("[Map] Building with seed %d", baseSeed))

	local result: BuildResult? = nil
	local best: BuildResult? = nil
	local attempts = 0
	for attempt = 1, settings.MaxBuildAttempts do
		attempts = attempt
		MapService.Teardown()
		result = generate(submarine, pool, baseSeed + attempt - 1)
		local current = result :: BuildResult
		if current.placed >= settings.MinRooms then
			break
		end
		if best == nil or current.placed > (best :: BuildResult).placed then
			best = current
		end
		if attempt < settings.MaxBuildAttempts then
			print(string.format(
				"[Map] Seed %d placed only %d of %d minimum rooms; retrying with seed %d",
				current.seed, current.placed, settings.MinRooms, current.seed + 1
			))
		end
	end

	local final = result :: BuildResult
	if final.placed < settings.MinRooms then
		local kept = best :: BuildResult
		warn(string.format(
			"[Map] SHORT MAP: no seed reached %d rooms in %d attempts; keeping seed %d with %d room(s).",
			settings.MinRooms, attempts, kept.seed, kept.placed
		))
		if kept.seed ~= final.seed then
			-- Generation is deterministic per seed, so the best attempt can be rebuilt exactly.
			MapService.Teardown()
			final = generate(submarine, pool, kept.seed)
		end
	end

	for _, room in ipairs(generatedRooms) do
		removeDevParts(room)
	end
	local opened, capped = RoomStitcher.FinalizeDoorways()
	print(string.format(
		"[Map] Built seed %d: %d room(s) placed of target %d, %d doorway(s) opened, %d capped, %d placement(s) rejected, %d build attempt(s)",
		final.seed, final.placed, final.target, opened, capped, final.rejected, attempts
	))
	return #generatedRooms > 0
end

function MapService.Teardown()
	local folder = workspace:FindFirstChild(MAP_FOLDER_NAME)
	while folder do
		folder:Destroy()
		folder = workspace:FindFirstChild(MAP_FOLDER_NAME)
	end
	RoomStitcher.RestoreExisting()
	RoomStitcher.Reset()
	table.clear(generatedRooms)
end

function MapService.GetRooms(): {Model}
	return table.clone(generatedRooms)
end

function MapService.GetFloors(): {Instance}
	local floors = {}
	for _, room in ipairs(generatedRooms) do
		local folder = room:FindFirstChild("Floors")
		if folder then
			table.insert(floors, folder)
		else
			warn(string.format("[Map] MISSING Floors folder in %s; nothing can spawn on it.", room:GetFullName()))
		end
	end
	return floors
end

function MapService.GetRoomBounds(): {BasePart}
	local bounds = {}
	for _, room in ipairs(generatedRooms) do
		local part = room.PrimaryPart
		if part then
			table.insert(bounds, part)
		end
	end
	return bounds
end

local function floorArea(room: Model): number
	local area = 0
	local folder = room:FindFirstChild("Floors")
	if folder then
		for _, descendant in ipairs(folder:GetDescendants()) do
			if descendant:IsA("BasePart") then
				area += descendant.Size.X * descendant.Size.Z
			end
		end
	end
	return area
end

-- Weighted by floor area, so big rooms get proportionally more of what spawns.
function MapService.RandomRoom(rng: Random): Model?
	local total = 0
	local areas = {}
	for index, room in ipairs(generatedRooms) do
		areas[index] = floorArea(room)
		total += areas[index]
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for index, room in ipairs(generatedRooms) do
		roll -= areas[index]
		if roll < 0 then
			return room
		end
	end
	return generatedRooms[#generatedRooms]
end

return MapService
