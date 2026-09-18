--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OxygenTypes = require(Shared:WaitForChild("OxygenTypes"))
local LootTypes = require(Shared:WaitForChild("LootTypes"))
local QuotaTypes = require(Shared:WaitForChild("QuotaTypes"))
local Config = require(Shared:WaitForChild("Config"))
local lootUpdated = Shared:WaitForChild("Remotes"):WaitForChild("LootUpdated") :: RemoteEvent
local dropRequested = Shared:WaitForChild("Remotes"):WaitForChild("DropLoot") :: RemoteEvent
local oxygenUpdated = Shared:WaitForChild("Remotes"):WaitForChild("OxygenUpdated") :: RemoteEvent
local quotaUpdated = Shared:WaitForChild("Remotes"):WaitForChild("QuotaUpdated") :: RemoteEvent
local flashlightInput = Shared:WaitForChild("Remotes"):WaitForChild("FlashlightInput") :: RemoteEvent
local flashlightUpdated = Shared:WaitForChild("Remotes"):WaitForChild("FlashlightUpdated") :: RemoteEvent
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local hud = Instance.new("ScreenGui")
hud.Name = "OxygenHUD"
hud.ResetOnSpawn = false
hud.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -24)
panel.Size = UDim2.fromOffset(380, 164)
panel.BackgroundColor3 = Color3.fromRGB(20, 30, 40)
panel.BorderSizePixel = 0
panel.Parent = hud

local label = Instance.new("TextLabel")
label.Position = UDim2.fromOffset(10, 6)
label.Size = UDim2.new(1, -20, 0, 28)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 16
label.TextColor3 = Color3.new(1, 1, 1)
label.Text = "Oxygen: waiting for server..."
label.Parent = panel

local track = Instance.new("Frame")
track.Position = UDim2.fromOffset(10, 40)
track.Size = UDim2.new(1, -20, 0, 18)
track.BackgroundColor3 = Color3.fromRGB(50, 60, 70)
track.BorderSizePixel = 0
track.Parent = panel

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(65, 210, 160)
fill.BorderSizePixel = 0
fill.Parent = track

local lootLabel = Instance.new("TextLabel")
lootLabel.Position = UDim2.fromOffset(10, 64)
lootLabel.Size = UDim2.new(1, -20, 0, 28)
lootLabel.BackgroundTransparency = 1
lootLabel.Font = Enum.Font.Gotham
lootLabel.TextSize = 14
lootLabel.TextColor3 = Color3.new(1, 1, 1)
lootLabel.Text = "Carried Value: waiting for server..."
lootLabel.Parent = panel

lootUpdated.OnClientEvent:Connect(function(snapshot: LootTypes.Snapshot)
	lootLabel.Text = if snapshot.carrying then string.format("Carried Value: %g | %s | G: drop/deposit", snapshot.value, snapshot.name)
		else "Carried Value: 0 | Empty hands"
end)

local quotaLabel = Instance.new("TextLabel")
quotaLabel.Position = UDim2.fromOffset(10, 96)
quotaLabel.Size = UDim2.new(1, -20, 0, 28)
quotaLabel.BackgroundTransparency = 1
quotaLabel.Font = Enum.Font.GothamBold
quotaLabel.TextSize = 16
quotaLabel.TextColor3 = Color3.new(1, 1, 1)
quotaLabel.Text = "Banked: waiting for server..."
quotaLabel.Parent = panel

quotaUpdated.OnClientEvent:Connect(function(snapshot: QuotaTypes.Snapshot)
	quotaLabel.Text = string.format("Banked: %g / %g%s", snapshot.bankedValue, snapshot.quota, if snapshot.met then " | Quota met" else "")
end)

local healthLabel = Instance.new("TextLabel")
healthLabel.Position = UDim2.fromOffset(10, 128)
healthLabel.Size = UDim2.new(1, -20, 0, 28)
healthLabel.BackgroundTransparency = 1
healthLabel.Font = Enum.Font.GothamBold
healthLabel.TextSize = 16
healthLabel.TextColor3 = Color3.new(1, 1, 1)
healthLabel.Text = "HP: waiting for server..."
healthLabel.Parent = panel

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
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Config.LootDropKey then
		dropRequested:FireServer()
	elseif input.KeyCode == Config.Flashlight.ToggleKey then
		flashlightInput:FireServer("Toggle")
	end
end)

oxygenUpdated.OnClientEvent:Connect(function(snapshot: OxygenTypes.Snapshot)
	safeZonePosition = snapshot.safeZonePosition
	showSafeZoneMarker = snapshot.available and not snapshot.inSub and not snapshot.roundEnded
		and not snapshot.downed and snapshot.health > 0
	local fraction = math.clamp(snapshot.oxygen / snapshot.maximum, 0, 1)
	fill.Size = UDim2.fromScale(fraction, 1)
	fill.BackgroundColor3 = if fraction <= 0.25 then Color3.fromRGB(235, 85, 70) else Color3.fromRGB(65, 210, 160)
	local status = if snapshot.roundEnded then "Round ended"
		elseif snapshot.downed then "Downed"
		elseif not snapshot.available then "SafeZone missing"
		elseif snapshot.inSub then "In sub"
		elseif snapshot.oxygen <= 0 then "OUT OF AIR!"
		else "Outside sub"
	label.Text = string.format("Oxygen %d/%d | %s", math.ceil(snapshot.oxygen), snapshot.maximum, status)
	healthLabel.Text = string.format("HP %d/%d", math.ceil(snapshot.health), snapshot.healthMaximum)
	healthLabel.TextColor3 = if snapshot.health < snapshot.healthMaximum then Color3.fromRGB(235, 85, 70) else Color3.new(1, 1, 1)
end)
