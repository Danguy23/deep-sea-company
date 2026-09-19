--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeartbeatService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MovementService = require(script.Parent:WaitForChild("MovementService"))
local OxygenService = require(script.Parent:WaitForChild("OxygenService"))
local LootService = require(script.Parent:WaitForChild("LootService"))
local QuotaService = require(script.Parent:WaitForChild("QuotaService"))
local ThreatService = require(script.Parent:WaitForChild("ThreatService"))

type Phase = "Lobby" | "Dive" | "Return" | "Payout" | "GameOver"

local RunService = {}
local phase: Phase = "Lobby"
local started = false
local phaseElapsed = 0
local diveNumber = 0

local function transition(nextPhase: Phase, reason: string)
	print(string.format("[Run] %s -> %s | %s", phase, nextPhase, reason))
	phase = nextPhase
	phaseElapsed = 0
	if nextPhase ~= "Dive" then ThreatService.Deactivate() end
end

local function endDive(reason: string)
	if phase ~= "Dive" then return end
	-- Set the phase first: duplicate signals cannot resolve the same dive twice.
	transition("Return", reason)
	OxygenService.SetActive(false)
	LootService.EndRound()
end

local function checkCrew()
	if phase ~= "Dive" then return end
	local crew = Players:GetPlayers()
	for _, player in crew do
		if not OxygenService.IsDowned(player) then return end
	end
	endDive(if #crew == 0 then "crew left" else "all players downed/out of air")
end

local function crewReady(): boolean
	local crew = Players:GetPlayers()
	if #crew == 0 then return false end
	for _, player in crew do
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return false end
	end
	return true
end

local function beginDive(nextQuota: number?)
	local target = nextQuota or QuotaService.GetSnapshot().quota
	QuotaService.Reset(target)
	MovementService.Reset()
	LootService.BeginRound()
	OxygenService.Reset()
	diveNumber += 1
	transition("Dive", string.format("dive %d; banked 0 / %g; oxygen %g", diveNumber, target, Config.OxygenMax))
	OxygenService.SetActive(true)
	ThreatService.Activate()
end

function RunService.Start()
	if started then return end
	started = true
	QuotaService.Start()
	MovementService.Start()
	LootService.Start()
	OxygenService.Start()
	ThreatService.Start()
	QuotaService.QuotaMet:Connect(function() endDive("quota met") end)
	OxygenService.Depleted:Connect(checkCrew)
	print(string.format("[Run] Lobby | waiting for a living player; auto-start delay %gs", Config.LobbyDelay))
	HeartbeatService.Heartbeat:Connect(function(deltaTime: number)
		phaseElapsed += deltaTime
		if phase == "Lobby" then
			if not crewReady() then
				phaseElapsed = 0
			elseif phaseElapsed >= Config.LobbyDelay then
				beginDive()
			end
		elseif phase == "Dive" then
			checkCrew()
		elseif phase == "Return" and phaseElapsed >= Config.ReturnDelay then
			local result = QuotaService.GetSnapshot()
			transition("Payout", string.format("banked %g / %g; %s", result.bankedValue, result.quota,
				if result.bankedValue >= result.quota then "SUCCESS" else "FAILED"))
		elseif phase == "Payout" and phaseElapsed >= Config.PayoutDelay then
			local result = QuotaService.GetSnapshot()
			if result.bankedValue >= result.quota then
				-- Wait for characters to be ready if a successful crew also died.
				if crewReady() then
					beginDive(result.quota + Config.QuotaIncrease)
				elseif #Players:GetPlayers() == 0 then
					transition("GameOver", "crew left before next dive")
				end
			else
				transition("GameOver", "quota missed; resetting run")
			end
		elseif phase == "GameOver" and phaseElapsed >= Config.GameOverDelay then
			QuotaService.Reset(Config.StartingQuota)
			OxygenService.Reset()
			diveNumber = 0
			transition("Lobby", "run reset; waiting for crew")
		end
	end)
end

return RunService
