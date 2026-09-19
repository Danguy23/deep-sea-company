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
	health: number,
	character: Model?,
	inSub: boolean?,
	downed: boolean,
	suffocating: boolean,
	logElapsed: number,
	characterConnection: RBXScriptConnection,
}

local OxygenService = {}
local states: {[Player]: PlayerState} = {}
local started = false
local active = false
local zoneWasAvailable: boolean? = nil

-- Reports death after the drowning countdown; RunService owns the dive end.
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

local function sendSnapshot(player: Player, state: PlayerState, zone: BasePart?)
	local snapshot: OxygenTypes.Snapshot = {
		oxygen = state.oxygen,
		maximum = Config.OxygenMax,
		health = state.health,
		healthMaximum = Config.HealthMax,
		inSub = state.inSub == true,
		downed = state.downed,
		roundEnded = not active,
		available = zone ~= nil,
		safeZonePosition = if zone then zone.Position else nil,
	}
	oxygenUpdated:FireClient(player, snapshot)
end

local function downPlayer(player: Player, state: PlayerState, reason: string): boolean
	if not active or state.downed then return false end
	local character = state.character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid then return false end
	state.health = 0
	state.downed = true
	state.suffocating = false
	humanoid.Health = 0
	print(string.format("[Oxygen] %s DOWNED (%s); oxygen %.1f/%d.", player.Name, reason, state.oxygen, Config.OxygenMax))
	sendSnapshot(player, state, SafeZoneService.Find())
	depleted:Fire(player)
	return true
end

local function addPlayer(player: Player)
	if states[player] then
		return
	end
	local state: PlayerState
	local function onCharacter(character: Model)
		state.character = character
		state.health = Config.HealthMax
		state.suffocating = false
		state.inSub = nil
		state.logElapsed = 0
		print(string.format("[Oxygen] %s: oxygen %.1f/%d; active=%s", player.Name, state.oxygen, Config.OxygenMax, tostring(active)))
	end
	state = {
		oxygen = Config.OxygenMax,
		health = Config.HealthMax,
		character = nil,
		inSub = nil,
		downed = false,
		suffocating = false,
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
	if humanoid then
		humanoid.MaxHealth = Config.HealthMax
		-- Keep damage authoritative; Roblox's passive regeneration cannot erase it.
		state.health = math.min(state.health, humanoid.Health)
		humanoid.Health = state.health
	end
	if active and not state.downed and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") and character and zone then
		local inSub = SafeZoneService.IsCharacterInside(character, root, zone)
		if inSub ~= state.inSub then
			print(string.format("[Oxygen] %s: %s sub at %.1f/%d", player.Name, if inSub then "entered" else "outside", state.oxygen, Config.OxygenMax))
		end
		state.inSub = inSub
		local rate = if inSub then Config.OxygenRefillPerSecond else -Config.OxygenDrainPerSecond
		local oxygenBefore = state.oxygen
		state.oxygen = math.clamp(state.oxygen + rate * elapsed, 0, Config.OxygenMax)
		if not inSub and state.oxygen <= 0 then
			-- Only damage for the portion of this tick spent without oxygen.
			local drowningElapsed = math.max(0, elapsed - oxygenBefore / Config.OxygenDrainPerSecond)
			state.health = math.max(0, state.health - Config.HealthMax / Config.DrowningSeconds * drowningElapsed)
			humanoid.Health = state.health
			if not state.suffocating then
				print(string.format("[Oxygen] %s OUT OF AIR; HP %.1f/%g, drowning at %g HP/s.", player.Name, state.health, Config.HealthMax, Config.HealthMax / Config.DrowningSeconds))
			end
			state.suffocating = true
		elseif state.suffocating then
			state.suffocating = false
			print(string.format("[Oxygen] %s rescued in sub; HP %.1f/%g, oxygen refilling.", player.Name, state.health, Config.HealthMax))
		end
		state.logElapsed += elapsed
		if state.logElapsed >= Config.OxygenLogInterval then
			state.logElapsed = 0
			print(string.format("[Oxygen] %s: %.1f/%d (%s)", player.Name, state.oxygen, Config.OxygenMax, if inSub then "refilling" else "draining"))
		end
		if state.health <= 0 then downPlayer(player, state, "out of air") end
	end
	-- Repeated snapshots let a late-loading HUD recover without client requests.
	sendSnapshot(player, state, zone)
end

function OxygenService.SetActive(value: boolean)
	active = value
end

function OxygenService.Reset()
	for player, state in states do
		state.oxygen = Config.OxygenMax
		local humanoid = if state.character then state.character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid and humanoid.Health > 0 then
			state.health = Config.HealthMax
			humanoid.MaxHealth = Config.HealthMax
			humanoid.Health = state.health
		end
		state.downed = false
		state.suffocating = false
		state.inSub = nil
		state.logElapsed = 0
		sendSnapshot(player, state, SafeZoneService.Find())
	end
end

function OxygenService.IsDowned(player: Player): boolean
	local state = states[player]
	local humanoid = if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
	return (state ~= nil and state.downed) or (humanoid ~= nil and humanoid.Health <= 0)
end

-- All hazards use this path so downed state and RunService's crew check stay unified.
function OxygenService.DownPlayer(player: Player, reason: string): boolean
	local state = states[player]
	if not state then return false end
	return downPlayer(player, state, reason)
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
	print(string.format("[Oxygen] Service started: max=%g, drain=%g/s, refill=%g/s, HP=%g, drowning=%gs (see Shared.Config).", Config.OxygenMax, Config.OxygenDrainPerSecond, Config.OxygenRefillPerSecond, Config.HealthMax, Config.DrowningSeconds))
end

return OxygenService
