--!strict

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
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
local patrolDestination = Vector3.zero
local threatBounds: BasePart? = nil
local currentPath: Path? = nil
local pathWaypoints = {} :: {PathWaypoint}
local pathWaypointIndex = 1
local pathGoal: Vector3? = nil
local pathAge = 0
local pathBlocked = false
local pathBlockedConnection: RBXScriptConnection? = nil
local updateElapsed = 0
local updateRunning = false
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

local function findRuinMarker(name: string): BasePart?
	local ruin = workspace:FindFirstChild("GreyboxRuin")
	local marker = if ruin then ruin:FindFirstChild(name, true) else nil
	if marker and marker:IsA("BasePart") then return marker end
	return nil
end

local function clampToThreatBounds(destination: Vector3): Vector3
	local bounds = threatBounds
	if not bounds then return destination end
	local halfSize = bounds.Size / 2
	local localPosition = bounds.CFrame:PointToObjectSpace(destination)
	local clamped = bounds.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(localPosition.X, -halfSize.X, halfSize.X),
		0,
		math.clamp(localPosition.Z, -halfSize.Z, halfSize.Z)
	))
	return Vector3.new(clamped.X, destination.Y, clamped.Z)
end

local function planarDistance(first: Vector3, second: Vector3): number
	return (Vector3.new(first.X, 0, first.Z) - Vector3.new(second.X, 0, second.Z)).Magnitude
end

local function clearNavigation()
	if pathBlockedConnection then pathBlockedConnection:Disconnect() end
	pathBlockedConnection = nil
	currentPath = nil
	pathWaypoints = {}
	pathWaypointIndex = 1
	pathGoal = nil
	pathAge = 0
	pathBlocked = false
end

local function computePath(startPosition: Vector3, finishPosition: Vector3): (Path?, {PathWaypoint}?)
	local path = PathfindingService:CreatePath({
		AgentRadius = settings.PathAgentRadius,
		AgentHeight = settings.PathAgentHeight,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = settings.PathWaypointSpacing,
	})
	local success, message = pcall(function()
		path:ComputeAsync(startPosition, finishPosition)
	end)
	if not success then
		warn("[Threat] Path computation failed: " .. tostring(message))
		return nil, nil
	end
	if path.Status ~= Enum.PathStatus.Success then return nil, nil end
	local waypoints = path:GetWaypoints()
	if #waypoints == 0 then return nil, nil end
	return path, waypoints
end

local function usePath(path: Path, waypoints: {PathWaypoint}, goal: Vector3, startPosition: Vector3)
	clearNavigation()
	currentPath = path
	pathWaypoints = waypoints
	pathGoal = goal
	while pathWaypointIndex <= #pathWaypoints
		and planarDistance(pathWaypoints[pathWaypointIndex].Position, startPosition)
			<= settings.PathWaypointReachedDistance do
		pathWaypointIndex += 1
	end
	pathBlockedConnection = path.Blocked:Connect(function(blockedIndex: number)
		if currentPath == path and blockedIndex >= pathWaypointIndex then pathBlocked = true end
	end)
end

local function makeGroundRayParams(): RaycastParams?
	local ruin = workspace:FindFirstChild("GreyboxRuin")
	local floors = if ruin then ruin:FindFirstChild("Floors") else nil
	local submarine = workspace:FindFirstChild("Submarine")
	local submarineFloor = if submarine then submarine:FindFirstChild("Floor") else nil
	if not floors or not submarineFloor or not submarineFloor:IsA("BasePart") then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {floors, submarineFloor}
	params.RespectCanCollide = true
	return params
end

local function makeClearanceParams(bounds: BasePart, zone: BasePart): OverlapParams
	local excluded: {Instance} = {bounds, zone}
	if bounds.Parent then table.insert(excluded, bounds.Parent) end
	if creature then table.insert(excluded, creature :: Model) end
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(excluded, player.Character) end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	params.RespectCanCollide = true
	return params
end

local function randomGroundPosition(bounds: BasePart, zone: BasePart, minimumDistance: number): Vector3?
	local groundParams = makeGroundRayParams()
	if not groundParams then return nil end
	local clearanceParams = makeClearanceParams(bounds, zone)
	local halfSize = bounds.Size / 2
	local point = bounds.CFrame:PointToWorldSpace(Vector3.new(
		random:NextNumber(-halfSize.X, halfSize.X),
		0,
		random:NextNumber(-halfSize.Z, halfSize.Z)
	))
	if planarDistance(point, zone.Position) < minimumDistance then return nil end
	local rayOrigin = Vector3.new(point.X, bounds.Position.Y + settings.SpawnRayHeight, point.Z)
	local ground = workspace:Raycast(rayOrigin, -Vector3.yAxis * settings.SpawnRayHeight * 2, groundParams)
	if not ground or ground.Normal.Y < settings.SpawnMinimumGroundNormalY then return nil end
	local position = ground.Position + Vector3.yAxis * (settings.BodySize.Y / 2 + settings.SpawnGroundClearance)
	if #workspace:GetPartBoundsInBox(CFrame.new(position), settings.BodySize, clearanceParams) > 0 then return nil end
	return position
end

local function chooseSpawnPosition(bounds: BasePart, zone: BasePart): (Vector3?, number)
	for attempt = 1, settings.SpawnAttempts do
		local candidate = randomGroundPosition(bounds, zone, settings.SpawnMinimumDistance)
		if not candidate then continue end
		local path = computePath(candidate, zone.Position)
		if path then return candidate, attempt end
	end
	return nil, settings.SpawnAttempts
end

local function choosePatrolDestination(): boolean
	local part = body
	local bounds = threatBounds
	local zone = SafeZoneService.Find()
	if not part or not bounds or not zone then return false end
	for _ = 1, settings.SpawnAttempts do
		local candidate = randomGroundPosition(bounds, zone, 0)
		if not candidate then continue end
		local path, waypoints = computePath(part.Position, candidate)
		if path and waypoints then
			patrolDestination = candidate
			usePath(path, waypoints, candidate, part.Position)
			return true
		end
	end
	clearNavigation()
	warn("[Threat] Could not find a reachable patrol destination inside ThreatBounds.")
	return false
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

local function refreshPath(part: BasePart, destination: Vector3): boolean
	local path, waypoints = computePath(part.Position, destination)
	if not path or not waypoints then return false end
	usePath(path, waypoints, destination, part.Position)
	return true
end

local function moveAlongPath(model: Model, part: BasePart, destination: Vector3, speed: number, elapsed: number): (boolean, boolean)
	destination = clampToThreatBounds(destination)
	pathAge += elapsed
	local goalMoved = if pathGoal then planarDistance(pathGoal, destination) else math.huge
	local needsPath = not currentPath or pathBlocked or pathAge >= settings.PathRecomputeInterval
		or goalMoved >= settings.PathGoalMoveThreshold
	if needsPath and not refreshPath(part, destination) then
		pathAge = 0
		if not currentPath or pathBlocked then clearNavigation() end
		return false, currentPath ~= nil
	end

	while pathWaypointIndex <= #pathWaypoints do
		local waypoint = pathWaypoints[pathWaypointIndex]
		local waypointPosition = Vector3.new(waypoint.Position.X, part.Position.Y, waypoint.Position.Z)
		local distance = (waypointPosition - part.Position).Magnitude
		if distance > settings.PathWaypointReachedDistance then
			local direction = (waypointPosition - part.Position).Unit
			local nextPosition = part.Position + direction * math.min(speed * elapsed, distance)
			model:PivotTo(CFrame.lookAt(nextPosition, nextPosition + direction))
			return false, true
		end
		pathWaypointIndex += 1
	end
	return planarDistance(part.Position, destination) <= settings.PatrolArrivalDistance, true
end

local function hasClearAttackLine(model: Model, player: Player, from: Vector3, destination: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: {Instance} = {model}
	if player.Character then table.insert(excluded, player.Character) end
	params.FilterDescendantsInstances = excluded
	params.RespectCanCollide = true
	return workspace:Raycast(from, destination - from, params) == nil
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
		clearNavigation()
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
		local _, hasPath = moveAlongPath(model, part, root.Position, speed, elapsed)
		local attackDistance = (root.Position - part.Position).Magnitude
		if hasPath and attackDistance <= settings.AttackDistance
			and hasClearAttackLine(model, chasedPlayer, part.Position, root.Position) then
			target = nil
			mode = "Idle"
			chaseElapsed = 0
			sprinting = false
			if OxygenService.DownPlayer(chasedPlayer, "caught by threat") then
				print(string.format("[Threat] Player downed: %s", chasedPlayer.Name))
			end
			if active then choosePatrolDestination() end
		end
	else
		local reached, hasPath = moveAlongPath(model, part, patrolDestination, settings.MoveSpeed, elapsed)
		if reached or not hasPath then choosePatrolDestination() end
	end
end

function ThreatService.Activate()
	ThreatService.Deactivate()
	local zone = SafeZoneService.Find()
	if not zone then
		warn("[Threat] MISSING Workspace.Submarine.SafeZone; creature cannot spawn for this Dive.")
		return
	end
	local bounds = findRuinMarker("ThreatBounds")
	if not bounds then
		warn("[Threat] MISSING Workspace.GreyboxRuin ThreatBounds Part; creature cannot spawn outside authored ruin bounds.")
		return
	end
	threatBounds = bounds
	local spawnPosition, spawnAttempt = chooseSpawnPosition(bounds, zone)
	if not spawnPosition then
		threatBounds = nil
		warn(string.format("[Threat] No valid spawn after %d attempts; check ThreatBounds, map collision, or SpawnMinimumDistance.", spawnAttempt))
		return
	end
	local model, part, beamHighlight = createCreature(spawnPosition)
	creature = model
	body = part
	highlight = beamHighlight
	choosePatrolDestination()
	target = nil
	mode = "Idle"
	chaseElapsed = 0
	sprinting = false
	active = true
	print(string.format("[Threat] Inactive -> idle | spawned %.1f studs from SafeZone at (%.1f, %.1f), attempt %d",
		planarDistance(spawnPosition, zone.Position), spawnPosition.X, spawnPosition.Z, spawnAttempt))
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
	clearNavigation()
	threatBounds = nil
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
		and isFinitePositive(settings.SpawnMinimumDistance)
		and settings.SpawnAttempts > 0 and settings.SpawnAttempts % 1 == 0
		and isFinitePositive(settings.SpawnRayHeight)
		and isFinitePositive(settings.SpawnGroundClearance)
		and settings.SpawnMinimumGroundNormalY > 0 and settings.SpawnMinimumGroundNormalY <= 1
		and settings.PathAgentRadius > 0 and settings.PathAgentRadius % 1 == 0
		and settings.PathAgentHeight > 0 and settings.PathAgentHeight % 1 == 0
		and isFinitePositive(settings.PathWaypointSpacing)
		and isFinitePositive(settings.PathRecomputeInterval)
		and isFinitePositive(settings.PathGoalMoveThreshold)
		and isFinitePositive(settings.PathWaypointReachedDistance)
		and isFinitePositive(settings.PatrolArrivalDistance),
		"Config.Threat needs valid spawn, pathfinding, movement, and detection settings")
	started = true
	HeartbeatService.Heartbeat:Connect(function(deltaTime: number)
		if not active or updateRunning then return end
		updateElapsed += deltaTime
		if updateElapsed < settings.UpdateInterval then return end
		local elapsed = updateElapsed
		updateElapsed = 0
		updateRunning = true
		local success, message = pcall(update, elapsed)
		updateRunning = false
		if not success then warn("[Threat] Update failed: " .. tostring(message)) end
	end)
	print(string.format("[Threat] Service ready: spawn >=%g studs from SafeZone, path agent %gx%g, patrol %g/s, chase %g/s, sprint %g/s.",
		settings.SpawnMinimumDistance, settings.PathAgentRadius * 2, settings.PathAgentHeight,
		settings.MoveSpeed, settings.ChaseSpeed, settings.SprintSpeed))
end

return ThreatService
