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

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "Atmosphere"
		atmosphere.Parent = Lighting
	end

	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") and child ~= atmosphere then
			warn(string.format("[Atmosphere] Removing extra Atmosphere %s during Play", child.Name))
			child:Destroy()
		elseif child:IsA("ColorCorrectionEffect") then
			child.Enabled = false
			child.Brightness = 0
			child.Contrast = 0
			child.Saturation = 0
			child.TintColor = Color3.new(1, 1, 1)
		end
	end

	atmosphere.Color = settings.AtmosphereColor
	atmosphere.Decay = settings.AtmosphereDecay
	atmosphere.Density = settings.AtmosphereDensity
	atmosphere.Offset = settings.AtmosphereOffset
	atmosphere.Glare = settings.AtmosphereGlare
	atmosphere.Haze = settings.AtmosphereHaze

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
	sky.CelestialBodiesShown = settings.CelestialBodiesShown
	sky.StarCount = settings.StarCount

	print(string.format("[Atmosphere] Default lighting restored | fog %g-%g studs; clock %g; brightness %g",
		settings.FogStart, settings.ViewDistance, settings.ClockTime, settings.Brightness))
end

return AtmosphereService
