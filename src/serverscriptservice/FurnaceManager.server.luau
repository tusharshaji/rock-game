local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

-- Create the remote immediately, before anything below that might yield (WaitForChild on
-- FurnaceTemplate, requiring InventoryManager) -- otherwise clients waiting on this remote at
-- startup see an "Infinite yield possible" warning while it sits blocked behind those lookups.
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
local ItemIconRenderer = require(ReplicatedStorage:WaitForChild("ItemIconRenderer"))

-- Expects a Model named "FurnaceTemplate" directly under ReplicatedStorage (not ServerStorage --
-- it has to be somewhere the client can also see it, since PlacementController.client.luau clones
-- it locally for the ghost/hologram preview while placing). It needs a child part/model named
-- "Tray" -- that's what detects items being dropped in for smelting, and where finished items pop
-- back out.
local furnaceTemplate = ReplicatedStorage:WaitForChild("FurnaceTemplate", 10)
local dropItemsFolder = ServerStorage:WaitForChild("DropItems")

-- PivotTo() places a Model's CENTER at the given CFrame, not its base, so placing that center
-- exactly on the ground buries the bottom half. Lifting by half the model's own height first
-- makes it sit flush on the surface instead. Computed once from the template so it stays correct
-- automatically if the model is resized later.
local furnaceHalfHeight = furnaceTemplate and furnaceTemplate:GetExtentsSize().Y / 2 or 0

local PLACEMENT_DISTANCE = 6
local MAX_QUEUE_SIZE = 10
local MAX_FUEL = 500
local FURNACE_PICKUP_RANGE = 6 -- studs from the tray; anything valid dropped within this gets pulled in each scan tick

-- Which raw item smelts into what, and how long each unit takes (seconds)
local SMELT_RECIPES = {
	RawIronItem = { Result = "IronIngotItem", Time = 10 },
	MeatItem = { Result = "CookedMeatItem", Time = 8 },
}

-- How many seconds of burn time each fuel unit provides
local FUEL_VALUES = {
	CoalItem = 30,
	WoodItem = 10,
}

local furnaceStates = {} -- [furnaceInstance] = { fuel = number, queue = { {itemName=, progress=} } }

-- ===== Spawns a physical, pickupable output item at a given position. Mirrors the drop logic
-- used in InventoryManager/PickupServer (template clone if one exists in DropItems, generic Part
-- fallback otherwise, welded + unanchored so it falls and settles). Takes a raw position rather
-- than the furnace itself, since it also gets used when the furnace is destroyed/broken -- at
-- that point querying the (already-destroyed) furnace instance for its Tray isn't reliable. =====
local function spawnOutput(position, itemName, amount)
	local template = dropItemsFolder:FindFirstChild(itemName)
	local drop = template and template:Clone() or Instance.new("Part")
	if not template then
		drop.Name = itemName
		drop.Size = Vector3.new(1, 1, 1)
	end

	local jitter = Vector3.new(math.random(-1, 1), 1.5, math.random(-1, 1))
	drop:PivotTo(CFrame.new(position + jitter))
	drop:SetAttribute("ItemName", itemName)
	drop:SetAttribute("Amount", amount)
	CollectionService:AddTag(drop, "Pickupable")

	local parts = {}
	if drop:IsA("BasePart") then
		table.insert(parts, drop)
	else
		for _, child in ipairs(drop:GetDescendants()) do
			if child:IsA("BasePart") then
				table.insert(parts, child)
			end
		end
	end

	local anchorPart
	if drop:IsA("Model") then
		anchorPart = drop.PrimaryPart or parts[1]
	else
		anchorPart = drop
	end

	for _, part in ipairs(parts) do
		part.CanTouch = false
		part.Anchored = false
		part.CanCollide = true
		if anchorPart and part ~= anchorPart then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = anchorPart
			weld.Part1 = part
			weld.Parent = part
		end
	end

	drop.Parent = workspace
end

-- A part found via GetPartBoundsInRadius could be any BasePart of a (possibly multi-part) drop --
-- walk up to the Pickupable-tagged root that actually carries the ItemName/Amount attributes.
local function resolveDropRoot(part)
	if CollectionService:HasTag(part, "Pickupable") then
		return part
	end
	local parent = part.Parent
	if parent and CollectionService:HasTag(parent, "Pickupable") then
		return parent
	end
	return nil
end

local function tryConsumeDrop(state, drop)
	local itemName = drop:GetAttribute("ItemName")
	local amount = drop:GetAttribute("Amount") or 1
	if not itemName then return end

	if FUEL_VALUES[itemName] then
		state.fuel = math.min(state.fuel + FUEL_VALUES[itemName] * amount, MAX_FUEL)
		print("[Furnace] Consumed", amount, itemName, "as fuel, new total:", state.fuel)
		drop:Destroy()
	elseif SMELT_RECIPES[itemName] then
		local addedAny = false
		for _ = 1, amount do
			if #state.queue >= MAX_QUEUE_SIZE then break end
			table.insert(state.queue, { itemName = itemName, progress = 0 })
			addedAny = true
		end
		if addedAny then
			print("[Furnace] Queued", itemName, "for smelting, queue size:", #state.queue)
			drop:Destroy()
		end
	end
	-- Anything else nearby isn't valid furnace input -- leave it alone.
end

-- Pulls in anything valid within FURNACE_PICKUP_RANGE of the tray. Runs once per tick of the
-- main loop below rather than relying on exact physical contact, since a dropped item landing
-- precisely on the (usually small) tray part turned out to be unreliable in practice.
local function scanFurnaceForItems(furnace, state)
	local tray = furnace:FindFirstChild("Tray")
	if not tray then return end

	local trayPosition = tray:GetPivot().Position
	local nearbyParts = workspace:GetPartBoundsInRadius(trayPosition, FURNACE_PICKUP_RANGE)

	local processed = {}
	for _, part in ipairs(nearbyParts) do
		local drop = resolveDropRoot(part)
		if drop and not processed[drop] then
			processed[drop] = true
			tryConsumeDrop(state, drop)
		end
	end
end

-- Builds the floating fuel bar + smelt-queue icon row above a placed furnace. Server-created (not
-- client-only like the placement ghost) so it replicates and is visible to every player, matching
-- a shared world structure.
local function createFurnaceDisplay(furnace, tray)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FurnaceStatus"
	billboard.Size = UDim2.new(0, 200, 0, 60)
	billboard.StudsOffset = Vector3.new(0, furnaceHalfHeight + 2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 60
	billboard.Adornee = tray
	billboard.Parent = furnace

	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = billboard

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = container

	local fuelBarBg = Instance.new("Frame")
	fuelBarBg.Name = "FuelBarBg"
	fuelBarBg.Size = UDim2.new(1, 0, 0, 14)
	fuelBarBg.BackgroundColor3 = Color3.fromRGB(42, 30, 21)
	fuelBarBg.BackgroundTransparency = 0.2
	fuelBarBg.LayoutOrder = 1
	fuelBarBg.Parent = container

	local fuelFill = Instance.new("Frame")
	fuelFill.Name = "Fill"
	fuelFill.Size = UDim2.new(0, 0, 1, 0)
	fuelFill.BackgroundColor3 = Color3.fromRGB(230, 140, 40)
	fuelFill.BorderSizePixel = 0
	fuelFill.Parent = fuelBarBg

	local fuelText = Instance.new("TextLabel")
	fuelText.Size = UDim2.new(1, 0, 1, 0)
	fuelText.BackgroundTransparency = 1
	fuelText.Text = "0 / " .. MAX_FUEL
	fuelText.TextColor3 = Color3.fromRGB(255, 255, 255)
	fuelText.Font = Enum.Font.GothamBold
	fuelText.TextSize = 11
	fuelText.TextStrokeTransparency = 0.5
	fuelText.ZIndex = 2
	fuelText.Parent = fuelBarBg

	local queueRow = Instance.new("Frame")
	queueRow.Name = "QueueRow"
	queueRow.Size = UDim2.new(1, 0, 0, 26)
	queueRow.BackgroundTransparency = 1
	queueRow.LayoutOrder = 2
	queueRow.Parent = container

	local queueLayout = Instance.new("UIListLayout")
	queueLayout.FillDirection = Enum.FillDirection.Horizontal
	queueLayout.SortOrder = Enum.SortOrder.LayoutOrder
	queueLayout.Padding = UDim.new(0, 2)
	queueLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	queueLayout.Parent = queueRow

	return { fuelFill = fuelFill, fuelText = fuelText, queueRow = queueRow }
end

local function updateFurnaceDisplay(state)
	local ui = state.ui
	if not ui then return end

	local fraction = math.clamp(state.fuel / MAX_FUEL, 0, 1)
	ui.fuelFill.Size = UDim2.new(fraction, 0, 1, 0)
	ui.fuelText.Text = math.floor(state.fuel) .. " / " .. MAX_FUEL

	for _, child in ipairs(ui.queueRow:GetChildren()) do
		if child:IsA("ViewportFrame") then child:Destroy() end
	end

	for _, job in ipairs(state.queue) do
		local icon = Instance.new("ViewportFrame")
		icon.Size = UDim2.new(0, 22, 0, 22)
		icon.BackgroundColor3 = Color3.fromRGB(48, 35, 24)
		icon.BackgroundTransparency = 0.2
		icon.Parent = ui.queueRow
		ItemIconRenderer.SetIcon(icon, job.itemName)
	end
end

-- The breakable-node system (StonePickaxeScript etc.) looks for the "Breakable" attribute on
-- individual BaseParts, not Models -- so on a multi-part furnace, it's likely set on one specific
-- part (its main body) rather than the furnace Model itself. Find that part so we can watch its
-- destruction directly, since destroying it won't necessarily destroy the whole Model too.
local function findBreakablePart(furnace)
	if furnace:GetAttribute("Breakable") then
		return furnace
	end
	for _, descendant in ipairs(furnace:GetDescendants()) do
		if descendant:GetAttribute("Breakable") then
			return descendant
		end
	end
	return nil
end

local function registerFurnace(furnace)
	local tray = furnace:FindFirstChild("Tray")
	if not tray then
		warn("Furnace placed without a 'Tray' part/model inside it -- smelting won't work for it.")
		return
	end

	local state = {
		fuel = 0,
		queue = {},
		position = tray:GetPivot().Position, -- cached so we can still drop items here after Destroy()
	}
	state.ui = createFurnaceDisplay(furnace, tray)
	furnaceStates[furnace] = state

	local handled = false
	local function onBroken()
		if handled then return end
		handled = true

		-- Drop whatever was still mid-smelt back into the world as its original raw item (it
		-- never finished, so it doesn't get the smelted result).
		for _, job in ipairs(state.queue) do
			spawnOutput(state.position, job.itemName, 1)
		end
		furnaceStates[furnace] = nil

		if furnace.Parent then
			furnace:Destroy() -- clean up whatever's left if only one part broke, not the whole Model
		end
	end

	furnace.AncestryChanged:Connect(function(_, parent)
		if not parent then onBroken() end
	end)

	local breakablePart = findBreakablePart(furnace)
	if breakablePart and breakablePart ~= furnace then
		breakablePart.AncestryChanged:Connect(function(_, parent)
			if not parent then onBroken() end
		end)
	end
end

-- ===== Placement =====
-- rotationY is the player-chosen facing angle (radians) from the client's ghost preview. It's
-- purely cosmetic, so it's trusted directly; the POSITION is still computed here via the server's
-- own raycast rather than trusting client-supplied coordinates, so a modified client can't place
-- furnaces somewhere the position validation wouldn't otherwise allow.
placeItemEvent.OnServerEvent:Connect(function(player, itemName, rotationY)
	if itemName ~= "Furnace" then return end -- only handles its own item; BoatManager etc. handle theirs
	if not furnaceTemplate then return end
	if typeof(rotationY) ~= "number" then rotationY = 0 end
	-- Ingredients were already spent at craft time (see InventoryManager's craft handler +
	-- DeployablePlacementManager) -- this just checks there's still a live blueprint to place.
	if not DeployablePlacementManager.IsPending(player, "Furnace") then return end

	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local horizontalPosition = rootPart.Position + rootPart.CFrame.LookVector * PLACEMENT_DISTANCE

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	-- Cast relative to the player's own current elevation, not a fixed high altitude -- otherwise
	-- placing underground (a cave, etc.) starts the ray above the cave ceiling and it just hits
	-- the outer surface instead of the actual floor beneath the player.
	local result = workspace:Raycast(horizontalPosition + Vector3.new(0, 10, 0), Vector3.new(0, -50, 0), raycastParams)
	local groundPosition = result and result.Position or horizontalPosition
	local placePosition = groundPosition + Vector3.new(0, furnaceHalfHeight, 0)

	DeployablePlacementManager.ClearPending(player)

	local furnace = furnaceTemplate:Clone()
	furnace:PivotTo(CFrame.new(placePosition) * CFrame.Angles(0, rotationY, 0))
	furnace.Parent = workspace

	registerFurnace(furnace)
end)

-- ===== Main loop: pulls in nearby items, burns fuel, and advances whatever's first in each
-- furnace's queue =====
task.spawn(function()
	while true do
		task.wait(1)
		for furnace, state in pairs(furnaceStates) do
			scanFurnaceForItems(furnace, state)

			if #state.queue > 0 and state.fuel > 0 then
				state.fuel -= 1
				local job = state.queue[1]
				job.progress += 1

				local recipe = SMELT_RECIPES[job.itemName]
				if recipe and job.progress >= recipe.Time then
					table.remove(state.queue, 1)
					spawnOutput(state.position, recipe.Result, 1)
				end
			end

			updateFurnaceDisplay(state)
		end
	end
end)
