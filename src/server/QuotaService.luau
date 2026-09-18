--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local QuotaTypes = require(Shared:WaitForChild("QuotaTypes"))
local quotaUpdated = Shared:WaitForChild("Remotes"):WaitForChild("QuotaUpdated") :: RemoteEvent

local QuotaService = {}
local bankedValue = 0
local quota = Config.StartingQuota
local met = false
local started = false
local quotaMet = Instance.new("BindableEvent")
-- Server-only signal, fired once on the first deposit reaching the target.
QuotaService.QuotaMet = quotaMet.Event

local function snapshot(): QuotaTypes.Snapshot
	return {bankedValue = bankedValue, quota = quota, met = met}
end

function QuotaService.AddValue(player: Player, value: number, itemName: string)
	assert(started, "QuotaService must be started before banking loot")
	assert(value == value and math.abs(value) < math.huge and value >= 0, "Invalid deposit Value")
	bankedValue += value
	local newlyMet = not met and bankedValue >= quota
	if newlyMet then
		met = true
	end
	print(string.format("[Quota] %s deposited %s: Value=%g. Banked: %g / %g", player.Name, itemName, value, bankedValue, quota))
	quotaUpdated:FireAllClients(snapshot())
	if newlyMet then
		print(string.format("[Quota] QUOTA MET! Banked: %g / %g. Awaiting run state machine.", bankedValue, quota))
		quotaMet:Fire(bankedValue, quota)
	end
end

function QuotaService.Start()
	if started then return end
	assert(quota > 0 and quota < math.huge, "Config.StartingQuota must be finite and positive")
	started = true
	print(string.format("[Quota] Service started. Banked: %g / %g", bankedValue, quota))
	-- Periodic snapshots cover HUD startup and respawn without trusting client data.
	local accumulated = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulated += deltaTime
		if accumulated < Config.QuotaUpdateInterval then return end
		accumulated = 0
		for _, player in Players:GetPlayers() do
			quotaUpdated:FireClient(player, snapshot())
		end
	end)
end

return QuotaService
