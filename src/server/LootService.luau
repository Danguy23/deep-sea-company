--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local SafeZoneService = require(script.Parent:WaitForChild("SafeZoneService"))
local QuotaService = require(script.Parent:WaitForChild("QuotaService"))
local MovementService = require(script.Parent:WaitForChild("MovementService"))
local MapService = require(script.Parent:WaitForChild("MapService"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LootTypes = require(Shared:WaitForChild("LootTypes"))
local remotes = Shared:WaitForChild("Remotes")
local lootUpdated = remotes:WaitForChild("LootUpdated") :: RemoteEvent
local dropRequested = remotes:WaitForChild("DropLoot") :: RemoteEvent
local selectRequested = remotes:WaitForChild("SelectLootSlot") :: RemoteEvent

type SizeClass = "Small" | "Medium" | "Large"
type Registration = {prompt: ProximityPrompt, connections: {RBXScriptConnection}}
type InventoryItem = {part: BasePart, originalParent: Instance, canCollide: boolean, massless: boolean, sizeClass: SizeClass}
type InventoryState = {slots: {[number]: InventoryItem}, selected: number}
type Template = {part: BasePart, parent: Instance, sizeClass: SizeClass}

local LootService = {}
local registered: {[BasePart]: Registration} = {}
local owners: {[BasePart]: Player} = {}
local inventories: {[Player]: InventoryState} = {}
local templates: {Template} = {}
local random = Random.new()
local started = false
local roundEnded = true
local inventoryFolder: Folder? = nil

local function numericAttribute(part: BasePart, name: string): number?
	local value = part:GetAttribute(name)
	if typeof(value) == "number" and value == value and math.abs(value) < math.huge and value >= 0 then return value end
	return nil
end

local function sizeClassOf(part: BasePart): SizeClass?
	local value = part:GetAttribute("SizeClass")
	if value == "Small" or value == "Medium" or value == "Large" then return value end
	return nil
end

local function sizeScale(sizeClass: SizeClass): number
	if sizeClass == "Small" then return Config.LootSmallScale end
	if sizeClass == "Large" then return Config.LootLargeScale end
	return Config.LootMediumScale
end

local function physicalSize(authoredSize: Vector3, sizeClass: SizeClass): Vector3
	local longestDimension = math.max(authoredSize.X, authoredSize.Y, authoredSize.Z)
	return authoredSize / longestDimension * Config.LootBaseSize * sizeScale(sizeClass)
end

local function ensureInventory(player: Player): InventoryState
	local state = inventories[player]
	if state then return state end
	state = {slots = {}, selected = 1}
	inventories[player] = state
	return state
end

local function largeItemCount(state: InventoryState): number
	local count = 0
	for _, item in state.slots do if item.sizeClass == "Large" then count += 1 end end
	return count
end

local function applyInventorySpeed(player: Player, state: InventoryState)
	local penalty = math.clamp(largeItemCount(state) * Config.LootLargeSpeedPenaltyPerItem, 0, Config.LootMaxSpeedPenalty)
	MovementService.SetCarryMultiplier(player, 1 - penalty)
end

local function sendSnapshot(player: Player)
	local state = ensureInventory(player)
	local slots: {LootTypes.SlotSnapshot} = {}
	for index = 1, Config.LootInventoryCapacity do
		local item = state.slots[index]
		table.insert(slots, {
			occupied = item ~= nil,
			name = if item then item.part.Name else "",
			value = if item then numericAttribute(item.part, "Value") or 0 else 0,
			sizeClass = if item then item.sizeClass else "",
		})
	end
	local snapshot: LootTypes.Snapshot = {slots = slots, selected = state.selected, capacity = Config.LootInventoryCapacity}
	lootUpdated:FireClient(player, snapshot)
end

local function firstEmptySlot(state: InventoryState): number?
	for index = 1, Config.LootInventoryCapacity do if not state.slots[index] then return index end end
	return nil
end

local function chooseSpawn(part: BasePart, placed: {Vector3}): boolean
	local zone = SafeZoneService.Find()
	if not zone then warn("[Loot] Missing SafeZone; keeping authored loot positions."); return true end
	if #MapService.GetRooms() == 0 then
		warn("[Loot] MISSING generated map rooms (MapService); keeping authored loot positions.")
		return true
	end
	-- Only Bounds volumes are ignored, so room walls and props still block a spawn.
	local excluded: {Instance} = {zone}
	for _, roomBounds in MapService.GetRoomBounds() do table.insert(excluded, roomBounds) end
	for _, player in Players:GetPlayers() do if player.Character then table.insert(excluded, player.Character) end end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = MapService.GetFloors()
	rayParams.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = excluded
	overlap.RespectCanCollide = true
	for _ = 1, Config.LootSpawnAttempts do
		local room = MapService.RandomRoom(random)
		local bounds = if room then room.PrimaryPart else nil
		if not bounds then continue end
		local halfSize = bounds.Size / 2
		local usableX = halfSize.X - Config.LootSpawnBoundsPadding
		local usableZ = halfSize.Z - Config.LootSpawnBoundsPadding
		if usableX <= 0 or usableZ <= 0 then continue end
		local point = bounds.CFrame:PointToWorldSpace(Vector3.new(
			random:NextNumber(-usableX, usableX),
			0,
			random:NextNumber(-usableZ, usableZ)
		))
		local safeZoneOffset = Vector3.new(point.X - zone.Position.X, 0, point.Z - zone.Position.Z)
		if safeZoneOffset.Magnitude < Config.LootSpawnMinimumSafeZoneDistance then continue end
		local rayOrigin = Vector3.new(point.X, bounds.Position.Y + Config.LootSpawnRayHeight, point.Z)
		local ground = workspace:Raycast(rayOrigin,
			-Vector3.yAxis * Config.LootSpawnRayHeight * 2, rayParams)
		if not ground or ground.Normal.Y < Config.LootSpawnMinGroundNormalY then continue end
		local position = ground.Position + Vector3.yAxis * (part.Size.Y / 2 + Config.LootSpawnClearance)
		local spawnCFrame = CFrame.new(position)
		if #workspace:GetPartBoundsInBox(spawnCFrame, part.Size, overlap) > 0 then continue end
		local separated = true
		for _, other in placed do
			if (other - position).Magnitude < math.max(Config.LootSpawnMinSeparation, part.Size.Magnitude) then separated = false; break end
		end
		if not separated then continue end
		part.CFrame = spawnCFrame
		part.Anchored = true
		print(string.format("[Loot] Spawn %s [%s]: (%.1f, %.1f), %.1f studs from sub.",
			part.Name, sizeClassOf(part) or "Medium", position.X, position.Z, safeZoneOffset.Magnitude))
		return true
	end
	warn("[Loot] No clear spawn across the generated rooms for " .. part.Name .. "; check room Bounds, Floors, and clearance.")
	return false
end

local function clearSlot(player: Player, state: InventoryState, slot: number): InventoryItem?
	local item = state.slots[slot]
	if not item then return nil end
	state.slots[slot] = nil
	owners[item.part] = nil
	applyInventorySpeed(player, state)
	return item
end

local function dropSlot(player: Player, slot: number, reason: string)
	local state = ensureInventory(player)
	local item = clearSlot(player, state, slot)
	if not item then return end
	local part = item.part
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") or not registered[part] then part:Destroy()
	else
		local parent = item.originalParent
		if parent ~= workspace and not parent:IsDescendantOf(workspace) then parent = workspace end
		part.Parent = parent
		part.CFrame = root.CFrame * Config.LootDropOffset
			* CFrame.new((slot - (Config.LootInventoryCapacity + 1) / 2) * Config.LootDropSlotSpacing, 0, 0)
		part.CanCollide = item.canCollide
		part.Massless = item.massless
		part.Anchored = false
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		if part:CanSetNetworkOwnership() then part:SetNetworkOwner(nil) end
		registered[part].prompt.Enabled = not roundEnded
	end
	print(string.format("[Loot] %s dropped slot %d: %s (%s)", player.Name, slot, part.Name, reason))
	if player.Parent == Players then sendSnapshot(player) end
end

local function dropAll(player: Player, reason: string)
	for slot = 1, Config.LootInventoryCapacity do dropSlot(player, slot, reason) end
end

local function pickup(player: Player, part: BasePart)
	local function reject(reason: string) print(string.format("[Loot] Pickup rejected for %s: %s", player.Name, reason)) end
	if roundEnded then reject("round ended"); return end
	local state = ensureInventory(player)
	local slot = firstEmptySlot(state)
	if not slot then reject("inventory full"); return end
	if owners[part] or not registered[part] or not CollectionService:HasTag(part, "Loot")
		or not part:IsDescendantOf(workspace) then reject("item unavailable"); return end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then reject("character unavailable"); return end
	if (root.Position - part.Position).Magnitude > Config.LootPickupDistance then reject("out of range"); return end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: {Instance} = {character :: Model}
	local safeZone = SafeZoneService.Find()
	if safeZone then table.insert(excluded, safeZone) end
	rayParams.FilterDescendantsInstances = excluded
	local hit = workspace:Raycast(root.Position, part.Position - root.Position, rayParams)
	if hit and hit.Instance ~= part then reject("blocked line of sight"); return end
	local value = numericAttribute(part, "Value")
	local sizeClass = sizeClassOf(part)
	if not value or not sizeClass then reject("invalid loot attributes"); return end
	local folder = inventoryFolder
	if not folder then reject("inventory storage unavailable"); return end
	state.slots[slot] = {part = part, originalParent = part.Parent :: Instance, canCollide = part.CanCollide,
		massless = part.Massless, sizeClass = sizeClass}
	state.selected = slot
	owners[part] = player
	registered[part].prompt.Enabled = false
	part.Anchored = true
	part.CanCollide = false
	part.Massless = true
	part.Parent = folder
	applyInventorySpeed(player, state)
	print(string.format("[Loot] %s stored %s [%s] in slot %d; Value=%g; large items=%d; WalkSpeed=%.2f",
		player.Name, part.Name, sizeClass, slot, value, largeItemCount(state), MovementService.GetWalkSpeed(player)))
	sendSnapshot(player)
end

local function unregister(part: BasePart)
	local entry = registered[part]
	if not entry then return end
	registered[part] = nil
	for _, connection in entry.connections do connection:Disconnect() end
	local owner = owners[part]
	if owner then
		local state = ensureInventory(owner)
		for slot, item in state.slots do if item.part == part then clearSlot(owner, state, slot); break end end
		if owner.Parent == Players then sendSnapshot(owner) end
	end
	entry.prompt:Destroy()
end

local function depositAll(player: Player, state: InventoryState)
	local deposits: {{slot: number, name: string, value: number}} = {}
	for slot = 1, Config.LootInventoryCapacity do
		local item = state.slots[slot]
		if not item then continue end
		local value = numericAttribute(item.part, "Value")
		if value == nil or not registered[item.part] or not CollectionService:HasTag(item.part, "Loot") then
			warn(string.format("[Quota] Deposit rejected for slot %d: inventory loot is unavailable or has invalid Value.", slot))
			continue
		end
		local name = item.part.Name
		clearSlot(player, state, slot)
		unregister(item.part)
		item.part:Destroy()
		table.insert(deposits, {slot = slot, name = name, value = value})
	end
	if #deposits == 0 then return end
	-- Remove the whole inventory before banking. If one item meets quota and ends
	-- the Dive, the other items that entered the SafeZone are still deposited.
	sendSnapshot(player)
	for _, deposit in deposits do
		print(string.format("[Loot] %s deposited slot %d: %s; WalkSpeed=%.2f", player.Name, deposit.slot,
			deposit.name, MovementService.GetWalkSpeed(player)))
		QuotaService.AddValue(player, deposit.value, deposit.name)
	end
end

local function dropOrDeposit(player: Player)
	local state = ensureInventory(player)
	local slot = state.selected
	if not state.slots[slot] then return end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if roundEnded or not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		dropSlot(player, slot, "character unavailable"); return
	end
	local zone = SafeZoneService.Find()
	if zone and SafeZoneService.IsCharacterInside(character, root, zone) then depositAll(player, state)
	else dropSlot(player, slot, "G requested") end
end

local function register(instance: Instance)
	if not instance:IsDescendantOf(workspace) or not instance:IsA("BasePart") then return end
	local part = instance
	if registered[part] then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LootPickupPrompt"
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.ActionText = "Pick up"
	prompt.KeyboardKeyCode = Config.LootPickupKey
	prompt.MaxActivationDistance = Config.LootPickupDistance
	prompt.HoldDuration = Config.LootPromptHoldDuration
	prompt.RequiresLineOfSight = true
	prompt.Parent = part
	local function refresh()
		prompt.ObjectText = string.format("%s | %s | Value %g", part.Name, sizeClassOf(part) or "?", numericAttribute(part, "Value") or 0)
		prompt.Enabled = not roundEnded and not owners[part] and part:IsDescendantOf(workspace)
			and numericAttribute(part, "Value") ~= nil and sizeClassOf(part) ~= nil
	end
	registered[part] = {prompt = prompt, connections = {
		prompt.Triggered:Connect(function(player: Player) pickup(player, part) end),
		part:GetAttributeChangedSignal("Value"):Connect(refresh),
		part:GetAttributeChangedSignal("SizeClass"):Connect(refresh),
		part.AncestryChanged:Connect(refresh),
		part.Destroying:Connect(function() unregister(part) end),
	}}
	refresh()
end

function LootService.EndRound()
	roundEnded = true
	for player, state in inventories do
		local lost = 0
		for slot = 1, Config.LootInventoryCapacity do
			local item = clearSlot(player, state, slot)
			if item then unregister(item.part); item.part:Destroy(); lost += 1 end
		end
		if lost > 0 then print(string.format("[Loot] %s lost %d unbanked inventory item(s) at run end.", player.Name, lost)) end
		if player.Parent == Players then sendSnapshot(player) end
	end
	for _, entry in registered do entry.prompt.Enabled = false end
	print("[Loot] Round ended; pickups disabled.")
end

function LootService.BeginRound()
	LootService.EndRound()
	for _, item in CollectionService:GetTagged("Loot") do
		if item:IsA("BasePart") and item:IsDescendantOf(workspace) then unregister(item); item:Destroy() end
	end
	roundEnded = false
	local placed: {Vector3} = {}
	local spawned = 0
	for _, template in templates do
		local part = template.part:Clone()
		part.Size = physicalSize(part.Size, template.sizeClass)
		part:SetAttribute("SizeClass", template.sizeClass)
		if not chooseSpawn(part, placed) then part:Destroy(); continue end
		table.insert(placed, part.Position)
		local parent = template.parent
		if parent ~= workspace and not parent:IsDescendantOf(workspace) then parent = workspace end
		part.Parent = parent
		CollectionService:AddTag(part, "Loot")
		register(part)
		spawned += 1
	end
	print(string.format("[Loot] Fresh dive: respawned %d varied-size loot Parts.", spawned))
end

function LootService.Start()
	if started then return end
	assert(Config.LootInventoryCapacity == 4 and #Config.LootSlotKeys == Config.LootInventoryCapacity
		and Config.LootHighlightDistance > Config.LootPickupDistance and Config.LootHighlightUpdateInterval > 0
		and Config.LootHighlightOutlineTransparency >= 0 and Config.LootHighlightOutlineTransparency <= 1
		and #Config.LootSizeClassPattern > 0 and Config.LootBaseSize > 0
		and Config.LootSmallScale > 0 and Config.LootSmallScale < Config.LootMediumScale
		and Config.LootMediumScale > 0 and Config.LootLargeScale > Config.LootMediumScale
		and Config.LootLargeSpeedPenaltyPerItem > 0
		and Config.LootSpawnAttempts > 0 and Config.LootSpawnAttempts % 1 == 0
		and Config.LootSpawnBoundsPadding >= 0 and Config.LootSpawnMinimumSafeZoneDistance >= 0,
		"Loot inventory, feedback, size, or spawn settings are invalid")
	started = true
	local folder = Instance.new("Folder")
	folder.Name = "PlayerLootInventories"
	folder.Parent = ServerStorage
	inventoryFolder = folder
	local templateIndex = 0
	for _, item in CollectionService:GetTagged("Loot") do
		if item:IsA("BasePart") and item:IsDescendantOf(workspace) then
			templateIndex += 1
			local copy = item:Clone()
			local patternValue = Config.LootSizeClassPattern[(templateIndex - 1) % #Config.LootSizeClassPattern + 1]
			local assigned = sizeClassOf(copy)
			if not assigned and (patternValue == "Small" or patternValue == "Medium" or patternValue == "Large") then assigned = patternValue end
			if assigned then table.insert(templates, {part = copy, parent = item.Parent :: Instance, sizeClass = assigned}) end
		end
	end
	if #templates == 0 then warn("[Loot] No scene loot templates captured; new dives will have no loot.") end
	CollectionService:GetInstanceAddedSignal("Loot"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("Loot"):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then unregister(instance) end
	end)
	for _, item in CollectionService:GetTagged("Loot") do register(item) end
	Players.PlayerAdded:Connect(function(player: Player) ensureInventory(player); sendSnapshot(player) end)
	Players.PlayerRemoving:Connect(function(player: Player) dropAll(player, "player left"); inventories[player] = nil end)
	for _, player in Players:GetPlayers() do ensureInventory(player); sendSnapshot(player) end
	dropRequested.OnServerEvent:Connect(dropOrDeposit)
	selectRequested.OnServerEvent:Connect(function(player: Player, slot: any)
		if typeof(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > Config.LootInventoryCapacity then return end
		local state = ensureInventory(player)
		state.selected = slot
		sendSnapshot(player)
	end)
	local accumulated = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulated += deltaTime
		if accumulated < Config.LootUpdateInterval then return end
		accumulated = 0
		local zone = SafeZoneService.Find()
		for player, state in inventories do
			local character = player.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if next(state.slots) ~= nil and (not humanoid or humanoid.Health <= 0) then
				dropAll(player, "character removed")
			elseif not roundEnded and next(state.slots) ~= nil and character and root and root:IsA("BasePart")
				and zone and SafeZoneService.IsCharacterInside(character, root, zone) then
				depositAll(player, state)
			end
		end
		for _, player in Players:GetPlayers() do sendSnapshot(player) end
	end)
	print("[Loot] Service started. E stores up to four items; SafeZone deposits all; 1-4 select; G drops outside.")
end

return LootService
