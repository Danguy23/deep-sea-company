--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SafeZoneService = require(script.Parent:WaitForChild("SafeZoneService"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local OxygenTypes = require(Shared:WaitForChild("OxygenTypes"))
local oxygenUpdated = Shared:WaitForChild("Remotes"):WaitForChild("OxygenUpdated") :: RemoteEvent

type PlayerState = {
	oxygen: number,
	character: Model?,
	inSub: boolean?,
	downed: boolean,
	logElapsed: number,
	characterConnection: RBXScriptConnection,
}

local OxygenService = {}
local states: {[Player]: PlayerState} = {}
local started = false
local roundEnded = false
local zoneWasAvailable: boolean? = nil

-- Future run logic can subscribe to this server-only signal.
local depleted = Instance.new("BindableEvent")
OxygenService.Depleted = depleted.Event

local function findSafeZone(): BasePart?
	local safeZone = SafeZoneService.Find()
	local available = safeZone ~= nil
	if available ~= zoneWasAvailable then
		zoneWasAvailable = available
		if available then
			print("[Oxygen] Workspace.Submarine.SafeZone found; oxygen updates active.")
		else
			warn("[Oxygen] MISSING Workspace.Submarine Model / SafeZone Part. Oxygen paused until the scene is fixed.")
		end
	end
	return safeZone
end

local function sendSnapshot(player: Player, state: PlayerState, available: boolean)
	local snapshot: OxygenTypes.Snapshot = {
		oxygen = state.oxygen,
		maximum = Config.OxygenMax,
		inSub = state.inSub == true,
		downed = state.downed,
		roundEnded = roundEnded,
		available = available,
	}
	oxygenUpdated:FireClient(player, snapshot)
end

local function addPlayer(player: Player)
	if states[player] then
		return
	end
	local state: PlayerState
	local function onCharacter(character: Model)
		state.character = character
		state.oxygen = if roundEnded then 0 else Config.OxygenMax
		state.inSub = nil
		state.downed = roundEnded
		state.logElapsed = 0
		print(string.format("[Oxygen] %s: oxygen %.1f/%d; roundEnded=%s", player.Name, state.oxygen, Config.OxygenMax, tostring(roundEnded)))
	end
	state = {
		oxygen = Config.OxygenMax,
		character = nil,
		inSub = nil,
		downed = roundEnded,
		logElapsed = 0,
		characterConnection = player.CharacterAdded:Connect(onCharacter),
	}
	states[player] = state
	if player.Character then
		onCharacter(player.Character)
	end
end

local function updatePlayer(player: Player, state: PlayerState, zone: BasePart?, elapsed: number)
	local character = state.character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not roundEnded and not state.downed and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") and character and zone then
		local inSub = SafeZoneService.IsCharacterInside(character, root, zone)
		if inSub ~= state.inSub then
			print(string.format("[Oxygen] %s: %s sub at %.1f/%d", player.Name, if inSub then "entered" else "outside", state.oxygen, Config.OxygenMax))
		end
		state.inSub = inSub
		local rate = if inSub then Config.OxygenRefillPerSecond else -Config.OxygenDrainPerSecond
		state.oxygen = math.clamp(state.oxygen + rate * elapsed, 0, Config.OxygenMax)
		state.logElapsed += elapsed
		if state.logElapsed >= Config.OxygenLogInterval then
			state.logElapsed = 0
			print(string.format("[Oxygen] %s: %.1f/%d (%s)", player.Name, state.oxygen, Config.OxygenMax, if inSub then "refilling" else "draining"))
		end
		if state.oxygen <= 0 then
			state.downed = true
			roundEnded = true
			humanoid.Health = 0
			print(string.format("[Oxygen] %s DOWNED at 0/%d. Round ended; press Stop then Play for a new test.", player.Name, Config.OxygenMax))
			depleted:Fire(player)
		end
	end
	-- Repeated snapshots let a late-loading HUD recover without client requests.
	sendSnapshot(player, state, zone ~= nil)
end

function OxygenService.Start()
	if started then
		return
	end
	started = true
	findSafeZone()
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		local state = states[player]
		if state then
			state.characterConnection:Disconnect()
			states[player] = nil
		end
	end)
	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
	local accumulated = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulated += deltaTime
		if accumulated < Config.OxygenUpdateInterval then
			return
		end
		local elapsed = accumulated
		accumulated = 0
		local zone = findSafeZone()
		for player, state in states do
			updatePlayer(player, state, zone, elapsed)
		end
	end)
	print(string.format("[Oxygen] Service started: max=%g, drain=%g/s, refill=%g/s (see Shared.Config).", Config.OxygenMax, Config.OxygenDrainPerSecond, Config.OxygenRefillPerSecond))
end

return OxygenService
