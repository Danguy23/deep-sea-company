--!strict

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local AtmosphereService = {}
local started = false

function AtmosphereService.Start()
	if started then return end
	local settings = Config.Underwater
	assert(settings.FogStart >= 0 and settings.ViewDistance > settings.FogStart
		and settings.ViewDistance < math.huge, "Config.Underwater needs 0 <= FogStart < finite ViewDistance")
	started = true

	-- Atmosphere overrides linear fog. Remove it only in the running session;
	-- the authored scene remains intact when Studio stops Play.
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") then
			warn(string.format("[Atmosphere] Removing %s during Play so underwater fog can work", child.Name))
			child:Destroy()
		end
	end

	Lighting.FogColor = settings.TintColor
	Lighting.FogStart = settings.FogStart
	Lighting.FogEnd = settings.ViewDistance
	Lighting.Ambient = settings.AmbientColor
	Lighting.OutdoorAmbient = settings.AmbientColor
	Lighting.Brightness = settings.Brightness
	Lighting.ClockTime = settings.ClockTime
	Lighting.EnvironmentDiffuseScale = settings.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = settings.EnvironmentSpecularScale
	Lighting.ExposureCompensation = settings.ExposureCompensation
	Lighting.ColorShift_Top = settings.ColorShift
	Lighting.ColorShift_Bottom = settings.ColorShift
	Lighting.GlobalShadows = settings.GlobalShadows

	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Name = "UnderwaterSky"
		sky.Parent = Lighting
	end
	-- Keep the night sky from advertising an open surface above the player.
	-- Fog obscures geometry, but does not hide celestial bodies or stars.
	sky.CelestialBodiesShown = settings.CelestialBodiesShown
	sky.StarCount = settings.StarCount

	print(string.format("[Atmosphere] Underwater look applied | fog %g-%g studs; clock %g; brightness %g",
		settings.FogStart, settings.ViewDistance, settings.ClockTime, settings.Brightness))
end

return AtmosphereService
