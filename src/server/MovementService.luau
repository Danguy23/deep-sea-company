--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SimulationService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MovementTypes = require(Shared:WaitForChild("MovementTypes"))
local settings = Config.Movement
local remotes = Shared:WaitForChild("Remotes")
-- Retain the existing transport; its payload now includes all movement intent.
local sprintInput = remotes:WaitForChild("SprintInput") :: RemoteEvent
local movementUpdated = remotes:WaitForChild("MovementUpdated") :: RemoteEvent

type OriginalSettings = {
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoJump: boolean,
	jumping: boolean,
	swimming: boolean,
}

type PlayerState = {
	character: Model?,
	humanoid: Humanoid?,
	root: BasePart?,
	original: OriginalSettings?,
	active: boolean,
	ownershipAuto: boolean,
	ownershipPlayer: Player?,
	ownershipSaved: boolean,
	ownershipWarning: boolean,
	stamina: number,
	wantsSprint: boolean,
	sprinting: boolean,
	exhausted: boolean,
	carryMultiplier: number,
	walkSpeed: number, -- desired limit, separate from smoothed Humanoid.WalkSpeed
	intent: Vector3,
	command: Vector3, -- world-space XZ velocity requested through the Humanoid
	jumpHeld: boolean,
	jumpRequested: boolean,
	jumpLocked: boolean,
	leftSupport: boolean,
	grounded: boolean,
	lastJump: number,
	lastInput: number,
	messageWindow: number,
	messageCount: number,
	lastPosition: Vector3?,
	lastVelocity: Vector3,
	lastSimulationDelta: number,
	jumpStartY: number?,
	jumpApexY: number,
	probe: RaycastParams,
	characterConnections: {RBXScriptConnection},
	playerConnections: {RBXScriptConnection},
}

local MovementService = {}
local states: {[Player]: PlayerState} = {}
local started = false
local floatyEnabled = settings.GroundedFloatyEnabled

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

local function updateSpeedLimit(state: PlayerState)
	state.walkSpeed = (if state.sprinting then settings.SprintSpeed else settings.WalkSpeed) * state.carryMultiplier
end

local function clearIntent(state: PlayerState)
	state.intent = Vector3.zero
	state.wantsSprint = false
	state.jumpRequested = false
	-- Require a release packet before accepting a press after reset/timeout.
	state.jumpHeld = true
end

local function clearMotion(state: PlayerState)
	clearIntent(state)
	state.command = Vector3.zero
	state.sprinting = false
	state.grounded = false
	state.jumpLocked = false
	state.leftSupport = false
	state.jumpStartY = nil
	state.lastPosition = nil
	state.lastVelocity = Vector3.zero
	state.lastSimulationDelta = 0
end

local function restoreOwnership(state: PlayerState)
	local root = state.root
	if state.ownershipSaved and root and root:CanSetNetworkOwnership() then
		if state.ownershipAuto then root:SetNetworkOwnershipAuto()
		else root:SetNetworkOwner(state.ownershipPlayer) end
		state.ownershipSaved = false
	end
end

local function setActive(state: PlayerState, active: boolean)
	if state.active == active then return end
	local humanoid, root, original = state.humanoid, state.root, state.original
	if not humanoid or not root or not original then return end
	state.active = active
	clearMotion(state)
	humanoid.Jump = false
	if active then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		humanoid.AutoJumpEnabled = false
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.WalkSpeed = 0
	else
		humanoid:Move(Vector3.zero, false)
		humanoid.WalkSpeed = original.walkSpeed
		humanoid.JumpPower = original.jumpPower
		humanoid.JumpHeight = original.jumpHeight
		humanoid.AutoJumpEnabled = original.autoJump
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, original.jumping)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, original.swimming)
		restoreOwnership(state)
	end
	local character = state.character
	if character then character:SetAttribute("GroundedFloatyActive", active) end
end

local function eligible(state: PlayerState): boolean
	local humanoid, root = state.humanoid, state.root
	if not humanoid or not root or humanoid.Health <= 0 or humanoid.Parent ~= state.character
		or not root:IsDescendantOf(Workspace) or root.Anchored
		or (root.AssemblyRootPart and root.AssemblyRootPart.Anchored)
		or humanoid.Sit or humanoid.SeatPart or humanoid.PlatformStand or not humanoid.EvaluateStateMachine then
		return false
	end
	-- Other states belong to seats, climbing, ragdolls or external controllers.
	local mode = humanoid:GetState()
	return mode == Enum.HumanoidStateType.Running or mode == Enum.HumanoidStateType.RunningNoPhysics
		or mode == Enum.HumanoidStateType.Landed or mode == Enum.HumanoidStateType.Freefall
end

local function claimOwnership(player: Player, state: PlayerState): boolean
	local root = state.root
	if not root then return false end
	local canSet, reason = root:CanSetNetworkOwnership()
	if not canSet then
		if not state.ownershipWarning then
			warn(string.format("[Movement] %s: cannot simulate character on server: %s", player.Name, tostring(reason)))
			state.ownershipWarning = true
		end
		return false
	end
	if not state.ownershipSaved then
		state.ownershipAuto = root:GetNetworkOwnershipAuto()
		state.ownershipPlayer = root:GetNetworkOwner()
		state.ownershipSaved = true
	end
	if root:GetNetworkOwnershipAuto() or root:GetNetworkOwner() ~= nil then root:SetNetworkOwner(nil) end
	state.ownershipWarning = false
	return true
end

local function support(state: PlayerState, humanoid: Humanoid, root: BasePart): (boolean, boolean)
	-- R15 standing root height = half root + HipHeight; R6 includes the leg.
	-- Recompute to follow avatar scaling instead of treating extra reach as ray length.
	local reach = root.Size.Y / 2 + humanoid.HipHeight
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = if state.character then state.character:FindFirstChild("Left Leg") else nil
		if not leg or not leg:IsA("BasePart") then return false, true end
		reach += leg.Size.Y
	end
	state.probe.CollisionGroup = root.CollisionGroup
	local hit = Workspace:Raycast(root.Position, -Vector3.yAxis * (reach + settings.GroundProbeExtraDistance), state.probe)
	local lostSupport = hit == nil or humanoid.FloorMaterial == Enum.Material.Air
	if not hit or hit.Normal.Y < math.cos(math.rad(humanoid.MaxSlopeAngle)) then return false, lostSupport end
	local supportY = if hit.Instance:IsA("BasePart") then hit.Instance:GetVelocityAtPosition(hit.Position).Y else 0
	-- Walking uphill can have substantial Y velocity while genuinely supported.
	-- Only the takeoff latch needs the upward-speed guard against stale floor contact.
	return not lostSupport and (not state.jumpLocked
		or root.AssemblyLinearVelocity.Y - supportY <= settings.GroundedUpwardSpeed), lostSupport
end

local function updateStamina(player: Player, state: PlayerState, elapsed: number, canMove: boolean)
	local wasSprinting = state.sprinting
	-- Glide is output, never evidence of held input.
	local moving = state.intent.Magnitude > settings.InputDeadzone
	state.sprinting = canMove and state.wantsSprint and moving and not state.exhausted and state.stamina > 0
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
	updateSpeedLimit(state)
	if state.sprinting ~= wasSprinting then
		print(string.format("[Movement] %s: %s; target limit %.1f studs/s", player.Name,
			if state.sprinting then "sprinting" else "walking", state.walkSpeed))
	end
end

local function updateHorizontal(state: PlayerState, humanoid: Humanoid, root: BasePart, dt: number)
	local target = state.intent * state.walkSpeed
	local command = state.command
	local rate = settings.GroundAcceleration
	if target.Magnitude == 0 or target.Magnitude < command.Magnitude then rate = settings.GroundDeceleration end
	if target:Dot(command) < 0 then rate = settings.OpposingInputBraking end
	if not state.grounded then rate *= settings.AirControlMultiplier end
	local difference = target - command
	local distance = difference.Magnitude
	if distance > 0 then command += difference * math.min(1, rate * dt / distance) end

	-- Discard command into a nearby unwalkable wall when contact stalls the body.
	-- This changes only requested movement; collisions decide actual velocity.
	if command.Magnitude > settings.StopSpeedThreshold then
		local reach = math.max(root.Size.X, root.Size.Z) / 2 + settings.WallProbeExtraDistance
		local hit = Workspace:Raycast(root.Position, command.Unit * reach, state.probe)
		if hit and math.abs(hit.Normal.Y) < math.cos(math.rad(humanoid.MaxSlopeAngle)) then
			local normal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z).Unit
			local actualIntoWall = math.max(0, -root.AssemblyLinearVelocity:Dot(normal))
			local excess = -command:Dot(normal) - actualIntoWall - settings.WallSpeedAllowance
			if excess > 0 then command += normal * excess end
		end
	end
	if command.Magnitude < settings.StopSpeedThreshold then command = Vector3.zero end
	state.command = command
	humanoid.WalkSpeed = command.Magnitude
	-- Keep feeding the decaying direction after release; Move(zero) would kill glide.
	humanoid:Move(if command.Magnitude > 0 then command.Unit else Vector3.zero, false)
end

local function updateVertical(player: Player, state: PlayerState, humanoid: Humanoid, root: BasePart, dt: number, now: number)
	humanoid.Jump = false
	local grounded, lostSupport = support(state, humanoid, root)
	if lostSupport then state.leftSupport = true end
	if grounded and state.leftSupport then
		state.jumpLocked = false
		state.leftSupport = false
		if state.jumpStartY and settings.DebugMovement then
			local rise = state.jumpApexY - state.jumpStartY
			print(string.format("[Movement] %s jump: rootY %.3f, apexY %.3f, rise %.3f studs; target %.3f; %s (stationary support baseline)",
				player.Name, state.jumpStartY, state.jumpApexY, rise, settings.JumpHeight,
				if math.abs(rise - settings.JumpHeight) <= settings.JumpHeightTestTolerance then "within tolerance" else "CHECK"))
		end
		state.jumpStartY = nil
	end
	local launch = state.jumpRequested and grounded and not state.jumpLocked and now - state.lastJump >= settings.JumpCooldown
	state.jumpRequested = false -- consume even rejected requests; no landing buffer
	if launch then
		state.jumpLocked = true
		state.leftSupport = false
		state.lastJump = now
		state.jumpStartY = root.Position.Y
		state.jumpApexY = root.Position.Y
		grounded = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		if settings.DebugMovement then
			print(string.format("[Movement] %s takeoff: rootY %.3f; launch %.3f studs/s", player.Name,
				root.Position.Y, math.sqrt(2 * settings.EffectiveGravity * settings.JumpHeight)))
		end
	end
	state.grounded = grounded
	if state.jumpStartY then state.jumpApexY = math.max(state.jumpApexY, root.Position.Y) end
	if not grounded then
		-- The ONLY player Y-velocity writer. Takeoff replaces Y once; correction
		-- uses current physical velocity thereafter, retaining collision responses.
		local velocity = root.AssemblyLinearVelocity
		local y = if launch then math.sqrt(2 * settings.EffectiveGravity * settings.JumpHeight) else velocity.Y
		y += (Workspace.Gravity - settings.EffectiveGravity) * dt
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, y, velocity.Z)
	end
end

local function updatePlayer(player: Player, state: PlayerState, dt: number, now: number)
	local humanoid, root = state.humanoid, state.root
	if not humanoid or not root then return end
	local canMove = eligible(state)
	local shouldActivate = floatyEnabled and canMove and claimOwnership(player, state)
	setActive(state, shouldActivate)
	-- An anchored assembly cannot restore ownership until it is unanchored.
	if not shouldActivate then restoreOwnership(state) end
	if now - state.lastInput > settings.InputTimeout then clearIntent(state) end
	if not canMove then clearIntent(state) end
	if state.active then
		local previous = state.lastPosition
		if previous and (root.Position - previous - state.lastVelocity * state.lastSimulationDelta).Magnitude > settings.TeleportDistance then
			clearMotion(state)
			if settings.DebugMovement then print(string.format("[Movement] %s: teleport cleared momentum", player.Name)) end
		end
	end
	updateStamina(player, state, dt, canMove and (not floatyEnabled or state.active))
	if state.active then
		updateVertical(player, state, humanoid, root, dt, now)
		updateHorizontal(state, humanoid, root, dt)
		state.lastPosition = root.Position
		state.lastVelocity = root.AssemblyLinearVelocity
		state.lastSimulationDelta = dt
	elseif not floatyEnabled and canMove then
		humanoid.WalkSpeed = state.walkSpeed
	end
end

local function cleanupCharacter(state: PlayerState)
	setActive(state, false)
	for _, connection in state.characterConnections do connection:Disconnect() end
	table.clear(state.characterConnections)
	clearMotion(state)
	state.character = nil
	state.humanoid = nil
	state.root = nil
	state.original = nil
	state.ownershipSaved = false
	state.probe.FilterDescendantsInstances = {}
end

local function resetState(player: Player, state: PlayerState)
	state.stamina = settings.StaminaMax
	state.exhausted = false
	state.carryMultiplier = 1
	-- Round reset clears horizontal momentum, but must not unlock an in-flight jump.
	clearIntent(state)
	state.command = Vector3.zero
	state.sprinting = false
	updateSpeedLimit(state)
	if state.active and state.humanoid then
		state.humanoid.WalkSpeed = 0
		state.humanoid:Move(Vector3.zero, false)
	end
	sendSnapshot(player, state)
end

local function addPlayer(player: Player)
	if states[player] then return end
	local probe = RaycastParams.new()
	probe.FilterType = Enum.RaycastFilterType.Exclude
	probe.RespectCanCollide = true
	probe.IgnoreWater = true -- audited map has no physical water; this does not cancel buoyancy
	local state: PlayerState = {
		character = nil, humanoid = nil, root = nil, original = nil,
		active = false, ownershipAuto = true, ownershipPlayer = nil, ownershipSaved = false, ownershipWarning = false,
		stamina = settings.StaminaMax, wantsSprint = false, sprinting = false, exhausted = false,
		carryMultiplier = 1, walkSpeed = settings.WalkSpeed, intent = Vector3.zero, command = Vector3.zero,
		jumpHeld = true, jumpRequested = false, jumpLocked = false, leftSupport = false, grounded = false,
		lastJump = -math.huge, lastInput = -math.huge, messageWindow = 0, messageCount = 0,
		lastPosition = nil, lastVelocity = Vector3.zero, lastSimulationDelta = 0, jumpStartY = nil, jumpApexY = 0,
		probe = probe, characterConnections = {}, playerConnections = {},
	}
	states[player] = state
	local function onCharacter(character: Model)
		if player.Character ~= character or state.character == character then return end
		cleanupCharacter(state)
		state.character = character
		local instance = character:WaitForChild("Humanoid", settings.CharacterWaitSeconds)
		local root = character:WaitForChild("HumanoidRootPart", settings.CharacterWaitSeconds)
		if states[player] ~= state or state.character ~= character or player.Character ~= character then return end
		if not instance or not instance:IsA("Humanoid") or not root or not root:IsA("BasePart") then
			warn(string.format("[Movement] %s: missing Humanoid/root; movement unavailable", player.Name))
			return
		end
		state.humanoid = instance
		state.root = root
		state.original = {
			walkSpeed = instance.WalkSpeed, jumpPower = instance.JumpPower, jumpHeight = instance.JumpHeight,
			autoJump = instance.AutoJumpEnabled, jumping = instance:GetStateEnabled(Enum.HumanoidStateType.Jumping),
			swimming = instance:GetStateEnabled(Enum.HumanoidStateType.Swimming),
		}
		state.probe.FilterDescendantsInstances = {character}
		state.lastJump = -math.huge
		state.lastInput = -math.huge
		-- AutoJumpEnabled replicates, unlike state enablement. Preserve its pre-mode value for the client.
		character:SetAttribute("MovementOriginalAutoJump", state.original.autoJump)
		character:SetAttribute("GroundedFloatyActive", false)
		table.insert(state.characterConnections, instance.Died:Connect(function() cleanupCharacter(state) end))
		resetState(player, state)
	end
	table.insert(state.playerConnections, player.CharacterAdded:Connect(onCharacter))
	table.insert(state.playerConnections, player.CharacterRemoving:Connect(function(character: Model)
		if state.character == character then cleanupCharacter(state) end
	end))
	if player.Character then task.spawn(onCharacter, player.Character) end
end

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function receiveIntent(player: Player, payload: any)
	local state = states[player]
	if not state then return end
	local now = os.clock()
	if now - state.messageWindow >= 1 then
		state.messageWindow = now
		state.messageCount = 0
	end
	state.messageCount += 1
	if state.messageCount > settings.MaxInputMessagesPerSecond then return end
	if typeof(payload) ~= "table" or payload.character ~= state.character or payload.character ~= player.Character
		or not state.humanoid or state.humanoid.Health <= 0 or typeof(payload.move) ~= "Vector3"
		or typeof(payload.sprint) ~= "boolean" or typeof(payload.jump) ~= "boolean" then return end
	local move = payload.move :: Vector3
	if not finite(move.X) or not finite(move.Y) or not finite(move.Z) then return end
	move = Vector3.new(move.X, 0, move.Z)
	local magnitude = move.Magnitude
	if not finite(magnitude) then return end
	if magnitude > 1 then move /= magnitude end
	state.intent = if magnitude <= settings.InputDeadzone then Vector3.zero else move
	state.wantsSprint = payload.sprint
	if payload.jump and not state.jumpHeld and state.active and state.grounded and not state.jumpLocked then
		state.jumpRequested = true
	end
	state.jumpHeld = payload.jump
	state.lastInput = now
end

function MovementService.SetCarryMultiplier(player: Player, multiplier: number)
	local state = states[player]
	if not state or not finite(multiplier) then return end
	state.carryMultiplier = math.clamp(multiplier, 0, 1)
	updateSpeedLimit(state)
	sendSnapshot(player, state)
end

function MovementService.GetWalkSpeed(player: Player): number
	local state = states[player]
	return if state then state.walkSpeed else settings.WalkSpeed
end

function MovementService.Reset()
	for player, state in states do resetState(player, state) end
end

function MovementService.SetGroundedFloatyEnabled(enabled: boolean)
	floatyEnabled = enabled
	if not enabled then
		for _, state in states do setActive(state, false) end
	end
end

function MovementService.Start()
	if started then return end
	assert(settings.WalkSpeed > 0 and settings.SprintSpeed > settings.WalkSpeed
		and settings.StaminaMax > 0 and settings.StaminaDrainPerSecond > 0
		and settings.StaminaRecoveryPerSecond > 0 and settings.StaminaResumeThreshold > 0
		and settings.StaminaResumeThreshold < settings.StaminaMax and settings.UpdateInterval > 0
		and settings.EffectiveGravity > 0 and settings.JumpHeight > 0
		and settings.GroundAcceleration > 0 and settings.GroundDeceleration > 0 and settings.OpposingInputBraking > 0
		and settings.AirControlMultiplier > 0 and settings.InputDeadzone >= 0 and settings.InputDeadzone < 1
		and settings.StopSpeedThreshold > 0 and settings.GroundProbeExtraDistance >= 0
		and settings.InputSendRate > 0 and settings.InputTimeout > 1 / settings.InputSendRate
		and settings.MaxInputMessagesPerSecond >= settings.InputSendRate,
		"Config.Movement needs valid speeds, gravity, input timing, and stamina rates")
	started = true
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		local state = states[player]
		if not state then return end
		cleanupCharacter(state)
		for _, connection in state.playerConnections do connection:Disconnect() end
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do addPlayer(player) end
	sprintInput.OnServerEvent:Connect(receiveIntent)
	local accumulated = 0
	-- One simulation loop for horizontal commands, launch, and airborne compensation.
	SimulationService.PreSimulation:Connect(function(deltaTimeSim: number)
		local now = os.clock()
		accumulated += deltaTimeSim
		local publish = accumulated >= settings.UpdateInterval
		if publish then accumulated = 0 end
		for player, state in states do
			updatePlayer(player, state, deltaTimeSim, now)
			if publish then sendSnapshot(player, state) end
		end
	end)
	print(string.format("[Movement] Service started: floaty %s; walk %g, sprint %g, stamina %g; gravity %g, jump %g.",
		tostring(floatyEnabled), settings.WalkSpeed, settings.SprintSpeed, settings.StaminaMax,
		settings.EffectiveGravity, settings.JumpHeight))
end

return MovementService
