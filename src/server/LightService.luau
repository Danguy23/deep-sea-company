--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local settings = Config.Flashlight
local remotes = Shared:WaitForChild("Remotes")
local flashlightInput = remotes:WaitForChild("FlashlightInput") :: RemoteEvent
local flashlightUpdated = remotes:WaitForChild("FlashlightUpdated") :: RemoteEvent

type PlayerState = {
	character: Model?,
	attachment: Attachment?,
	light: SpotLight?,
	deathConnection: RBXScriptConnection?,
	connections: {RBXScriptConnection},
	nextToggle: number,
	nextAim: number,
}

local LightService = {}
local states: {[Player]: PlayerState} = {}
local started = false

local function clearLight(player: Player, state: PlayerState)
	if state.deathConnection then state.deathConnection:Disconnect() end
	if state.attachment then state.attachment:Destroy() end
	state.deathConnection = nil
	state.attachment = nil
	state.light = nil
	state.character = nil
	if player.Parent == Players then flashlightUpdated:FireClient(player, false) end
end

local function addPlayer(player: Player)
	if states[player] then return end
	local state: PlayerState = {
		character = nil,
		attachment = nil,
		light = nil,
		deathConnection = nil,
		connections = {},
		nextToggle = 0,
		nextAim = 0,
	}
	states[player] = state

	local function onCharacter(character: Model)
		if player.Character ~= character or states[player] ~= state then return end
		clearLight(player, state)
		state.character = character
		local head = character:WaitForChild("Head", settings.CharacterWaitSeconds)
		local humanoid = character:WaitForChild("Humanoid", settings.CharacterWaitSeconds)
		-- Ignore setup that finished after removal or another respawn.
		if states[player] ~= state or state.character ~= character or player.Character ~= character then return end
		if not head or not head:IsA("BasePart") or not humanoid or not humanoid:IsA("Humanoid") then
			warn(string.format("[Light] %s: missing Head or Humanoid; flashlight unavailable", player.Name))
			return
		end
		if humanoid.Health <= 0 then return end

		local attachment = Instance.new("Attachment")
		attachment.Name = "FlashlightAttachment"
		attachment.Position = settings.Offset
		attachment.Parent = head
		local light = Instance.new("SpotLight")
		light.Name = "Flashlight"
		light.Face = Enum.NormalId.Front
		light.Range = settings.Range
		light.Angle = settings.Angle
		light.Brightness = settings.Brightness
		light.Color = settings.Color
		light.Shadows = settings.Shadows
		light.Enabled = false
		light.Parent = attachment
		state.attachment = attachment
		state.light = light
		state.nextToggle = 0
		state.nextAim = 0
		state.deathConnection = humanoid.Died:Connect(function()
			clearLight(player, state)
		end)
		flashlightUpdated:FireClient(player, false)
		print(string.format("[Light] %s: flashlight ready OFF | range %g studs; angle %g; brightness %g",
			player.Name, settings.Range, settings.Angle, settings.Brightness))
	end

	table.insert(state.connections, player.CharacterAdded:Connect(onCharacter))
	table.insert(state.connections, player.CharacterRemoving:Connect(function(character: Model)
		if state.character == character then clearLight(player, state) end
	end))
	if player.Character then task.spawn(onCharacter, player.Character) end
end

function LightService.Start()
	if started then return end
	assert(settings.AimUpdateInterval > 0 and settings.ToggleCooldown >= 0,
		"Config.Flashlight needs a positive AimUpdateInterval and nonnegative ToggleCooldown")
	started = true
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		local state = states[player]
		if not state then return end
		for _, connection in state.connections do connection:Disconnect() end
		clearLight(player, state)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do addPlayer(player) end

	flashlightInput.OnServerEvent:Connect(function(player: Player, action: any, direction: any)
		local state = states[player]
		if not state or not state.light or not state.attachment then return end
		local light = state.light
		local attachment = state.attachment
		local now = os.clock()
		if action == "Toggle" then
			if now < state.nextToggle then return end
			state.nextToggle = now + settings.ToggleCooldown
			light.Enabled = not light.Enabled
			flashlightUpdated:FireClient(player, light.Enabled)
			print(string.format("[Light] %s: flashlight %s", player.Name, if light.Enabled then "ON" else "OFF"))
		elseif action == "Aim" then
			if not light.Enabled or now < state.nextAim then return end
			state.nextAim = now + settings.AimUpdateInterval
			if typeof(direction) ~= "Vector3" then return end
			local magnitude = direction.Magnitude
			if magnitude ~= magnitude or magnitude <= 0 or magnitude >= math.huge then return end
			local head = attachment.Parent
			if not head or not head:IsA("BasePart") then return end
			-- Accept look direction only; origin and light settings stay server-owned.
			local localDirection = head.CFrame:VectorToObjectSpace(direction.Unit)
			attachment.CFrame = CFrame.new(settings.Offset) * CFrame.lookAt(Vector3.zero, localDirection)
		end
	end)
end

return LightService
