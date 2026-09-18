--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LootTypes = require(Shared:WaitForChild("LootTypes"))
local remotes = Shared:WaitForChild("Remotes")
local lootUpdated = remotes:WaitForChild("LootUpdated") :: RemoteEvent
local dropRequested = remotes:WaitForChild("DropLoot") :: RemoteEvent

type Registration = {prompt: ProximityPrompt, connections: {RBXScriptConnection}}
type Carry = {
	part: BasePart,
	root: BasePart,
	humanoid: Humanoid,
	weld: WeldConstraint,
	baseSpeed: number,
	canCollide: boolean,
	massless: boolean,
	deathConnection: RBXScriptConnection,
}

local LootService = {}
local registered: {[BasePart]: Registration} = {}
local carried: {[Player]: Carry} = {}
local owners: {[BasePart]: Player} = {}
local started = false
local roundEnded = false

local function numericAttribute(part: BasePart, name: string): number?
	local value = part:GetAttribute(name)
	if typeof(value) == "number" and value == value and math.abs(value) < math.huge and value >= 0 then
		return value
	end
	return nil
end

local function weightOf(part: BasePart): number
	return numericAttribute(part, "Weight") or Config.LootDefaultWeight
end

local function applySpeed(carry: Carry)
	local penalty = math.clamp(weightOf(carry.part) * Config.LootSpeedPenaltyPerWeight, 0, Config.LootMaxSpeedPenalty)
	carry.humanoid.WalkSpeed = carry.baseSpeed * (1 - penalty)
end

local function sendSnapshot(player: Player)
	local carry = carried[player]
	local snapshot: LootTypes.Snapshot = {
		carrying = carry ~= nil,
		name = if carry then carry.part.Name else "",
		value = if carry then numericAttribute(carry.part, "Value") or 0 else 0,
		weight = if carry then weightOf(carry.part) else 0,
	}
	lootUpdated:FireClient(player, snapshot)
end

local function drop(player: Player, reason: string)
	local carry = carried[player]
	if not carry then
		return
	end
	-- Clear ownership before changing physics or firing any callbacks.
	carried[player] = nil
	owners[carry.part] = nil
	carry.deathConnection:Disconnect()
	carry.weld:Destroy()
	carry.humanoid.WalkSpeed = carry.baseSpeed
	local part = carry.part
	part.CanCollide = carry.canCollide
	part.Massless = carry.massless
	if part:IsDescendantOf(workspace) then
		part.CFrame = carry.root.CFrame * Config.LootDropOffset
		part.Anchored = false
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		local canSetOwnership = part:CanSetNetworkOwnership()
		if canSetOwnership then
			part:SetNetworkOwner(nil)
		end
	end
	local entry = registered[part]
	if entry then
		entry.prompt.Enabled = not roundEnded and part:IsDescendantOf(workspace) and numericAttribute(part, "Value") ~= nil
	end
	print(string.format("[Loot] %s dropped %s (%s); WalkSpeed=%.2f", player.Name, part.Name, reason, carry.baseSpeed))
	if player.Parent == Players then
		sendSnapshot(player)
	end
end

local function pickup(player: Player, part: BasePart)
	local function reject(reason: string)
		print(string.format("[Loot] Pickup rejected for %s: %s", player.Name, reason))
	end
	if roundEnded then reject("round ended"); return end
	if carried[player] then reject("already carrying one item"); return end
	if owners[part] or not registered[part] or not CollectionService:HasTag(part, "Loot") or not part:IsDescendantOf(workspace) then
		reject("item unavailable"); return
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then reject("character unavailable"); return end
	-- Prompt events are input intent: independently validate range and visibility.
	if (root.Position - part.Position).Magnitude > Config.LootPickupDistance then reject("out of range"); return end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character :: Model}
	local hit = workspace:Raycast(root.Position, part.Position - root.Position, rayParams)
	if hit and hit.Instance ~= part then reject("blocked line of sight"); return end
	local value = numericAttribute(part, "Value")
	if not value then reject("invalid Value attribute"); return end
	local weld = Instance.new("WeldConstraint")
	weld.Name = "LootCarryWeld"
	local carry: Carry = {
		part = part, root = root, humanoid = humanoid, weld = weld,
		baseSpeed = humanoid.WalkSpeed, canCollide = part.CanCollide, massless = part.Massless,
		deathConnection = humanoid.Died:Connect(function() drop(player, "death") end),
	}
	carried[player] = carry
	owners[part] = player
	registered[part].prompt.Enabled = false
	part.CanCollide = false
	part.Massless = true
	part.Anchored = false
	part.CFrame = root.CFrame * Config.LootCarryOffset
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	applySpeed(carry)
	print(string.format("[Loot] %s picked up %s: Value=%g Weight=%g WalkSpeed=%.2f", player.Name, part.Name, value, weightOf(part), humanoid.WalkSpeed))
	sendSnapshot(player)
end

local function unregister(part: BasePart)
	local entry = registered[part]
	if not entry then return end
	registered[part] = nil
	for _, connection in entry.connections do connection:Disconnect() end
	local owner = owners[part]
	if owner then drop(owner, "item removed") end
	entry.prompt:Destroy()
end

local function register(instance: Instance)
	if not instance:IsA("BasePart") then
		warn("[Loot] Loot tag requires a Part: " .. instance:GetFullName())
		return
	end
	local part = instance
	if registered[part] then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LootPickupPrompt"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = part.Name
	prompt.KeyboardKeyCode = Config.LootPickupKey
	prompt.MaxActivationDistance = Config.LootPickupDistance
	prompt.HoldDuration = Config.LootPromptHoldDuration
	prompt.RequiresLineOfSight = true
	prompt.Parent = part
	local function refresh()
		prompt.ObjectText = string.format("%s | Value %g", part.Name, numericAttribute(part, "Value") or 0)
		prompt.Enabled = not roundEnded and not owners[part] and part:IsDescendantOf(workspace) and numericAttribute(part, "Value") ~= nil
		local owner = owners[part]
		if owner then applySpeed(carried[owner]) end
	end
	registered[part] = {prompt = prompt, connections = {
		prompt.Triggered:Connect(function(player: Player) pickup(player, part) end),
		part:GetAttributeChangedSignal("Value"):Connect(refresh),
		part:GetAttributeChangedSignal("Weight"):Connect(refresh),
		part.AncestryChanged:Connect(function()
			if not part:IsDescendantOf(workspace) and owners[part] then drop(owners[part], "item left Workspace") end
			refresh()
		end),
		part.Destroying:Connect(function() unregister(part) end),
	}}
	refresh()
	if not numericAttribute(part, "Value") then warn("[Loot] Missing/invalid numeric Value: " .. part:GetFullName()) end
	if part:GetAttribute("Weight") ~= nil and not numericAttribute(part, "Weight") then warn("[Loot] Invalid Weight; using default: " .. part:GetFullName()) end
	print(string.format("[Loot] Registered %s: Value=%g Weight=%g", part.Name, numericAttribute(part, "Value") or 0, weightOf(part)))
end

function LootService.EndRound()
	roundEnded = true
	for player in carried do drop(player, "round ended") end
	for _, entry in registered do entry.prompt.Enabled = false end
	print("[Loot] Round ended; pickups disabled until Stop/Play.")
end

function LootService.Start()
	if started then return end
	started = true
	CollectionService:GetInstanceAddedSignal("Loot"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("Loot"):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then unregister(instance) end
	end)
	local items = CollectionService:GetTagged("Loot")
	for _, item in items do register(item) end
	if #items == 0 then warn("[Loot] No Parts tagged Loot found; tag scene Parts and add numeric Value attributes.") end
	dropRequested.OnServerEvent:Connect(function(player: Player) drop(player, "G requested") end)
	Players.PlayerRemoving:Connect(function(player: Player) drop(player, "player left") end)
	local accumulated = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulated += deltaTime
		if accumulated < Config.LootUpdateInterval then return end
		accumulated = 0
		for player, carry in carried do
			if player.Character ~= carry.root.Parent or carry.humanoid.Health <= 0 then drop(player, "character removed") end
		end
		for _, player in Players:GetPlayers() do sendSnapshot(player) end
	end)
	print("[Loot] Service started. Hold E to pick up; G to drop. One item per player.")
end

return LootService
