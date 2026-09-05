local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

-- Create the remote immediately, before anything below that might yield (WaitForChild on
-- WoodBoat, requiring InventoryManager) -- mirrors FurnaceManager.server.luau. Shared with the
-- furnace: PlaceItem carries an itemName, and each manager just ignores events for items that
-- aren't its own.
local function getOrCreateRemote(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = ReplicatedStorage
	end
	return event
end

local placeItemEvent = getOrCreateRemote("PlaceItem")

local DeployablePlacementManager = require(ServerScriptService:WaitForChild("DeployablePlacementManager"))

-- Expects a Model named "WoodBoat" directly under ReplicatedStorage (not ServerStorage -- the
-- client also needs to see it, since PlacementController.client.luau clones it locally for the
-- ghost/hologram preview while placing), same convention as FurnaceTemplate. Needs its
-- PrimaryPart set, and a VehicleSeat somewhere inside it (any name) to be drivable.
local boatTemplate = ReplicatedStorage:WaitForChild("WoodBoat", 10)

-- Works whether WoodBoat is a Model (GetExtentsSize) or just a single BasePart (Size directly) --
-- GetExtentsSize only exists on Model, so calling it unconditionally here would error and (since
-- this runs at the top level) silently kill the rest of this script before the placement handler
-- below ever gets connected.
local function getSize(instance)
	if instance:IsA("Model") then
		return instance:GetExtentsSize()
	elseif instance:IsA("BasePart") then
		return instance.Size
	end
	return Vector3.new(4, 4, 4)
end

-- Same Model-or-BasePart flexibility as getSize above -- a bare Part has no PrimaryPart property
-- at all (accessing it errors), so it has to be its own "primary part".
local function getPrimaryPart(instance)
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	elseif instance:IsA("BasePart") then
		return instance
	end
	return nil
end

local boatHalfHeight = boatTemplate and getSize(boatTemplate).Y / 2 or 0

local PLACEMENT_DISTANCE = 6 -- studs; matches FurnaceManager/PlacementController
local BOAT_MAX_SPEED = 40 -- studs/sec forward at full throttle
local BOAT_MAX_TURN_SPEED = 2 -- radians/sec at full steer

-- Keeps the boat upright (resists tipping/capsizing from waves or collisions) while still letting
-- it rotate freely around its own up axis for steering. AlignOrientation with PrimaryAxisOnly only
-- pulls the local up vector toward world up -- it doesn't fight yaw at all.
local function addUprightStabilizer(primaryPart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "UprightAttachment"
	attachment.Parent = primaryPart

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Attachment0 = attachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.PrimaryAxisOnly = true
	alignOrientation.PrimaryAxis = Vector3.new(0, 1, 0)
	alignOrientation.MaxTorque = math.huge
	alignOrientation.Responsiveness = 25
	alignOrientation.Parent = primaryPart
end

-- Drives the boat from whichever VehicleSeat is inside it -- Throttle/Steer are set automatically
-- by Roblox for whoever's sitting in the seat and replicate to the server on their own, no custom
-- remote needed. Runs server-side (rather than trusting client-reported speed) so a modified
-- client can't move the boat faster than BOAT_MAX_SPEED/BOAT_MAX_TURN_SPEED.
local function addDriving(boat, primaryPart, seat)
	local heartbeatConnection
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		local throttle = seat.Throttle
		local steer = seat.Steer

		local lookVector = primaryPart.CFrame.LookVector
		local forward = lookVector * (throttle * BOAT_MAX_SPEED)

		-- Only override the horizontal velocity -- leave vertical alone so buoyancy/wave bobbing
		-- from Terrain water still applies instead of being stomped every frame.
		local currentVelocity = primaryPart.AssemblyLinearVelocity
		primaryPart.AssemblyLinearVelocity = Vector3.new(forward.X, currentVelocity.Y, forward.Z)
		-- Negated: A/D turn opposite of Roblox's default Steer sign for this boat -- W/S (throttle) untouched.
		primaryPart.AssemblyAngularVelocity = Vector3.new(0, -steer * BOAT_MAX_TURN_SPEED, 0)
	end)

	boat.AncestryChanged:Connect(function(_, parent)
		if not parent then
			heartbeatConnection:Disconnect()
		end
	end)
end

-- Being parent/child in the Instance tree doesn't physically connect two parts -- without an
-- explicit weld, a VehicleSeat (or any other loose part) sitting inside the boat is an independent
-- physics body that can collide with and push against the hull, which is what was making placed
-- boats tip over/capsize instead of floating flat.
-- Anchoring/unanchoring every BasePart in the boat, not just the primary one -- before welds
-- exist, an unanchored seat would still fall/simulate on its own even if the hull is anchored.
local function setAssemblyAnchored(boat, anchored)
	if boat:IsA("BasePart") then
		boat.Anchored = anchored
	end
	for _, descendant in ipairs(boat:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
		end
	end
end

local function weldAssemblyTogether(boat, primaryPart)
	for _, descendant in ipairs(boat:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= primaryPart then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primaryPart
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
end

local function registerBoat(boat)
	local primaryPart = getPrimaryPart(boat)
	if not primaryPart then
		warn("WoodBoat placed without a PrimaryPart/BasePart -- can't drive or stabilize it.")
		return
	end

	weldAssemblyTogether(boat, primaryPart)
	addUprightStabilizer(primaryPart)

	local seat = boat:FindFirstChildWhichIsA("VehicleSeat", true)
	if not seat then
		warn("WoodBoat placed without a VehicleSeat inside it -- it won't be drivable.")
		return
	end

	addDriving(boat, primaryPart, seat)
end

-- ===== Placement =====
-- Mirrors FurnaceManager's placement handler exactly, including trusting the client's rotationY
-- (cosmetic only) but recomputing position server-side. Deliberately does NOT set
-- RaycastParams.IgnoreWater -- a boat placed over water should land on the water surface, not sink
-- through it to whatever's on the seabed.
placeItemEvent.OnServerEvent:Connect(function(player, itemName, rotationY)
	if itemName ~= "WoodBoat" then return end -- only handles its own item; FurnaceManager etc. handle theirs
	if not boatTemplate then return end
	if typeof(rotationY) ~= "number" then rotationY = 0 end
	-- Ingredients were already spent at craft time (see InventoryManager's craft handler +
	-- DeployablePlacementManager) -- this just checks there's still a live blueprint to place.
	if not DeployablePlacementManager.IsPending(player, "WoodBoat") then return end

	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local horizontalPosition = rootPart.Position + rootPart.CFrame.LookVector * PLACEMENT_DISTANCE

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(horizontalPosition + Vector3.new(0, 10, 0), Vector3.new(0, -50, 0), raycastParams)
	local groundPosition = result and result.Position or horizontalPosition
	local placePosition = groundPosition + Vector3.new(0, boatHalfHeight, 0)

	DeployablePlacementManager.ClearPending(player)

	local boat = boatTemplate:Clone()
	-- Stays fully anchored (zero gravity/velocity) through positioning, welding, and stabilizer
	-- setup, then gets released all at once -- otherwise it starts falling/simulating the instant
	-- it's parented into workspace, and can pick up enough velocity before the weld/stabilizer are
	-- even in place to slam into the water and tip itself over on impact.
	setAssemblyAnchored(boat, true)
	boat:PivotTo(CFrame.new(placePosition) * CFrame.Angles(0, rotationY, 0))
	boat.Parent = workspace

	registerBoat(boat)
	setAssemblyAnchored(boat, false)
end)
