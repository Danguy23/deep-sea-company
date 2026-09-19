--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeartbeatService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MovementTypes = require(Shared:WaitForChild("MovementTypes"))
local settings = Config.Movement
local remotes = Shared:WaitForChild("Remotes")
local sprintInput = remotes:WaitForChild("SprintInput") :: RemoteEvent
local movementUpdated = remotes:WaitForChild("MovementUpdated") :: RemoteEvent

type PlayerState = {
	character: Model?,
	humanoid: Humanoid?,
	stamina: number,
	wantsSprint: boolean,
	sprinting: boolean,
	exhausted: boolean,
	carryMultiplier: number,
	walkSpeed: number,
	characterConnection: RBXScriptConnection,
}

local MovementService = {}
local states: {[Player]: PlayerState} = {}
local started = false

local function sendSnapshot(player: Player, state: PlayerState)
	local snapshot: MovementTypes.Snapshot = {
		stamina = state.stamina,
		maximum = settings.StaminaMax,
		sprinting = state.sprinting,
		exhausted = state.exhausted,
		walkSpeed = state.walkSpeed,
	}
	movementUpdated:FireClient(player, snapshot)
end

local function applySpeed(state: PlayerState)
	local baseSpeed = if state.sprinting then settings.SprintSpeed else settings.WalkSpeed
	state.walkSpeed = baseSpeed * state.carryMultiplier
	local humanoid = state.humanoid
	if humanoid and humanoid.Health > 0 then humanoid.WalkSpeed = state.walkSpeed end
end

local function resetState(player: Player, state: PlayerState)
	state.stamina = settings.StaminaMax
	state.wantsSprint = false
	state.sprinting = false
	state.exhausted = false
	state.carryMultiplier = 1
	applySpeed(state)
	sendSnapshot(player, state)
end

local function addPlayer(player: Player)
	if states[player] then return end
	local state: PlayerState
	local function onCharacter(character: Model)
		state.character = character
		state.humanoid = nil
		local instance = character:WaitForChild("Humanoid", settings.CharacterWaitSeconds)
		if states[player] ~= state or state.character ~= character or player.Character ~= character then return end
		if not instance or not instance:IsA("Humanoid") then
			warn(string.format("[Movement] %s: missing Humanoid; movement unavailable", player.Name))
			return
		end
		state.humanoid = instance
		resetState(player, state)
	end
	state = {
		character = nil,
		humanoid = nil,
		stamina = settings.StaminaMax,
		wantsSprint = false,
		sprinting = false,
		exhausted = false,
		carryMultiplier = 1,
		walkSpeed = settings.WalkSpeed,
		characterConnection = player.CharacterAdded:Connect(onCharacter),
	}
	states[player] = state
	if player.Character then task.spawn(onCharacter, player.Character) end
end

local function updatePlayer(player: Player, state: PlayerState, elapsed: number)
	local humanoid = state.humanoid
	if not humanoid or humanoid.Health <= 0 or humanoid.Parent ~= state.character then
		state.sprinting = false
		applySpeed(state)
		sendSnapshot(player, state)
		return
	end

	local wasSprinting = state.sprinting
	local moving = humanoid.MoveDirection.Magnitude > settings.MovementThreshold
	state.sprinting = state.wantsSprint and moving and not state.exhausted and state.stamina > 0
	if state.sprinting then
		state.stamina = math.max(0, state.stamina - settings.StaminaDrainPerSecond * elapsed)
		if state.stamina <= 0 then
			state.exhausted = true
			state.sprinting = false
		end
	else
		state.stamina = math.min(settings.StaminaMax, state.stamina + settings.StaminaRecoveryPerSecond * elapsed)
		if state.exhausted and state.stamina >= settings.StaminaResumeThreshold then state.exhausted = false end
	end
	applySpeed(state)
	if state.sprinting ~= wasSprinting then
		print(string.format("[Movement] %s: %s at %.1f studs/s", player.Name,
			if state.sprinting then "sprinting" else "walking", state.walkSpeed))
	end
	sendSnapshot(player, state)
end

function MovementService.SetCarryMultiplier(player: Player, multiplier: number)
	local state = states[player]
	if not state then return end
	state.carryMultiplier = math.clamp(multiplier, 0, 1)
	applySpeed(state)
	sendSnapshot(player, state)
end

function MovementService.GetWalkSpeed(player: Player): number
	local state = states[player]
	return if state then state.walkSpeed else settings.WalkSpeed
end

function MovementService.Reset()
	for player, state in states do resetState(player, state) end
end

function MovementService.Start()
	if started then return end
	assert(settings.WalkSpeed > 0 and settings.SprintSpeed > settings.WalkSpeed
		and settings.StaminaMax > 0 and settings.StaminaDrainPerSecond > 0
		and settings.StaminaRecoveryPerSecond > 0 and settings.StaminaResumeThreshold > 0
		and settings.StaminaResumeThreshold < settings.StaminaMax and settings.UpdateInterval > 0,
		"Config.Movement needs valid speeds, stamina rates, and update interval")
	started = true
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		local state = states[player]
		if not state then return end
		state.characterConnection:Disconnect()
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do addPlayer(player) end
	sprintInput.OnServerEvent:Connect(function(player: Player, wantsSprint: any)
		local state = states[player]
		if state and typeof(wantsSprint) == "boolean" then state.wantsSprint = wantsSprint end
	end)
	local accumulated = 0
	HeartbeatService.Heartbeat:Connect(function(deltaTime: number)
		accumulated += deltaTime
		if accumulated < settings.UpdateInterval then return end
		local elapsed = accumulated
		accumulated = 0
		for player, state in states do updatePlayer(player, state, elapsed) end
	end)
	print(string.format("[Movement] Service started: walk %g, sprint %g, stamina %g.",
		settings.WalkSpeed, settings.SprintSpeed, settings.StaminaMax))
end

return MovementService
