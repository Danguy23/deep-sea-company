--!strict
-- Assembles prebuilt room templates into a map by mating their Connector
-- attachments, then settles the doorway caps. Picking rooms, randomness, and
-- teardown live in MapService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local settings = Config.RoomStitch

type Box = {min: Vector3, max: Vector3}
type CapState = {Transparency: number, CanCollide: boolean, CanQuery: boolean, CanTouch: boolean}

local RoomStitcher = {}

-- Rooms placed in the current build. Reset forgets them; it never destroys.
local placedRooms = {} :: {Model}

-- Models that already stood in the world (the Submarine) and outlive every map.
-- Their mated caps are hidden instead of destroyed so RestoreExisting can bring
-- them back. Only RestoreExisting clears these, so a Reset alone never loses a cap.
local existingRooms = {} :: {Model}
local hiddenCaps = {} :: {[BasePart]: CapState}

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

-- The original state is recorded only once, so finalizing twice cannot
-- overwrite it with the hidden state.
local function hideCap(cap: BasePart)
	if not hiddenCaps[cap] then
		hiddenCaps[cap] = {
			Transparency = cap.Transparency,
			CanCollide = cap.CanCollide,
			CanQuery = cap.CanQuery,
			CanTouch = cap.CanTouch,
		}
	end
	cap.Transparency = 1
	cap.CanCollide = false
	cap.CanQuery = false
	cap.CanTouch = false
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

-- Registers a room that already stands in the world, without cloning it, so new
-- rooms can attach to its Connectors and its Bounds count for overlap checks.
function RoomStitcher.RegisterExisting(model: Model): boolean
	if not boundsOf(model) then
		return false
	end
	if not table.find(placedRooms, model) then
		table.insert(placedRooms, model)
	end
	if not table.find(existingRooms, model) then
		table.insert(existingRooms, model)
	end
	return true
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
		-- Overlap is an expected outcome while generating, so callers count it instead of a warning.
		if placedBounds and boxesOverlap(box, worldBox(placedBounds)) then
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

-- Caps are settled here in one pass rather than inside Attach, because later
-- generation steps try placements and reject some: a cap opened for a placement
-- that then gets rolled back would leave a hole to the void. Safe to call twice.
-- Returns how many doorways were opened, capped, and missing a cap.
function RoomStitcher.FinalizeDoorways(): (number, number, number)
	local opened, capped, missing = 0, 0, 0
	for _, room in ipairs(placedRooms) do
		for id, connector in pairs(RoomStitcher.GetConnectors(room)) do
			local cap = room:FindFirstChild("Cap_" .. id)
			if connector:GetAttribute("Mated") == true then
				-- Both rooms at a joint drop their cap, so the doorway opens from either side.
				if cap and cap:IsA("BasePart") and table.find(existingRooms, room) then
					hideCap(cap)
					opened += 1
				elseif cap then
					cap:Destroy()
					opened += 1
				end
			elseif cap == nil then
				missing += 1
				warn(string.format(
					"[RoomStitcher] MISSING Cap_%s on %s; that unused doorway is a hole to the void.",
					id, room:GetFullName()
				))
			elseif cap:IsA("BasePart") then
				cap.Anchored = true
				cap.CanCollide = true
				capped += 1
			else
				missing += 1
				warn(string.format(
					"[RoomStitcher] Cap_%s on %s is a %s, not a Part; that unused doorway is a hole to the void.",
					id, room:GetFullName(), cap.ClassName
				))
			end
		end
	end
	print(string.format(
		"[RoomStitcher] Doorways finalized: %d room(s), %d opened, %d capped, %d missing.",
		#placedRooms, opened, capped, missing
	))
	return opened, capped, missing
end

-- Puts every registered-existing model back as it was before any map touched it.
function RoomStitcher.RestoreExisting()
	for _, room in ipairs(existingRooms) do
		for _, connector in pairs(RoomStitcher.GetConnectors(room)) do
			connector:SetAttribute("Mated", nil)
		end
	end
	for cap, state in pairs(hiddenCaps) do
		cap.Transparency = state.Transparency
		cap.CanCollide = state.CanCollide
		cap.CanQuery = state.CanQuery
		cap.CanTouch = state.CanTouch
	end
	table.clear(hiddenCaps)
	table.clear(existingRooms)
end

function RoomStitcher.Reset()
	table.clear(placedRooms)
end

return RoomStitcher
