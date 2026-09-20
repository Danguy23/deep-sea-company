--!strict

local Players = game:GetService("Players")

type PlayerState = {
	downed: boolean,
}

local DownService = {}
local states: {[Player]: PlayerState} = {}
local started = false
local active = false
local downed = Instance.new("BindableEvent")

DownService.Downed = downed.Event

local function addPlayer(player: Player)
	if states[player] then return end
	states[player] = {downed = false}
end

function DownService.SetActive(value: boolean)
	active = value
end

function DownService.Reset()
	for _, state in states do
		state.downed = false
	end
end

function DownService.IsDowned(player: Player): boolean
	local state = states[player]
	local humanoid = if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
	return (state ~= nil and state.downed) or (humanoid ~= nil and humanoid.Health <= 0)
end

-- All hazards use this path so downed state and RunService's crew check stay unified.
function DownService.DownPlayer(player: Player, reason: string): boolean
	local state = states[player]
	if not active or not state or state.downed then return false end
	local humanoid = if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then return false end
	state.downed = true
	humanoid.Health = 0
	print(string.format("[Down] %s DOWNED (%s).", player.Name, reason))
	downed:Fire(player)
	return true
end

function DownService.Start()
	if started then return end
	started = true
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do addPlayer(player) end
	print("[Down] Service started; hazards can down players during Dive.")
end

return DownService
