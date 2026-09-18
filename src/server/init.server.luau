--!strict

local OxygenService = require(script:WaitForChild("OxygenService"))
local LootService = require(script:WaitForChild("LootService"))

LootService.Start()
OxygenService.Depleted:Connect(function()
	LootService.EndRound()
end)
OxygenService.Start()
