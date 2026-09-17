--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OxygenTypes = require(Shared:WaitForChild("OxygenTypes"))
local oxygenUpdated = Shared:WaitForChild("Remotes"):WaitForChild("OxygenUpdated") :: RemoteEvent
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local hud = Instance.new("ScreenGui")
hud.Name = "OxygenHUD"
hud.ResetOnSpawn = false
hud.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -24)
panel.Size = UDim2.fromOffset(300, 68)
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

oxygenUpdated.OnClientEvent:Connect(function(snapshot: OxygenTypes.Snapshot)
	local fraction = math.clamp(snapshot.oxygen / snapshot.maximum, 0, 1)
	fill.Size = UDim2.fromScale(fraction, 1)
	fill.BackgroundColor3 = if fraction <= 0.25 then Color3.fromRGB(235, 85, 70) else Color3.fromRGB(65, 210, 160)
	local status = if snapshot.roundEnded then "Round ended"
		elseif snapshot.downed then "Downed"
		elseif not snapshot.available then "SafeZone missing"
		elseif snapshot.inSub then "In sub"
		else "Outside sub"
	label.Text = string.format("Oxygen %d/%d | %s", math.ceil(snapshot.oxygen), snapshot.maximum, status)
end)
