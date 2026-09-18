--!strict

local SafeZoneService = {}

function SafeZoneService.Find(): BasePart?
	local submarine = workspace:FindFirstChild("Submarine")
	local zone = if submarine and submarine:IsA("Model") then submarine:FindFirstChild("SafeZone") else nil
	return if zone and zone:IsA("BasePart") then zone else nil
end

function SafeZoneService.IsCharacterInside(character: Model, root: BasePart, zone: BasePart): boolean
	local point = zone.CFrame:PointToObjectSpace(root.Position)
	local halfSize = zone.Size / 2
	if math.abs(point.X) <= halfSize.X and math.abs(point.Y) <= halfSize.Y and math.abs(point.Z) <= halfSize.Z then
		return true
	end
	-- Count character limbs touching the boundary, excluding carried loot.
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = {character}
	overlap.MaxParts = 1
	return #workspace:GetPartBoundsInBox(zone.CFrame, zone.Size + Vector3.new(0.1, 0.1, 0.1), overlap) > 0
end

return SafeZoneService
