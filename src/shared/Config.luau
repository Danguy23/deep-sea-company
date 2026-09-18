--!strict

return table.freeze({
	OxygenMax = 100,
	OxygenDrainPerSecond = 5,
	OxygenRefillPerSecond = 20,
	OxygenUpdateInterval = 0.1,
	OxygenLogInterval = 5,
	LootPickupDistance = 10,
	LootPickupKey = Enum.KeyCode.E,
	LootPromptHoldDuration = 0.2,
	LootDefaultWeight = 4,
	LootSpeedPenaltyPerWeight = 0.05,
	LootMaxSpeedPenalty = 0.7,
	LootCarryOffset = CFrame.new(0, 0, -3),
	LootDropOffset = CFrame.new(0, 0, -5),
	LootUpdateInterval = 0.25,
	LootDropKey = Enum.KeyCode.G,
})
