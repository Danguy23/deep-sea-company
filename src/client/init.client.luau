--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OxygenTypes = require(Shared:WaitForChild("OxygenTypes"))
local LootTypes = require(Shared:WaitForChild("LootTypes"))
local QuotaTypes = require(Shared:WaitForChild("QuotaTypes"))
local MovementTypes = require(Shared:WaitForChild("MovementTypes"))
local Config = require(Shared:WaitForChild("Config"))
local lootUpdated = Shared:WaitForChild("Remotes"):WaitForChild("LootUpdated") :: RemoteEvent
local dropRequested = Shared:WaitForChild("Remotes"):WaitForChild("DropLoot") :: RemoteEvent
local selectLootSlot = Shared:WaitForChild("Remotes"):WaitForChild("SelectLootSlot") :: RemoteEvent
local oxygenUpdated = Shared:WaitForChild("Remotes"):WaitForChild("OxygenUpdated") :: RemoteEvent
local quotaUpdated = Shared:WaitForChild("Remotes"):WaitForChild("QuotaUpdated") :: RemoteEvent
local flashlightInput = Shared:WaitForChild("Remotes"):WaitForChild("FlashlightInput") :: RemoteEvent
local flashlightUpdated = Shared:WaitForChild("Remotes"):WaitForChild("FlashlightUpdated") :: RemoteEvent
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
statusPanel.Size = UDim2.fromOffset(280, 116)
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
local oxygenFill, oxygenLabel = createStatusBar("AIR", 78, Color3.fromRGB(80, 195, 225))

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
	stroke.Color = Color3.fromRGB(80, 105, 110)
	stroke.Thickness = 2
	stroke.Parent = slot
	table.insert(slotLabels, slot)
	table.insert(slotStrokes, stroke)
end

lootUpdated.OnClientEvent:Connect(function(snapshot: LootTypes.Snapshot)
	for index = 1, snapshot.capacity do
		local slot = snapshot.slots[index]
		slotLabels[index].Text = if slot and slot.occupied
			then string.format("%d | %s\n%s\n$%g", index, slot.sizeClass, slot.name, slot.value)
			else string.format("%d\nEMPTY", index)
		slotStrokes[index].Color = if index == snapshot.selected then Color3.fromRGB(110, 235, 205)
			else Color3.fromRGB(80, 105, 110)
		slotStrokes[index].Thickness = if index == snapshot.selected then 4 else 2
	end
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

local flashlightEnabled = false
local aimElapsed = 0

flashlightUpdated.OnClientEvent:Connect(function(enabled: boolean)
	flashlightEnabled = enabled
	aimElapsed = Config.Flashlight.AimUpdateInterval
end)

local markerSettings = Config.SafeZoneMarker
local safeZonePosition: Vector3? = nil
local showSafeZoneMarker = false
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
RunService.RenderStepped:Connect(function()
	local target = safeZonePosition
	local camera = workspace.CurrentCamera
	safeZoneMarker.Visible = showSafeZoneMarker and target ~= nil and camera ~= nil
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

-- Sample camera look as input intent; the server owns the actual light.
RunService.Heartbeat:Connect(function(deltaTime: number)
	if not flashlightEnabled then return end
	aimElapsed += deltaTime
	if aimElapsed < Config.Flashlight.AimUpdateInterval then return end
	aimElapsed = 0
	local camera = workspace.CurrentCamera
	if camera then flashlightInput:FireServer("Aim", camera.CFrame.LookVector) end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == movementSettings.SprintKey then
		sprintInput:FireServer(true)
		return
	end
	if processed then return end
	for index, keyCode in Config.LootSlotKeys do
		if input.KeyCode == keyCode then
			selectLootSlot:FireServer(index)
			return
		end
	end
	if input.KeyCode == Config.LootDropKey then
		dropRequested:FireServer()
	elseif input.KeyCode == Config.Flashlight.ToggleKey then
		flashlightInput:FireServer("Toggle")
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == movementSettings.SprintKey then sprintInput:FireServer(false) end
end)

UserInputService.WindowFocusReleased:Connect(function()
	sprintInput:FireServer(false)
end)

oxygenUpdated.OnClientEvent:Connect(function(snapshot: OxygenTypes.Snapshot)
	safeZonePosition = snapshot.safeZonePosition
	showSafeZoneMarker = snapshot.available and not snapshot.inSub and not snapshot.roundEnded
		and not snapshot.downed and snapshot.health > 0
	local oxygenFraction = math.clamp(snapshot.oxygen / snapshot.maximum, 0, 1)
	oxygenFill.Size = UDim2.fromScale(oxygenFraction, 1)
	oxygenFill.BackgroundColor3 = if oxygenFraction <= 0.25 then Color3.fromRGB(235, 85, 70)
		else Color3.fromRGB(80, 195, 225)
	local healthFraction = math.clamp(snapshot.health / snapshot.healthMaximum, 0, 1)
	healthFill.Size = UDim2.fromScale(healthFraction, 1)
	local status = if snapshot.roundEnded then "Round ended"
		elseif snapshot.downed then "Downed"
		elseif not snapshot.available then "SafeZone missing"
		elseif snapshot.inSub then "In sub"
		elseif snapshot.oxygen <= 0 then "OUT OF AIR!"
		else "Outside sub"
	oxygenLabel.Text = string.format("AIR %d", math.ceil(snapshot.oxygen))
	healthLabel.Text = string.format("HP %d", math.ceil(snapshot.health))
	if status == "Downed" then healthLabel.Text = "DOWN" end
end)
