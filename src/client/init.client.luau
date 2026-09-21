--!strict

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LootTypes = require(Shared:WaitForChild("LootTypes"))
local QuotaTypes = require(Shared:WaitForChild("QuotaTypes"))
local MovementTypes = require(Shared:WaitForChild("MovementTypes"))
local RunTypes = require(Shared:WaitForChild("RunTypes"))
local Config = require(Shared:WaitForChild("Config"))
local lootUpdated = Shared:WaitForChild("Remotes"):WaitForChild("LootUpdated") :: RemoteEvent
local dropRequested = Shared:WaitForChild("Remotes"):WaitForChild("DropLoot") :: RemoteEvent
local selectLootSlot = Shared:WaitForChild("Remotes"):WaitForChild("SelectLootSlot") :: RemoteEvent
local quotaUpdated = Shared:WaitForChild("Remotes"):WaitForChild("QuotaUpdated") :: RemoteEvent
local runUpdated = Shared:WaitForChild("Remotes"):WaitForChild("RunUpdated") :: RemoteEvent
local sprintInput = Shared:WaitForChild("Remotes"):WaitForChild("SprintInput") :: RemoteEvent
local movementUpdated = Shared:WaitForChild("Remotes"):WaitForChild("MovementUpdated") :: RemoteEvent
local localPlayer = Players.LocalPlayer
localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
local playerGui = localPlayer:WaitForChild("PlayerGui")

local hud = Instance.new("ScreenGui")
hud.Name = "DiveHUD"
hud.ResetOnSpawn = false
hud.Parent = playerGui

local movementSettings = Config.Movement

-- Adapt Roblox's existing keyboard/gamepad/touch controls at their output boundary.
-- The captured vector is raw intent, never the smoothed Humanoid.MoveDirection.
local controls: any = nil
local originalMove: any = nil
local movementHumanoid: Humanoid? = nil
local movementCharacter: Model? = nil
local movementConnections: {RBXScriptConnection} = {}
local movementActive = false
local originalClientJumping = true
local originalClientSwimming = true
local movementIntent = Vector3.zero
local lastMovementSample = -math.huge
local inputElapsed = 0
local sprintHeld = false
local jumpHeld = false
local inputFocused = true
local originalPlayerAutoJump = localPlayer.AutoJumpEnabled

local function sendMovementIntent()
	local character = localPlayer.Character
	if not character then return end
	local focused = inputFocused and UserInputService:GetFocusedTextBox() == nil
	local payload: MovementTypes.Intent = {
		character = character,
		move = if focused then movementIntent else Vector3.zero,
		sprint = focused and sprintHeld,
		jump = focused and jumpHeld,
	}
	sprintInput:FireServer(payload)
end

local function clearMovementInput()
	movementIntent = Vector3.zero
	sprintHeld = false
	jumpHeld = false
	lastMovementSample = -math.huge
	sendMovementIntent()
end

local function setClientMovementActive(active: boolean)
	movementActive = active
	local humanoid, character = movementHumanoid, movementCharacter
	if humanoid and character then
		humanoid.Jump = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,
			not active and originalClientJumping)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming,
			not active and originalClientSwimming)
		humanoid.AutoJumpEnabled = not active and character:GetAttribute("MovementOriginalAutoJump") ~= false
	end
	localPlayer.AutoJumpEnabled = not active and originalPlayerAutoJump
	local button = ContextActionService:GetButton("MovementJump")
	if button then button.Visible = active end
	clearMovementInput()
end

local function unbindMovementCharacter()
	setClientMovementActive(false)
	for _, connection in movementConnections do connection:Disconnect() end
	table.clear(movementConnections)
	movementCharacter = nil
	movementHumanoid = nil
end

local function bindMovementCharacter(character: Model, humanoid: Humanoid)
	unbindMovementCharacter()
	movementCharacter = character
	movementHumanoid = humanoid
	originalClientJumping = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
	originalClientSwimming = humanoid:GetStateEnabled(Enum.HumanoidStateType.Swimming)
	local function refresh()
		setClientMovementActive(humanoid.Health > 0 and character:GetAttribute("GroundedFloatyActive") == true)
	end
	table.insert(movementConnections, character:GetAttributeChangedSignal("GroundedFloatyActive"):Connect(refresh))
	table.insert(movementConnections, humanoid.Died:Connect(unbindMovementCharacter))
	refresh()
end

-- Loading in a task keeps the HUD/character hooks available during PlayerModule startup.
task.spawn(function()
	local playerModule = StarterPlayer:FindFirstChild("PlayerModule")
	if playerModule and playerModule:FindFirstChild("ControlModule") then
		-- Current Roblox layout: the singleton ControlModule lives in StarterPlayer.
		controls = require(playerModule:WaitForChild("ControlModule") :: ModuleScript)
	else
		-- Legacy Roblox layout exposes the same control adapter through GetControls().
		local legacy = localPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript
		controls = require(legacy):GetControls()
	end
	assert(typeof(controls.moveFunction) == "function", "[Movement] Roblox control adapter has no moveFunction")
	originalMove = controls.moveFunction
	controls.moveFunction = function(player: Player, move: Vector3, cameraRelative: boolean)
		local humanoid = movementHumanoid
		if cameraRelative and humanoid then move = controls:calculateRawMoveVector(humanoid, move) end
		movementIntent = Vector3.new(move.X, 0, move.Z)
		lastMovementSample = os.clock()
		if not movementActive then originalMove(player, move, false) end
	end
end)

local function movementAction(action: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if action == "MovementJump" and not movementActive then return Enum.ContextActionResult.Pass end
	if inputState == Enum.UserInputState.Begin then
		if UserInputService:GetFocusedTextBox() or not inputFocused then return Enum.ContextActionResult.Pass end
		if action == "MovementJump" then jumpHeld = true else sprintHeld = true end
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		if action == "MovementJump" then jumpHeld = false else sprintHeld = false end
	else
		return Enum.ContextActionResult.Sink
	end
	-- Edges send immediately so a quick tap between regular packets is not lost.
	sendMovementIntent()
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindActionAtPriority("MovementSprint", movementAction, true, Enum.ContextActionPriority.High.Value,
	movementSettings.SprintKey, movementSettings.SprintGamepadKey)
ContextActionService:BindActionAtPriority("MovementJump", movementAction, true, Enum.ContextActionPriority.High.Value,
	movementSettings.JumpKey, movementSettings.JumpGamepadKey)
ContextActionService:SetTitle("MovementSprint", "Sprint")
ContextActionService:SetTitle("MovementJump", "Jump")
ContextActionService:SetPosition("MovementSprint", movementSettings.SprintTouchPosition)
ContextActionService:SetPosition("MovementJump", movementSettings.JumpTouchPosition)

local function updateMovementInput(deltaTime: number)
	if movementActive and movementHumanoid then movementHumanoid.Jump = false end
	if os.clock() - lastMovementSample > movementSettings.InputTimeout then movementIntent = Vector3.zero end
	inputElapsed += deltaTime
	if inputElapsed >= 1 / movementSettings.InputSendRate then
		inputElapsed %= 1 / movementSettings.InputSendRate
		sendMovementIntent()
	end
end

localPlayer.CharacterRemoving:Connect(unbindMovementCharacter)
script.Destroying:Connect(function()
	unbindMovementCharacter()
	if controls and originalMove then controls.moveFunction = originalMove end
	ContextActionService:UnbindAction("MovementSprint")
	ContextActionService:UnbindAction("MovementJump")
end)

local quotaLabel = Instance.new("TextLabel")
quotaLabel.AnchorPoint = Vector2.new(0.5, 0)
quotaLabel.Position = UDim2.new(0.5, 0, 0, 18)
quotaLabel.Size = UDim2.fromOffset(430, 42)
quotaLabel.BackgroundColor3 = Color3.fromRGB(12, 24, 28)
quotaLabel.BackgroundTransparency = 0.15
quotaLabel.BorderSizePixel = 0
quotaLabel.Font = Enum.Font.GothamBold
quotaLabel.TextSize = 22
quotaLabel.TextColor3 = Color3.new(1, 1, 1)
quotaLabel.Text = "Banked: waiting for server..."
quotaLabel.Parent = hud

local statusPanel = Instance.new("Frame")
statusPanel.Position = UDim2.fromOffset(24, 24)
statusPanel.Size = UDim2.fromOffset(280, 81)
statusPanel.BackgroundColor3 = Color3.fromRGB(12, 24, 28)
statusPanel.BackgroundTransparency = 0.15
statusPanel.BorderSizePixel = 0
statusPanel.Parent = hud

local function createStatusBar(name: string, y: number, color: Color3): (Frame, TextLabel)
	local text = Instance.new("TextLabel")
	text.Position = UDim2.fromOffset(10, y)
	text.Size = UDim2.fromOffset(62, 26)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.Text = name
	text.TextColor3 = color
	text.TextSize = 14
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Parent = statusPanel
	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(72, y + 4)
	track.Size = UDim2.fromOffset(196, 18)
	track.BackgroundColor3 = Color3.fromRGB(42, 52, 56)
	track.BorderSizePixel = 0
	track.Parent = statusPanel
	local fill = Instance.new("Frame")
	fill.Name = name .. "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track
	return fill, text
end

local healthFill, healthLabel = createStatusBar("HP", 8, Color3.fromRGB(225, 65, 65))
local staminaFill, staminaLabel = createStatusBar("STAM", 43, Color3.fromRGB(70, 220, 115))

local healthConnection: RBXScriptConnection? = nil

local function updateHealth(humanoid: Humanoid)
	local fraction = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
	healthFill.Size = UDim2.fromScale(fraction, 1)
	healthLabel.Text = if humanoid.Health <= 0 then "DOWN" else string.format("HP %d", math.ceil(humanoid.Health))
end

local function bindCharacter(character: Model)
	if healthConnection then healthConnection:Disconnect() end
	healthConnection = nil
	local instance = character:WaitForChild("Humanoid")
	if localPlayer.Character ~= character or not instance:IsA("Humanoid") then return end
	local humanoid = instance
	bindMovementCharacter(character, humanoid)
	updateHealth(humanoid)
	healthConnection = humanoid.HealthChanged:Connect(function()
		updateHealth(humanoid)
	end)
end

localPlayer.CharacterAdded:Connect(function(character: Model)
	task.spawn(bindCharacter, character)
end)
if localPlayer.Character then task.spawn(bindCharacter, localPlayer.Character) end

local inventoryConsole = Instance.new("Frame")
inventoryConsole.AnchorPoint = Vector2.new(0.5, 1)
inventoryConsole.Position = UDim2.new(0.5, 0, 1, -24)
inventoryConsole.Size = UDim2.fromOffset(392, 92)
inventoryConsole.BackgroundColor3 = Color3.fromRGB(12, 24, 28)
inventoryConsole.BackgroundTransparency = 0.1
inventoryConsole.BorderSizePixel = 0
inventoryConsole.Parent = hud

local slotLabels: {TextLabel} = {}
local slotStrokes: {UIStroke} = {}
for index = 1, Config.LootInventoryCapacity do
	local slot = Instance.new("TextLabel")
	slot.Position = UDim2.fromOffset(8 + (index - 1) * 96, 8)
	slot.Size = UDim2.fromOffset(88, 76)
	slot.BackgroundColor3 = Color3.fromRGB(28, 42, 46)
	slot.BorderSizePixel = 0
	slot.Font = Enum.Font.GothamBold
	slot.Text = string.format("%d\nEMPTY", index)
	slot.TextColor3 = Color3.fromRGB(205, 225, 225)
	slot.TextSize = 12
	slot.TextWrapped = true
	slot.Parent = inventoryConsole
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(80, 105, 110)
	stroke.Thickness = 2
	stroke.Parent = slot
	table.insert(slotLabels, slot)
	table.insert(slotStrokes, stroke)
end

local inventoryFull = false
local activeLootHighlights: {[BasePart]: Highlight} = {}
local lootHighlightPool: {Highlight} = {}
local lootHighlightElapsed = 0
local lootHighlightFolder = Instance.new("Folder")
lootHighlightFolder.Name = "LootHighlights"
lootHighlightFolder.Parent = workspace

local function lootPrompt(part: BasePart): ProximityPrompt?
	local prompt = part:FindFirstChild("LootPickupPrompt")
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

local function refreshLootPrompt(part: BasePart)
	local prompt = lootPrompt(part)
	if prompt then prompt.ActionText = if inventoryFull then "Inventory full" else "Pick up" end
end

local function showLootHighlight(part: BasePart)
	if activeLootHighlights[part] then return end
	local highlight = table.remove(lootHighlightPool)
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "LootOutline"
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = 1
		highlight.Parent = lootHighlightFolder
	end
	highlight.OutlineColor = Config.LootHighlightColor
	highlight.OutlineTransparency = Config.LootHighlightOutlineTransparency
	highlight.Adornee = part
	highlight.Enabled = true
	activeLootHighlights[part] = highlight
end

local function hideLootHighlight(part: BasePart, highlight: Highlight)
	activeLootHighlights[part] = nil
	highlight.Enabled = false
	highlight.Adornee = nil
	table.insert(lootHighlightPool, highlight)
end

local function lootIsVisible(camera: Camera, part: BasePart, rayParams: RaycastParams): boolean
	local offset = part.Position - camera.CFrame.Position
	if offset.Magnitude > Config.LootHighlightDistance then return false end
	local _, onScreen = camera:WorldToViewportPoint(part.Position)
	if not onScreen then return false end
	local hit = workspace:Raycast(camera.CFrame.Position, offset, rayParams)
	return hit == nil or hit.Instance == part
end

local function updateLootFeedback()
	local camera = workspace.CurrentCamera
	local visible: {[BasePart]: boolean} = {}
	if camera then
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local excluded: {Instance} = {}
		if localPlayer.Character then table.insert(excluded, localPlayer.Character) end
		local submarine = workspace:FindFirstChild("Submarine")
		local safeZone = if submarine then submarine:FindFirstChild("SafeZone") else nil
		if safeZone then table.insert(excluded, safeZone) end
		local ruin = workspace:FindFirstChild("GreyboxRuin")
		local threatBounds = if ruin then ruin:FindFirstChild("ThreatBounds", true) else nil
		if threatBounds then table.insert(excluded, threatBounds) end
		rayParams.FilterDescendantsInstances = excluded
		rayParams.IgnoreWater = true
		for _, instance in CollectionService:GetTagged("Loot") do
			if not instance:IsA("BasePart") or not instance:IsDescendantOf(workspace) then continue end
			local part = instance
			refreshLootPrompt(part)
			local prompt = lootPrompt(part)
			if prompt and prompt.Enabled and lootIsVisible(camera, part, rayParams) then
				visible[part] = true
				showLootHighlight(part)
			end
		end
	end
	for part, highlight in activeLootHighlights do
		if not visible[part] then hideLootHighlight(part, highlight) end
	end
end

lootUpdated.OnClientEvent:Connect(function(snapshot: LootTypes.Snapshot)
	local occupiedSlots = 0
	for index = 1, snapshot.capacity do
		local slot = snapshot.slots[index]
		if slot and slot.occupied then occupiedSlots += 1 end
		slotLabels[index].Text = if slot and slot.occupied
			then string.format("%d | %s\n%s\n$%g", index, slot.sizeClass, slot.name, slot.value)
			else string.format("%d\nEMPTY", index)
		slotStrokes[index].Color = if index == snapshot.selected then Color3.fromRGB(110, 235, 205)
			else Color3.fromRGB(80, 105, 110)
		slotStrokes[index].Thickness = if index == snapshot.selected then 4 else 2
	end
	inventoryFull = occupiedSlots >= snapshot.capacity
	for _, instance in CollectionService:GetTagged("Loot") do
		if instance:IsA("BasePart") then refreshLootPrompt(instance) end
	end
end)

RunService.Heartbeat:Connect(function(deltaTime: number)
	lootHighlightElapsed += deltaTime
	if lootHighlightElapsed < Config.LootHighlightUpdateInterval then return end
	lootHighlightElapsed = 0
	updateLootFeedback()
end)

movementUpdated.OnClientEvent:Connect(function(snapshot: MovementTypes.Snapshot)
	local fraction = math.clamp(snapshot.stamina / snapshot.maximum, 0, 1)
	staminaFill.Size = UDim2.fromScale(fraction, 1)
	staminaLabel.Text = if snapshot.exhausted then "TIRED" else "STAM"
end)

quotaUpdated.OnClientEvent:Connect(function(snapshot: QuotaTypes.Snapshot)
	quotaLabel.Text = string.format("Banked: %g / %g%s", snapshot.bankedValue, snapshot.quota,
		if snapshot.met then " | QUOTA MET" else "")
end)

local markerSettings = Config.SafeZoneMarker
local safeZonePosition: Vector3? = nil
local runPhase: RunTypes.Phase = "Lobby"
local navigationGui = Instance.new("ScreenGui")
navigationGui.Name = "SafeZoneNavigation"
navigationGui.ResetOnSpawn = false
navigationGui.IgnoreGuiInset = true
navigationGui.Parent = playerGui

local safeZoneMarker = Instance.new("TextLabel")
safeZoneMarker.Name = "SafeZoneMarker"
safeZoneMarker.AnchorPoint = Vector2.new(0.5, 0.5)
safeZoneMarker.Size = UDim2.fromOffset(markerSettings.IconSize, markerSettings.IconSize)
safeZoneMarker.BackgroundColor3 = markerSettings.BackgroundColor
safeZoneMarker.BackgroundTransparency = markerSettings.BackgroundTransparency
safeZoneMarker.BorderSizePixel = 0
safeZoneMarker.Font = Enum.Font.GothamBold
safeZoneMarker.Text = "⌂"
safeZoneMarker.TextSize = markerSettings.TextSize
safeZoneMarker.TextColor3 = markerSettings.Color
safeZoneMarker.Visible = false
safeZoneMarker.Parent = navigationGui

local markerCorner = Instance.new("UICorner")
markerCorner.CornerRadius = UDim.new(0.5, 0)
markerCorner.Parent = safeZoneMarker

local safeZoneArrow = Instance.new("TextLabel")
safeZoneArrow.AnchorPoint = Vector2.new(0.5, 0.5)
safeZoneArrow.Size = UDim2.fromOffset(markerSettings.ArrowSize, markerSettings.ArrowSize)
safeZoneArrow.BackgroundTransparency = 1
safeZoneArrow.Font = Enum.Font.GothamBold
safeZoneArrow.Text = "▲"
safeZoneArrow.TextSize = markerSettings.ArrowSize
safeZoneArrow.TextColor3 = markerSettings.Color
safeZoneArrow.Parent = safeZoneMarker

-- Project the server's SafeZone position each frame so the icon tracks the camera.
RunService.RenderStepped:Connect(function(deltaTime: number)
	updateMovementInput(deltaTime)
	local target = safeZonePosition
	local camera = workspace.CurrentCamera
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local submarine = workspace:FindFirstChild("Submarine")
	local zoneInstance = if submarine then submarine:FindFirstChild("SafeZone") else nil
	local zone = if zoneInstance and zoneInstance:IsA("BasePart") then zoneInstance else nil
	local inSub = false
	if root and root:IsA("BasePart") and zone then
		local point = zone.CFrame:PointToObjectSpace(root.Position)
		local halfSize = zone.Size / 2
		inSub = math.abs(point.X) <= halfSize.X and math.abs(point.Y) <= halfSize.Y
			and math.abs(point.Z) <= halfSize.Z
	end
	safeZoneMarker.Visible = runPhase == "Dive" and target ~= nil and camera ~= nil
		and humanoid ~= nil and humanoid.Health > 0 and root ~= nil and not inSub
	if not safeZoneMarker.Visible or not target or not camera then return end
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		safeZoneMarker.Visible = false
		return
	end
	local center = viewport / 2
	local padding = math.min(markerSettings.EdgePadding, math.min(viewport.X, viewport.Y) / 4)
	local bottomPadding = math.max(padding, math.min(markerSettings.BottomPadding, viewport.Y / 3))
	local minimum = Vector2.new(padding, padding)
	local maximum = Vector2.new(viewport.X - padding, viewport.Y - bottomPadding)
	local projected = camera:WorldToViewportPoint(target)
	local point = Vector2.new(projected.X, projected.Y)
	local withinBounds = projected.Z > 0 and point.X >= minimum.X and point.X <= maximum.X
		and point.Y >= minimum.Y and point.Y <= maximum.Y
	safeZoneArrow.Visible = not withinBounds
	if not withinBounds then
		-- Camera-space direction avoids mirrored projection for targets behind us.
		local cameraTarget = camera.CFrame:PointToObjectSpace(target)
		local direction = Vector2.new(cameraTarget.X, -cameraTarget.Y)
		if direction.Magnitude == 0 then direction = Vector2.new(0, 1) end
		direction = direction.Unit
		local horizontal = if direction.X > 0 then (maximum.X - center.X) / direction.X
			elseif direction.X < 0 then (minimum.X - center.X) / direction.X else math.huge
		local vertical = if direction.Y > 0 then (maximum.Y - center.Y) / direction.Y
			elseif direction.Y < 0 then (minimum.Y - center.Y) / direction.Y else math.huge
		point = center + direction * math.min(horizontal, vertical)
		local iconCenter = Vector2.new(markerSettings.IconSize / 2, markerSettings.IconSize / 2)
		local arrowPosition = iconCenter + direction * markerSettings.ArrowOffset
		safeZoneArrow.Position = UDim2.fromOffset(arrowPosition.X, arrowPosition.Y)
		safeZoneArrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
	end
	safeZoneMarker.Position = UDim2.fromOffset(point.X, point.Y)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if UserInputService:GetFocusedTextBox() then return end
	if processed then return end
	for index, keyCode in Config.LootSlotKeys do
		if input.KeyCode == keyCode then
			selectLootSlot:FireServer(index)
			return
		end
	end
	if input.KeyCode == Config.LootDropKey then
		dropRequested:FireServer()
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	inputFocused = false
	clearMovementInput()
end)

UserInputService.WindowFocused:Connect(function() inputFocused = true end)
UserInputService.TextBoxFocused:Connect(clearMovementInput)

runUpdated.OnClientEvent:Connect(function(snapshot: RunTypes.Snapshot)
	runPhase = snapshot.phase
	safeZonePosition = snapshot.safeZonePosition
end)
