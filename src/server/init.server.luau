--!strict

local OxygenService = require(script:WaitForChild("OxygenService"))
local LootService = require(script:WaitForChild("LootService"))
local QuotaService = require(script:WaitForChild("QuotaService"))

QuotaService.Start()
LootService.Start()
OxygenService.Depleted:Connect(function()
	LootService.EndRound()
end)
OxygenService.Start()
