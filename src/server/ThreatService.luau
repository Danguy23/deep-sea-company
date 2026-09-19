--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeartbeatService = game:GetService("RunService")
local LightService = require(script.Parent:WaitForChild("LightService"))
local OxygenService = require(script.Parent:WaitForChild("OxygenService"))
local SafeZoneService = require(script.Parent:WaitForChild("SafeZoneService"))

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local settings = Config.Threat

type Mode = "Inactive" | "Idle" | "Chase" | "Sprint"

local ThreatService = {}
local random = Random.new()
local started = false
local active = false
local mode: Mode = "Inactive"
local creature: Model? = nil
local body: BasePart? = nil
local highlight: Highlight? = nil
local target: Player? = nil
local patrolOrigin = Vector3.zero
local patrolDestination = Vector3.zero
local patrolDirection = 1
local updateElapsed = 0
local chaseElapsed = 0
local sprintAfter = 0
local sprinting = false

local function isFinitePositive(value: number): boolean
	return value > 0 and value < math.huge
end

local function createEye(model: Model, bodyPart: BasePart, offset: Vector3, name: string)
	local eye = Instance.new("Part")
	eye.Name = name
	eye.Shape = Enum.PartType.Ball
	eye.Size = settings.EyeSize
	eye.Color = settings.EyeColor
	eye.Material = Enum.Material.Neon
	eye.Anchored = true
	eye.CanCollide = false
	eye.CanQuery = false
	eye.CanTouch = false
	eye.CastShadow = false
	eye.CFrame = bodyPart.CFrame * CFrame.new(offset)
	eye.Parent = model
end

local function createCreature(position: Vector3): (Model, BasePart, Highlight)
	local model = Instance.new("Model")
	model.Name = "AbyssalThreat"

	local part = Instance.new("Part")
	part.Name = "Body"
	part.Shape = Enum.PartType.Ball
	part.Size = settings.BodySize
	part.Color = settings.BodyColor
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = settings.BodyReflectance
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.CFrame = CFrame.new(position)
	part.Parent = model
	createEye(model, part, settings.EyeOffset, "LeftEye")
	createEye(model, part, Vector3.new(-settings.EyeOffset.X, settings.EyeOffset.Y, settings.EyeOffset.Z), "RightEye")

	local beamHighlight = Instance.new("Highlight")
	beamHighlight.Name = "FlashlightHighlight"
	beamHighlight.Adornee = model
	beamHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
	beamHighlight.FillColor = settings.IlluminatedBodyColor
	beamHighlight.FillTransparency = settings.HighlightFillTransparency
	beamHighlight.OutlineColor = settings.EyeColor
	beamHighlight.OutlineTransparency = settings.HighlightOutlineTransparency
	beamHighlight.Enabled = false
	beamHighlight.Parent = model

	model.PrimaryPart = part
	model.Parent = workspace
	return model, part, beamHighlight
end

local function choosePatrolDestination()
	local part = body
	local offset = if part then part.Position - patrolOrigin else Vector3.zero
	local planarOffset = Vector3.new(offset.X, 0, offset.Z)
	local angle = if planarOffset.Magnitude > 0.001
		then math.atan2(planarOffset.Z, planarOffset.X) + settings.PatrolArcAngle * patrolDirection
		else random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(settings.PatrolMinimumRadius, settings.PatrolRadius)
	patrolDestination = patrolOrigin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function updateVisibility(part: BasePart)
	local illuminated = false
	for _, player in Players:GetPlayers() do
		if LightService.IsIlluminating(player, part.Position) then
			illuminated = true
			break
		end
	end
	part.Color = if illuminated then settings.IlluminatedBodyColor else settings.BodyColor
	if highlight then highlight.Enabled = illuminated end
end

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	if OxygenService.IsDowned(player) then return nil end
	local zone = SafeZoneService.Find()
	if zone and SafeZoneService.IsCharacterInside(character, root, zone) then return nil end
	return root
end

local function nearestDetectable(from: Vector3): (Player?, number, boolean)
	local nearest: Player? = nil
	local nearestDistance = math.huge
	local nearestLit = false
	for _, player in Players:GetPlayers() do
		local root = characterRoot(player)
		if not root then continue end
		local lit = LightService.IsEnabled(player)
		local radius = if lit then settings.LitDetectionRadius else settings.DarkDetectionRadius
		local distance = (root.Position - from).Magnitude
		if distance <= radius and distance < nearestDistance then
			nearest = player
			nearestDistance = distance
			nearestLit = lit
		end
	end
	return nearest, nearestDistance, nearestLit
end

local function moveToward(model: Model, part: BasePart, destination: Vector3, speed: number, elapsed: number): boolean
	local offset = destination - part.Position
	local distance = offset.Magnitude
	if distance <= settings.PatrolArrivalDistance then return true end
	local direction = offset.Unit
	local nextPosition = part.Position + direction * math.min(speed * elapsed, distance)
	model:PivotTo(CFrame.lookAt(nextPosition, nextPosition + direction))
	return false
end

local function update(elapsed: number)
	local part = body
	local model = creature
	if not active or not model or not part or not part:IsDescendantOf(workspace) then return end
	updateVisibility(part)

	local detected, distance, lit = nearestDetectable(part.Position)
	if detected ~= target then
		if target then
			print(string.format("[Threat] Target lost: %s | %s -> idle", target.Name,
				if sprinting then "sprint" else "chase"))
		end
		target = detected
		if detected then
			mode = "Chase"
			chaseElapsed = 0
			sprintAfter = random:NextNumber(settings.SprintDelayMinimum, settings.SprintDelayMaximum)
			sprinting = false
			print(string.format("[Threat] Idle -> chase | target %s; flashlight %s; distance %.1f; sprint in %.1fs",
				detected.Name, if lit then "ON" else "OFF", distance, sprintAfter))
		else
			mode = "Idle"
			chaseElapsed = 0
			sprinting = false
			choosePatrolDestination()
		end
	end

	local chasedPlayer = target
	if chasedPlayer then
		local root = characterRoot(chasedPlayer)
		if not root then
			print(string.format("[Threat] Target lost: %s | %s -> idle", chasedPlayer.Name,
				if sprinting then "sprint" else "chase"))
			target = nil
			mode = "Idle"
			chaseElapsed = 0
			sprinting = false
			choosePatrolDestination()
			return
		end
		chaseElapsed += elapsed
		if not sprinting and chaseElapsed >= sprintAfter then
			sprinting = true
			mode = "Sprint"
			print(string.format("[Threat] Chase -> sprint | target %s; speed %g", chasedPlayer.Name, settings.SprintSpeed))
		end
		local speed = if sprinting then settings.SprintSpeed else settings.ChaseSpeed
		local reached = moveToward(model, part, root.Position, speed, elapsed)
		if reached or (root.Position - part.Position).Magnitude <= settings.AttackDistance then
			target = nil
			mode = "Idle"
			chaseElapsed = 0
			sprinting = false
			if OxygenService.DownPlayer(chasedPlayer, "caught by threat") then
				print(string.format("[Threat] Player downed: %s", chasedPlayer.Name))
			end
			if active then choosePatrolDestination() end
		end
	elseif moveToward(model, part, patrolDestination, settings.MoveSpeed, elapsed) then
		choosePatrolDestination()
	end
end

function ThreatService.Activate()
	ThreatService.Deactivate()
	local zone = SafeZoneService.Find()
	if not zone then
		warn("[Threat] MISSING Workspace.Submarine.SafeZone; creature cannot spawn for this Dive.")
		return
	end
	local forward = Vector3.new(zone.CFrame.LookVector.X, 0, zone.CFrame.LookVector.Z)
	if forward.Magnitude < 0.001 then forward = Vector3.zAxis end
	local spawnPosition = zone.Position + forward.Unit * settings.SpawnDistance + Vector3.yAxis * settings.HoverHeight
	local model, part, beamHighlight = createCreature(spawnPosition)
	creature = model
	body = part
	highlight = beamHighlight
	patrolOrigin = zone.Position + Vector3.yAxis * settings.HoverHeight
	patrolDirection = if random:NextInteger(0, 1) == 0 then -1 else 1
	choosePatrolDestination()
	target = nil
	mode = "Idle"
	chaseElapsed = 0
	sprinting = false
	active = true
	print(string.format("[Threat] Inactive -> idle | spawned %.1f studs from SafeZone", settings.SpawnDistance))
end

function ThreatService.Deactivate()
	active = false
	updateElapsed = 0
	target = nil
	mode = "Inactive"
	chaseElapsed = 0
	sprinting = false
	if creature then
		creature:Destroy()
		print("[Threat] Despawned; inactive outside Dive")
	end
	creature = nil
	body = nil
	highlight = nil
end

function ThreatService.Start()
	if started then return end
	assert(isFinitePositive(settings.MoveSpeed)
		and isFinitePositive(settings.DarkDetectionRadius)
		and settings.LitDetectionRadius > settings.DarkDetectionRadius
		and isFinitePositive(settings.LitDetectionRadius)
		and isFinitePositive(settings.ChaseSpeed)
		and isFinitePositive(settings.SprintSpeed)
		and settings.SprintSpeed > settings.ChaseSpeed
		and isFinitePositive(settings.SprintDelayMinimum)
		and isFinitePositive(settings.SprintDelayMaximum)
		and settings.SprintDelayMaximum >= settings.SprintDelayMinimum
		and isFinitePositive(settings.AttackDistance)
		and isFinitePositive(settings.UpdateInterval)
		and isFinitePositive(settings.SpawnDistance)
		and isFinitePositive(settings.PatrolMinimumRadius)
		and isFinitePositive(settings.PatrolRadius)
		and settings.PatrolMinimumRadius < settings.PatrolRadius
		and isFinitePositive(settings.PatrolArcAngle)
		and settings.PatrolArcAngle < math.pi
		and isFinitePositive(settings.PatrolArrivalDistance),
		"Config.Threat needs positive finite values, ordered detection radii, and an ordered patrol band")
	started = true
	HeartbeatService.Heartbeat:Connect(function(deltaTime: number)
		if not active then return end
		updateElapsed += deltaTime
		if updateElapsed < settings.UpdateInterval then return end
		local elapsed = updateElapsed
		updateElapsed = 0
		update(elapsed)
	end)
	print(string.format("[Threat] Service ready: dark radius %g, lit radius %g, patrol %g-%g studs from SafeZone at %g/s, chase %g/s, sprint %g/s after %g-%gs.",
		settings.DarkDetectionRadius, settings.LitDetectionRadius, settings.PatrolMinimumRadius,
		settings.PatrolRadius, settings.MoveSpeed, settings.ChaseSpeed, settings.SprintSpeed,
		settings.SprintDelayMinimum, settings.SprintDelayMaximum))
end

return ThreatService
