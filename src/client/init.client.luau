--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OxygenTypes = require(Shared:WaitForChild("OxygenTypes"))
local LootTypes = require(Shared:WaitForChild("LootTypes"))
local QuotaTypes = require(Shared:WaitForChild("QuotaTypes"))
local Config = require(Shared:WaitForChild("Config"))
local lootUpdated = Shared:WaitForChild("Remotes"):WaitForChild("LootUpdated") :: RemoteEvent
local dropRequested = Shared:WaitForChild("Remotes"):WaitForChild("DropLoot") :: RemoteEvent
local oxygenUpdated = Shared:WaitForChild("Remotes"):WaitForChild("OxygenUpdated") :: RemoteEvent
local quotaUpdated = Shared:WaitForChild("Remotes"):WaitForChild("QuotaUpdated") :: RemoteEvent
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

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Config.LootDropKey and not UserInputService:GetFocusedTextBox() then
		dropRequested:FireServer()
	end
end)

oxygenUpdated.OnClientEvent:Connect(function(snapshot: OxygenTypes.Snapshot)
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
