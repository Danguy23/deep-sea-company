--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeartbeatService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RunTypes = require(Shared:WaitForChild("RunTypes"))
local runUpdated = Shared:WaitForChild("Remotes"):WaitForChild("RunUpdated") :: RemoteEvent
local MovementService = require(script.Parent:WaitForChild("MovementService"))
local DownService = require(script.Parent:WaitForChild("DownService"))
local LootService = require(script.Parent:WaitForChild("LootService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local QuotaService = require(script.Parent:WaitForChild("QuotaService"))
local SafeZoneService = require(script.Parent:WaitForChild("SafeZoneService"))
local ThreatService = require(script.Parent:WaitForChild("ThreatService"))

type Phase = RunTypes.Phase

local RunService = {}
local phase: Phase = "Lobby"
local started = false
local phaseElapsed = 0
local runUpdateElapsed = 0
local diveNumber = 0

local function runSnapshot(): RunTypes.Snapshot
	local safeZone = SafeZoneService.Find()
	return {
		phase = phase,
		safeZonePosition = if safeZone then safeZone.Position else nil,
	}
end

local function transition(nextPhase: Phase, reason: string)
	print(string.format("[Run] %s -> %s | %s", phase, nextPhase, reason))
	phase = nextPhase
	phaseElapsed = 0
	if nextPhase ~= "Dive" then ThreatService.Deactivate() end
	runUpdated:FireAllClients(runSnapshot())
end

local function endDive(reason: string)
	if phase ~= "Dive" then return end
	-- Set the phase first: duplicate signals cannot resolve the same dive twice.
	transition("Return", reason)
	DownService.SetActive(false)
	LootService.EndRound()
end

local function checkCrew()
	if phase ~= "Dive" then return end
	local crew = Players:GetPlayers()
	for _, player in crew do
		if not DownService.IsDowned(player) then return end
	end
	endDive(if #crew == 0 then "crew left" else "all players downed")
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

-- Spreads living characters in a grid over the SafeZone footprint, standing on its
-- floor, so nobody is left in a map that is about to be torn down or starts stacked.
local function gatherCrewInSub()
	local zone = SafeZoneService.Find()
	if not zone then
		warn("[Run] MISSING Workspace.Submarine.SafeZone; crew stays where it is for this Dive.")
		return
	end
	local crew: {{root: BasePart, humanoid: Humanoid, character: Model}} = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			table.insert(crew, {root = root, humanoid = humanoid, character = character})
		end
	end
	if #crew == 0 then return end
	local columns = math.ceil(math.sqrt(#crew))
	local rows = math.ceil(#crew / columns)
	local cellX, cellZ = zone.Size.X / columns, zone.Size.Z / rows
	local floorY = -zone.Size.Y / 2
	for index, member in crew do
		local column = (index - 1) % columns
		local row = (index - 1) // columns
		local standHeight = member.humanoid.HipHeight + member.root.Size.Y / 2 + Config.CrewGatherClearance
		local spot = zone.CFrame * CFrame.new(
			-zone.Size.X / 2 + cellX * (column + 0.5),
			floorY + standHeight,
			-zone.Size.Z / 2 + cellZ * (row + 0.5)
		)
		member.root.AssemblyLinearVelocity = Vector3.zero
		member.character:PivotTo(spot)
	end
end

local function beginDive(nextQuota: number?)
	gatherCrewInSub()
	MapService.Teardown()
	if not MapService.Build() then
		warn("[Run] Map build FAILED; diving with the Submarine alone.")
	end
	local target = nextQuota or QuotaService.GetSnapshot().quota
	QuotaService.Reset(target)
	MovementService.Reset()
	LootService.BeginRound()
	DownService.Reset()
	diveNumber += 1
	transition("Dive", string.format("dive %d; banked 0 / %g", diveNumber, target))
	DownService.SetActive(true)
	ThreatService.Activate()
end

function RunService.Start()
	if started then return end
	started = true
	QuotaService.Start()
	MovementService.Start()
	LootService.Start()
	DownService.Start()
	ThreatService.Start()
	QuotaService.QuotaMet:Connect(function() endDive("quota met") end)
	DownService.Downed:Connect(checkCrew)
	Players.PlayerAdded:Connect(function(player: Player)
		task.defer(function()
			if player.Parent == Players then runUpdated:FireClient(player, runSnapshot()) end
		end)
	end)
	print(string.format("[Run] Lobby | waiting for a living player; auto-start delay %gs", Config.LobbyDelay))
	HeartbeatService.Heartbeat:Connect(function(deltaTime: number)
		phaseElapsed += deltaTime
		runUpdateElapsed += deltaTime
		if runUpdateElapsed >= Config.RunUpdateInterval then
			runUpdateElapsed = 0
			runUpdated:FireAllClients(runSnapshot())
		end
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
			DownService.Reset()
			MapService.Teardown()
			diveNumber = 0
			transition("Lobby", "run reset; waiting for crew")
		end
	end)
end

return RunService
