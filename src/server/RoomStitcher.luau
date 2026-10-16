--!strict
-- Assembles prebuilt room templates into a map by mating their Connector
-- attachments. Placement only: picking rooms, randomness, cap removal, and
-- teardown live elsewhere.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local settings = Config.RoomStitch

type Box = {min: Vector3, max: Vector3}

local RoomStitcher = {}

-- Rooms placed in the current build. Reset forgets them; it never destroys.
local placedRooms = {} :: {Model}

local function boundsOf(room: Model): BasePart?
	local bounds = room.PrimaryPart
	if not bounds then
		warn(string.format("[RoomStitcher] MISSING PrimaryPart on %s; a room needs an anchored Bounds Part.", room:GetFullName()))
		return nil
	end
	if bounds.Name ~= "Bounds" then
		warn(string.format("[RoomStitcher] %s has PrimaryPart %q, expected 'Bounds'.", room:GetFullName(), bounds.Name))
		return nil
	end
	return bounds
end

-- Rooms only ever rotate in 90 degree steps around Y, so a Bounds world box is
-- exactly its axis-aligned box. Any other rotation makes the box conservative.
local function warnIfNotAxisAligned(bounds: BasePart)
	local cf = bounds.CFrame
	for _, axis in ipairs({cf.RightVector, cf.UpVector, cf.LookVector}) do
		for _, component in ipairs({axis.X, axis.Y, axis.Z}) do
			local magnitude = math.abs(component)
			if magnitude > settings.TouchTolerance and magnitude < 1 - settings.TouchTolerance then
				warn(string.format(
					"[RoomStitcher] %s is not rotated in 90 degree steps; overlap checks fall back to a conservative box.",
					bounds:GetFullName()
				))
				return
			end
		end
	end
end

local function worldBox(bounds: BasePart): Box
	local cf = bounds.CFrame
	local half = bounds.Size / 2
	local min, max = cf.Position, cf.Position
	for xSign = -1, 1, 2 do
		for ySign = -1, 1, 2 do
			for zSign = -1, 1, 2 do
				local corner = cf * Vector3.new(half.X * xSign, half.Y * ySign, half.Z * zSign)
				min, max = min:Min(corner), max:Max(corner)
			end
		end
	end
	return {min = min, max = max}
end

-- Shared faces are how mated rooms are meant to sit, so a touch is not an overlap.
local function boxesOverlap(a: Box, b: Box): boolean
	local depth = a.max:Min(b.max) - a.min:Max(b.min)
	local tolerance = settings.TouchTolerance
	return depth.X > tolerance and depth.Y > tolerance and depth.Z > tolerance
end

function RoomStitcher.GetConnectors(room: Model): {[string]: Attachment}
	local connectors: {[string]: Attachment} = {}
	for _, descendant in ipairs(room:GetDescendants()) do
		if descendant:IsA("Attachment") and descendant.Name == "Connector" then
			local attribute = descendant:GetAttribute("ConnectorId")
			local id: string? = if typeof(attribute) == "string" then attribute else nil
			if id == nil or id == "" then
				warn(string.format(
					"[RoomStitcher] %s has a Connector with a missing or non-string ConnectorId; ignoring it.",
					room:GetFullName()
				))
			elseif connectors[id] then
				warn(string.format(
					"[RoomStitcher] %s has more than one Connector with ConnectorId %q; ignoring the duplicate.",
					room:GetFullName(), id
				))
			else
				connectors[id] = descendant
			end
		end
	end
	return connectors
end

function RoomStitcher.PlaceFirst(template: Model, pivot: CFrame, parent: Instance): Model
	local clone = template:Clone()
	clone:PivotTo(pivot)
	clone.Parent = parent
	table.insert(placedRooms, clone)
	local bounds = boundsOf(clone)
	if bounds then
		warnIfNotAxisAligned(bounds)
	end
	return clone
end

function RoomStitcher.Attach(
	placedRoom: Model,
	placedConnectorId: string,
	template: Model,
	templateConnectorId: string,
	parent: Instance
): Model?
	local placedConnector = RoomStitcher.GetConnectors(placedRoom)[placedConnectorId]
	if not placedConnector then
		warn(string.format("[RoomStitcher] Rejected: %s has no Connector %q.", placedRoom:GetFullName(), placedConnectorId))
		return nil
	end
	if placedConnector:GetAttribute("Mated") == true then
		warn(string.format(
			"[RoomStitcher] Rejected: %s Connector %q is already mated.",
			placedRoom:GetFullName(), placedConnectorId
		))
		return nil
	end

	local clone = template:Clone()
	local cloneConnector = RoomStitcher.GetConnectors(clone)[templateConnectorId]
	if not cloneConnector then
		warn(string.format("[RoomStitcher] Rejected: %s has no Connector %q.", template:GetFullName(), templateConnectorId))
		clone:Destroy()
		return nil
	end

	-- Face the new connector back into the placed one, keeping both up vectors +Y.
	local target = placedConnector.WorldCFrame * CFrame.Angles(0, math.pi, 0)
	local offset = cloneConnector.WorldCFrame:Inverse() * clone:GetPivot()
	clone:PivotTo(target * offset)

	local bounds = boundsOf(clone)
	if not bounds then
		warn(string.format("[RoomStitcher] Rejected: %s cannot be placed without Bounds.", template:GetFullName()))
		clone:Destroy()
		return nil
	end
	warnIfNotAxisAligned(bounds)

	local box = worldBox(bounds)
	for _, placed in ipairs(placedRooms) do
		local placedBounds = boundsOf(placed)
		if placedBounds and boxesOverlap(box, worldBox(placedBounds)) then
			warn(string.format(
				"[RoomStitcher] Rejected: %s on %s Connector %q would overlap the already-placed %s.",
				template.Name, placedRoom:GetFullName(), placedConnectorId, placed:GetFullName()
			))
			clone:Destroy()
			return nil
		end
	end

	clone.Parent = parent
	placedConnector:SetAttribute("Mated", true)
	cloneConnector:SetAttribute("Mated", true)
	table.insert(placedRooms, clone)
	return clone
end

function RoomStitcher.Reset()
	table.clear(placedRooms)
end

return RoomStitcher
