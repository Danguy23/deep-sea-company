--!strict

return table.freeze({
	-- Neutral Studio-style lighting baseline. Retune these values when the
	-- underwater look is reintroduced.
	Underwater = table.freeze({
		FogStart = 0,
		ViewDistance = 100000,
		TintColor = Color3.fromRGB(192, 192, 192),
		AmbientColor = Color3.fromRGB(70, 70, 70),
		Brightness = 2,
		ClockTime = 14,
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = 0,
		ExposureCompensation = 0,
		ColorShift = Color3.new(0, 0, 0),
		GlobalShadows = true,
		AtmosphereColor = Color3.fromRGB(199, 199, 199),
		AtmosphereDecay = Color3.fromRGB(106, 112, 125),
		AtmosphereDensity = 0.3,
		AtmosphereOffset = 0.25,
		AtmosphereGlare = 0,
		AtmosphereHaze = 0,
		CelestialBodiesShown = true,
		StarCount = 3000,
	}),
	Movement = table.freeze({
		GroundedFloatyEnabled = true,
		EffectiveGravity = 80, -- studs/s^2; player airborne gravity only
		JumpHeight = 7, -- studs; sole source of custom takeoff strength
		WalkSpeed = 12, -- studs/s; desired limit, separate from smoothed WalkSpeed
		SprintSpeed = 20, -- studs/s
		GroundAcceleration = 36, -- studs/s^2
		GroundDeceleration = 24, -- studs/s^2
		OpposingInputBraking = 60, -- studs/s^2
		AirControlMultiplier = 0.5, -- fraction of horizontal acceleration/braking
		InputDeadzone = 0.08, -- unitless input magnitude (outside it, preserve analog magnitude)
		StopSpeedThreshold = 0.15, -- studs/s
		GroundProbeExtraDistance = 0.25, -- studs beyond rig-aware foot reach
		GroundedUpwardSpeed = 2, -- studs/s relative to support; reject stale contact during takeoff
		WallProbeExtraDistance = 0.3, -- studs beyond root horizontal radius
		WallSpeedAllowance = 0.5, -- studs/s of command allowed beyond actual speed into a wall
		TeleportDistance = 8, -- studs of unexpected displacement beyond previous velocity * dt
		JumpCooldown = 0.2, -- seconds; also requires landing and a new press
		InputSendRate = 30, -- Hz; button edges also send immediately
		InputTimeout = 0.3, -- seconds without valid input before clearing intent
		MaxInputMessagesPerSecond = 60, -- per-player fixed one-second receive window
		DebugMovement = false,
		JumpHeightTestTolerance = 0.2, -- studs; apex-rise diagnostic tolerance
		SprintKey = Enum.KeyCode.LeftShift,
		SprintGamepadKey = Enum.KeyCode.ButtonL3,
		JumpKey = Enum.KeyCode.Space,
		JumpGamepadKey = Enum.KeyCode.ButtonA,
		SprintTouchPosition = UDim2.fromScale(0.65, 0.55),
		JumpTouchPosition = UDim2.fromScale(0.85, 0.55),
		StaminaMax = 100,
		StaminaDrainPerSecond = 18,
		StaminaRecoveryPerSecond = 14,
		StaminaResumeThreshold = 25,
		UpdateInterval = 0.1,
		CharacterWaitSeconds = 5,
	}),
	Threat = table.freeze({
		MoveSpeed = 10,
		SightRange = 100,
		FieldOfViewAngle = 120,
		ChaseSpeed = 10,
		SprintSpeed = 18,
		SprintDelayMinimum = 3,
		SprintDelayMaximum = 9,
		AttackDistance = 4,
		UpdateInterval = 0.1,
		SpawnMinimumDistance = 65,
		SpawnAttempts = 30,
		SpawnRayHeight = 8,
		SpawnGroundClearance = 0.1,
		SpawnMinimumGroundNormalY = 0.95,
		PathAgentRadius = 3,
		PathAgentHeight = 5,
		PathWaypointSpacing = 4,
		PathRecomputeInterval = 0.75,
		PathGoalMoveThreshold = 4,
		PathWaypointReachedDistance = 1.5,
		PatrolArrivalDistance = 2,
		BodySize = Vector3.new(5, 4, 9),
		BodyColor = Color3.fromRGB(24, 52, 58),
		BodyReflectance = 0.2,
		EyeSize = Vector3.new(0.7, 0.7, 0.4),
		EyeOffset = Vector3.new(1.15, 0.45, -4.45),
		EyeColor = Color3.fromRGB(90, 255, 225),
	}),
	SafeZoneMarker = table.freeze({
		IconSize = 28,
		TextSize = 22,
		ArrowSize = 14,
		ArrowOffset = 24,
		EdgePadding = 56,
		BottomPadding = 210,
		Color = Color3.fromRGB(110, 235, 205),
		BackgroundColor = Color3.fromRGB(12, 28, 32),
		BackgroundTransparency = 0.2,
	}),
	RoomStitch = table.freeze({
		-- Mated rooms share a face, so an intersection this shallow is a touch,
		-- not an overlap. Also the slack on the 90 degree rotation assumption.
		TouchTolerance = 0.01,
	}),
	MapGen = table.freeze({
		MinRooms = 5, -- generated rooms per map, not counting the Submarine
		MaxRooms = 9,
		PlacementAttemptsPerDoorway = 8, -- tries before an open doorway is left capped
		MaxBuildAttempts = 5, -- seeds tried before keeping a map short of MinRooms
		Seed = nil :: number?, -- fixed seed for debugging; nil picks a fresh one each build
		-- Template names in ServerStorage.RoomTemplates and their relative pick weights.
		RoomPool = table.freeze({
			Room_ExperimentLab_01 = 3,
			Room_ServerRoom_01 = 3,
			Room_CorridorStraight_01 = 2,
			Room_CorridorTurn_01 = 2,
			Room_JunctionT_01 = 2,
		}) :: {[string]: number},
	}),
	LootPickupDistance = 10,
	LootPickupKey = Enum.KeyCode.E,
	LootPromptHoldDuration = 0,
	LootHighlightColor = Color3.fromRGB(235, 235, 235),
	LootHighlightOutlineTransparency = 0.5,
	LootHighlightDistance = 60,
	LootHighlightUpdateInterval = 0.1,
	LootInventoryCapacity = 4,
	LootSlotKeys = table.freeze({Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four}),
	LootSizeClassPattern = table.freeze({"Small", "Medium", "Large", "Medium"}),
	-- Longest dimension of a Medium loot Part; class scales preserve authored proportions.
	LootBaseSize = 1.5,
	LootSmallScale = 0.75,
	LootMediumScale = 1,
	LootLargeScale = 1.45,
	LootLargeSpeedPenaltyPerItem = 0.15,
	LootMaxSpeedPenalty = 0.45,
	LootDropOffset = CFrame.new(0, 0, -5),
	LootDropSlotSpacing = 3,
	LootUpdateInterval = 0.25,
	LootDropKey = Enum.KeyCode.G,
	LootSpawnAttempts = 50,
	LootSpawnBoundsPadding = 3,
	LootSpawnMinimumSafeZoneDistance = 8,
	LootSpawnRayHeight = 30,
	LootSpawnMinGroundNormalY = 0.95,
	LootSpawnClearance = 0.1,
	LootSpawnMinSeparation = 8,
	StartingQuota = 200,
	QuotaIncrease = 50,
	CrewGatherClearance = 0.5, -- studs above the sub floor when the crew is moved in at Dive start
	LobbyDelay = 3,
	ReturnDelay = 1,
	PayoutDelay = 2,
	GameOverDelay = 2,
	QuotaUpdateInterval = 0.5,
	RunUpdateInterval = 0.5,
})
